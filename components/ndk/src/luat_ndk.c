#include <stdlib.h>
#include <string.h>

#include "luat_mem.h"
#include "luat_fs.h"
#include "luat_rtos.h"
#include "luat_ndk.h"

#define LUAT_LOG_TAG "ndk"
#include "luat_log.h"

static void ndk_postexec(luat_ndk_t *ctx, uint32_t pc, uint32_t ir, uint32_t trap);
static void ndk_othercsr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value);
static void ndk_othercsr_read(luat_ndk_t *ctx, uint32_t csrno, uint32_t *value);
static uint32_t ndk_control_store(luat_ndk_t *ctx, uint32_t addy, uint32_t value);

// mini-rv32ima configuration
#define MINI_RV32_RAM_SIZE (ctx->ram_size)
#define MINIRV32_POSTEXEC(pc, ir, trap) ndk_postexec(ctx, pc, ir, trap)
#define MINIRV32_OTHERCSR_WRITE(csrno, value) ndk_othercsr_write(ctx, csrno, value)
#define MINIRV32_OTHERCSR_READ(csrno, value) ndk_othercsr_read(ctx, csrno, &value)
#define MINIRV32_HANDLE_MEM_STORE_CONTROL( addy, val ) if( ndk_control_store(ctx, addy, val ) ) return val;
#define MINIRV32_STEPPROTO static int32_t MiniRV32IMAStep(luat_ndk_t *ctx, struct MiniRV32IMAState *state, uint8_t *image, uint32_t vProcAddress, uint32_t elapsedUs, int count)
#define MINIRV32_IMPLEMENTATION
#include "mini-rv32ima.h"

#define NDK_DEFAULT_STEP_BUDGET 32768
#define NDK_STEP_CHUNK 256
#define NDK_DEFAULT_ELAPSED_US 100
#define NDK_MAX_LOG_STR 120

static inline bool ndk_addr_valid(luat_ndk_t *ctx, uint32_t addr, size_t len) {
    if (!ctx) return false;
    if (addr < MINIRV32_RAM_IMAGE_OFFSET) return false;
    uint64_t start = (uint64_t)(addr - MINIRV32_RAM_IMAGE_OFFSET);
    uint64_t end = start + len;
    return end <= ctx->ram_size;
}

static void ndk_log_string(luat_ndk_t *ctx, uint32_t guest_addr) {
    if (!ctx) return;
    if (!ndk_addr_valid(ctx, guest_addr, 1)) return;
    uint32_t off = guest_addr - MINIRV32_RAM_IMAGE_OFFSET;
    char tmp[NDK_MAX_LOG_STR + 1];
    size_t i = 0;
    for (; i < NDK_MAX_LOG_STR && off + i < ctx->ram_size; i++) {
        tmp[i] = (char)ctx->ram[off + i];
        if (tmp[i] == '\0') break;
    }
    tmp[i] = '\0';
    LLOGI("vm: %s", tmp);
}

static void ndk_postexec(luat_ndk_t *ctx, uint32_t pc, uint32_t ir, uint32_t trap) {
    (void)pc;
    (void)ir;
    if (!ctx || trap == 0) return;
    ctx->trap_pending = 1;
    ctx->last_trap = trap;
}

static void ndk_othercsr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value) {
    if (!ctx) return;
    switch (csrno) {
    case 0x136:
        LLOGI("vm num: %u", value);
        break;
    case 0x137:
        LLOGI("vm ptr: 0x%08X", value);
        break;
    case 0x138:
        ndk_log_string(ctx, value);
        break;
    default:
        break;
    }
}

static void ndk_othercsr_read(luat_ndk_t *ctx, uint32_t csrno, uint32_t *value) {
    if (!ctx || !value) return;
    switch (csrno) {
    case 0x139:
        *value = MINIRV32_RAM_IMAGE_OFFSET + ctx->exchange_offset;
        break;
    case 0x13A:
        *value = (uint32_t)ctx->exchange_size;
        break;
    case 0x13B:
        *value = (uint32_t)ctx->ram_size;
        break;
    default:
        *value = 0; // 未知 CSR 返回0
        break;
    }
}

static void ndk_reset_core(luat_ndk_t *ndk) {
    memset(ndk->core, 0, sizeof(MiniRV32IMAState));
    ndk->core->pc = MINIRV32_RAM_IMAGE_OFFSET;
    ndk->core->mtvec = MINIRV32_RAM_IMAGE_OFFSET;
    ndk->core->mstatus = 0x00001800; // machine mode, MPIE cleared
    ndk->core->extraflags = 3;       // machine mode
    ndk->trap_pending = 0;
    ndk->last_mcause = 0;
    ndk->last_mtval = 0;
    ndk->last_trap = 0;
}

static int ndk_reload_image(luat_ndk_t *ndk) {
    if (!ndk || !ndk->image_path) return LUAT_NDK_ERR_PARAM;
    
    FILE *fd = luat_fs_fopen(ndk->image_path, "rb");
    if (fd == NULL) {
        LLOGE("open %s fail", ndk->image_path);
        return LUAT_NDK_ERR_IO;
    }
    
    memset(ndk->ram, 0, ndk->ram_size);
    size_t readed = luat_fs_fread(ndk->ram, 1, ndk->image_size, fd);
    luat_fs_fclose(fd);
    
    if (readed != ndk->image_size) {
        LLOGE("read image %u/%u", (unsigned int)readed, (unsigned int)ndk->image_size);
        return LUAT_NDK_ERR_IO;
    }
    
    if (ndk->exchange_offset < ndk->ram_size) {
        memset(ndk->ram + ndk->exchange_offset, 0, ndk->exchange_size);
    }
    ndk_reset_core(ndk);
    return LUAT_NDK_OK;
}

static int ndk_load_image(luat_ndk_t *ndk, const char *path) {
    if (!ndk || !path) return LUAT_NDK_ERR_PARAM;
    
    size_t sz = luat_fs_fsize(path);
    if (sz == 0 || sz > ndk->exchange_offset) {
        LLOGE("image too large %u", (unsigned int)sz);
        return LUAT_NDK_ERR_IMAGE_TOO_LARGE;
    }
    ndk->image_size = sz;
    
    return ndk_reload_image(ndk);
}

static int ndk_exec_inner(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us, int32_t *retval) {
    if (!ndk || !ndk->core || !ndk->ram) return LUAT_NDK_ERR_PARAM;
    if (step_budget == 0) step_budget = NDK_DEFAULT_STEP_BUDGET;
    if (elapsed_us == 0) elapsed_us = NDK_DEFAULT_ELAPSED_US;

    int32_t ret = 0;

    ndk->trap_pending = 0;
    ndk->stop_request = 0;
    ndk->last_mcause = 0;
    ndk->last_mtval = 0;
    ndk->last_trap = 0;
    ndk->core->mcause = 0;
    ndk->core->mtval = 0;

    uint32_t left = step_budget;
    int rc = LUAT_NDK_OK;

    while (left > 0 && !ndk->trap_pending && !ndk->stop_request) {
        uint32_t chunk = left > NDK_STEP_CHUNK ? NDK_STEP_CHUNK : left;
        ret = MiniRV32IMAStep(ndk, ndk->core, ndk->ram, MINIRV32_RAM_IMAGE_OFFSET, elapsed_us, chunk);
        if (ret == 0x5555) {
            return LUAT_NDK_OK;
        }
        left -= chunk;
        if (ndk->core->mcause) break;
    }

    if (ndk->stop_request) {
        return LUAT_NDK_ERR_TIMEOUT;
    }

    ndk->last_mcause = ndk->core->mcause;
    ndk->last_mtval = ndk->core->mtval;

    if (ndk->trap_pending || ndk->last_mcause) {
        rc = LUAT_NDK_ERR_TRAP;
        if (ndk->last_mcause == 11) {
            rc = LUAT_NDK_OK;
            if (retval) *retval = (int32_t)ndk->core->regs[10];
        }
    } else if (left == 0) {
        rc = LUAT_NDK_ERR_TIMEOUT;
    }
    return rc;
}

int luat_ndk_init(luat_ndk_t *ndk, const char *path, size_t mem_size, size_t exchange_size) {
    if (!ndk || !path) return LUAT_NDK_ERR_PARAM;
    memset(ndk, 0, sizeof(luat_ndk_t));

    if (mem_size == 0) mem_size = LUAT_NDK_DEFAULT_RAM_SIZE;
    if (exchange_size == 0) exchange_size = LUAT_NDK_DEFAULT_EXCHANGE_SIZE;

    if (mem_size > LUAT_NDK_MAX_RAM_SIZE || exchange_size >= mem_size) {
        return LUAT_NDK_ERR_PARAM;
    }

    ndk->ram_size = mem_size;
    ndk->exchange_size = exchange_size;
    ndk->exchange_offset = mem_size - exchange_size;

    ndk->ram = luat_heap_malloc(ndk->ram_size);
    ndk->core = luat_heap_malloc(sizeof(MiniRV32IMAState));
    if (ndk->ram == NULL || ndk->core == NULL) {
        luat_ndk_deinit(ndk);
        return LUAT_NDK_ERR_NOMEM;
    }
    memset(ndk->ram, 0, ndk->ram_size);
    memset(ndk->core, 0, sizeof(MiniRV32IMAState));

    size_t plen = strlen(path);
    ndk->image_path = luat_heap_malloc(plen + 1);
    if (ndk->image_path == NULL) {
        luat_ndk_deinit(ndk);
        return LUAT_NDK_ERR_NOMEM;
    }
    memcpy(ndk->image_path, path, plen);
    ndk->image_path[plen] = '\0';

    int rc = ndk_load_image(ndk, path);
    if (rc != LUAT_NDK_OK) {
        luat_ndk_deinit(ndk);
        return rc;
    }

    ndk_reset_core(ndk);
    return LUAT_NDK_OK;
}

void luat_ndk_deinit(luat_ndk_t *ndk) {
    if (!ndk) return;
    ndk->stop_request = 1;
    if (ndk->worker) {
        luat_rtos_task_sleep(10);
    }
    if (ndk->ram) {
        luat_heap_free(ndk->ram);
        ndk->ram = NULL;
    }
    if (ndk->core) {
        luat_heap_free(ndk->core);
        ndk->core = NULL;
    }
    if (ndk->image_path) {
        luat_heap_free(ndk->image_path);
        ndk->image_path = NULL;
    }
    ndk->running = 0;
    ndk->worker = NULL;
}

int luat_ndk_reset(luat_ndk_t *ndk) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk->running) return LUAT_NDK_ERR_BUSY;
    if (ndk->image_path == NULL || ndk->image_size == 0) return LUAT_NDK_ERR_IO;
    return ndk_reload_image(ndk);
}

int luat_ndk_set_data(luat_ndk_t *ndk, const void *data, size_t len, size_t offset) {
    if (!ndk || !data) return LUAT_NDK_ERR_PARAM;
    if (offset >= ndk->exchange_size) return LUAT_NDK_ERR_PARAM;
    if (len > ndk->exchange_size - offset) len = ndk->exchange_size - offset;
    memcpy(ndk->ram + ndk->exchange_offset + offset, data, len);
    return (int)len;
}

int luat_ndk_get_data(luat_ndk_t *ndk, void *out, size_t len, size_t offset, size_t *actual) {
    if (!ndk || !out) return LUAT_NDK_ERR_PARAM;
    if (offset >= ndk->exchange_size) return LUAT_NDK_ERR_PARAM;
    if (len > ndk->exchange_size - offset) len = ndk->exchange_size - offset;
    memcpy(out, ndk->ram + ndk->exchange_offset + offset, len);
    if (actual) *actual = len;
    return LUAT_NDK_OK;
}

int luat_ndk_exec(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us, int32_t *retval) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk->running) return LUAT_NDK_ERR_BUSY;
    ndk->running = 1;
    int rc = ndk_exec_inner(ndk, step_budget, elapsed_us, retval);
    ndk->running = 0;
    return rc;
}

typedef struct ndk_thread_arg {
    luat_ndk_t *ctx;
    uint32_t step_budget;
    uint32_t elapsed_us;
} ndk_thread_arg_t;

static void ndk_thread_entry(void *param) {
    ndk_thread_arg_t *arg = (ndk_thread_arg_t *)param;
    if (!arg || !arg->ctx) {
        luat_heap_free(arg);
        return;
    }
    luat_rtos_task_handle handle = arg->ctx->worker;
    ndk_exec_inner(arg->ctx, arg->step_budget, arg->elapsed_us, NULL);
    arg->ctx->running = 0;
    arg->ctx->worker = NULL;
    luat_heap_free(arg);
    if (handle) {
        luat_rtos_task_delete(handle);
    }
}

int luat_ndk_start_thread(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk->running) return LUAT_NDK_ERR_BUSY;
    ndk_thread_arg_t *arg = luat_heap_malloc(sizeof(ndk_thread_arg_t));
    if (!arg) return LUAT_NDK_ERR_NOMEM;
    arg->ctx = ndk;
    arg->step_budget = step_budget;
    arg->elapsed_us = elapsed_us;
    ndk->running = 1;
    ndk->stop_request = 0;
    int rc = luat_rtos_task_create(&ndk->worker, 2048, 60, "ndk", ndk_thread_entry, arg, 0);
    if (rc) {
        ndk->running = 0;
        ndk->worker = NULL;
        luat_heap_free(arg);
        return LUAT_NDK_ERR_NOMEM;
    }
    static uint32_t g_thread_counter = 1;
    ndk->thread_id = g_thread_counter++;
    return (int)ndk->thread_id;
}

int luat_ndk_stop_thread(luat_ndk_t *ndk, uint32_t wait_ms) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (!ndk->running) return LUAT_NDK_OK;
    ndk->stop_request = 1;
    uint32_t wait_left = wait_ms;
    while (ndk->running && wait_left > 0) {
        luat_rtos_task_sleep(10);
        if (wait_left >= 10) wait_left -= 10; else wait_left = 0;
    }
    return ndk->running ? LUAT_NDK_ERR_TIMEOUT : LUAT_NDK_OK;
}

bool luat_ndk_is_busy(luat_ndk_t *ndk) {
    if (!ndk) return false;
    return ndk->running != 0;
}

uint32_t luat_ndk_exchange_addr(const luat_ndk_t *ndk) {
    if (!ndk) return 0;
    return MINIRV32_RAM_IMAGE_OFFSET + ndk->exchange_offset;
}

static uint32_t ndk_control_store(luat_ndk_t *ctx, uint32_t addy, uint32_t value) {
    if (addy == 0x11100000) {
        LLOGD("Control Store: set val to %08X", value);
        ctx->core->pc = ctx->core->pc + 4;
        return value;
    }
    LLOGD("Control Store: unknown addy %08X val %08X", addy, value);
    return 0;
}
