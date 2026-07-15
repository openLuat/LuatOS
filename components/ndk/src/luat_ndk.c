#ifdef _WIN32
#include <windows.h>
#endif
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>

#include "luat_mem.h"
#include "luat_fs.h"
#include "luat_rtos.h"
#include "luat_ndk.h"
#include "luat_ndk_host.h"
#include "luat_ndk_abi.h"

#define LUAT_LOG_TAG "ndk"
#include "luat_log.h"

static void ndk_postexec(luat_ndk_t *ctx, uint32_t pc, uint32_t ir, uint32_t trap);

static int ndk_set_isa(luat_ndk_t *ndk, const char *isa) {
    const char *selected = isa;
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (selected == NULL || selected[0] == '\0') {
        selected = LUAT_NDK_ISA_RV32IMA;
    }
    if (strcmp(selected, LUAT_NDK_ISA_RV32IMA) != 0) {
        return LUAT_NDK_ERR_PARAM;
    }
    memcpy(ndk->isa, selected, strlen(selected) + 1);
    return LUAT_NDK_OK;
}

// mini-rv32ima configuration
#define MINI_RV32_RAM_SIZE (ctx->ram_size)
#define MINIRV32_POSTEXEC(pc, ir, trap) ndk_postexec(ctx, pc, ir, trap)
#define MINIRV32_LUATOS_RV32C_PATCH 1
#define MINIRV32_GET_MISA() 0x40401105u
#define MINIRV32_OTHERCSR_WRITE(csrno, value) luat_ndk_host_othercsr_write(ctx, csrno, value)
#define MINIRV32_OTHERCSR_READ(csrno, value) luat_ndk_host_othercsr_read(ctx, csrno, &value)
#define MINIRV32_HANDLE_MEM_STORE_CONTROL( addy, val ) if( luat_ndk_host_control_store(ctx, addy, val ) ) return val;
#define MINIRV32_STEPPROTO static int32_t MiniRV32IMAStep(luat_ndk_t *ctx, struct MiniRV32IMAState *state, uint8_t *image, uint32_t vProcAddress, uint32_t elapsedUs, int count)
#define MINIRV32_IMPLEMENTATION
#include "mini-rv32ima.h"

#define NDK_STEP_BUDGET_UNLIMITED 0u
#define NDK_STEP_CHUNK 256
#define NDK_DEFAULT_ELAPSED_US 100
#define NDK_STOP_POLL_MS 10
#define NDK_DEINIT_WAIT_MS 1000

static inline bool ndk_state_active(luat_ndk_state_t state) {
    return state == LUAT_NDK_STATE_RUNNING || state == LUAT_NDK_STATE_STOPPING || state == LUAT_NDK_STATE_RESETTING;
}

static inline int ndk_lock(luat_ndk_t *ndk) {
    if (!ndk) return -1;
    luat_rtos_mutex_t lock = NULL;
    uint32_t critical = luat_rtos_entry_critical();
    if (!ndk->lock || ndk->lock_closing) {
        luat_rtos_exit_critical(critical);
        return -1;
    }
    ndk->lock_refs++;
    lock = ndk->lock;
    luat_rtos_exit_critical(critical);
    if (luat_rtos_mutex_lock(lock, LUAT_WAIT_FOREVER) != 0) {
        critical = luat_rtos_entry_critical();
        if (ndk->lock_refs) ndk->lock_refs--;
        luat_rtos_exit_critical(critical);
        return -1;
    }
    return 0;
}

static inline void ndk_unlock(luat_ndk_t *ndk) {
    if (!ndk) return;
    if (ndk->lock) {
        luat_rtos_mutex_unlock(ndk->lock);
    }
    uint32_t critical = luat_rtos_entry_critical();
    if (ndk->lock_refs) {
        ndk->lock_refs--;
    }
    luat_rtos_exit_critical(critical);
}

static void ndk_free_fields(luat_ndk_t *ndk) {
    if (!ndk) return;
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
    ndk->worker = NULL;
    ndk->thread_id = 0;
    ndk->image_size = 0;
    ndk->trap_pending = 0;
    ndk->stop_request = 0;
    ndk->isa[0] = '\0';
    ndk->state = LUAT_NDK_STATE_DEINIT;
    ndk->lock_closing = 0;
    ndk->lock_refs = 0;
    if (ndk->lock) {
        luat_rtos_mutex_delete(ndk->lock);
        ndk->lock = NULL;
    }
}

static void ndk_init_fail_cleanup(luat_ndk_t *ndk) {
    if (!ndk) return;
    ndk_free_fields(ndk);
}

static bool ndk_should_stop(luat_ndk_t *ndk) {
    bool stop = true;
    if (!ndk) return true;
    if (ndk_lock(ndk) != 0) return true;
    stop = ndk->stop_request || ndk->state == LUAT_NDK_STATE_STOPPING || ndk->state == LUAT_NDK_STATE_DEINIT;
    ndk_unlock(ndk);
    return stop;
}

static void ndk_postexec(luat_ndk_t *ctx, uint32_t pc, uint32_t ir, uint32_t trap) {
    (void)pc;
    (void)ir;
    if (!ctx || trap == 0) return;
    ctx->trap_pending = 1;
    ctx->last_trap = trap;
}

static void ndk_reset_abi_state(luat_ndk_t *ndk) {
    size_t event_bytes = 0;
    size_t slot_count = 0;

    ndk->abi_features = LUAT_NDK_FEATURE_META | LUAT_NDK_FEATURE_TIME | LUAT_NDK_FEATURE_EVENT |
        LUAT_NDK_FEATURE_GPIO | LUAT_NDK_FEATURE_UART | LUAT_NDK_FEATURE_CRYPTO;
    ndk->last_error = LUAT_NDK_HOST_ERR_NONE;

    event_bytes = (ndk->exchange_size > (LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE))
        ? (ndk->exchange_size - (LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE))
        : 0;
    slot_count = event_bytes / sizeof(luat_ndk_event_t);
    if (slot_count > 8) {
        slot_count = 8;
    }
    ndk->event_slots = (uint16_t)slot_count;
    ndk->event_head = 0;
    ndk->event_tail = 0;
    ndk->event_enabled = 0;
    luat_ndk_gpio_reset(ndk);
    luat_ndk_uart_reset(ndk);

    if (ndk->ram && ndk->exchange_offset + LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE <= ndk->ram_size) {
        luat_ndk_event_header_t *hdr = (luat_ndk_event_header_t*)(ndk->ram + ndk->exchange_offset + LUAT_NDK_EVENT_HDR_OFFSET);
        hdr->host_write = 0;
        hdr->guest_read = 0;
        hdr->slot_count = ndk->event_slots;
        hdr->overflow = 0;
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
    ndk_reset_abi_state(ndk);
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
    luat_ndk_event_reset(ndk);
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
    /* step_budget == 0 means "run until SYSCON exit, ecall, trap, or ndk.stop".
     * Use ndk.stop() as the escape hatch for long-running guests. */
    if (elapsed_us == 0) elapsed_us = NDK_DEFAULT_ELAPSED_US;

    int32_t ret = 0;

    ndk->trap_pending = 0;
    ndk->last_mcause = 0;
    ndk->last_mtval = 0;
    ndk->last_trap = 0;
    ndk->core->mcause = 0;
    ndk->core->mtval = 0;

    uint32_t left = step_budget;
    int rc = LUAT_NDK_OK;
    int unlimited = (step_budget == NDK_STEP_BUDGET_UNLIMITED);

    while ((unlimited || left > 0) && !ndk->trap_pending && !ndk_should_stop(ndk)) {
        uint32_t chunk = unlimited ? NDK_STEP_CHUNK
                                  : (left > NDK_STEP_CHUNK ? NDK_STEP_CHUNK : left);
        ret = MiniRV32IMAStep(ndk, ndk->core, ndk->ram, MINIRV32_RAM_IMAGE_OFFSET, elapsed_us, chunk);
        if (ret == 0x5555) {
            return LUAT_NDK_OK;
        }
        if (!unlimited) left -= chunk;
        if (ndk->core->mcause) break;
    }

    if (ndk_should_stop(ndk)) {
        return LUAT_NDK_ERR_TIMEOUT;
    }

    ndk->last_mcause = ndk->core->mcause;
    ndk->last_mtval = ndk->core->mtval;

    if (ndk->trap_pending || ndk->last_mcause) {
        /* Dump the full guest register file (x0..x31) + mcause + mtval
         * + mepc + mstatus + mtvec. Format mirrors a real RISC-V
         * crash dump so you can `llvm-objdump -d guest.elf` and
         * read the same `xNN` ABI names. Two rows of 8 to keep
         * within log line width. */
        const uint32_t *r = ndk->core->regs;
        LLOGE("ndk TRAP mcause=%lu mtval=0x%08lX mepc=0x%08lX",
              (unsigned long)ndk->last_mcause,
              (unsigned long)ndk->last_mtval,
              (unsigned long)ndk->core->mepc);
        LLOGE("ndk TRAP  mstatus=0x%08lX mtvec=0x%08lX extraflags=0x%08lX",
              (unsigned long)ndk->core->mstatus,
              (unsigned long)ndk->core->mtvec,
              (unsigned long)ndk->core->extraflags);
        LLOGE("ndk TRAP  x0(z)=0x%08lX  x1(ra)=0x%08lX  x2(sp)=0x%08lX  x3(gp)=0x%08lX",
              (unsigned long)r[0], (unsigned long)r[1],
              (unsigned long)r[2], (unsigned long)r[3]);
        LLOGE("ndk TRAP  x4(tp)=0x%08lX  x5(t0)=0x%08lX  x6(t1)=0x%08lX  x7(t2)=0x%08lX",
              (unsigned long)r[4], (unsigned long)r[5],
              (unsigned long)r[6], (unsigned long)r[7]);
        LLOGE("ndk TRAP  x8(s0)=0x%08lX  x9(s1)=0x%08lX x10(a0)=0x%08lX x11(a1)=0x%08lX",
              (unsigned long)r[8], (unsigned long)r[9],
              (unsigned long)r[10], (unsigned long)r[11]);
        LLOGE("ndk TRAP x12(a2)=0x%08lX x13(a3)=0x%08lX x14(a4)=0x%08lX x15(a5)=0x%08lX",
              (unsigned long)r[12], (unsigned long)r[13],
              (unsigned long)r[14], (unsigned long)r[15]);
        LLOGE("ndk TRAP x16(a6)=0x%08lX x17(a7)=0x%08lX x18(s2)=0x%08lX x19(s3)=0x%08lX",
              (unsigned long)r[16], (unsigned long)r[17],
              (unsigned long)r[18], (unsigned long)r[19]);
        LLOGE("ndk TRAP x20(s4)=0x%08lX x21(s5)=0x%08lX x22(s6)=0x%08lX x23(s7)=0x%08lX",
              (unsigned long)r[20], (unsigned long)r[21],
              (unsigned long)r[22], (unsigned long)r[23]);
        LLOGE("ndk TRAP x24(s8)=0x%08lX x25(s9)=0x%08lX x26(s10)=0x%08lX x27(s11)=0x%08lX",
              (unsigned long)r[24], (unsigned long)r[25],
              (unsigned long)r[26], (unsigned long)r[27]);
        LLOGE("ndk TRAP x28(t3)=0x%08lX x29(t4)=0x%08lX x30(t5)=0x%08lX x31(t6)=0x%08lX",
              (unsigned long)r[28], (unsigned long)r[29],
              (unsigned long)r[30], (unsigned long)r[31]);
        rc = LUAT_NDK_ERR_TRAP;
        if (ndk->last_mcause == 11) {
            rc = LUAT_NDK_OK;
            if (retval) *retval = (int32_t)ndk->core->regs[10];
        }
    } else if (!unlimited && left == 0) {
        rc = LUAT_NDK_ERR_TIMEOUT;
    }
    return rc;
}

int luat_ndk_init(luat_ndk_t *ndk, const char *path, size_t mem_size, size_t exchange_size, const char *isa) {
    if (!ndk || !path) return LUAT_NDK_ERR_PARAM;
    memset(ndk, 0, sizeof(luat_ndk_t));
    ndk->state = LUAT_NDK_STATE_DEINIT;
    if (luat_rtos_mutex_create(&ndk->lock) != 0 || !ndk->lock) {
        ndk->lock = NULL;
        return LUAT_NDK_ERR_NOMEM;
    }
    ndk->state = LUAT_NDK_STATE_IDLE;
    ndk->stop_request = 0;
    ndk->lock_closing = 0;
    ndk->lock_refs = 0;

    if (mem_size == 0) mem_size = LUAT_NDK_DEFAULT_RAM_SIZE;
    if (exchange_size == 0) exchange_size = LUAT_NDK_DEFAULT_EXCHANGE_SIZE;

    if (mem_size > LUAT_NDK_MAX_RAM_SIZE || exchange_size >= mem_size) {
        ndk_init_fail_cleanup(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    int rc = ndk_set_isa(ndk, isa);
    if (rc != LUAT_NDK_OK) {
        ndk_init_fail_cleanup(ndk);
        return rc;
    }

    ndk->ram_size = mem_size;
    ndk->exchange_size = exchange_size;
    ndk->exchange_offset = mem_size - exchange_size;

    ndk->ram = luat_heap_malloc(ndk->ram_size);
    ndk->core = luat_heap_malloc(sizeof(MiniRV32IMAState));
    if (ndk->ram == NULL || ndk->core == NULL) {
        ndk_init_fail_cleanup(ndk);
        return LUAT_NDK_ERR_NOMEM;
    }
    memset(ndk->ram, 0, ndk->ram_size);
    memset(ndk->core, 0, sizeof(MiniRV32IMAState));

    size_t plen = strlen(path);
    ndk->image_path = luat_heap_malloc(plen + 1);
    if (ndk->image_path == NULL) {
        ndk_init_fail_cleanup(ndk);
        return LUAT_NDK_ERR_NOMEM;
    }
    memcpy(ndk->image_path, path, plen);
    ndk->image_path[plen] = '\0';

    rc = ndk_load_image(ndk, path);
    if (rc != LUAT_NDK_OK) {
        ndk_init_fail_cleanup(ndk);
        return rc;
    }

    ndk_reset_core(ndk);

    return LUAT_NDK_OK;
}

void luat_ndk_deinit(luat_ndk_t *ndk) {
    if (!ndk) return;
    uint32_t critical = luat_rtos_entry_critical();
    bool deinit_in_progress = ndk->lock && ndk->lock_closing;
    luat_rtos_exit_critical(critical);
    if (deinit_in_progress) {
        uint32_t wait_left = NDK_DEINIT_WAIT_MS;
        while (wait_left > 0) {
            luat_rtos_task_sleep(NDK_STOP_POLL_MS);
            if (wait_left >= NDK_STOP_POLL_MS) wait_left -= NDK_STOP_POLL_MS;
            else wait_left = 0;
            critical = luat_rtos_entry_critical();
            bool done = ndk->lock == NULL;
            luat_rtos_exit_critical(critical);
            if (done) return;
        }
        return;
    }

    if (!ndk->lock) {
        luat_ndk_gpio_reset(ndk);
        luat_ndk_uart_reset(ndk);
        ndk_free_fields(ndk);
        return;
    }

    int stop_rc = luat_ndk_stop_thread(ndk, NDK_DEINIT_WAIT_MS);
    if (stop_rc == LUAT_NDK_ERR_TIMEOUT) {
        LLOGE("deinit timeout waiting worker");
        return;
    }

    if (ndk_lock(ndk) != 0) return;
    luat_ndk_gpio_reset(ndk);
    luat_ndk_uart_reset(ndk);
    uint8_t *ram = ndk->ram;
    MiniRV32IMAState *core = ndk->core;
    char *image_path = ndk->image_path;
    ndk->ram = NULL;
    ndk->core = NULL;
    ndk->image_path = NULL;
    ndk->worker = NULL;
    ndk->state = LUAT_NDK_STATE_DEINIT;
    ndk->stop_request = 0;
    ndk->trap_pending = 0;
    ndk->image_size = 0;
    ndk->thread_id = 0;
    ndk->isa[0] = '\0';
    ndk->lock_closing = 1;
    ndk_unlock(ndk);

    uint32_t wait_left = NDK_DEINIT_WAIT_MS;
    while (wait_left > 0) {
        critical = luat_rtos_entry_critical();
        uint32_t lock_refs = ndk->lock_refs;
        luat_rtos_exit_critical(critical);
        if (lock_refs == 0) break;
        luat_rtos_task_sleep(NDK_STOP_POLL_MS);
        if (wait_left >= NDK_STOP_POLL_MS) {
            wait_left -= NDK_STOP_POLL_MS;
        } else {
            wait_left = 0;
        }
    }
    critical = luat_rtos_entry_critical();
    luat_rtos_mutex_t lock = (ndk->lock_refs == 0) ? ndk->lock : NULL;
    if (lock) {
        ndk->lock = NULL;
    }
    luat_rtos_exit_critical(critical);
    if (lock) {
        luat_rtos_mutex_delete(lock);
    }
    else {
        LLOGE("deinit timeout waiting lock refs");
    }

    if (ram) {
        luat_heap_free(ram);
    }
    if (core) {
        luat_heap_free(core);
    }
    if (image_path) {
        luat_heap_free(image_path);
    }
}

int luat_ndk_reset(luat_ndk_t *ndk) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk_state_active(ndk->state) || ndk->worker != NULL) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_BUSY;
    }
    if (ndk->state == LUAT_NDK_STATE_DEINIT || ndk->image_path == NULL || ndk->image_size == 0 || !ndk->ram || !ndk->core) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_IO;
    }

    ndk->state = LUAT_NDK_STATE_RESETTING;
    int rc = ndk_reload_image(ndk);
    if (ndk->state == LUAT_NDK_STATE_RESETTING) {
        ndk->state = LUAT_NDK_STATE_IDLE;
    }
    ndk_unlock(ndk);
    return rc;
}

int luat_ndk_set_data(luat_ndk_t *ndk, const void *data, size_t len, size_t offset) {
    if (!ndk || !data) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state == LUAT_NDK_STATE_DEINIT || !ndk->ram) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    if (offset >= ndk->exchange_size) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    if (len > ndk->exchange_size - offset) len = ndk->exchange_size - offset;
    memcpy(ndk->ram + ndk->exchange_offset + offset, data, len);
    ndk_unlock(ndk);
    return (int)len;
}

int luat_ndk_get_data(luat_ndk_t *ndk, void *out, size_t len, size_t offset, size_t *actual) {
    if (!ndk || !out) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state == LUAT_NDK_STATE_DEINIT || !ndk->ram) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    if (offset >= ndk->exchange_size) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_PARAM;
    }
    if (len > ndk->exchange_size - offset) len = ndk->exchange_size - offset;
    memcpy(out, ndk->ram + ndk->exchange_offset + offset, len);
    if (actual) *actual = len;
    ndk_unlock(ndk);
    return LUAT_NDK_OK;
}

int luat_ndk_exec(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us, int32_t *retval) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state != LUAT_NDK_STATE_IDLE || ndk->worker != NULL) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_BUSY;
    }
    ndk->state = LUAT_NDK_STATE_RUNNING;
    ndk->stop_request = 0;
    ndk_unlock(ndk);
    int rc = ndk_exec_inner(ndk, step_budget, elapsed_us, retval);
    if (ndk_lock(ndk) == 0) {
        if (ndk->state != LUAT_NDK_STATE_DEINIT) {
            ndk->state = LUAT_NDK_STATE_IDLE;
        }
        ndk->stop_request = 0;
        ndk_unlock(ndk);
    }
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
    luat_ndk_t *ctx = arg->ctx;
    luat_rtos_task_handle handle = NULL;
    if (ndk_lock(ctx) == 0) {
        handle = ctx->worker;
        ndk_unlock(ctx);
    }
    ndk_exec_inner(ctx, arg->step_budget, arg->elapsed_us, NULL);
    if (ndk_lock(ctx) == 0) {
        ctx->worker = NULL;
        if (ctx->state != LUAT_NDK_STATE_DEINIT) {
            ctx->state = LUAT_NDK_STATE_IDLE;
            ctx->stop_request = 0;
        }
        ndk_unlock(ctx);
    }
    luat_heap_free(arg);
    if (handle) {
        luat_rtos_task_delete(handle);
    }
}

int luat_ndk_start_thread(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state != LUAT_NDK_STATE_IDLE || ndk->worker != NULL) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_BUSY;
    }
    ndk_thread_arg_t *arg = luat_heap_malloc(sizeof(ndk_thread_arg_t));
    if (!arg) {
        ndk_unlock(ndk);
        return LUAT_NDK_ERR_NOMEM;
    }
    arg->ctx = ndk;
    arg->step_budget = step_budget;
    arg->elapsed_us = elapsed_us;
    ndk->state = LUAT_NDK_STATE_RUNNING;
    ndk->stop_request = 0;
    int rc = luat_rtos_task_create(&ndk->worker, 2048, 60, "ndk", ndk_thread_entry, arg, 0);
    if (rc) {
        ndk->state = LUAT_NDK_STATE_IDLE;
        ndk->worker = NULL;
        ndk_unlock(ndk);
        luat_heap_free(arg);
        return LUAT_NDK_ERR_NOMEM;
    }
    static volatile atomic_uint_least32_t g_thread_counter = 0;
    ndk->thread_id = (uint32_t)atomic_fetch_add(&g_thread_counter, 1) + 1u;
    uint32_t tid = ndk->thread_id;
    ndk_unlock(ndk);
    return (int)tid;
}

int luat_ndk_stop_thread(luat_ndk_t *ndk, uint32_t wait_ms) {
    if (!ndk) return LUAT_NDK_ERR_PARAM;
    if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_PARAM;
    if (ndk->state == LUAT_NDK_STATE_DEINIT || (ndk->state == LUAT_NDK_STATE_IDLE && ndk->worker == NULL)) {
        ndk_unlock(ndk);
        return LUAT_NDK_OK;
    }
    if (ndk->state == LUAT_NDK_STATE_RUNNING) {
        ndk->state = LUAT_NDK_STATE_STOPPING;
    }
    ndk->stop_request = 1;
    ndk_unlock(ndk);

    uint32_t wait_left = wait_ms;
    while (wait_left > 0) {
        luat_rtos_task_sleep(NDK_STOP_POLL_MS);
        if (wait_left >= NDK_STOP_POLL_MS) {
            wait_left -= NDK_STOP_POLL_MS;
        } else {
            wait_left = 0;
        }
        if (ndk_lock(ndk) != 0) return LUAT_NDK_ERR_TIMEOUT;
        bool done = (ndk->state == LUAT_NDK_STATE_DEINIT) || (ndk->state == LUAT_NDK_STATE_IDLE && ndk->worker == NULL);
        if (done) {
            ndk->stop_request = 0;
            ndk_unlock(ndk);
            return LUAT_NDK_OK;
        }
        ndk_unlock(ndk);
    }

    return LUAT_NDK_ERR_TIMEOUT;
}

bool luat_ndk_is_busy(luat_ndk_t *ndk) {
    if (!ndk) return false;
    if (ndk_lock(ndk) != 0) return true;
    bool busy = ndk_state_active(ndk->state) || ndk->worker != NULL;
    ndk_unlock(ndk);
    return busy;
}

uint32_t luat_ndk_exchange_addr(const luat_ndk_t *ndk) {
    if (!ndk) return 0;
    return MINIRV32_RAM_IMAGE_OFFSET + ndk->exchange_offset;
}
