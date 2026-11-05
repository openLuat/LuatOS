#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_arq.h"
#include "luat_crypto.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"
extern airlink_statistic_t g_airlink_statistic;

/* Pending allocation/free belongs exclusively to TX. RX only publishes ACKs
 * and session changes. The mutex protects cross-task scalar snapshots. */
static luat_rtos_mutex_t lock;
static struct {
    uint32_t local, peer, retired[8];
    uint8_t retired_pos;
    uint16_t tx_seq, rx_next, peer_ack;
    uint8_t state, reset, ack_valid, need_ack, mem_high, force_down;
    uint8_t devinfo_pending, stalled;
    uint64_t last_devinfo;
    struct { luat_airlink_cmd_t* cmd; uint16_t seq; uint64_t sent, first; } pending;
} arq;
static const uint8_t hello_magic[8] = {'A','L','-','A','R','Q','3',0};

#define LOCK() luat_rtos_mutex_lock(lock, LUAT_WAIT_FOREVER)
#define UNLOCK() luat_rtos_mutex_unlock(lock)

void luat_airlink_arq_init(void) {
    luat_airlink_flags_init();
    luat_airlink_peer_flags_reset();
    if (!lock) luat_rtos_mutex_create(&lock);
    memset(&arq, 0, sizeof(arq));
    if (luat_crypto_trng((char*)&arq.local, sizeof(arq.local))) arq.local = 0;
    /* A failed RNG leaves ARQ disabled rather than reusing a boot identity. */
    arq.devinfo_pending = 1;
}

void luat_airlink_arq_stop(void) {
    LOCK();
    if (arq.pending.cmd) luat_airlink_cmd_free(arq.pending.cmd);
    arq.pending.cmd = NULL;
    arq.state = ARQ_STATE_LEGACY;
    UNLOCK();
    luat_airlink_peer_flags_reset();
}

size_t luat_airlink_arq_devinfo(uint8_t* dst, const luat_airlink_dev_info_t* info) {
    luat_airlink_cmd_t* cmd = (void*)dst;
    cmd->cmd = 0x10;
    cmd->len = sizeof(*info) + AIRLINK_ARQ_HELLO_SIZE;
    memcpy(cmd->data, info, sizeof(*info));
    memset(cmd->data + 1, 0, 3); // Historical devinfo alignment padding, not capabilities.
    uint8_t* tail = cmd->data + sizeof(*info);
    memcpy(tail, hello_magic, 8);
    LOCK();
    if (!arq.local) cmd->len = sizeof(*info);
    memcpy(tail + 8, &arq.local, 4);
    memcpy(tail + 12, &arq.peer, 4);
    UNLOCK();
    return sizeof(*cmd) + cmd->len;
}

int luat_airlink_arq_peer_info(const luat_airlink_cmd_t* cmd) {
    uint32_t peer = 0, echo = 0;
    if (cmd->len == sizeof(luat_airlink_dev_info_t) + AIRLINK_ARQ_HELLO_SIZE) {
        const uint8_t* tail = cmd->data + sizeof(luat_airlink_dev_info_t);
        if (!memcmp(tail, hello_magic, 8)) {
            memcpy(&peer, tail + 8, 4);
            memcpy(&echo, tail + 12, 4);
        }
    }
    int changed = 0;
    LOCK();
    for (unsigned i = 0; peer && i < 8; i++) {
        if (peer == arq.retired[i]) { UNLOCK(); return -1; }
    }
    if (peer != arq.peer) {
        if (arq.state == ARQ_STATE_ARQ) {
            if (peer && echo && echo != arq.local) { UNLOCK(); return -1; }
            // Rotate our endpoint session on peer restart. Even a HELLO older
            // than the bounded retired cache cannot reactivate DATA addressed
            // to our former nonce. No repeated rotation while negotiating.
            arq.local += 0x9e3779b9u;
            if (!arq.local) arq.local += 0x9e3779b9u;
        }
        changed = 1;
        if (arq.peer) arq.retired[arq.retired_pos++ % 8] = arq.peer;
        arq.peer = peer;
        arq.rx_next = 0;
        arq.ack_valid = 0;
        arq.reset = 1;
        arq.need_ack = arq.force_down = arq.mem_high = 0;
        arq.state = peer ? ARQ_STATE_NEGOTIATING : ARQ_STATE_LEGACY;
        arq.devinfo_pending = 1;
    }
    if (peer && arq.local && echo == arq.local && arq.state != ARQ_STATE_ARQ) {
        arq.state = ARQ_STATE_ARQ;
        arq.devinfo_pending = 1;
        LLOGI("ARQ3 ready session=%08x peer=%08x", arq.local, peer);
    }
    UNLOCK();
    if (changed) luat_airlink_peer_flags_reset();
    return peer ? 1 : 0;
}

static uint16_t get16(const uint8_t* p) { return (uint16_t)(p[0] | ((uint16_t)p[1] << 8)); }
static uint32_t get32(const uint8_t* p) { return (uint32_t)get16(p) | ((uint32_t)get16(p + 2) << 16); }
static void put16(uint8_t* p, uint16_t n) { p[0] = (uint8_t)n; p[1] = (uint8_t)(n >> 8); }
static void put32(uint8_t* p, uint32_t n) { put16(p, (uint16_t)n); put16(p + 2, (uint16_t)(n >> 16)); }

size_t luat_airlink_arq_pack(uint8_t* dst, size_t capacity, const luat_airlink_cmd_t* inner, uint16_t seq) {
    if (!dst || !lock || (inner && (inner->len > AIRLINK_ARQ_MAX_DATA ||
        inner->cmd == AIRLINK_CMD_ARQ || inner->cmd == 0x10))) return 0;
    size_t inner_size = inner ? sizeof(*inner) + inner->len : 0;
    size_t payload = sizeof(luat_airlink_cmd_t) + AIRLINK_ARQ_META_SIZE + inner_size;
    size_t total = sizeof(airlink_link_data_t) + payload;
    if (total > capacity || total > 1600) return 0;
    LOCK();
    uint32_t local = arq.local, peer = arq.peer;
    uint16_t ack = arq.rx_next;
    int ready = arq.state == ARQ_STATE_ARQ && !arq.reset;
    UNLOCK();
    if (!local || !peer || (inner && !ready)) return 0;
    uint8_t* outer = dst + sizeof(airlink_link_data_t);
    put16(outer, AIRLINK_CMD_ARQ); put16(outer + 2, (uint16_t)(payload - sizeof(luat_airlink_cmd_t)));
    uint8_t* meta = outer + sizeof(luat_airlink_cmd_t);
    memcpy(meta, "ARQ3", 4); meta[4] = 1; meta[5] = inner ? 1 : 2;
    put16(meta + 6, AIRLINK_ARQ_META_SIZE);
    put32(meta + 8, local); put32(meta + 12, peer);
    put16(meta + 16, inner ? seq : 0); put16(meta + 18, ack);
    if (inner) memcpy(meta + AIRLINK_ARQ_META_SIZE, inner, inner_size);
    luat_airlink_data_pack(outer, payload, dst); // Fresh incrementing link pkgid on every attempt.
    return total;
}

int luat_airlink_arq_receive(airlink_link_data_t* frame) {
    if (!lock || !luat_airlink_arq_command_valid(frame)) return -1;
    luat_airlink_cmd_t* cmd = (void*)frame->data;
    if (cmd->cmd == 0x10) {
        if (cmd->len > sizeof(luat_airlink_dev_info_t)) {
            const uint8_t* tail = cmd->data + sizeof(luat_airlink_dev_info_t);
            if (cmd->len != sizeof(luat_airlink_dev_info_t) + AIRLINK_ARQ_HELLO_SIZE ||
                memcmp(tail, hello_magic, 8) || !get32(tail + 8)) return -1;
        }
        int hello = luat_airlink_arq_peer_info(cmd);
        if (hello < 0) return -1;
        if (hello) luat_airlink_arq_set_peer_mem_high(frame->flags.mem_is_high);
        luat_airlink_peer_frame_update(frame);
        return luat_airlink_on_data_accept(frame->data, frame->len);
    }
    if (cmd->cmd != AIRLINK_CMD_ARQ) {
        if (luat_airlink_arq_state() == ARQ_STATE_LEGACY) {
            luat_airlink_peer_frame_update(frame);
            return luat_airlink_on_data_accept(frame->data, frame->len);
        }
        return -1;
    }
    // No malformed or unknown cmd 0x33 payload may escape to application dispatch.
    const uint8_t* meta = cmd->data;
    if (cmd->len < AIRLINK_ARQ_META_SIZE || frame->len != sizeof(*cmd) + cmd->len ||
        memcmp(meta, "ARQ3", 4) || meta[4] != 1 || get16(meta + 6) != AIRLINK_ARQ_META_SIZE) return -1;
    luat_airlink_cmd_t* inner = NULL;
    if (meta[5] == 1) {
        if (cmd->len < AIRLINK_ARQ_META_SIZE + sizeof(*cmd)) return -1;
        inner = (void*)(cmd->data + AIRLINK_ARQ_META_SIZE);
        if (inner->len > AIRLINK_ARQ_MAX_DATA || inner->cmd == AIRLINK_CMD_ARQ || inner->cmd == 0x10 ||
            cmd->len != AIRLINK_ARQ_META_SIZE + sizeof(*inner) + inner->len) return -1;
    } else if (meta[5] != 2 || cmd->len != AIRLINK_ARQ_META_SIZE || get16(meta + 16)) return -1;
    LOCK();
    int valid = arq.state == ARQ_STATE_ARQ && arq.local && arq.peer &&
        get32(meta + 8) == arq.peer && get32(meta + 12) == arq.local;
    UNLOCK();
    if (!valid) return -1;
    luat_airlink_peer_flags_update(&frame->flags);
    luat_airlink_arq_put_peer(get16(meta + 18));
    luat_airlink_arq_set_peer_mem_high(frame->flags.mem_is_high);
    if (!inner) return 0;
    uint16_t seq = get16(meta + 16);
    if (luat_airlink_arq_rx(seq) == ARQ_RX_DUP) return 0;
    int ret = luat_airlink_on_data_accept((uint8_t*)inner, sizeof(*inner) + inner->len);
    if (!ret) luat_airlink_arq_rx_commit(seq);
    return ret;
}

int luat_airlink_arq_command_valid(airlink_link_data_t* f) {
    if (f->len < sizeof(luat_airlink_cmd_t)) return 0;
    luat_airlink_cmd_t* cmd = (void*)f->data;
    // Released UART heartbeat encodes cmd.len=128 but sends only 128 bytes
    // INCLUDING the command header. Accept that one legacy shape, zero-fill
    // the missing devinfo tail in its handler; never relax data-frame lengths.
    if (cmd->cmd == 0x10 && cmd->len == 128 && f->len == 128)
        cmd->len = 128 - sizeof(*cmd);
    return cmd->len <= f->len - sizeof(*cmd);
}

/* Called by TX before obtaining a pending pointer. A reboot makes delivery of
 * the old session indeterminate: report it as a drop, never silently replay. */
void luat_airlink_arq_check_giveup(uint64_t now) {
    LOCK();
    if (arq.reset) {
        if (arq.pending.cmd) {
            luat_airlink_cmd_free(arq.pending.cmd);
            arq.pending.cmd = NULL;
            g_airlink_statistic.tx_pkg.drop++;
            g_airlink_statistic.arq.arq_giveup++;
        }
        arq.tx_seq = 0;
        arq.reset = 0;
    }
    if (arq.pending.cmd && !arq.stalled && now - arq.pending.first >= ARQ_GIVEUP_MS) {
        arq.stalled = 1;
        arq.force_down = 1;
        g_airlink_statistic.arq.arq_giveup++;
        /* Keep the same sequence and payload until ACK or explicit reboot. */
    }
    UNLOCK();
}

#define GETTER(type, name, field) type name(void) { if (!lock) return 0; LOCK(); type v = arq.field; UNLOCK(); return v; }
GETTER(uint16_t, luat_airlink_arq_peek_ack, rx_next)
GETTER(uint16_t, luat_airlink_arq_get_peer_ack, peer_ack)
GETTER(int, luat_airlink_arq_state, state)
GETTER(int, luat_airlink_arq_peer_mem_high, mem_high)
GETTER(int, luat_airlink_arq_devinfo_pending, devinfo_pending)
GETTER(uint64_t, luat_airlink_arq_last_devinfo_ms, last_devinfo)

int luat_airlink_arq_take_need_ack(void) { LOCK(); int v = arq.need_ack; arq.need_ack = 0; UNLOCK(); return v; }
int luat_airlink_arq_consume_force_down(void) { if (!lock) return 0; LOCK(); int v = arq.force_down; arq.force_down = 0; UNLOCK(); return v; }
void luat_airlink_arq_set_devinfo_pending(int v) { LOCK(); arq.devinfo_pending = v; UNLOCK(); }
void luat_airlink_arq_set_last_devinfo_ms(uint64_t v) { LOCK(); arq.last_devinfo = v; UNLOCK(); }
void luat_airlink_arq_set_peer_mem_high(uint8_t v) { LOCK(); arq.mem_high = v; UNLOCK(); }
void luat_airlink_arq_put_peer(uint16_t ack) { LOCK(); arq.peer_ack = ack; arq.ack_valid = 1; UNLOCK(); }

/* These accessors are TX-only; RX never frees or replaces pending.cmd. */
int luat_airlink_arq_pending_active(void) { return arq.pending.cmd != NULL; }
luat_airlink_cmd_t* luat_airlink_arq_pending_cmd(void) { return arq.pending.cmd; }
uint16_t luat_airlink_arq_pending_seq(void) { return arq.pending.seq; }
uint64_t luat_airlink_arq_pending_sent_ms(void) { return arq.pending.sent; }
int luat_airlink_arq_pending_set(luat_airlink_cmd_t* cmd, uint64_t now) {
    if (!lock || !cmd || cmd->len > AIRLINK_ARQ_MAX_DATA || cmd->cmd == AIRLINK_CMD_ARQ || cmd->cmd == 0x10) return -1;
    LOCK();
    if (arq.pending.cmd || arq.reset || arq.state != ARQ_STATE_ARQ) { UNLOCK(); return -1; }
    arq.pending.cmd = cmd;
    arq.pending.seq = arq.tx_seq++;
    arq.pending.sent = arq.pending.first = now;
    arq.stalled = 0;
    /* A prior frame's ACK must not acknowledge a newly allocated slot. */
    arq.ack_valid = 0;
    UNLOCK();
    return 0;
}
void luat_airlink_arq_pending_retransmit(uint64_t now) {
    arq.pending.sent = now;
    g_airlink_statistic.arq.tx_retx++;
}
int luat_airlink_arq_pending_try_ack(void) {
    LOCK();
    int ok = !arq.reset && arq.pending.cmd && arq.ack_valid &&
        arq.peer_ack == (uint16_t)(arq.pending.seq + 1);
    if (ok) { luat_airlink_cmd_free(arq.pending.cmd); arq.pending.cmd = NULL; arq.stalled = arq.force_down = 0; }
    UNLOCK(); return ok;
}

int luat_airlink_arq_rx(uint16_t seq) {
    LOCK();
    int ret = ARQ_RX_DELIVER;
    if (seq != arq.rx_next) {
        g_airlink_statistic.arq.rx_dup++;
        arq.need_ack = 1;
        ret = ARQ_RX_DUP;
    }
    UNLOCK(); return ret;
}
void luat_airlink_arq_rx_commit(uint16_t seq) {
    LOCK();
    if (seq == arq.rx_next) { arq.rx_next++; arq.need_ack = 1; }
    UNLOCK();
}
