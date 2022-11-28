#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/timers.h"

/**
 * @brief 创建软件定时器
 * 
 * @param timer_handle[OUT] 返回定时器句柄
 * @return int =0成功，其他失败
 */
int luat_rtos_timer_create(luat_rtos_timer_t *timer_handle) {
    timer_handle = luat_heap_malloc(sizeof(TimerHandle_t));
    if (timer_handle == NULL)
        return -1;
    return 0;
}

/**
 * @brief 删除软件定时器
 * 
 * @param timer_handle 定时器句柄
 * @return int =0成功，其他失败
 */
int luat_rtos_timer_delete(luat_rtos_timer_t timer_handle);

/**
 * @brief 启动软件定时器
 * 
 * @param timer_handle 定时器句柄
 * @param timeout 超时时间，单位ms，没有特殊值
 * @param repeat 0不重复，其他重复
 * @param callback_fun 定时时间到后的回调函数
 * @param user_param 回调函数时的最后一个输入参数
 * @return int =0成功，其他失败
 */
int luat_rtos_timer_start(luat_rtos_timer_t timer_handle, uint32_t timeout, uint8_t repeat, luat_rtos_timer_callback_t callback_fun, void *user_param);

/**
 * @brief 停止软件定时器
 * 
 * @param timer_handle 定时器句柄
 * @return int =0成功，其他失败
 */
int luat_rtos_timer_stop(luat_rtos_timer_t timer_handle);
/*------------------------------------------------ timer   end----------------------------------------------- */
/** @}*/