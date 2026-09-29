/**
 * @file semphr.h
 * @brief PC simulator semphr.h shim (mp4player only). See FreeRTOS.h for scope.
 *
 * Only xSemaphoreGive() is used, by mp4_decode.c to signal its decode thread's
 * "done" semaphore. The PC simulator implements counting semaphores in
 * bsp/pc/port/rtos/luat_rtos_semaphore_pc.c, so map straight onto that.
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

/** @return 0 on success, non-zero on error (matches luat_rtos_semaphore_release). */
static inline int xSemaphoreGive(SemaphoreHandle_t semaphore_handle)
{
    return luat_rtos_semaphore_release((luat_rtos_semaphore_t)semaphore_handle);
}

#ifdef __cplusplus
}
#endif

#endif /* LUATOS_PC_STUB_SEMPHR_H */
