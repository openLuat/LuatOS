/* SPDX-License-Identifier: MIT */
#include "luat_zenoh_pico.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_crypto.h"
#include "luat_mcu.h"
#include "zenoh-pico.h"
#include <stdatomic.h>
#include <string.h>
#ifdef LUAT_ZENOH_TEST_BARRIERS
/* 仅主机回归控制真实线程交错，目标构建不包含此屏障。 */
extern void luat_zp_test_barrier(int point, uint32_t generation);
#define ZP_TEST_POINT(p, g) luat_zp_test_barrier(p, g)
#else
#define ZP_TEST_POINT(p, g) ((void)0)
#endif

typedef struct {
    uint32_t generation, id, query, timeout_ms;
    int op;
    size_t length;
    char key[LUAT_ZP_KEY_MAX + 1];
    uint8_t payload[LUAT_ZP_PAYLOAD_MAX];
    char parameters[LUAT_ZP_PARAMETERS_MAX + 1];
} command_t;
typedef struct {
    z_owned_subscriber_t value;
    uint32_t generation, id;
    int used;
} subscriber_t;

static luat_rtos_queue_t commands, events;
static luat_rtos_task_handle worker_handle;
static atomic_uint active, wanted, state, dropped, io_failed, rng_failed;
static atomic_flag command_gate = ATOMIC_FLAG_INIT;
static uint32_t next_generation;
static int adapter_index;
static char locator[320];

/* 只保护零等待队列接纳/关闭排空，不在门内执行SDK或网络操作。 */
static void command_gate_enter(void) {
    while (atomic_flag_test_and_set(&command_gate)) luat_rtos_task_sleep(1);
}
static void command_gate_leave(void) { atomic_flag_clear(&command_gate); }

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
static int post(luat_zp_event_t *e) {
    if (!e) return -1;
    if (luat_rtos_queue_send(events, &e, sizeof(e), 0) != 0) {
        luat_heap_free(e); atomic_fetch_add(&dropped, 1); return -1;
    }
    luat_zenoh_pico_wake();
    return 0;
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


/* Get closure必须活到SDK drop；本地取消只抑制后续Lua分发，不提前free。 */
typedef struct {
    uint32_t generation, id;
    uint64_t deadline;
    int used, starting, sdk_done, terminal, done_posted, code;
    const char *reason;
} request_t;
typedef struct {
    z_owned_queryable_t value;
    uint32_t generation, id;
    int used;
} queryable_t;
typedef struct {
    z_owned_query_t value;
    uint32_t generation, id, queryable;
    uint64_t deadline;
    int used;
} pending_query_t;
static request_t requests[LUAT_ZP_GET_MAX];
static pending_query_t pending_queries[LUAT_ZP_QUERY_MAX];
static uint32_t next_query_token;

static int event_sample(luat_zp_event_t *e, const z_loaned_sample_t *sample) {
    z_view_string_t key;
    if (z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key) < 0) return -2;
    e->key_len = z_string_len(z_loan(key));
    e->payload_len = z_bytes_len(z_sample_payload(sample));
    if (e->key_len > LUAT_ZP_KEY_MAX || e->payload_len > LUAT_ZP_PAYLOAD_MAX) return -2;
    memcpy(e->key, z_string_data(z_loan(key)), e->key_len);
    z_bytes_reader_t reader = z_bytes_get_reader(z_sample_payload(sample));
    if (z_bytes_reader_read(&reader, e->payload, e->payload_len) != e->payload_len) return -2;
    e->operation = z_sample_kind(sample) == Z_SAMPLE_KIND_DELETE ? "delete" : "put";
    return 0;
}
static void request_terminal(request_t *r, const char *reason, int code) {
    if (r->terminal) return;
    r->terminal = 1; r->reason = reason; r->code = code;
}
static void flush_requests(void) {
    uint64_t now = luat_mcu_tick64_ms();
    for (int i = 0; i < LUAT_ZP_GET_MAX; ++i) {
        request_t *r = &requests[i];
        if (!r->used) continue;
        if (!r->terminal && now >= r->deadline) request_terminal(r, "timeout", -12);
        if (r->terminal && !r->done_posted) {
            luat_zp_event_t *e = new_event(r->generation, r->id, "get_done", r->code);
            if (e) { e->request = r->id; e->reason = r->reason; }
            if (post(e) == 0) r->done_posted = 1;
        }
        if (r->sdk_done && r->done_posted) r->used = 0;
    }
}
static void on_get_reply(z_loaned_reply_t *reply, void *context) {
    request_t *r = context;
    if (!r->used || r->terminal || atomic_load(&wanted) != r->generation) return;
    if (luat_mcu_tick64_ms() >= r->deadline) { request_terminal(r, "timeout", -12); return; }
    luat_zp_event_t *e = new_event(r->generation, r->id, "get_reply", 0);
    if (!e) return;
    e->request = r->id;
    if (z_reply_is_ok(reply)) {
        if (event_sample(e, z_reply_ok(reply))) { luat_heap_free(e); atomic_fetch_add(&dropped, 1); return; }
    } else {
        const z_loaned_bytes_t *payload = z_reply_err_payload(z_reply_err(reply));
        e->code = -11; e->operation = "error"; e->payload_len = z_bytes_len(payload);
        if (e->payload_len > LUAT_ZP_PAYLOAD_MAX) { luat_heap_free(e); atomic_fetch_add(&dropped, 1); return; }
        z_bytes_reader_t reader = z_bytes_get_reader(payload);
        if (z_bytes_reader_read(&reader, e->payload, e->payload_len) != e->payload_len) {
            luat_heap_free(e); atomic_fetch_add(&dropped, 1); return;
        }
    }
    post(e);
}
static void on_get_drop(void *context) {
    request_t *r = context;
    r->sdk_done = 1;
    if (!r->starting && !r->terminal) {
        int expired = luat_mcu_tick64_ms() >= r->deadline;
        request_terminal(r, expired ? "timeout" : "completed", expired ? -12 : 0);
    }
}
static void execute_get(z_owned_session_t *s, command_t *c) {
    request_t *r = NULL;
    for (int i = 0; i < LUAT_ZP_GET_MAX; ++i) if (!requests[i].used) { r = &requests[i]; break; }
    z_view_keyexpr_t key;
    int rc = r ? z_view_keyexpr_from_str(&key, c->key) : -5;
    if (rc) {
        luat_zp_event_t *e = new_event(c->generation, c->id, "get_done", rc);
        if (e) { e->request = c->id; e->reason = "error"; }
        post(e); return;
    }
    memset(r, 0, sizeof(*r)); r->used = r->starting = 1;
    r->generation = c->generation; r->id = c->id; r->deadline = luat_mcu_tick64_ms() + c->timeout_ms;
    z_owned_bytes_t payload;
    rc = z_bytes_copy_from_buf(&payload, c->payload, c->length);
    if (rc == 0) {
        z_owned_closure_reply_t closure; z_closure(&closure, on_get_reply, on_get_drop, r);
        z_get_options_t options; z_get_options_default(&options);
        options.timeout_ms = c->timeout_ms; options.payload = z_move(payload);
        options.consolidation = z_query_consolidation_none();
        options.target = Z_QUERY_TARGET_ALL;
        rc = z_get(z_loan(*s), z_loan(key), c->parameters, z_move(closure), &options);
    } else r->sdk_done = 1;
    r->starting = 0;
    if (rc) { request_terminal(r, "error", rc); r->sdk_done = 1; }
    else if (r->sdk_done) request_terminal(r, "completed", 0);
    else post(new_event(c->generation, c->id, "get_started", 0));
    flush_requests();
}
static void drop_query(pending_query_t *q) {
    if (q->used) { z_drop(z_move(q->value)); q->used = 0; }
}
static void on_query(z_loaned_query_t *query, void *context) {
    queryable_t *owner = context;
    if (atomic_load(&wanted) != owner->generation) return;
    pending_query_t *q = NULL;
    for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) if (!pending_queries[i].used) { q = &pending_queries[i]; break; }
    if (!q || next_query_token == UINT32_MAX) { atomic_fetch_add(&dropped, 1); return; }
    luat_zp_event_t *e = new_event(owner->generation, 0, "query", 0);
    if (!e) return;
    z_view_string_t key, parameters;
    const z_loaned_bytes_t *payload = z_query_payload(query);
    if (z_keyexpr_as_view_string(z_query_keyexpr(query), &key) < 0) { luat_heap_free(e); return; }
    z_query_parameters(query, &parameters);
    e->key_len = z_string_len(z_loan(key)); e->parameters_len = z_string_len(z_loan(parameters));
    e->payload_len = payload ? z_bytes_len(payload) : 0;
    if (e->key_len > LUAT_ZP_KEY_MAX || e->parameters_len > LUAT_ZP_PARAMETERS_MAX || e->payload_len > LUAT_ZP_PAYLOAD_MAX) {
        luat_heap_free(e); atomic_fetch_add(&dropped, 1); return;
    }
    memcpy(e->key, z_string_data(z_loan(key)), e->key_len);
    if (e->parameters_len) memcpy(e->parameters, z_string_data(z_loan(parameters)), e->parameters_len);
    if (e->payload_len) {
        z_bytes_reader_t reader = z_bytes_get_reader(payload);
        if (z_bytes_reader_read(&reader, e->payload, e->payload_len) != e->payload_len) {
            luat_heap_free(e); atomic_fetch_add(&dropped, 1); return;
        }
    }
    if (z_query_take_from_loaned(&q->value, query) < 0) { luat_heap_free(e); atomic_fetch_add(&dropped, 1); return; }
    q->used = 1; q->generation = owner->generation; q->queryable = owner->id;
    q->id = ++next_query_token; q->deadline = luat_mcu_tick64_ms() + 5000;
    e->queryable = owner->id; e->query = q->id; e->operation = "get";
    if (post(e)) drop_query(q);
}
static void expire_queries(void) {
    uint64_t now = luat_mcu_tick64_ms();
    for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) {
        pending_query_t *q = &pending_queries[i];
        if (q->used && now >= q->deadline) {
            luat_zp_event_t *e = new_event(q->generation, 0, "query_expired", -12);
            if (e) { e->query = q->id; e->queryable = q->queryable; }
            drop_query(q); post(e);
        }
    }
}
static int execute_query(z_owned_session_t *s, queryable_t *owners, command_t *c) {
    if (c->op == LUAT_ZP_CANCEL_GET) {
        for (int i = 0; i < LUAT_ZP_GET_MAX; ++i) if (requests[i].used && requests[i].id == c->id) {
            request_terminal(&requests[i], "cancelled_local", -13); flush_requests(); return 0;
        }
        return -4;
    }
    if (c->op == LUAT_ZP_UNQUERYABLE) {
        for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) if (owners[i].used && owners[i].id == c->query) {
            for (int k = 0; k < LUAT_ZP_QUERY_MAX; ++k)
                if (pending_queries[k].used && pending_queries[k].queryable == c->query) drop_query(&pending_queries[k]);
            int rc = z_undeclare_queryable(z_move(owners[i].value)); owners[i].used = 0; return rc;
        }
        return -4;
    }
    if (c->op == LUAT_ZP_REPLY || c->op == LUAT_ZP_FINISH_QUERY) {
        for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) {
            pending_query_t *q = &pending_queries[i];
            if (!q->used || q->id != c->query || q->generation != c->generation) continue;
            if (c->op == LUAT_ZP_FINISH_QUERY) { drop_query(q); return 0; }
            if (luat_mcu_tick64_ms() >= q->deadline) { drop_query(q); return -12; }
            z_view_keyexpr_t key; if (z_view_keyexpr_from_str(&key, c->key) < 0) return -2;
            z_owned_bytes_t payload; if (z_bytes_copy_from_buf(&payload, c->payload, c->length) < 0) return -3;
            return z_query_reply(z_loan(q->value), z_loan(key), z_move(payload), NULL);
        }
        return -4;
    }
    if (c->op == LUAT_ZP_QUERYABLE) {
        z_view_keyexpr_t key; if (z_view_keyexpr_from_str(&key, c->key) < 0) return -2;
        for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) if (!owners[i].used) {
            owners[i].generation = c->generation; owners[i].id = c->id;
            z_owned_closure_query_t closure; z_closure(&closure, on_query, NULL, &owners[i]);
            int rc = z_declare_queryable(z_loan(*s), &owners[i].value, z_loan(key), z_move(closure), NULL);
            owners[i].used = rc == 0; return rc;
        }
        return -5;
    }
    return -2;
}

static void clear_session(z_owned_session_t *s, subscriber_t *subs, queryable_t *owners, int opened) {
    for (int i = 0; i < LUAT_ZP_SUB_MAX; ++i) {
        if (subs[i].used) { z_drop(z_move(subs[i].value)); subs[i].used = 0; }
    }
    for (int i = 0; i < LUAT_ZP_GET_MAX; ++i)
        if (requests[i].used) request_terminal(&requests[i], "closed", -8);
    for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) {
        drop_query(&pending_queries[i]);
        if (owners[i].used) { z_drop(z_move(owners[i].value)); owners[i].used = 0; }
    }
    if (opened) z_drop(z_move(*s));
    flush_requests();
    /* VM不取事件也不能阻塞close，dropped报告未投递终态。 */
    memset(requests, 0, sizeof(requests));
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

/* 关闭时仍在队列内的Get也已向Lua接纳，必须终结而非静默free。 */
static void command_closed(command_t *c) {
    if (c->op != LUAT_ZP_GET) return;
    luat_zp_event_t *e = new_event(c->generation, c->id, "get_done", -8);
    if (e) { e->request = c->id; e->reason = "closed"; }
    post(e);
}
static void drain_commands_closed(uint32_t generation) {
    command_t *c;
    while (luat_rtos_queue_recv(commands, &c, sizeof(c), 0) == 0) {
        if (c->generation == generation) command_closed(c);
        luat_heap_free(c);
    }
}

/* 先关闭接纳再排空；在检查后暂停的生产者必须重新过同一门。 */
static void stop_commands(uint32_t generation) {
    command_gate_enter();
    atomic_store(&wanted, 0);
    drain_commands_closed(generation);
    command_gate_leave();
}

static void worker(void *unused) {
    (void)unused;
    for (;;) {
        uint32_t gen = atomic_load(&active);
        if (!gen) { luat_rtos_task_sleep(5); continue; }
        if (atomic_load(&wanted) != gen) {
            stop_commands(gen);
            luat_zp_event_t *closed = new_event(gen, 0, "closed", 0);
            atomic_store(&state, LUAT_ZP_CLOSED); atomic_store(&active, 0);
            post(closed); continue;
        }
        z_owned_session_t session;
        subscriber_t subs[LUAT_ZP_SUB_MAX] = {0};
        queryable_t owners[LUAT_ZP_QUERY_MAX] = {0};
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
                if (cmd->op == LUAT_ZP_GET) ZP_TEST_POINT(1, cmd->generation);
                if (cmd->generation == gen && atomic_load(&wanted) == gen) {
                    if (cmd->op == LUAT_ZP_GET) execute_get(&session, cmd);
                    else {
                        int result = cmd->op <= LUAT_ZP_UNSUBSCRIBE ? execute(&session, subs, cmd) : execute_query(&session, owners, cmd);
                        const char *kind = cmd->op == LUAT_ZP_PUBLISH ? "published" :
                            cmd->op == LUAT_ZP_SUBSCRIBE ? "subscribed" :
                            cmd->op == LUAT_ZP_UNSUBSCRIBE ? "unsubscribed" :
                            cmd->op == LUAT_ZP_QUERYABLE ? "queryable" :
                            cmd->op == LUAT_ZP_UNQUERYABLE ? "unqueryable" :
                            cmd->op == LUAT_ZP_REPLY ? "replied" :
                            cmd->op == LUAT_ZP_FINISH_QUERY ? "query_finished" : "get_cancel_requested";
                        luat_zp_event_t *e = new_event(gen, cmd->id, result == 0 ? kind : "error", result);
                        if (e) e->query = cmd->query;
                        post(e);
                    }
                } else if (cmd->generation == gen) command_closed(cmd);
                luat_heap_free(cmd);
                if (luat_zenoh_pico_io_failed() || luat_zenoh_pico_rng_failed()) break;
            }
            flush_requests(); expire_queries();
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
        stop_commands(gen);
        clear_session(&session, subs, owners, opened);
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
    return luat_zenoh_pico_command_ex(gen, op, id, key, payload, len, NULL, 0, 0);
}
int luat_zenoh_pico_command_ex(uint32_t gen, int op, uint32_t id, const char *key, const void *payload,
                              size_t len, const char *parameters, uint32_t query, uint32_t timeout_ms) {
    if (!gen || atomic_load(&wanted) != gen || atomic_load(&state) != LUAT_ZP_ONLINE) return -8;
    if (len > LUAT_ZP_PAYLOAD_MAX || (key && strlen(key) > LUAT_ZP_KEY_MAX) ||
        (parameters && strlen(parameters) > LUAT_ZP_PARAMETERS_MAX)) return -2;
    command_t *c = luat_heap_malloc(sizeof(*c));
    if (!c) return -3;
    memset(c, 0, sizeof(*c)); c->generation = gen; c->id = id; c->op = op; c->length = len;
    if (key) memcpy(c->key, key, strlen(key) + 1);
    if (len) memcpy(c->payload, payload, len);
    if (parameters) memcpy(c->parameters, parameters, strlen(parameters) + 1);
    c->query = query; c->timeout_ms = timeout_ms;
    if (op == LUAT_ZP_GET) ZP_TEST_POINT(2, gen);
    command_gate_enter();
    int rc = atomic_load(&wanted) == gen && atomic_load(&state) == LUAT_ZP_ONLINE ?
        (luat_rtos_queue_send(commands, &c, sizeof(c), 0) == 0 ? 0 : -10) : -8;
    command_gate_leave();
    if (rc) { luat_heap_free(c); return rc; }
    return 0;
}
void luat_zenoh_pico_close(uint32_t gen) {
    if (gen && atomic_compare_exchange_strong(&wanted, &gen, 0)) atomic_store(&state, LUAT_ZP_CLOSING);
}
int luat_zenoh_pico_state(uint32_t gen) {
    if (atomic_load(&active) != gen) return LUAT_ZP_CLOSED;
    return atomic_load(&state);
}
