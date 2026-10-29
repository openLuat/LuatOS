#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_arq.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

extern airlink_statistic_t g_airlink_statistic;

typedef struct {
    uint8_t  state;          // ARQ_STATE_*
    uint8_t  peer_acked_once;
    uint8_t  peer_mem_high;
    uint8_t  consec_giveup;
    uint8_t  force_down;
    uint8_t  need_ack;       // RX 置位, TX 取走清除
    uint8_t  devinfo_pending;
    uint16_t tx_seq;
    uint16_t rx_next;        // RX 维护
    uint16_t peer_ack;       // RX 写, TX 读
    uint64_t last_devinfo_ms;
    struct {
        luat_airlink_cmd_t *cmd;
        uint16_t seq;
        uint64_t sent_ms;
        uint64_t first_sent_ms;
    } pending;
} luat_airlink_arq_t;

static luat_airlink_arq_t g_arq;

void luat_airlink_arq_init(void) {
    memset(&g_arq, 0, sizeof(g_arq));
}

void luat_airlink_arq_stop(void) {
    if (g_arq.pending.cmd) {
        luat_airlink_cmd_free(g_arq.pending.cmd);
        g_arq.pending.cmd = NULL;
    }
}

// ---------- 发送侧 ----------

void luat_airlink_arq_check_giveup(uint64_t now) {
    if (!g_arq.pending.cmd) return;
    uint32_t limit = g_arq.peer_acked_once ? ARQ_GIVEUP_MS : ARQ_NEGO_TIMEOUT_MS;
    if (now - g_arq.pending.first_sent_ms < limit) return;
    luat_airlink_cmd_free(g_arq.pending.cmd);
    g_arq.pending.cmd = NULL;
    if (!g_arq.peer_acked_once) {
        g_arq.state = ARQ_STATE_LEGACY;
        g_airlink_statistic.arq.arq_nego_timeout++;
    } else {
        g_airlink_statistic.arq.arq_giveup++;
        if (++g_arq.consec_giveup >= ARQ_GIVEUP_LIMIT) {
            g_arq.force_down = 1;
        }
    }
    // 不重置 tx_seq
}

int luat_airlink_arq_take_need_ack(void) {
    int v = g_arq.need_ack;
    g_arq.need_ack = 0;
    return v;
}

uint16_t luat_airlink_arq_peek_ack(void) {
    return g_arq.rx_next;
}

uint16_t luat_airlink_arq_get_peer_ack(void) {
    return g_arq.peer_ack;
}

int luat_airlink_arq_state(void) {
    return g_arq.state;
}

int luat_airlink_arq_peer_mem_high(void) {
    return g_arq.peer_mem_high;
}

// ---------- pending ----------

int luat_airlink_arq_pending_active(void) {
    return g_arq.pending.cmd != NULL;
}

luat_airlink_cmd_t* luat_airlink_arq_pending_cmd(void) {
    return g_arq.pending.cmd;
}

uint16_t luat_airlink_arq_pending_seq(void) {
    return g_arq.pending.seq;
}

uint64_t luat_airlink_arq_pending_sent_ms(void) {
    return g_arq.pending.sent_ms;
}

void luat_airlink_arq_pending_set(luat_airlink_cmd_t* cmd, uint64_t now) {
    g_arq.pending.cmd = cmd;
    g_arq.pending.seq = g_arq.tx_seq++;
    g_arq.pending.sent_ms = now;
    g_arq.pending.first_sent_ms = now;
}

void luat_airlink_arq_pending_retransmit(uint64_t now) {
    g_arq.pending.sent_ms = now;
    g_airlink_statistic.arq.tx_retx++;
}

int luat_airlink_arq_pending_try_ack(void) {
    if (!g_arq.pending.cmd) return 0;
    if ((int16_t)(g_arq.peer_ack - (uint16_t)(g_arq.pending.seq + 1)) != 0) return 0;
    luat_airlink_cmd_free(g_arq.pending.cmd);
    g_arq.pending.cmd = NULL;
    g_arq.peer_acked_once = 1;
    g_arq.consec_giveup = 0;
    return 1;
}

// ---------- devinfo ----------

int luat_airlink_arq_devinfo_pending(void) {
    return g_arq.devinfo_pending;
}

void luat_airlink_arq_set_devinfo_pending(int v) {
    g_arq.devinfo_pending = v;
}

uint64_t luat_airlink_arq_last_devinfo_ms(void) {
    return g_arq.last_devinfo_ms;
}

void luat_airlink_arq_set_last_devinfo_ms(uint64_t now) {
    g_arq.last_devinfo_ms = now;
}

// ---------- 接收侧 ----------

void luat_airlink_arq_put_peer(uint16_t ack) {
    g_arq.peer_ack = ack;
}

void luat_airlink_arq_set_peer_mem_high(uint8_t v) {
    g_arq.peer_mem_high = v;
}

int luat_airlink_arq_rx(uint16_t seq) {
    int16_t d = (int16_t)(seq - g_arq.rx_next);
    if (d == 0) {
        g_arq.rx_next++;
        g_arq.need_ack = 1;
        return ARQ_RX_DELIVER;
    }
    if (d == -1) {
        g_airlink_statistic.arq.rx_dup++;
        g_arq.need_ack = 1;
        return ARQ_RX_DUP;
    }
    g_arq.rx_next = seq + 1;
    g_airlink_statistic.arq.rx_adopt++;
    g_arq.need_ack = 1;
    return ARQ_RX_ADOPT;
}

// ---------- 协商 ----------

void luat_airlink_arq_on_peer_caps(uint8_t caps) {
    int has_arq = (caps & AIRLINK_CAP_ARQ) ? 1 : 0;
    if (g_arq.state == ARQ_STATE_LEGACY) {
        if (has_arq) {
            g_arq.state = ARQ_STATE_ARQ;
            g_arq.peer_acked_once = 0;
            LLOGI("arq enabled");
        }
    } else { // ARQ
        if (!has_arq) {
            g_arq.state = ARQ_STATE_LEGACY;
            if (g_arq.pending.cmd) {
                luat_airlink_cmd_free(g_arq.pending.cmd);
                g_arq.pending.cmd = NULL;
            }
            g_airlink_statistic.arq.arq_giveup++;
            LLOGW("arq disabled (peer)");
        }
        // 含 ARQ: 什么都不做
    }
}

// ---------- force_down ----------

int luat_airlink_arq_consume_force_down(void) {
    if (!g_arq.force_down) return 0;
    g_arq.force_down = 0;
    if (g_arq.pending.cmd) {
        luat_airlink_cmd_free(g_arq.pending.cmd);
        g_arq.pending.cmd = NULL;
    }
    g_arq.consec_giveup = 0;
    // state/序号不变
    return 1;
}
