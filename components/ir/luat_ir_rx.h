#ifndef LUAT_IR_RX_H
#define LUAT_IR_RX_H

#include "luat_base.h"

/** 启用指定引脚的下降沿捕获。成功返回 0；失败时不得留下已启用的中断。 */
int luat_ir_capture_start(int pin);
/** 同步停止捕获。返回后中断不得再访问接收器，调用方将释放其状态。 */
void luat_ir_capture_stop(int pin);
/** 在中断中上报下降沿；now_us 是边沿发生时的单调时间戳，单位为微秒。 */
void luat_ir_rx_edge(int pin, uint64_t now_us);

int luat_ir_rx_init(lua_State *L);
int luat_ir_rx_stats(lua_State *L);
int luat_ir_rx_close(lua_State *L);

#endif
