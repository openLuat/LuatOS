/******************************************************************************
 *  io_queue设备操作抽象层
 *****************************************************************************/
#ifndef __LUAT_IO_QUEUE_H__
#define __LUAT_IO_QUEUE_H__

#include "luat_base.h"
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif
#ifdef __LUATOS__
int l_io_queue_done_handler(lua_State *L, void* ptr);
int l_io_queue_capture_handler(lua_State *L, void* ptr);
void luat_io_queue_init(uint8_t hw_timer_id, uint32_t cmd_cnt, uint32_t repeat_cnt);
void luat_io_queue_capture_start_with_sys_tick(uint8_t pin, uint8_t pull_mode, uint8_t irq_mode);
#else
void luat_io_queue_init(uint8_t hw_timer_id, uint32_t cmd_cnt, uint32_t repeat_cnt, CBDataFun_t *cb);
void luat_io_queue_capture_start_with_sys_tick(uint8_t pin, uint8_t pull_mode, uint8_t irq_mode, CBDataFun_t *cb);
#endif
void luat_io_queue_start(uint8_t hw_timer_id);
void luat_io_queue_stop(uint8_t hw_timer_id, uint32_t *repeat_cnt, uint32_t *cmd_cnt);
void luat_io_queue_clear(uint8_t hw_timer_id);
void luat_io_queue_release(uint8_t hw_timer_id);
void luat_io_queue_set_delay(uint8_t hw_timer_id, uint16_t time, uint8_t sub_tick, uint8_t is_continue);
void luat_io_queue_repeat_delay(uint8_t hw_timer_id);
void luat_io_queue_add_io_config(uint8_t hw_timer_id, uint8_t pin, uint8_t is_input, uint8_t pull_mode, uint8_t level);
void luat_io_queue_add_io_out(uint8_t hw_timer_id, uint8_t pin, uint8_t level);
void luat_io_queue_add_io_in(uint8_t hw_timer_id, uint8_t pin, CBFuncEx_t CB, void *user_data);
void luat_io_queue_capture_set(uint8_t hw_timer_id, uint32_t max_tick, uint8_t pin, uint8_t pull_mode, uint8_t irq_mode);
void luat_io_queue_capture(uint8_t hw_timer_id, CBFuncEx_t CB, void *user_data);
void luat_io_queue_capture_end(uint8_t hw_timer_id, uint8_t pin);
void luat_io_queue_end(uint8_t hw_timer_id);
uint8_t luat_io_queue_check_done(uint8_t hw_timer_id);
int luat_io_queue_get_size(uint8_t hw_timer_id);
void luat_io_queue_get_data(uint8_t hw_timer_id, uint8_t *input_buff, uint32_t *input_cnt, uint8_t *capture_buff, uint32_t *capture_cnt);
void luat_io_queue_capture_end_with_sys_tick(uint8_t pin);
#endif
