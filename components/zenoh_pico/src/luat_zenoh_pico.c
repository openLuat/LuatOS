/* SPDX-License-Identifier: MIT */
#include "luat_zenoh_pico.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_crypto.h"
#include "luat_mcu.h"
#include "zenoh-pico.h"
#include "zenoh-pico/utils/auth.h"
#if ZP_LUATOS_PATCH_ABI != 20261116
#error "This binding requires the matching LuatOS patched SDK"
#endif
#include <stdatomic.h>
#include <string.h>
#ifdef LUAT_ZENOH_TEST_BARRIERS
/* 仅主机回归控制真实线程交错，目标构建不包含此屏障。 */
extern void luat_zp_test_barrier(int point, uint32_t generation);
extern void luat_zp_test_payload_alloc(int sending, size_t length);
extern void luat_zp_test_command(uint32_t generation, uint32_t id, int op);
extern void luat_zp_test_sample(size_t length);
#define ZP_TEST_POINT(p, g) luat_zp_test_barrier(p, g)
#else
#define ZP_TEST_POINT(p, g) ((void)0)
#endif

typedef struct {
    uint32_t generation, id, query, timeout_ms;
    uint64_t deadline;
    int op, get_reserved;
    size_t length;
    char key[LUAT_ZP_KEY_MAX + 1];
    uint8_t *payload;
    char parameters[LUAT_ZP_PARAMETERS_MAX + 1];
} command_t;
typedef struct {
    z_owned_subscriber_t value;
    uint32_t generation, id;
    int used;
} subscriber_t;

static luat_rtos_queue_t commands, events;
static luat_rtos_task_handle worker_handle;
/* Open 成功前预留本代的 closed 对象。队列满时另存一条，先发完较早的事件。 */
static luat_zp_event_t *close_reserve;
static _Atomic(luat_zp_event_t *) overflow_closed;
static atomic_uint active, wanted, state, dropped, io_failed, rng_failed, cleanup_io, io_cancelled;
static atomic_uint get_reserved;
static atomic_uint tx_bytes, rx_bytes, tx_peak, rx_peak, tx_rejected, rx_rejected;
static atomic_flag command_gate = ATOMIC_FLAG_INIT;
static uint32_t next_generation;
static int adapter_index;
static char locator[320];
/* 只由VM在active=0时写入，再由worker消费/擦除；close不抢先擦除。 */
static char auth_user[129], auth_password[129];
static void clear_auth(void) {
    _z_secure_zero(auth_user, sizeof(auth_user));
    _z_secure_zero(auth_password, sizeof(auth_password));
}
static const char *open_failure_reason(int rc) {
    if (rc == _Z_ERR_AUTH_CONFIG) return "auth_config";
    if (rc == _Z_ERR_AUTH_PROTOCOL) return "auth_protocol";
    if (rc == _Z_ERR_AUTH_REJECTED) return "auth_rejected";
    if (rc == _Z_ERR_AUTH_CRYPTO) return "auth_crypto";
    if (rc == _Z_ERR_SYSTEM_OUT_OF_MEMORY) return "out_of_memory";
    return NULL;
}
/* 首次故障冻结；清场错误不可覆盖原阶段，也不保存key或payload。 */
static luat_zp_io_failure_t io_diagnostic;
static int auth_stage, auth_remote_reason = -1;
void luat_zenoh_pico_auth_observe(int stage, int remote_reason) {
    auth_stage = stage; auth_remote_reason = remote_reason;
}

/* 先预留再分配，出队仍占额度；只在所有者释放时归还，重开不清零。 */
static int reserve_payload(atomic_uint *used, atomic_uint *peak, atomic_uint *rejected,
                           size_t length, unsigned limit) {
    unsigned before = atomic_load(used);
    for (;;) {
        if (length > limit || before > limit - length) {
            atomic_fetch_add(rejected, 1); return -10;
        }
        unsigned after = before + (unsigned)length;
        if (atomic_compare_exchange_weak(used, &before, after)) {
            unsigned high = atomic_load(peak);
            while (high < after && !atomic_compare_exchange_weak(peak, &high, after)) {}
            return 0;
        }
    }
}
static int payload_alloc(uint8_t **out, size_t length, int sending) {
    *out = NULL;
    if (!length) return 0;
    atomic_uint *used = sending ? &tx_bytes : &rx_bytes;
    atomic_uint *rejected = sending ? &tx_rejected : &rx_rejected;
    int rc = reserve_payload(used, sending ? &tx_peak : &rx_peak, rejected, length,
                            sending ? LUAT_ZP_TX_PAYLOAD_BUDGET : LUAT_ZP_RX_PAYLOAD_BUDGET);
    if (rc) return rc;
#ifdef LUAT_ZENOH_TEST_BARRIERS
    luat_zp_test_payload_alloc(sending, length);
#endif
    *out = luat_heap_malloc(length);
    if (!*out) {
        atomic_fetch_sub(used, (unsigned)length); atomic_fetch_add(rejected, 1); return -3;
    }
    return 0;
}
static void payload_free(uint8_t *payload, size_t length, atomic_uint *used) {
    if (payload) { luat_heap_free(payload); atomic_fetch_sub(used, (unsigned)length); }
}
/* TX缓冲的生命周期交给SDK引用计数，最后一个owner才归还预算。 */
typedef struct { size_t length; uint8_t data[]; } tx_payload_t;
static int tx_payload_alloc(uint8_t **out, size_t length) {
    *out = NULL;
    if (!length) return 0;
    if (length > SIZE_MAX - sizeof(tx_payload_t)) return -2;
    int rc = reserve_payload(&tx_bytes, &tx_peak, &tx_rejected, length, LUAT_ZP_TX_PAYLOAD_BUDGET);
    if (rc) return rc;
#ifdef LUAT_ZENOH_TEST_BARRIERS
    luat_zp_test_payload_alloc(1, length);
#endif
    tx_payload_t *owner = luat_heap_malloc(sizeof(*owner) + length);
    if (!owner) { atomic_fetch_sub(&tx_bytes, (unsigned)length); atomic_fetch_add(&tx_rejected, 1); return -3; }
    owner->length = length; *out = owner->data; return 0;
}
static void tx_payload_drop(void *data, void *context) {
    (void)context;
    if (!data) return;
    tx_payload_t *owner = (tx_payload_t *)((uint8_t *)data - offsetof(tx_payload_t, data));
    size_t length = owner->length;
    luat_heap_free(owner); atomic_fetch_sub(&tx_bytes, (unsigned)length);
}
#ifdef LUAT_ZENOH_TEST_BARRIERS
static atomic_int test_hold_next;
static z_owned_bytes_t test_held_bytes;
void luat_zp_test_hold_tx(void) { atomic_store(&test_hold_next, 1); }
void luat_zp_test_release_tx(void) { z_drop(z_move(test_held_bytes)); }
#endif
static int command_take_bytes(command_t *c, z_owned_bytes_t *bytes) {
    if (!c->length) { z_bytes_empty(bytes); return 0; }
#ifdef LUAT_ZENOH_TEST_TX_COPY_BASELINE
#ifndef LUAT_ZENOH_TEST_BARRIERS
#error "copy baseline is only available in the isolated host test"
#endif
    int rc = z_bytes_copy_from_buf(bytes, c->payload, c->length);
#else
    uint8_t *data = c->payload; c->payload = NULL;
    /* from_buf在失败时也消费data，不能再由command_free释放。 */
    int rc = z_bytes_from_buf(bytes, data, c->length, tx_payload_drop, NULL);
#endif
#ifdef LUAT_ZENOH_TEST_BARRIERS
    /* 真实SDK引用跨过published/close；仅由测试在确认worker完成后释放。 */
    if (!rc && atomic_exchange(&test_hold_next, 0)) {
        rc = z_bytes_clone(&test_held_bytes, z_loan(*bytes));
        if (rc) z_drop(z_move(*bytes));
    }
#endif
    return rc;
}
static void command_free(command_t *c) {
    if (!c) return;
    if (c->get_reserved) atomic_fetch_sub(&get_reserved, 1);
    tx_payload_drop(c->payload, NULL);
    luat_heap_free(c);
}
void luat_zenoh_pico_event_free(luat_zp_event_t *e) {
    if (e) { payload_free(e->payload, e->payload_len, &rx_bytes); luat_heap_free(e); }
}
void luat_zenoh_pico_payload_stats(luat_zp_payload_stats_t *s) {
    s->tx_bytes = atomic_load(&tx_bytes); s->rx_bytes = atomic_load(&rx_bytes);
    s->tx_peak = atomic_load(&tx_peak); s->rx_peak = atomic_load(&rx_peak);
    s->tx_rejected = atomic_load(&tx_rejected); s->rx_rejected = atomic_load(&rx_rejected);
}
static int event_payload(luat_zp_event_t *e, const z_loaned_bytes_t *bytes) {
    size_t length = bytes ? z_bytes_len(bytes) : 0;
    if (length > LUAT_ZP_PAYLOAD_MAX) return -2;
    int rc = payload_alloc(&e->payload, length, 0);
    if (rc) return rc;
    e->payload_len = length;
    if (length) {
        z_bytes_reader_t reader = z_bytes_get_reader(bytes);
        if (z_bytes_reader_read(&reader, e->payload, length) != length) return -2;
    }
    return 0;
}

/* 保护接纳、关闭与状态发布；不在门内执行SDK或网络操作。 */
static void command_gate_enter(void) {
    while (atomic_flag_test_and_set(&command_gate)) luat_rtos_task_sleep(1);
}
static void command_gate_leave(void) { atomic_flag_clear(&command_gate); }

/* SDK 回调只写 worker 私有数据；VM 读取的副本由 command_gate 保护。 */
static luat_zp_health_t observed_health, published_health;
static const char *transport_stage, *first_failure;
static int transport_rc, transport_remote_reason;

void luat_zp_observe_rx(const char *event, uint64_t peer_lease, uint64_t effective_lease) {
    if (peer_lease) {
        observed_health.peer_lease_ms = peer_lease;
        observed_health.effective_lease_ms = effective_lease;
    }
    observed_health.last_rx_ms = luat_mcu_tick64_ms();
    observed_health.rx_kind = event;
    observed_health.rx_seq++;
}
void luat_zp_observe_transport_fault(const char *stage, int result, int remote_reason) {
    if (!transport_stage && !atomic_load(&cleanup_io)) {
        if (!first_failure) first_failure = "transport";
        transport_stage = stage;
        transport_rc = result;
        transport_remote_reason = remote_reason;
    }
}
static void publish_rx(uint32_t generation) {
    command_gate_enter();
    if (atomic_load(&wanted) == generation) published_health = observed_health;
    command_gate_leave();
}
int luat_zenoh_pico_health(uint32_t generation, luat_zp_health_t *snapshot, uint64_t *age_ms) {
    command_gate_enter();
    int available = generation && atomic_load(&wanted) == generation &&
        atomic_load(&state) == LUAT_ZP_ONLINE && published_health.generation == generation &&
        published_health.rx_kind && published_health.effective_lease_ms;
    if (available) {
        *snapshot = published_health;
        uint64_t now = luat_mcu_tick64_ms();
        if (now >= snapshot->last_rx_ms) *age_ms = now - snapshot->last_rx_ms;
        else available = 0;
    }
    command_gate_leave();
    return available;
}

/* 与close共用短门：close返回后，本代工作任务不可再覆盖CLOSING。 */
static int publish_state(uint32_t generation, unsigned next) {
    command_gate_enter();
    int accepted = atomic_load(&wanted) == generation;
    if (accepted) atomic_store(&state, next);
    command_gate_leave();
    return accepted;
}

int luat_zenoh_pico_adapter(void) { return adapter_index; }
void luat_zenoh_pico_io_fail_at(const char *stage, int rc, size_t requested,
                              size_t transferred, uint64_t elapsed_ms) {
    if (atomic_load(&io_failed)) return;
    if (!first_failure && !atomic_load(&cleanup_io)) first_failure = "io";
    io_diagnostic.stage = stage; io_diagnostic.rc = rc;
    io_diagnostic.requested = requested; io_diagnostic.transferred = transferred;
    io_diagnostic.elapsed_ms = elapsed_ms;
    atomic_store(&io_failed, 1);
}
void luat_zenoh_pico_final_observe(int rc) { luat_zenoh_pico_io_fail_at("query_final", rc, 0, 0, 0); }
void luat_zenoh_pico_io_fail(void) { luat_zenoh_pico_io_fail_at("unspecified", -1, 0, 0, 0); }
void luat_zenoh_pico_io_progress(int sending, size_t bytes) {
    if (atomic_load(&io_failed)) return;
    if (sending) io_diagnostic.total_tx += bytes;
    else io_diagnostic.total_rx += bytes;
}
int luat_zenoh_pico_io_failed(void) { return atomic_load(&io_failed); }
void luat_zenoh_pico_rng_fail(void) { atomic_store(&rng_failed, 1); }
int luat_zenoh_pico_rng_failed(void) { return atomic_load(&rng_failed); }
int luat_zenoh_pico_io_aborted(void) {
    if (atomic_load(&rng_failed)) return -6;
    uint32_t gen = atomic_load(&active);
    if (gen && atomic_load(&wanted) != gen && !atomic_load(&cleanup_io)) {
        atomic_store(&io_cancelled, 1); return -13;
    }
    return 0;
}
uint32_t luat_zenoh_pico_dropped(void) { return atomic_load(&dropped); }

/* 结果队列有界；分配失败/队列满可由dropped及state观察。 */
static luat_zp_event_t *new_event(uint32_t gen, uint32_t id, const char *kind, int code) {
    luat_zp_event_t *e = !strcmp(kind, "closed") ? close_reserve : luat_heap_malloc(sizeof(*e));
    if (!e) { atomic_fetch_add(&dropped, 1); return NULL; }
    memset(e, 0, sizeof(*e));
    e->generation = gen; e->id = id; e->kind = kind; e->code = code;
    if (observed_health.generation == gen) e->first_failure = first_failure;
    if (observed_health.generation == gen && transport_stage) {
        e->transport_stage = transport_stage;
        e->transport_rc = transport_rc;
        e->transport_remote_reason = transport_remote_reason;
    }
    e->auth_stage = auth_stage; e->auth_remote_reason = auth_remote_reason;
    if (atomic_load(&io_failed) && io_diagnostic.generation == gen) {
        e->io_failure = io_diagnostic;
        e->reason = "io_failure";
    }
    return e;
}
static int post(luat_zp_event_t *e) {
    if (!e) return -1;
    if (luat_rtos_queue_send(events, &e, sizeof(e), 0) != 0) {
        luat_zenoh_pico_event_free(e); atomic_fetch_add(&dropped, 1); return -1;
    }
    luat_zenoh_pico_wake();
    return 0;
}
static void publish_closed(luat_zp_event_t *e) {
    command_gate_enter();
    close_reserve = NULL;
    if (luat_rtos_queue_send(events, &e, sizeof(e), 0) != 0) atomic_store(&overflow_closed, e);
    atomic_store(&active, 0);
    command_gate_leave();
    luat_zenoh_pico_wake();
}
int luat_zenoh_pico_pop(luat_zp_event_t **e) {
    if (!events) return -1;
    command_gate_enter();
    int rc = luat_rtos_queue_recv(events, e, sizeof(*e), 0);
    if (rc != 0) {
        *e = atomic_exchange(&overflow_closed, NULL);
        if (*e) rc = 0;
    }
    command_gate_leave();
    return rc;
}

static void on_sample(z_loaned_sample_t *sample, void *context) {
    subscriber_t *sub = context;
    if (atomic_load(&wanted) != sub->generation) return;
    z_view_string_t key;
    if (z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key) < 0) return;
    size_t kn = z_string_len(z_loan(key)), pn = z_bytes_len(z_sample_payload(sample));
#ifdef LUAT_ZENOH_TEST_BARRIERS
    luat_zp_test_sample(pn);
#endif
    if (kn > LUAT_ZP_KEY_MAX || pn > LUAT_ZP_PAYLOAD_MAX) {
        atomic_fetch_add(&dropped, 1); return;
    }
    luat_zp_event_t *e = new_event(sub->generation, 0, "sample", 0);
    if (!e) return;
    e->subscriber = sub->id; e->key_len = kn;
    e->operation = z_sample_kind(sample) == Z_SAMPLE_KIND_DELETE ? "delete" : "put";
    memcpy(e->key, z_string_data(z_loan(key)), kn);
    if (event_payload(e, z_sample_payload(sample))) {
        luat_zenoh_pico_event_free(e); atomic_fetch_add(&dropped, 1); return;
    }
    post(e);
}


/* Get closure必须活到SDK drop；本地取消只抑制后续Lua分发，不提前free。 */
typedef struct {
    uint32_t generation, id;
    uint64_t deadline;
    int used, starting, sdk_done, terminal, done_posted, code;
    const char *reason, *sdk_drop_source;
    uint32_t sdk_replies;
} request_t;
/* 最近四个 SDK drop 与唯一的 Lua 业务终态分别留存。 */
static luat_zp_get_trace_t completed_get[LUAT_ZP_GET_MAX];
static unsigned trace_cursor;
static const char *drop_source;
int luat_zenoh_pico_get_trace(uint32_t generation, uint32_t request, luat_zp_get_trace_t *out) {
    int found = 0;
    if (!generation || !request) return 0;
    command_gate_enter();
    for (unsigned i = 0; i < LUAT_ZP_GET_MAX; ++i) {
        if (completed_get[i].generation == generation && completed_get[i].request == request) {
            *out = completed_get[i]; found = 1; break;
        }
    }
    command_gate_leave();
    return found;
}
const char *luat_zp_swap_query_drop_scope(const char *source) {
    const char *previous = drop_source;
    drop_source = source;
    return previous;
}
typedef struct {
    z_owned_queryable_t value;
    uint32_t generation, id;
    int used;
} queryable_t;
typedef struct {
    z_owned_query_t value;
    uint32_t generation, id, queryable;
    uint64_t deadline;
    size_t retained_bytes;
    int used;
} pending_query_t;
static request_t requests[LUAT_ZP_GET_MAX];
static pending_query_t pending_queries[LUAT_ZP_QUERY_MAX];
static uint32_t next_query_token;

static int event_sample(luat_zp_event_t *e, const z_loaned_sample_t *sample) {
    z_view_string_t key;
    if (z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key) < 0) return -2;
    e->key_len = z_string_len(z_loan(key));
    if (e->key_len > LUAT_ZP_KEY_MAX) return -2;
    memcpy(e->key, z_string_data(z_loan(key)), e->key_len);
    int rc = event_payload(e, z_sample_payload(sample));
    if (rc) return rc;
    e->operation = z_sample_kind(sample) == Z_SAMPLE_KIND_DELETE ? "delete" : "put";
    return 0;
}
static void request_terminal(request_t *r, const char *reason, int code) {
    if (r->terminal) return;
    r->terminal = 1; r->reason = reason; r->code = code;
}
static void request_release(request_t *r) {
    r->used = 0;
    atomic_fetch_sub(&get_reserved, 1);
}
static void flush_requests(void) {
    uint64_t now = luat_mcu_tick64_ms();
    for (int i = 0; i < LUAT_ZP_GET_MAX; ++i) {
        request_t *r = &requests[i];
        if (!r->used) continue;
        if (!r->terminal && now >= r->deadline) request_terminal(r, "timeout", -12);
        if (r->terminal && !r->done_posted) {
            luat_zp_event_t *e = new_event(r->generation, r->id, "get_done", r->code);
            if (e) {
                e->request = r->id;
                e->reason = r->reason;
                e->sdk_replies = r->sdk_replies;
                e->sdk_drop_source = r->sdk_drop_source;
            }
            if (post(e) == 0) r->done_posted = 1;
        }
        if (r->sdk_done && r->done_posted) request_release(r);
    }
}
static void on_get_reply(z_loaned_reply_t *reply, void *context) {
    request_t *r = context;
    if (!r->used) return;
    if (r->sdk_replies < UINT32_MAX) r->sdk_replies++;
    if (r->terminal || atomic_load(&wanted) != r->generation) return;
    if (luat_mcu_tick64_ms() >= r->deadline) { request_terminal(r, "timeout", -12); return; }
    luat_zp_event_t *e = new_event(r->generation, r->id, "get_reply", 0);
    if (!e) { request_terminal(r, "resource_limit", -3); return; }
    e->request = r->id;
    int rc;
    if (z_reply_is_ok(reply)) {
        rc = event_sample(e, z_reply_ok(reply));
    } else {
        const z_loaned_bytes_t *payload = z_reply_err_payload(z_reply_err(reply));
        e->code = -11; e->operation = "error";
        rc = event_payload(e, payload);
    }
    if (rc) {
        luat_zenoh_pico_event_free(e); atomic_fetch_add(&dropped, 1);
        request_terminal(r, "resource_limit", rc); return;
    }
    if (post(e)) request_terminal(r, "resource_limit", -10);
}
static void on_get_drop(void *context) {
    request_t *r = context;
    r->sdk_done = 1;
    r->sdk_drop_source = drop_source ? drop_source : (atomic_load(&cleanup_io) ? "cleanup" : "unknown");
    command_gate_enter();
    completed_get[trace_cursor] = (luat_zp_get_trace_t){
        .generation = r->generation, .request = r->id, .sdk_replies = r->sdk_replies,
        .sdk_drop_source = r->sdk_drop_source };
    trace_cursor = (trace_cursor + 1) % LUAT_ZP_GET_MAX;
    command_gate_leave();
    if (!r->starting && !r->terminal) {
        int expired = (drop_source && !strcmp(drop_source, "sdk_timeout")) || luat_mcu_tick64_ms() >= r->deadline;
        if (expired) request_terminal(r, "timeout", -12);
        else if (drop_source && !strcmp(drop_source, "wire_final")) request_terminal(r, "completed", 0);
        else request_terminal(r, "sdk_drop_unknown", -1);
    }
}
static void execute_get(z_owned_session_t *s, command_t *c) {
    request_t *r = NULL;
    for (int i = 0; i < LUAT_ZP_GET_MAX; ++i) if (!requests[i].used) { r = &requests[i]; break; }
    if (!r) {
        /* 接纳时已预留同一容量，这里仅保护内部状态异常。 */
        luat_zp_event_t *e = new_event(c->generation, c->id, "get_done", -5);
        if (e) { e->request = c->id; e->reason = "error"; }
        post(e); return;
    }
    memset(r, 0, sizeof(*r)); r->used = r->starting = 1;
    c->get_reserved = 0;
    r->generation = c->generation; r->id = c->id; r->deadline = c->deadline;
    uint64_t now = luat_mcu_tick64_ms();
    if (now >= r->deadline) {
        r->starting = 0; r->sdk_done = 1; request_terminal(r, "timeout", -12); flush_requests(); return;
    }
    z_view_keyexpr_t key;
    int rc = z_view_keyexpr_from_str(&key, c->key);
    z_owned_bytes_t payload;
    if (!rc) rc = command_take_bytes(c, &payload);
    if (rc == 0) {
        z_owned_closure_reply_t closure; z_closure(&closure, on_get_reply, on_get_drop, r);
        z_get_options_t options; z_get_options_default(&options);
        options.timeout_ms = r->deadline - now; options.payload = z_move(payload);
        options.consolidation = z_query_consolidation_none();
        options.target = Z_QUERY_TARGET_ALL;
        rc = z_get(z_loan(*s), z_loan(key), c->parameters, z_move(closure), &options);
    } else r->sdk_done = 1;
    r->starting = 0;
    if (rc) { request_terminal(r, "error", rc); r->sdk_done = 1; }
    else if (r->sdk_done) {
        if (r->sdk_drop_source && !strcmp(r->sdk_drop_source, "wire_final")) request_terminal(r, "completed", 0);
        else if (r->sdk_drop_source && !strcmp(r->sdk_drop_source, "sdk_timeout")) request_terminal(r, "timeout", -12);
        else request_terminal(r, "sdk_drop_unknown", -1);
    }
    else post(new_event(c->generation, c->id, "get_started", 0));
    flush_requests();
}
static int drop_query(pending_query_t *q) {
    if (!q->used) return 0;
    int rc = _z_query_rc_drop_with_result(&q->value._rc);
    if (rc < 0) luat_zenoh_pico_io_fail_at("query_final", rc, 0, 0, 0);
    q->used = 0;
    atomic_fetch_sub(&rx_bytes, (unsigned)q->retained_bytes); q->retained_bytes = 0;
    return rc;
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
    const z_loaned_bytes_t *attachment = z_query_attachment(query);
    size_t pn = payload ? z_bytes_len(payload) : 0;
    size_t an = attachment ? z_bytes_len(attachment) : 0;
    if (z_keyexpr_as_view_string(z_query_keyexpr(query), &key) < 0) goto reject;
    z_query_parameters(query, &parameters);
    e->key_len = z_string_len(z_loan(key)); e->parameters_len = z_string_len(z_loan(parameters));
    if (e->key_len > LUAT_ZP_KEY_MAX || e->parameters_len > LUAT_ZP_PARAMETERS_MAX ||
        pn > LUAT_ZP_PAYLOAD_MAX || an > LUAT_ZP_PAYLOAD_MAX) goto reject;
    memcpy(e->key, z_string_data(z_loan(key)), e->key_len);
    if (e->parameters_len) memcpy(e->parameters, z_string_data(z_loan(parameters)), e->parameters_len);
    if (event_payload(e, payload)) goto reject;
    /* owned query继续持有SDK载荷和attachment，必须与Lua事件副本分别计费。 */
    size_t retained = pn + an;
    if (reserve_payload(&rx_bytes, &rx_peak, &rx_rejected, retained, LUAT_ZP_RX_PAYLOAD_BUDGET)) goto reject;
    if (z_query_take_from_loaned(&q->value, query) < 0) {
        atomic_fetch_sub(&rx_bytes, (unsigned)retained); goto reject;
    }
    q->used = 1; q->generation = owner->generation; q->queryable = owner->id;
    q->retained_bytes = retained;
    q->id = ++next_query_token; q->deadline = luat_mcu_tick64_ms() + LUAT_ZP_QUERY_TTL_MS;
    e->queryable = owner->id; e->query = q->id; e->operation = "get";
    if (post(e)) drop_query(q);
    return;
reject:
    luat_zenoh_pico_event_free(e); atomic_fetch_add(&dropped, 1);
}
static void expire_queries(void) {
    uint64_t now = luat_mcu_tick64_ms();
    for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) {
        pending_query_t *q = &pending_queries[i];
        if (q->used && now >= q->deadline) {
            luat_zp_event_t *e = new_event(q->generation, 0, "query_expired", -12);
            if (e) { e->query = q->id; e->queryable = q->queryable; }
            int cleanup = drop_query(q); if (e && cleanup < 0) e->cleanup_code = cleanup; post(e);
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
        for (int i = 0; i < LUAT_ZP_QUERYABLE_MAX; ++i) if (owners[i].used && owners[i].id == c->query) {
            int cleanup = 0;
            for (int k = 0; k < LUAT_ZP_QUERY_MAX; ++k) {
                if (pending_queries[k].used && pending_queries[k].queryable == c->query) {
                    int code = drop_query(&pending_queries[k]); if (!cleanup && code < 0) cleanup = code;
                }
            }
            int rc = z_undeclare_queryable(z_move(owners[i].value)); owners[i].used = 0;
            return rc ? rc : cleanup;
        }
        return -4;
    }
    if (c->op == LUAT_ZP_REPLY || c->op == LUAT_ZP_FINISH_QUERY) {
        for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) {
            pending_query_t *q = &pending_queries[i];
            if (!q->used || q->id != c->query || q->generation != c->generation) continue;
            if (c->op == LUAT_ZP_FINISH_QUERY) return drop_query(q);
            if (luat_mcu_tick64_ms() >= q->deadline) { drop_query(q); return -12; }
            z_view_keyexpr_t key; if (z_view_keyexpr_from_str(&key, c->key) < 0) return -2;
            z_owned_bytes_t payload; if (command_take_bytes(c, &payload) < 0) return -3;
            return z_query_reply(z_loan(q->value), z_loan(key), z_move(payload), NULL);
        }
        return -4;
    }
    if (c->op == LUAT_ZP_QUERYABLE) {
        z_view_keyexpr_t key; if (z_view_keyexpr_from_str(&key, c->key) < 0) return -2;
        for (int i = 0; i < LUAT_ZP_QUERYABLE_MAX; ++i) if (!owners[i].used) {
            owners[i].generation = c->generation; owners[i].id = c->id;
            z_owned_closure_query_t closure; z_closure(&closure, on_query, NULL, &owners[i]);
            int rc = z_declare_queryable(z_loan(*s), &owners[i].value, z_loan(key), z_move(closure), NULL);
            owners[i].used = rc == 0; return rc;
        }
        return -5;
    }
    return -2;
}

static int clear_session(z_owned_session_t *s, subscriber_t *subs, queryable_t *owners, int opened) {
    int cleanup = 0;
    for (int i = 0; i < LUAT_ZP_SUB_MAX; ++i) {
        if (subs[i].used) { z_drop(z_move(subs[i].value)); subs[i].used = 0; }
    }
    for (int i = 0; i < LUAT_ZP_GET_MAX; ++i)
        if (requests[i].used) request_terminal(&requests[i], "closed", -8);
    for (int i = 0; i < LUAT_ZP_QUERY_MAX; ++i) {
        int code = drop_query(&pending_queries[i]); if (!cleanup && code < 0) cleanup = code;
    }
    for (int i = 0; i < LUAT_ZP_QUERYABLE_MAX; ++i) {
        if (owners[i].used) { z_drop(z_move(owners[i].value)); owners[i].used = 0; }
    }
    if (opened) z_drop(z_move(*s));
    flush_requests();
    /* VM不取事件也不能阻塞close，dropped报告未投递终态。 */
    for (int i = 0; i < LUAT_ZP_GET_MAX; ++i)
        if (requests[i].used) request_release(&requests[i]);
    return cleanup;
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
        if (command_take_bytes(c, &bytes) < 0) return -3;
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
        command_free(c);
    }
}

/* 先关闭接纳再排空；在检查后暂停的生产者必须重新过同一门。 */
static void stop_commands(uint32_t generation) {
    command_gate_enter();
    atomic_store(&wanted, 0);
    drain_commands_closed(generation);
    command_gate_leave();
}

static void router_seen(const z_id_t *id, void *context) {
    (void)id;
    *(int *)context = 1;
}
/* 固定SDK client模式的同步查询，栈上的closure只活在worker本次调用。 */
static int router_connected(const z_loaned_session_t *session) {
    int seen = 0;
    z_owned_closure_zid_t closure;
    z_closure(&closure, router_seen, NULL, &seen);
    return z_info_routers_zid(session, z_move(closure)) == 0 && seen;
}

static void worker(void *unused) {
    (void)unused;
    for (;;) {
        uint32_t gen = atomic_load(&active);
        if (!gen) { luat_rtos_task_sleep(5); continue; }
        if (atomic_load(&wanted) != gen) {
            stop_commands(gen);
            clear_auth();
            luat_zp_event_t *closed = new_event(gen, 0, "closed", 0);
            publish_closed(closed); continue;
        }
        observed_health = (luat_zp_health_t){ .generation = gen };
        transport_stage = NULL; first_failure = NULL;
        memset(&io_diagnostic, 0, sizeof(io_diagnostic)); io_diagnostic.generation = gen;
        z_owned_session_t session;
        subscriber_t subs[LUAT_ZP_SUB_MAX] = {0};
        queryable_t owners[LUAT_ZP_QUERYABLE_MAX] = {0};
        z_owned_config_t config;
        int rc = z_config_default(&config);
        int opened = 0;
        const char *failure_reason = NULL;
        if (rc == 0) {
            rc = zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, "client");
            if (rc == 0) rc = zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, locator);
            if (rc == 0 && auth_user[0]) rc = zp_config_insert(z_loan_mut(config), Z_CONFIG_USER_KEY, auth_user);
            if (rc == 0 && auth_user[0]) rc = zp_config_insert(z_loan_mut(config), Z_CONFIG_PASSWORD_KEY, auth_password);
            if (rc == 0) rc = z_open(&session, z_move(config), NULL);
            else z_drop(z_move(config));
            opened = rc == 0;
        }
        clear_auth();
        failure_reason = open_failure_reason(rc);
        ZP_TEST_POINT(3, gen);
        if (opened && !luat_zenoh_pico_rng_failed()) {
            publish_rx(gen);
            if (publish_state(gen, LUAT_ZP_ONLINE)) post(new_event(gen, 0, "opened", 0));
        } else {
            if (rc == 0) rc = -6;
            if (publish_state(gen, LUAT_ZP_FAILED)) {
                luat_zp_event_t *e = new_event(gen, 0, "error", rc);
                if (e && !e->reason) e->reason = failure_reason;
                post(e);
            }
        }
        ZP_TEST_POINT(4, gen);
        while (opened && atomic_load(&wanted) == gen && !luat_zenoh_pico_rng_failed()) {
            command_t *cmd = NULL;
            /* 固定预算，不能依赖executor返回值或无限清空持续就绪队列。 */
            for (int i = 0; i < 4 && luat_rtos_queue_recv(commands, &cmd, sizeof(cmd), 0) == 0; ++i) {
#ifdef LUAT_ZENOH_TEST_BARRIERS
                luat_zp_test_command(cmd->generation, cmd->id, cmd->op);
#endif
                if (cmd->op == LUAT_ZP_GET) ZP_TEST_POINT(1, cmd->generation);
                if (cmd->generation == gen && atomic_load(&wanted) == gen) {
                    if (!luat_zenoh_pico_io_failed()) {
                        io_diagnostic.command_id = cmd->id; io_diagnostic.command_op = cmd->op;
                        io_diagnostic.command_bytes = cmd->length;
                    }
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
                        if (cmd->op == LUAT_ZP_FINISH_QUERY && result == _Z_RESOURCE_POSITIVE_REF_COUNT) {
                            kind = "query_owner_released"; result = 0;
                        }
                        luat_zp_event_t *e = new_event(gen, cmd->id, result == 0 ? kind : "error", result);
                        if (e) e->query = cmd->query;
                        post(e);
                    }
                } else if (cmd->generation == gen) command_closed(cmd);
                command_free(cmd);
                if (luat_zenoh_pico_io_failed() || luat_zenoh_pico_rng_failed()) break;
            }
            flush_requests(); expire_queries();
            uint64_t previous_rx = observed_health.rx_seq;
            for (int i = 0; i < 4 && !luat_zenoh_pico_io_failed() &&
                 !luat_zenoh_pico_rng_failed(); ++i) zp_spin_once(z_loan(session));
            /* 主动close中断读取不等于意外断连；真正IO首错仍保留。 */
            if (atomic_load(&wanted) != gen && !luat_zenoh_pico_io_failed()) break;
            int session_closed = z_session_is_closed(z_loan(session));
            int io_lost = luat_zenoh_pico_io_failed();
            if (session_closed || io_lost || !router_connected(z_loan(session))) {
                rc = -7;
                failure_reason = session_closed ? "session_closed" : "transport_disconnected";
                if (publish_state(gen, LUAT_ZP_FAILED)) {
                    luat_zp_event_t *failure = new_event(gen, 0, "error", rc);
                    if (failure && first_failure && !strcmp(first_failure, "transport"))
                        failure->reason = "transport_failure";
                    else if (failure && !io_lost) failure->reason = failure_reason;
                    post(failure);
                }
                break;
            }
            if (observed_health.rx_seq != previous_rx) publish_rx(gen);
            luat_rtos_task_sleep(5);
        }
        if (opened && luat_zenoh_pico_rng_failed() && atomic_load(&wanted) == gen) {
            rc = -6;
            if (publish_state(gen, LUAT_ZP_FAILED)) post(new_event(gen, 0, "error", rc));
        }
        if (atomic_load(&io_cancelled) && atomic_load(&wanted) != gen &&
            !luat_zenoh_pico_io_failed() && !luat_zenoh_pico_rng_failed()) {
            rc = 0; failure_reason = NULL;
        }
        /* 先固定业务终态，随后SDK清场产生的IO失败只属于清场，不能冒充原因。 */
        luat_zp_io_failure_t terminal_io = io_diagnostic;
        int failed_before_cleanup = luat_zenoh_pico_io_failed();
        stop_commands(gen);
        /* 取消新业务后，仅worker的有界SDK清场可发送撤销/Final/Close。 */
        atomic_store(&cleanup_io, 1);
        int cleanup = clear_session(&session, subs, owners, opened);
        atomic_store(&cleanup_io, 0);
        luat_zp_event_t *closed = new_event(gen, 0, "closed", rc);
        if (closed) {
            closed->cleanup_code = cleanup;
            if (cleanup < 0 && !rc) { closed->code = cleanup; failure_reason = "query_final_cleanup"; }
            if (failed_before_cleanup) closed->io_failure = terminal_io;
            else memset(&closed->io_failure, 0, sizeof(closed->io_failure));
            /* 握手失败保留SDK原码，不能仅在worker的-7分支保留IO分类。 */
            if (first_failure && !strcmp(first_failure, "transport")) closed->reason = "transport_failure";
            else closed->reason = failed_before_cleanup ? "io_failure" : failure_reason;
        }
        /* active归零同时发布CLOSED与可重开，事件准备期间仍保持清理态。 */
        ZP_TEST_POINT(5, gen);
        publish_closed(closed);
    }
}

int luat_zenoh_pico_open(const char *endpoint, int adapter, uint32_t *gen) {
    return luat_zenoh_pico_open_ex(endpoint, adapter, gen, NULL);
}
int luat_zenoh_pico_open_ex(const char *endpoint, int adapter, uint32_t *gen,
                          const luat_zp_open_options_t *options) {
    if (!endpoint || !gen) return -2;
    if (options && (options->username || options->password)) {
        if (!options->username || !options->password || !options->username_len || !options->password_len ||
            options->username_len > 128 || options->password_len > 128 ||
            memchr(options->username, 0, options->username_len) || memchr(options->password, 0, options->password_len) ||
            memchr(options->username, '\r', options->username_len) || memchr(options->username, '\n', options->username_len) ||
            memchr(options->password, '\r', options->password_len) || memchr(options->password, '\n', options->password_len))
            return _Z_ERR_AUTH_CONFIG;
        if (_z_usrpwd_selftest()) return _Z_ERR_AUTH_CRYPTO;
    }
    if (atomic_load(&active) || atomic_load(&overflow_closed)) return -8;
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
    close_reserve = luat_heap_malloc(sizeof(*close_reserve));
    if (!close_reserve) return -3;
    clear_auth(); auth_stage = 0; auth_remote_reason = -1;
    if (options && options->username) {
        memcpy(auth_user, options->username, options->username_len);
        memcpy(auth_password, options->password, options->password_len);
    }
    memcpy(locator, endpoint, n + 1); adapter_index = adapter;
    *gen = ++next_generation;
    atomic_store(&io_failed, 0); atomic_store(&rng_failed, 0); atomic_store(&io_cancelled, 0);
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
    if (len > LUAT_ZP_PAYLOAD_MAX || (len && !payload) || (key && strlen(key) > LUAT_ZP_KEY_MAX) ||
        (parameters && strlen(parameters) > LUAT_ZP_PARAMETERS_MAX)) return -2;
    if (op == LUAT_ZP_GET && (!timeout_ms || timeout_ms > LUAT_ZP_GET_TIMEOUT_MAX)) return -2;
    command_t *c = luat_heap_malloc(sizeof(*c));
    if (!c) return -3;
    memset(c, 0, sizeof(*c)); c->generation = gen; c->id = id; c->op = op; c->length = len;
    if (key) memcpy(c->key, key, strlen(key) + 1);
    int allocation_rc = tx_payload_alloc(&c->payload, len);
    if (allocation_rc) { command_free(c); return allocation_rc; }
    if (len) memcpy(c->payload, payload, len);
    if (parameters) memcpy(c->parameters, parameters, strlen(parameters) + 1);
    c->query = query; c->timeout_ms = timeout_ms;
    if (op == LUAT_ZP_GET) ZP_TEST_POINT(2, gen);
    command_gate_enter();
    int rc = -8;
    if (atomic_load(&wanted) == gen && atomic_load(&state) == LUAT_ZP_ONLINE) {
        if (op == LUAT_ZP_GET && atomic_load(&get_reserved) >= LUAT_ZP_GET_MAX) rc = -5;
        else {
            /* 入队前预留，只有SDK释放并投递终态后才允许复用。 */
            if (op == LUAT_ZP_GET) {
                atomic_fetch_add(&get_reserved, 1);
                c->get_reserved = 1; c->deadline = luat_mcu_tick64_ms() + timeout_ms;
            }
            rc = luat_rtos_queue_send(commands, &c, sizeof(c), 0) == 0 ? 0 : -10;
        }
    }
    command_gate_leave();
    if (rc) { command_free(c); return rc; }
    return 0;
}
void luat_zenoh_pico_close(uint32_t gen) {
    command_gate_enter();
    if (gen && atomic_load(&wanted) == gen) {
        atomic_store(&wanted, 0);
        atomic_store(&state, LUAT_ZP_CLOSING);
    }
    command_gate_leave();
}
int luat_zenoh_pico_state(uint32_t gen) {
    if (!gen || atomic_load(&active) != gen) return LUAT_ZP_CLOSED;
    return atomic_load(&state);
}
