#ifndef LUAT_IR_NEC_H
#define LUAT_IR_NEC_H

#include <stdint.h>

typedef struct {
    uint64_t last_edge_us;
    uint64_t last_key_us; /**< 最近一次有效完整帧或重复帧的时间，用于判断重复帧是否过期。 */
    uint32_t word;
    uint16_t addr;
    uint8_t cmd;
    uint8_t bits;
    uint8_t receiving;
    uint8_t have_edge;
    uint8_t have_key;
} luat_ir_nec_t;

typedef enum {
    LUAT_IR_NONE,
    LUAT_IR_KEY,
    LUAT_IR_REPEAT
} luat_ir_event_t;

/** 每个接收头独占一份清零的状态。按时间顺序传入下降沿的微秒时间戳，返回解码事件。 */
luat_ir_event_t luat_ir_nec_edge(luat_ir_nec_t *rx, uint64_t now_us);

#endif
