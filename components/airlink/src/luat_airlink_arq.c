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
    uint32_t local, peer, retired;
    uint16_t tag, tx_seq, rx_next, peer_ack;
    uint8_t state, reset, ack_valid, need_ack, mem_high, force_down;
    uint8_t devinfo_pending, stalled;
    uint64_t last_devinfo;
    struct { luat_airlink_cmd_t* cmd; uint16_t seq; uint64_t sent, first; } pending;
} arq;
static const uint8_t hello_magic[8] = {'A','L','-','A','R','Q','2',0};

#define LOCK() luat_rtos_mutex_lock(lock, LUAT_WAIT_FOREVER)
#define UNLOCK() luat_rtos_mutex_unlock(lock)

void luat_airlink_arq_init(void) {
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
}

size_t luat_airlink_arq_devinfo(uint8_t* dst, const luat_airlink_dev_info_t* info) {
    luat_airlink_cmd_t* cmd = (void*)dst;
    cmd->cmd = 0x10;
    cmd->len = sizeof(*info) + AIRLINK_ARQ_HELLO_SIZE;
    memcpy(cmd->data, info, sizeof(*info));
    /* Old experimental ARQ enables itself from bit2 alone. Do not enable it. */
    cmd->data[1] &= (uint8_t)~AIRLINK_CAP_ARQ;
    uint8_t* tail = cmd->data + sizeof(*info);
    memcpy(tail, hello_magic, 8);
    LOCK();
    memcpy(tail + 8, &arq.local, 4);
    memcpy(tail + 12, &arq.peer, 4);
    UNLOCK();
    return sizeof(*cmd) + cmd->len;
}

void luat_airlink_arq_peer_info(const luat_airlink_cmd_t* cmd) {
    uint32_t peer = 0, echo = 0;
    if (cmd->len == sizeof(luat_airlink_dev_info_t) + AIRLINK_ARQ_HELLO_SIZE) {
        const uint8_t* tail = cmd->data + sizeof(luat_airlink_dev_info_t);
        if (!memcmp(tail, hello_magic, 8)) {
            memcpy(&peer, tail + 8, 4);
            memcpy(&echo, tail + 12, 4);
        }
    }
    LOCK();
    if (peer && peer == arq.retired) { UNLOCK(); return; }
    if (peer != arq.peer) {
        arq.retired = arq.peer;
        arq.peer = peer;
        arq.rx_next = 0;
        arq.ack_valid = 0;
        arq.reset = 1;
        arq.state = peer ? ARQ_STATE_NEGOTIATING : ARQ_STATE_LEGACY;
        arq.devinfo_pending = 1;
        uint32_t sessions[2] = {arq.local < peer ? arq.local : peer, arq.local < peer ? peer : arq.local};
        arq.tag = luat_crc16_modbus((const uint8_t*)sessions, sizeof(sessions));
        if (!arq.tag) arq.tag = 1;
    }
    if (peer && arq.local && echo == arq.local && arq.state != ARQ_STATE_ARQ) {
        arq.state = ARQ_STATE_ARQ;
        arq.devinfo_pending = 1;
        LLOGI("ARQ2 ready session=%08x peer=%08x", arq.local, peer);
    }
    UNLOCK();
}

uint16_t luat_airlink_arq_tag(void) {
    if (!lock) return 0;
    LOCK(); uint16_t v = arq.tag; UNLOCK(); return v;
}

int luat_airlink_arq_frame_valid(const airlink_link_data_t* f) {
    LOCK();
    int ok = arq.local && arq.peer && AIRLINK_FL_ARQ(f->flags) &&
             (uint16_t)(f->flags.reserved >> 8) == arq.tag;
    UNLOCK(); return ok;
}

int luat_airlink_arq_allow_legacy(const airlink_link_data_t* f) {
    // An ARQ2 session tag marks reliable traffic even before this boot has
    // negotiated. Never execute a previous boot's retry as a legacy command.
    if (AIRLINK_FL_ARQ(f->flags) && (f->flags.reserved >> 8)) return 0;
    return luat_airlink_arq_state() == ARQ_STATE_LEGACY;
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
void luat_airlink_arq_pending_set(luat_airlink_cmd_t* cmd, uint64_t now) {
    LOCK();
    arq.pending.cmd = cmd;
    arq.pending.seq = arq.tx_seq++;
    arq.pending.sent = arq.pending.first = now;
    arq.stalled = 0;
    /* A prior frame's ACK must not acknowledge a newly allocated slot. */
    arq.ack_valid = 0;
    UNLOCK();
}
void luat_airlink_arq_pending_retransmit(uint64_t now) {
    arq.pending.sent = now;
    g_airlink_statistic.arq.tx_retx++;
}
int luat_airlink_arq_pending_try_ack(void) {
    LOCK();
    int ok = !arq.reset && arq.pending.cmd && arq.ack_valid &&
        arq.peer_ack == (uint16_t)(arq.pending.seq + 1);
    if (ok) { luat_airlink_cmd_free(arq.pending.cmd); arq.pending.cmd = NULL; arq.stalled = 0; }
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

void luat_airlink_arq_on_peer_caps(uint8_t caps) { (void)caps; /* Padding is not a handshake. */ }
