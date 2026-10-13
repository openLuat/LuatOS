/* SPDX-License-Identifier: MIT */
#include "luat_zenoh_pico.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_crypto.h"
#include "zenoh-pico.h"
#include <stdatomic.h>
#include <string.h>

typedef struct {
    uint32_t generation, id;
    int op;
    size_t length;
    char key[LUAT_ZP_KEY_MAX + 1];
    uint8_t payload[LUAT_ZP_PAYLOAD_MAX];
} command_t;
typedef struct {
    z_owned_subscriber_t value;
    uint32_t generation, id;
    int used;
} subscriber_t;

static luat_rtos_queue_t commands, events;
static luat_rtos_task_handle worker_handle;
static atomic_uint active, wanted, state, dropped, io_failed, rng_failed;
static uint32_t next_generation;
static int adapter_index;
static char locator[320];

int luat_zenoh_pico_adapter(void) { return adapter_index; }
void luat_zenoh_pico_io_fail(void) { atomic_store(&io_failed, 1); }
int luat_zenoh_pico_io_failed(void) { return atomic_load(&io_failed); }
void luat_zenoh_pico_rng_fail(void) { atomic_store(&rng_failed, 1); }
int luat_zenoh_pico_rng_failed(void) { return atomic_load(&rng_failed); }
uint32_t luat_zenoh_pico_dropped(void) { return atomic_load(&dropped); }

/* 结果队列有界；分配失败/队列满可由dropped及state观察。 */
static luat_zp_event_t *new_event(uint32_t gen, uint32_t id, const char *kind, int code) {
    luat_zp_event_t *e = luat_heap_malloc(sizeof(*e));
    if (!e) { atomic_fetch_add(&dropped, 1); return NULL; }
    memset(e, 0, sizeof(*e));
    e->generation = gen; e->id = id; e->kind = kind; e->code = code;
    return e;
}
static void post(luat_zp_event_t *e) {
    if (!e) return;
    if (luat_rtos_queue_send(events, &e, sizeof(e), 0) != 0) {
        luat_heap_free(e); atomic_fetch_add(&dropped, 1); return;
    }
    luat_zenoh_pico_wake();
}
int luat_zenoh_pico_pop(luat_zp_event_t **e) {
    return events ? luat_rtos_queue_recv(events, e, sizeof(*e), 0) : -1;
}
void luat_zenoh_pico_event_free(luat_zp_event_t *e) { luat_heap_free(e); }

static void on_sample(z_loaned_sample_t *sample, void *context) {
    subscriber_t *sub = context;
    if (atomic_load(&wanted) != sub->generation) return;
    z_view_string_t key;
    if (z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key) < 0) return;
    size_t kn = z_string_len(z_loan(key)), pn = z_bytes_len(z_sample_payload(sample));
    if (kn > LUAT_ZP_KEY_MAX || pn > LUAT_ZP_PAYLOAD_MAX) {
        atomic_fetch_add(&dropped, 1); return;
    }
    luat_zp_event_t *e = new_event(sub->generation, 0, "sample", 0);
    if (!e) return;
    e->subscriber = sub->id; e->key_len = kn; e->payload_len = pn;
    e->operation = z_sample_kind(sample) == Z_SAMPLE_KIND_DELETE ? "delete" : "put";
    memcpy(e->key, z_string_data(z_loan(key)), kn);
    z_bytes_reader_t reader = z_bytes_get_reader(z_sample_payload(sample));
    if (z_bytes_reader_read(&reader, e->payload, pn) != pn) {
        luat_heap_free(e); atomic_fetch_add(&dropped, 1); return;
    }
    post(e);
}

static void clear_session(z_owned_session_t *s, subscriber_t *subs, int opened) {
    for (int i = 0; i < LUAT_ZP_SUB_MAX; ++i) {
        if (subs[i].used) { z_drop(z_move(subs[i].value)); subs[i].used = 0; }
    }
    if (opened) z_drop(z_move(*s));
}

static int execute(z_owned_session_t *s, subscriber_t *subs, command_t *c) {
    if (c->op == LUAT_ZP_UNSUBSCRIBE) {
        for (int i = 0; i < LUAT_ZP_SUB_MAX; ++i) {
            if (subs[i].used && subs[i].id == c->id) {
                int rc = z_undeclare_subscriber(z_move(subs[i].value));
                subs[i].used = 0; return rc;
            }
        }
        return -4;
    }
    z_view_keyexpr_t key;
    if (z_view_keyexpr_from_str(&key, c->key) < 0) return -2;
    if (c->op == LUAT_ZP_PUBLISH) {
        z_owned_bytes_t bytes;
        if (z_bytes_copy_from_buf(&bytes, c->payload, c->length) < 0) return -3;
        z_put_options_t opts; z_put_options_default(&opts);
        opts.congestion_control = Z_CONGESTION_CONTROL_DROP;
        return z_put(z_loan(*s), z_loan(key), z_move(bytes), &opts);
    }
    if (c->op == LUAT_ZP_SUBSCRIBE) {
        for (int i = 0; i < LUAT_ZP_SUB_MAX; ++i) {
            if (!subs[i].used) {
                subs[i].generation = c->generation; subs[i].id = c->id;
                z_owned_closure_sample_t callback;
                z_closure(&callback, on_sample, NULL, &subs[i]);
                int rc = z_declare_subscriber(z_loan(*s), &subs[i].value, z_loan(key), z_move(callback), NULL);
                subs[i].used = rc == 0;
                return rc;
            }
        }
        return -5;
    }
    return -2;
}

static void worker(void *unused) {
    (void)unused;
    for (;;) {
        uint32_t gen = atomic_load(&active);
        if (!gen) { luat_rtos_task_sleep(5); continue; }
        if (atomic_load(&wanted) != gen) {
            luat_zp_event_t *closed = new_event(gen, 0, "closed", 0);
            atomic_store(&state, LUAT_ZP_CLOSED); atomic_store(&active, 0);
            post(closed); continue;
        }
        z_owned_session_t session;
        subscriber_t subs[LUAT_ZP_SUB_MAX] = {0};
        z_owned_config_t config;
        int rc = z_config_default(&config);
        int opened = 0;
        if (rc == 0) {
            rc = zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, "client");
            if (rc == 0) rc = zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, locator);
            if (rc == 0) rc = z_open(&session, z_move(config), NULL);
            else z_drop(z_move(config));
            opened = rc == 0;
        }
        if (opened && !luat_zenoh_pico_rng_failed()) {
            atomic_store(&state, LUAT_ZP_ONLINE);
            post(new_event(gen, 0, "opened", 0));
        } else {
            if (rc == 0) rc = -6;
            atomic_store(&state, LUAT_ZP_FAILED);
            post(new_event(gen, 0, "error", rc));
        }
        while (opened && atomic_load(&wanted) == gen && !luat_zenoh_pico_rng_failed()) {
            command_t *cmd = NULL;
            /* 固定预算，不能依赖executor返回值或无限清空持续就绪队列。 */
            for (int i = 0; i < 4 && luat_rtos_queue_recv(commands, &cmd, sizeof(cmd), 0) == 0; ++i) {
                if (cmd->generation == gen && atomic_load(&wanted) == gen) {
                    int result = execute(&session, subs, cmd);
                    const char *kind = cmd->op == LUAT_ZP_PUBLISH ? "published" :
                                       cmd->op == LUAT_ZP_SUBSCRIBE ? "subscribed" : "unsubscribed";
                    post(new_event(gen, cmd->id, result == 0 ? kind : "error", result));
                }
                luat_heap_free(cmd);
                if (luat_zenoh_pico_io_failed() || luat_zenoh_pico_rng_failed()) break;
            }
            for (int i = 0; i < 4 && !luat_zenoh_pico_io_failed() &&
                 !luat_zenoh_pico_rng_failed(); ++i) zp_spin_once(z_loan(session));
            if (z_session_is_closed(z_loan(session)) || luat_zenoh_pico_io_failed()) {
                rc = -7;
                atomic_store(&state, LUAT_ZP_FAILED); post(new_event(gen, 0, "error", rc)); break;
            }
            luat_rtos_task_sleep(5);
        }
        if (opened && luat_zenoh_pico_rng_failed() && atomic_load(&wanted) == gen) {
            rc = -6; atomic_store(&state, LUAT_ZP_FAILED); post(new_event(gen, 0, "error", rc));
        }
        clear_session(&session, subs, opened);
        command_t *cmd;
        while (luat_rtos_queue_recv(commands, &cmd, sizeof(cmd), 0) == 0) luat_heap_free(cmd);
        atomic_store(&wanted, 0);
        if (atomic_load(&state) != LUAT_ZP_FAILED) atomic_store(&state, LUAT_ZP_CLOSED);
        luat_zp_event_t *closed = new_event(gen, 0, "closed", rc);
        /* 终态回调可立即打开下一会话，投递前必须释放唯一资源槽。 */
        atomic_store(&active, 0);
        post(closed);
    }
}

int luat_zenoh_pico_open(const char *endpoint, int adapter, uint32_t *gen) {
    if (atomic_load(&active)) return -8;
    size_t n = strlen(endpoint);
    if (n < 7 || n >= sizeof(locator) || strncmp(endpoint, "tcp/", 4) ||
        strpbrk(endpoint, "#?; \t\r\n") || adapter < 0 || adapter > 126) return -2;
    if (next_generation == UINT32_MAX) return -9;
    uint8_t entropy[16];
    if (luat_crypto_trng((char *)entropy, sizeof(entropy)) != 0) return -6;
    if (!worker_handle) {
        if (luat_rtos_queue_create(&commands, LUAT_ZP_QUEUE_MAX, sizeof(command_t *)) != 0) return -3;
        if (luat_rtos_queue_create(&events, LUAT_ZP_QUEUE_MAX, sizeof(luat_zp_event_t *)) != 0) {
            luat_rtos_queue_delete(commands); commands = NULL; return -3;
        }
        if (luat_rtos_task_create(&worker_handle, LUAT_ZP_STACK_SIZE, 20, "zenohpico", worker, NULL, 16) != 0) {
            luat_rtos_queue_delete(commands); luat_rtos_queue_delete(events);
            commands = events = NULL; worker_handle = NULL; return -3;
        }
    }
    memcpy(locator, endpoint, n + 1); adapter_index = adapter;
    *gen = ++next_generation;
    atomic_store(&io_failed, 0); atomic_store(&rng_failed, 0);
    atomic_store(&state, LUAT_ZP_OPENING); atomic_store(&wanted, *gen);
    /* release/acquire默认seq_cst，把locator与adapter交给工作任务。 */
    atomic_store(&active, *gen);
    return 0;
}
int luat_zenoh_pico_command(uint32_t gen, int op, uint32_t id, const char *key, const void *payload, size_t len) {
    if (!gen || atomic_load(&wanted) != gen || atomic_load(&state) != LUAT_ZP_ONLINE) return -8;
    if (len > LUAT_ZP_PAYLOAD_MAX || (key && strlen(key) > LUAT_ZP_KEY_MAX)) return -2;
    command_t *c = luat_heap_malloc(sizeof(*c));
    if (!c) return -3;
    memset(c, 0, sizeof(*c)); c->generation = gen; c->id = id; c->op = op; c->length = len;
    if (key) memcpy(c->key, key, strlen(key) + 1);
    if (len) memcpy(c->payload, payload, len);
    if (luat_rtos_queue_send(commands, &c, sizeof(c), 0) != 0) { luat_heap_free(c); return -10; }
    return 0;
}
void luat_zenoh_pico_close(uint32_t gen) {
    if (gen && atomic_compare_exchange_strong(&wanted, &gen, 0)) atomic_store(&state, LUAT_ZP_CLOSING);
}
int luat_zenoh_pico_state(uint32_t gen) {
    if (atomic_load(&active) != gen) return LUAT_ZP_CLOSED;
    return atomic_load(&state);
}
