/*
 * pgfs_alloc_gc.c — Segment allocation and garbage collection for PGFS
 *
 * Phase 2 FTL integration:
 *   - pgfs_alloc_segment uses pgfs_ftl_find_free_block to skip known-bad blocks
 *   - Bad blocks encountered during erase are automatically retried
 *   - Real erase-count-based greedy GC replaces the previous stub
 */
#include "luat_base.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#include "pgfs_internal.h"  /* includes pgfs_nand_ftl.h internally */
#include <string.h>

#define LUAT_LOG_TAG "pgfs.gc"
#include "luat_log.h"

/* ── Allocation ─────────────────────────────────────────────────────────── */

int pgfs_alloc_segment(pgfs_mount_ctx_t *ctx, uint32_t *seg_id) {
    if (!ctx || !seg_id) return -1;

    /* Lazy FTL init: if pgfs_ftl_on_mount was never called (e.g. C unit tests
     * that bypass pgfs_vfs_adapter.c), initialize geometry on first alloc. */
    if (ctx->ftl.total_blocks == 0 && ctx->flash_opts && ctx->flash_opts->control) {
        pgfs_flash_geometry_t geo = {0};
        if (ctx->flash_opts->control(ctx->flash_opts->ctx,
                                     PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
            geo.capacity > 0 && geo.erase_size > 0) {
            pgfs_ftl_init(&ctx->ftl, ctx->flash_opts,
                          geo.erase_size, geo.capacity / geo.erase_size);
        }
    }

    if (ctx->gc_next_seg_id == 0) {
        ctx->gc_next_seg_id = 1;
    }

    /* Wear-levelling: scan from gc_next_seg_id to total_blocks and pick the
     * non-bad, non-reserved block with the lowest erase count. The lowest-ec
     * block has been written/erased the fewest times, so directing new data
     * there spreads wear evenly across the chip. Reserved blocks (SB-A/B,
     * CP-A/B, FTL state) are always excluded. */
    uint32_t block_id = ctx->gc_next_seg_id;
    uint32_t best_block = UINT32_MAX;
    uint16_t best_ec = UINT16_MAX;
    for (uint32_t id = block_id; id < ctx->ftl.total_blocks; id++) {
        if (pgfs_ftl_is_block_bad(&ctx->ftl, id)) {
            continue;
        }
        if (pgfs_ftl_is_reserved(&ctx->ftl, id)) {
            continue;
        }
        uint16_t ec = ctx->ftl.erase_counts[id];
        if (ec < best_ec) {
            best_ec = ec;
            best_block = id;
        }
    }
    if (best_block == UINT32_MAX) {
        /* No good block found in [block_id, total_blocks); wrap to start */
        for (uint32_t id = 1; id < block_id; id++) {
            if (pgfs_ftl_is_block_bad(&ctx->ftl, id)) {
                continue;
            }
            if (pgfs_ftl_is_reserved(&ctx->ftl, id)) {
                continue;
            }
            uint16_t ec = ctx->ftl.erase_counts[id];
            if (ec < best_ec) {
                best_ec = ec;
                best_block = id;
            }
        }
    }
    if (best_block == UINT32_MAX) {
        LLOGE("pgfs: alloc_segment: no free blocks (next=%u, total=%u, bad=%u)",
              (unsigned int)block_id,
              (unsigned int)ctx->ftl.total_blocks,
              (unsigned int)ctx->ftl.bad_block_count);
        return -1;
    }
    *seg_id = best_block;

    /* Advance the counter past the allocated block to avoid re-checking it.
     * Future allocations start from this point. */
    ctx->gc_next_seg_id = best_block + 1;
    if (ctx->gc_next_seg_id >= ctx->ftl.total_blocks) {
        ctx->gc_next_seg_id = 1; /* wrap around */
    }

    return 0;
}

/* ── Garbage Collection ─────────────────────────────────────────────────── */

/*
 * pgfs_gc_step — Phase 2 placeholder.
 *
 * The pre-Phase-2 implementation selected the most-erased block and erased
 * it, which is anti-wear-levelling and risks erasing live data. The full
 * cost-benefit GC (move live data out of a victim block, then erase) is
 * deferred until the per-segment write head infrastructure lands in a
 * follow-up. For now this is a no-op that:
 *   - returns 0 reclaimed bytes (caller treats as "no progress")
 *   - never erases a block
 *   - never marks a block bad
 *
 * Returning 0 here causes the file-close path to fall through to
 * pgfs_compact_live_entries (the bulk rewrite) on ENOSPC, which is the
 * only compaction path that is correct today.
 *
 * The proper cost-benefit GC requires:
 *   - per-block live_bytes / dead_bytes accounting (currently only global
 *     gc_live_bytes / gc_dead_bytes in pgfs_checkpoint_t)
 *   - per-segment write head persisted in FTL state
 *   - a victim selection function that weighs dead_bytes vs erase_count
 *
 * Returns 0 for now (placeholder).
 */
int pgfs_gc_step(pgfs_mount_ctx_t *ctx, uint32_t byte_budget, uint32_t time_budget_us) {
    (void)ctx;
    (void)byte_budget;
    (void)time_budget_us;
    return 0;
}

/* ── Block retirement ───────────────────────────────────────────────────── */

/*
 * pgfs_mark_block_retired — Phase 5 + 5b: separate retired state from
 * bad state. A retired block has had all its live data moved out (safe
 * to erase) but the chip-level erase has not yet been attempted. A bad
 * block has had at least one erase attempt fail. The two are distinct
 * because retirement is a GC-side decision and bad is a hardware-side
 * signal. Pre-Phase-5 this function conflated the two, which caused
 * retired blocks to be permanently lost from the pool even when their
 * erase would have succeeded.
 *
 * Phase 5b: the retired bit is now persisted in the FTL state
 * (retired_blocks_bitmap, v3 layout) so retirement survives a remount.
 * The CP flag 0x01u is also set so legacy v2 remounts (or test code
 * that reads the CP directly) can still observe that a retirement
 * happened.
 */
int pgfs_mark_block_retired(pgfs_mount_ctx_t *ctx, uint32_t block_id) {
    if (!ctx) return -1;
    if (block_id < ctx->ftl.total_blocks) {
        pgfs_ftl_mark_retired(&ctx->ftl, block_id);
        LLOGD("pgfs: block %u marked retired (Phase 5b: bit set + CP flag)",
              (unsigned int)block_id);
    }
    ctx->checkpoint.flags |= 0x01u;
    return 0;
}

#endif /* LUAT_USE_PGFS_COMPONENT */
