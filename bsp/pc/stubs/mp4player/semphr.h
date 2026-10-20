/**
 * @file semphr.h
 * @brief PC simulator semphr.h shim (mp4player only). See FreeRTOS.h for scope.
 *
 * Two callers need it:
 *   - mp4player/video_decode/mp4_decode.c: only xSemaphoreGive(), to signal its
 *     decode thread's "done" semaphore.
 *   - components/mplayer/src/luat_mplayer.c: the small set it needs to park a
 *     blocking render thread and to wait for decode-thread exit --
 *     xSemaphoreCreateBinary(), xSemaphoreTake(timeout), vSemaphoreDelete()
 *     and pdMS_TO_TICKS().
 * The PC simulator implements counting semaphores in
 * bsp/pc/port/rtos/luat_rtos_semaphore_pc.c, so both callers map straight onto it.
 */

#ifndef LUATOS_PC_STUB_SEMPHR_H
#define LUATOS_PC_STUB_SEMPHR_H

#include "luat_rtos.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef SemaphoreHandle_t
typedef void *SemaphoreHandle_t;
#endif
#ifndef TickType_t
typedef unsigned int TickType_t;
#endif
#ifndef pdTRUE
#define pdTRUE  1
#endif
#ifndef pdFALSE
#define pdFALSE 0
#endif

/**
 * FreeRTOS ticks are milliseconds at the default tick rate (portTICK_PERIOD_MS == 1)
 * and LuatOS timeouts are milliseconds as well, so this is an identity mapping.
 */
#define pdMS_TO_TICKS(ms) ((TickType_t)(ms))

/** @return 0 on success, non-zero on error (matches luat_rtos_semaphore_release). */
static inline int xSemaphoreGive(SemaphoreHandle_t semaphore_handle)
{
    return luat_rtos_semaphore_release((luat_rtos_semaphore_t)semaphore_handle);
}

/** @return an empty (initial count 0) binary semaphore, or NULL if the RTOS refused. */
static inline SemaphoreHandle_t xSemaphoreCreateBinary(void)
{
    luat_rtos_semaphore_t semaphore_handle = NULL;

    if (luat_rtos_semaphore_create(&semaphore_handle, 0) != 0) {
        return NULL;
    }
    return (SemaphoreHandle_t)semaphore_handle;
}

/**
 * @param timeout_ticks pdMS_TO_TICKS() result, i.e. milliseconds; portMAX_DELAY
 *                      (0xFFFFFFFF) waits forever.
 * @return pdTRUE when the semaphore was taken, pdFALSE on timeout.
 */
static inline int xSemaphoreTake(SemaphoreHandle_t semaphore_handle, TickType_t timeout_ticks)
{
    return luat_rtos_semaphore_take((luat_rtos_semaphore_t)semaphore_handle,
                                    (uint32_t)timeout_ticks) == 0 ? pdTRUE : pdFALSE;
}

static inline void vSemaphoreDelete(SemaphoreHandle_t semaphore_handle)
{
    luat_rtos_semaphore_delete((luat_rtos_semaphore_t)semaphore_handle);
}

#ifdef __cplusplus
}
#endif

#endif /* LUATOS_PC_STUB_SEMPHR_H */
