#ifndef LUAT_AIRLINK_ARQ_H
#define LUAT_AIRLINK_ARQ_H
#include "luat_airlink.h"

// UART reliability is carried by cmd 0x33, never by flags or link pkgid.
#define AIRLINK_CMD_ARQ       0x33
#define AIRLINK_ARQ_META_SIZE 20
#define AIRLINK_ARQ_HELLO_SIZE 16
#define AIRLINK_ARQ_MAX_DATA  1556 // 1600 - link(16) - outer cmd(4) - meta(20) - inner cmd(4)
#define ARQ_RTO_MS           60
#define ARQ_GIVEUP_MS        3000
enum { ARQ_STATE_LEGACY = 0, ARQ_STATE_ARQ = 1, ARQ_STATE_NEGOTIATING = 2 };
enum { ARQ_RX_DELIVER = 0, ARQ_RX_DUP = 1 };

void luat_airlink_arq_init(void);
void luat_airlink_arq_stop(void);
void luat_airlink_arq_check_giveup(uint64_t now);
int luat_airlink_arq_state(void);
int luat_airlink_arq_take_need_ack(void);
uint16_t luat_airlink_arq_peek_ack(void);
uint16_t luat_airlink_arq_get_peer_ack(void);
int luat_airlink_arq_peer_mem_high(void);
int luat_airlink_arq_pending_active(void);
luat_airlink_cmd_t* luat_airlink_arq_pending_cmd(void);
uint16_t luat_airlink_arq_pending_seq(void);
uint64_t luat_airlink_arq_pending_sent_ms(void);
// Ownership transfers only on success; rejects invalid sizes/state before pending.
int luat_airlink_arq_pending_set(luat_airlink_cmd_t* cmd, uint64_t now);
void luat_airlink_arq_pending_retransmit(uint64_t now);
int luat_airlink_arq_pending_try_ack(void);
int luat_airlink_arq_devinfo_pending(void);
void luat_airlink_arq_set_devinfo_pending(int v);
uint64_t luat_airlink_arq_last_devinfo_ms(void);
void luat_airlink_arq_set_last_devinfo_ms(uint64_t now);
void luat_airlink_arq_put_peer(uint16_t ack);
void luat_airlink_arq_set_peer_mem_high(uint8_t v);
int luat_airlink_arq_rx(uint16_t seq);
void luat_airlink_arq_rx_commit(uint16_t seq);
int luat_airlink_arq_consume_force_down(void);

size_t luat_airlink_arq_devinfo(uint8_t* dst, const luat_airlink_dev_info_t* info);
int luat_airlink_arq_peer_info(const luat_airlink_cmd_t* cmd);
int luat_airlink_arq_command_valid(airlink_link_data_t* frame);
// Builds a complete normal AirLink frame; inner=NULL builds ACK-only.
// Zero means invalid state/size; it is checked before writing the destination.
size_t luat_airlink_arq_pack(uint8_t* dst, size_t capacity, const luat_airlink_cmd_t* inner, uint16_t seq);
// UART-only: validate/decode before dispatch. Reserved/unknown envelopes are
// consumed here and never reach application handlers. Acceptance commits ACK.
int luat_airlink_arq_receive(airlink_link_data_t* frame);
#endif
