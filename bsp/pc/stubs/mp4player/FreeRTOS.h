/**
 * @file FreeRTOS.h
 * @brief PC simulator FreeRTOS compatibility shim (mp4player only).
 *
 * luatos-ext-components/mp4player/video_decode/mp4_decode.c is written for the
 * MCU builds and pulls in FreeRTOS.h / task.h / semphr.h for its mplayer glue
 * code (mplayer_mp4_thread). The PC simulator has no FreeRTOS and no
 * FreeRTOS headers, so this directory provides the minimal declarations that
 * the translation unit actually needs, mapped onto the LuatOS RTOS API
 * (luat_rtos_*), which the PC simulator does implement in port/rtos/.
 *
 * SCOPE: these headers are added to the include path ONLY when the optional
 * mp4player feature is enabled (see the mp4player block in bsp/pc/xmake.lua).
 * They must never be added globally — the file names are deliberately generic
 * and would shadow unrelated headers.
 *
 * Currently only mp4_decode.c uses FreeRTOS, and only three symbols:
 * xSemaphoreGive(), vTaskSuspend() and (legacy) soc_task_sleep_ms().
 * Extend here rather than creating new stub files if upstream starts using more.
 */

#ifndef LUATOS_PC_STUB_FREERTOS_H
#define LUATOS_PC_STUB_FREERTOS_H

#include "luat_rtos.h"

#ifdef __cplusplus
extern "C" {
#endif

/* FreeRTOS uses these typedefs in every public header; mp4player only casts
 * between void* and them, so the underlying LuatOS handle types fit as-is. */
typedef void *TaskHandle_t;
typedef void *SemaphoreHandle_t;
typedef unsigned int TickType_t;
typedef long BaseType_t;
typedef unsigned int UBaseType_t;

#define pdTRUE  1
#define pdFALSE 0
#define pdPASS  pdTRUE
#define pdFAIL  pdFALSE

/* portMAX_DELAY in FreeRTOS; LuatOS spells the same concept LUAT_RTOS_WAIT_FOREVER. */
#define portMAX_DELAY  0xFFFFFFFFU

#ifdef __cplusplus
}
#endif

#include "task.h"
#include "semphr.h"

#endif /* LUATOS_PC_STUB_FREERTOS_H */
