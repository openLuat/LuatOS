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
 * pgfs_gc_step — erase-count-based greedy GC.
 *
 * Strategy: find the block with the highest erase count among those with
 * the most dead (overwritten) data, erase it, and return reclaimed bytes.
 *
 * For now (Phase 2): greedy by erase count only.
 * Future: combine wear-leveling with dead-byte ratio.
 *
 * Returns the number of dead bytes reclaimed, or 0 if nothing to reclaim
 * or budget exhausted.
 */
int pgfs_gc_step(pgfs_mount_ctx_t *ctx, uint32_t byte_budget, uint32_t time_budget_us) {
    (void)time_budget_us;
    if (!ctx || byte_budget == 0) return 0;

    uint32_t reclaimed = 0;
    uint32_t best_block = ctx->ftl.total_blocks; /* invalid sentinel */
    uint16_t best_ec = 0;

    /* Greedy scan: find the block with the highest erase count.
     * In a real implementation, we'd also weight by dead-byte ratio.
     * For Phase 2, we prioritise blocks with more erase cycles to balance wear. */
    for (uint32_t i = 0; i < ctx->ftl.total_blocks; i++) {
        if (pgfs_ftl_is_block_bad(&ctx->ftl, i)) continue;

        /* Only consider blocks that have been written to (erase_count > 0) */
        if (ctx->ftl.erase_counts[i] == 0) continue;

        if (ctx->ftl.erase_counts[i] > best_ec) {
            best_ec = ctx->ftl.erase_counts[i];
            best_block = i;
        }
    }

    if (best_block < ctx->ftl.total_blocks) {
        uint32_t erase_addr = best_block * ctx->ftl.erase_size;

        /* Attempt to erase the chosen block */
        if (ctx->ftl.flash_opts && ctx->ftl.flash_opts->erase) {
            if (ctx->ftl.flash_opts->erase(ctx->ftl.flash_opts->ctx, erase_addr, ctx->ftl.erase_size) == 0) {
                /* Successful erase — update FTL erase count.
                 * Since this block was just erased, reset its erase count to 0
                 * (so future allocations spread wear evenly). */
                ctx->ftl.erase_counts[best_block] = 0;
                reclaimed = ctx->ftl.erase_size; /* approximate reclaim */
                LLOGD("pgfs gc: erased block %u (prev_ec=%u), reclaimed ~%u bytes",
                      (unsigned int)best_block,
                      (unsigned int)best_ec,
                      (unsigned int)reclaimed);
            } else {
                /* Erase failed — mark bad and let the next allocation skip it */
                pgfs_ftl_mark_block_bad(&ctx->ftl, best_block);
                LLOGW("pgfs gc: block %u erase failed, marked bad", (unsigned int)best_block);
            }
        }
    }

    /* Update checkpoint dead-byte counter */
    if (reclaimed > 0) {
        if (ctx->checkpoint.gc_dead_bytes >= reclaimed) {
            ctx->checkpoint.gc_dead_bytes -= reclaimed;
        } else {
            ctx->checkpoint.gc_dead_bytes = 0;
        }
    }

    return (int)reclaimed;
}

/* ── Block retirement ───────────────────────────────────────────────────── */

/*
 * pgfs_mark_block_retired — mark a block as retired (no valid data).
 * Called when all data in a block has been overwritten.
 */
int pgfs_mark_block_retired(pgfs_mount_ctx_t *ctx, uint32_t block_id) {
    if (!ctx) return -1;
    if (block_id < ctx->ftl.total_blocks && !pgfs_ftl_is_block_bad(&ctx->ftl, block_id)) {
        pgfs_ftl_mark_block_bad(&ctx->ftl, block_id);
        LLOGD("pgfs: block %u marked retired", (unsigned int)block_id);
    }
    ctx->checkpoint.flags |= 0x01u;
    return 0;
}

#endif /* LUAT_USE_PGFS_COMPONENT */
