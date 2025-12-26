#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "luat_rtos.h"

#ifndef LUAT_NDK_MAX_RAM_SIZE
#define LUAT_NDK_MAX_RAM_SIZE (32 * 1024)
#endif

#ifndef LUAT_NDK_DEFAULT_RAM_SIZE
#define LUAT_NDK_DEFAULT_RAM_SIZE (8 * 1024)
#endif

#ifndef LUAT_NDK_DEFAULT_EXCHANGE_SIZE
#define LUAT_NDK_DEFAULT_EXCHANGE_SIZE (4 * 1024)
#endif

#define LUAT_NDK_EXCHANGE_ALIGN 4

struct MiniRV32IMAState;
typedef struct MiniRV32IMAState MiniRV32IMAState;

typedef enum {
    LUAT_NDK_OK = 0,
    LUAT_NDK_ERR_PARAM = -1,
    LUAT_NDK_ERR_NOMEM = -2,
    LUAT_NDK_ERR_IO = -3,
    LUAT_NDK_ERR_IMAGE_TOO_LARGE = -4,
    LUAT_NDK_ERR_BUSY = -5,
    LUAT_NDK_ERR_TRAP = -6,
    LUAT_NDK_ERR_TIMEOUT = -7
} luat_ndk_err_t;

typedef struct luat_ndk {
    MiniRV32IMAState *core;
    uint8_t *ram;
    size_t ram_size;
    size_t ram_limit;
    size_t image_size;
    uint8_t *image_copy;
    size_t exchange_size;
    size_t exchange_offset;
    uint32_t last_mcause;
    uint32_t last_mtval;
    uint32_t last_trap;
    uint8_t trap_pending;
    uint8_t running;
    uint8_t stop_request;
    luat_rtos_task_handle worker;
    uint32_t thread_id;
    char *image_path;
} luat_ndk_t;

int luat_ndk_init(luat_ndk_t *ndk, const char *path, size_t mem_size, size_t exchange_size);
void luat_ndk_deinit(luat_ndk_t *ndk);
int luat_ndk_reset(luat_ndk_t *ndk);
int luat_ndk_set_data(luat_ndk_t *ndk, const void *data, size_t len, size_t offset);
int luat_ndk_get_data(luat_ndk_t *ndk, void *out, size_t len, size_t offset, size_t *actual);
int luat_ndk_exec(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us, int32_t *retval);
int luat_ndk_start_thread(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us);
int luat_ndk_stop_thread(luat_ndk_t *ndk, uint32_t wait_ms);
bool luat_ndk_is_busy(luat_ndk_t *ndk);
uint32_t luat_ndk_exchange_addr(const luat_ndk_t *ndk);
