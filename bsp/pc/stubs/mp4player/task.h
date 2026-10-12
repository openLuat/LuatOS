/**
 * @file task.h
 * @brief PC simulator task.h shim (mp4player only). See FreeRTOS.h for scope.
 *
 * mp4_decode.c only needs two things from FreeRTOS' task API:
 *   - vTaskSuspend() to park its decode thread forever after the thread body
 *     returns (MCU builds keep the task alive but idle),
 *   - soc_task_sleep_ms(), a legacy LuatOS name that current LuatOS no longer
 *     provides anywhere (renamed to luat_rtos_task_sleep()).
 */

#ifndef LUATOS_PC_STUB_TASK_H
#define LUATOS_PC_STUB_TASK_H

#include "luat_rtos.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef TaskHandle_t
typedef void *TaskHandle_t;
#endif
#ifndef TickType_t
typedef unsigned int TickType_t;
#endif

/**
 * LuatOS tasks are coroutines that terminate when their entry function returns,
 * so "suspend self forever" degenerates to "return". bsp/pc/port/rtos does not
 * implement luat_rtos_task_suspend(), hence the no-op.
 */
static inline void vTaskSuspend(TaskHandle_t task_handle)
{
    (void)task_handle;
}

/* Legacy LuatOS name used by luatos-ext-components; kept as an alias so that
 * PC does not need a separate definition in a stub .c file. */
static inline void soc_task_sleep_ms(uint32_t ms)
{
    luat_rtos_task_sleep(ms);
}

#ifdef __cplusplus
}
#endif

#endif /* LUATOS_PC_STUB_TASK_H */
