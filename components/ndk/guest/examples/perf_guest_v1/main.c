/*
 * perf_guest_v1 main.c — dispatcher for the NDK guest-implementation perf
 * test suite.
 *
 * Protocol: see perf_proto.h. The host writes req[0..3] (algo_id /
 * input_len / input_offset / control) and the payload into the exchange
 * buffer. The guest:
 *   1. Reads the req header.
 *   2. Validates bounds (in particular: in + in_len and out + out_cap
 *      must lie within ndk_memory_size()).
 *   3. Resolves the algo via perf_algo_get(algo_id).
 *   4. Calls perf_<algo>_run(...).
 *   5. Writes result[0] = status, result[1] = output_len.
 *   6. If PERF_CTRL_LAST_CHUNK is set, also writes result[2..3] = elapsed_us.
 *   7. Exits via SYSCON 0x5555.
 *
 * Timing: the guest samples CSR 0x141 / 0x142 (ndk_time_us_lo/hi) around
 * the algo call. This is the ONLY host-ABI call used (the MD5/CRC32
 * host-CSR shortcuts are explicitly FORBIDDEN — see perf_proto.h).
 */
#include "luat_ndk_helper.h"
#include "perf_proto.h"

#include <stdint.h>
#include <stddef.h>

/* NDK entry point: hand-rolled _start (not NDK_GUEST_START macro).
 *
 * Reason: NDK_GUEST_START relies on LLD placing the noreturn
 * function first in .text, but if any function is defined before
 * main() in the source, the linker puts main() at 0x80000000
 * and the simulator's reset vector runs main() with sp=0 →
 * mcause=7 / mtval=0xFFFFFFFC. Hand-rolling _start + defining
 * it first in this file guarantees the link order we need.
 *
 * `naked` is required: without it the compiler emits a function
 * prologue (`addi sp, sp, -N; sw ra, offset(sp)`) that runs
 * BEFORE the body — including before we set sp from CSR 0x13B.
 * The host ndk_reset_core() memsets all 32 GPRs to 0, so sp=0 at
 * entry; the prologue's `addi sp, sp, -0x10` produces sp=0xFFFFFFF0
 * and the very first `sw ra, 0xc(sp)` traps with
 * mcause=7 / mtval=0xFFFFFFFC. Marking _start `naked` and
 * initialising sp via inline asm before any store is the same
 * pattern NDK_GUEST_START uses. (hello_world uses this exact pattern;
 * see examples/hello_world/main.c.) */
extern int main(void);

__attribute__((naked, noreturn)) void _start(void) {
    __asm__ volatile(
        ".option norvc\n"
        "csrr t0, 0x13B\n"        /* t0 = memory_size */
        "li   t1, 0x80000000\n"
        "add  t0, t0, t1\n"
        "addi sp, t0, -16\n"      /* sp = RAM_BASE + mem_size - 16 */
        "addi sp, sp, -16\n"      /* leave room for a 16-byte red zone at top */
        "mv   t0, %0\n"
        "jalr ra, t0\n"           /* call main; ra = wfi park loop */
        "1: wfi\n"
        "j   1b\n"
        :: "r"(main)
    );
}

/* Resolves an algo_id to its run function. Returns NULL on unknown id. */
perf_algo_fn perf_algo_get(uint32_t algo_id) {
    switch (algo_id) {
        case PERF_ALGO_FNV1A_32:     return perf_fnv1a_run;
        case PERF_ALGO_CRC32_IEEE:   return perf_crc32_run;
        case PERF_ALGO_BASE64_ENC:   return perf_base64_run;
        case PERF_ALGO_MD5:          return perf_md5_run;
        case PERF_ALGO_HEAPSORT_I32: return perf_heapsort_run;
        default:                     return (perf_algo_fn)0;
    }
}

/* noinline wrapper around the function pointer call.
 *
 * We avoid the function pointer dispatch entirely and call each algo
 * directly via an if-else chain. Function pointers trigger aggressive
 * tail-call / inlining decisions by clang -Os that the NDK simulator
 * (which expects standard RISC-V call/return) cannot always handle.
 * The direct call forces a real `call algo / ret` pair. */
static uint32_t run_algo(uint32_t algo_id, const uint8_t *in, uint32_t in_len,
                         uint8_t *out, uint32_t *out_len,
                         uint32_t *elapsed_lo, uint32_t *elapsed_hi) {
    if (algo_id == PERF_ALGO_FNV1A_32) {
        return perf_fnv1a_run(in, in_len, out, out_len, elapsed_lo, elapsed_hi);
    }
    if (algo_id == PERF_ALGO_CRC32_IEEE) {
        return perf_crc32_run(in, in_len, out, out_len, elapsed_lo, elapsed_hi);
    }
    if (algo_id == PERF_ALGO_BASE64_ENC) {
        return perf_base64_run(in, in_len, out, out_len, elapsed_lo, elapsed_hi);
    }
    if (algo_id == PERF_ALGO_MD5) {
        return perf_md5_run(in, in_len, out, out_len, elapsed_lo, elapsed_hi);
    }
    if (algo_id == PERF_ALGO_HEAPSORT_I32) {
        return perf_heapsort_run(in, in_len, out, out_len, elapsed_lo, elapsed_hi);
    }
    return PERF_STATUS_UNSUPPORTED;
}

int main(void) {
    ndk_lprint("M0\n");
    volatile uint32_t *req   = (volatile uint32_t *)ndk_exchange_ptr();
    volatile uint32_t *out   = req + 4;       /* result region starts at +16 */
    ndk_lprint("M1\n");

    uint32_t algo_id        = req[0];
    uint32_t input_len      = req[1];
    uint32_t input_offset   = req[2];
    uint32_t control        = req[3];

    /* Sanity-check the request. The CRITICAL bound here is the EXCHANGE
     * BUFFER size, not the total guest RAM — anything outside the
     * exchange buffer is guest stack / data that the host does NOT
     * initialise, and writing to it triggers mcause=7 (store access
     * fault). */
    uint32_t exch_size = ndk_exchange_size();
    if (input_offset >= exch_size) {
        out[0] = PERF_STATUS_BAD_ARG;
        out[1] = 0u;
        ndk_exit_ok();
        return 0;
    }
    /* Cap input_len to the chunk budget and to what fits in the
     * exchange buffer after input_offset. */
    uint32_t max_in = exch_size - input_offset;
    if (input_len > max_in) input_len = max_in;
    if (input_len > PERF_MAX_CHUNK) input_len = PERF_MAX_CHUNK;

    const volatile uint8_t *in_ptr = ndk_exchange_ptr() + input_offset;
    uint8_t                *out_ptr = (uint8_t *)in_ptr + input_len;
    uint32_t                out_cap = (max_in >= input_len)
                                       ? (max_in - input_len)
                                       : 0u;

    /* Resolve the algo. If unknown, fail fast with a clear status. */
    perf_algo_fn run = perf_algo_get(algo_id);
    if (run == (perf_algo_fn)0) {
        out[0] = PERF_STATUS_UNSUPPORTED;
        out[1] = 0u;
        if (control & PERF_CTRL_LAST_CHUNK) {
            out[2] = 0u;  /* elapsed_us_lo */
            out[3] = 0u;  /* elapsed_us_hi */
        }
        ndk_exit_ok();
        return 0;
    }

    /* Run the algo. The algo itself does the timing measurement (so the
     * measurement is local to the work and skips any dispatcher overhead
     * that would be the same for all algos). */
    uint32_t produced   = 0u;
    uint32_t elapsed_lo = 0u;
    uint32_t elapsed_hi = 0u;
    uint32_t status = run_algo(algo_id, (const uint8_t *)in_ptr, input_len,
                               out_ptr, &produced, &elapsed_lo, &elapsed_hi);

    /* Commit the result. If the algo claimed to produce more than
     * out_cap, truncate and downgrade to BAD_BOUNDS. */
    if (produced > out_cap) {
        produced = out_cap;
        if (status == PERF_STATUS_OK) status = PERF_STATUS_BAD_BOUNDS;
    }

    out[0] = status;
    out[1] = produced;

    /* Only commit elapsed time on the last chunk — the host asked for it
     * by setting PERF_CTRL_LAST_CHUNK. */
    if (control & PERF_CTRL_LAST_CHUNK) {
        out[2] = elapsed_lo;
        out[3] = elapsed_hi;
    } else {
        /* Tell the host we deliberately held back the timing. */
        out[0] = PERF_STATUS_NOT_LAST_CHUNK;
    }

    ndk_exit_ok();
    return 0;
}
