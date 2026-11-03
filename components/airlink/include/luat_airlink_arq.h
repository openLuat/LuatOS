#ifndef LUAT_AIRLINK_ARQ_H
#define LUAT_AIRLINK_ARQ_H

#include "luat_airlink.h"

// =====================================================================
// 链路层停等 ARQ (窗口=1): 复用 pkgid([31:16]=ack,[15:0]=seq) + flags.reserved
// (bit0=arq, bit1=seqv)。详见 test/airlink_uart_ARQ设计方案.md
// =====================================================================

// flags.reserved 打包/解析 (reserved 字段内部位, 即整体 flags 的 bit8/9)
#define AIRLINK_FL_PACK(arq, seqv, wnd) \
    (((uint32_t)(arq) & 1u) | (((uint32_t)(seqv) & 1u) << 1) | (((uint32_t)(wnd) & 0xFu) << 2))
#define AIRLINK_FL_ARQ(f)   ((uint8_t)((f).reserved & 1u))
#define AIRLINK_FL_SEQV(f)  ((uint8_t)(((f).reserved >> 1) & 1u))

// pkgid 打包/解析
#define AIRLINK_PKGID(ack, seq) \
    ((((uint32_t)(ack) & 0xFFFFu) << 16) | ((uint32_t)(seq) & 0xFFFFu))
#define AIRLINK_PKGID_ACK(pkgid)  ((uint16_t)((pkgid) >> 16))
#define AIRLINK_PKGID_SEQ(pkgid)  ((uint16_t)((pkgid) & 0xFFFFu))

// 参数 (未修驱动, 丢包较多, 放弃阈值取宽)
#define ARQ_RTO_MS           60
#define ARQ_GIVEUP_MS        3000
#define ARQ_GIVEUP_LIMIT     3
#define ARQ_NEGO_TIMEOUT_MS  5000
#define ARQ_IDLE_WAIT_MS     500

enum {
    ARQ_STATE_LEGACY = 0,
    ARQ_STATE_ARQ = 1,
    ARQ_STATE_NEGOTIATING = 2,
};

enum {
    ARQ_RX_DELIVER = 0,
    ARQ_RX_DUP = 1,
    ARQ_RX_ADOPT = 2,
};

// 初始化/释放
void luat_airlink_arq_init(void);
void luat_airlink_arq_stop(void);

// 发送侧 (TX 任务)
void luat_airlink_arq_check_giveup(uint64_t now);
int  luat_airlink_arq_take_need_ack(void);
uint16_t luat_airlink_arq_peek_ack(void);
uint16_t luat_airlink_arq_get_peer_ack(void);
int  luat_airlink_arq_state(void);
int  luat_airlink_arq_peer_mem_high(void);

// pending 槽 (发送侧)
int  luat_airlink_arq_pending_active(void);
luat_airlink_cmd_t* luat_airlink_arq_pending_cmd(void);
uint16_t luat_airlink_arq_pending_seq(void);
uint64_t luat_airlink_arq_pending_sent_ms(void);
void luat_airlink_arq_pending_set(luat_airlink_cmd_t* cmd, uint64_t now); // tx_seq 自增
void luat_airlink_arq_pending_retransmit(uint64_t now);
int  luat_airlink_arq_pending_try_ack(void); // peer_ack 确认则释放, 返回1

// devinfo 心跳 (发送侧)
int  luat_airlink_arq_devinfo_pending(void);
void luat_airlink_arq_set_devinfo_pending(int v);
uint64_t luat_airlink_arq_last_devinfo_ms(void);
void luat_airlink_arq_set_last_devinfo_ms(uint64_t now);

// 接收侧 (RX 任务)
void luat_airlink_arq_put_peer(uint16_t ack);
void luat_airlink_arq_set_peer_mem_high(uint8_t v);
int  luat_airlink_arq_rx(uint16_t seq);
void luat_airlink_arq_rx_commit(uint16_t seq);

// UART-only ARQ2 negotiation. Never infer support from legacy padding/caps.
#define AIRLINK_ARQ_HELLO_SIZE 16
size_t luat_airlink_arq_devinfo(uint8_t* dst, const luat_airlink_dev_info_t* info);
void luat_airlink_arq_peer_info(const luat_airlink_cmd_t* cmd);
uint16_t luat_airlink_arq_tag(void);
int luat_airlink_arq_frame_valid(const airlink_link_data_t* frame);
int luat_airlink_arq_allow_legacy(const airlink_link_data_t* frame);
int luat_airlink_arq_command_valid(airlink_link_data_t* frame);

// 协商 (收到对端 caps 时调用)
void luat_airlink_arq_on_peer_caps(uint8_t caps);

// force_down 消费 (check_link_timeout 入口)
int  luat_airlink_arq_consume_force_down(void);

#endif /* LUAT_AIRLINK_ARQ_H */
