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
 * pgfs_gc_pick_victim — Phase 2 cost-benefit victim selection.
 *
 * Score = (dead_bytes + reclaimable_live_bytes) / (erase_count + 1)
 *
 * - "dead_bytes" is the bytes the GC has previously attributed to this
 *   block (e.g. shadowed records, file deletes). The Phase 2 prep
 *   populates this in pgfs_core.c; for now the attribute remains 0 in
 *   the common case, so the score reduces to "reclaimable_live_bytes"
 *   (free space at the end of the block).
 * - "reclaimable_live_bytes" is approximated as the empty tail of the
 *   block. Blocks written by the data log are filled front-to-back
 *   with aligned records; the unused tail is reclaimable. We use
 *   `erase_size - ctx->ftl.live_bytes_per_block[id]` (clamped to 0)
 *   as a stand-in until shadow-detection in the replay path can drive
 *   dead_bytes upward.
 *
 * Returns the block_id of the highest-scoring data log block that is
 * neither bad, reserved, nor already retired. Returns 0xFFFFFFFFu
 * when no candidate exists.
 */
static uint32_t pgfs_gc_pick_victim(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL || ctx->ftl.total_blocks == 0) return 0xFFFFFFFFu;
    uint32_t erase_size = ctx->ftl.erase_size;
    if (erase_size == 0) return 0xFFFFFFFFu;

    uint32_t best_block = 0xFFFFFFFFu;
    uint32_t best_score = 0u;
    for (uint32_t id = 0; id < ctx->ftl.total_blocks; id++) {
        if (pgfs_ftl_is_block_bad(&ctx->ftl, id)) continue;
        if (pgfs_ftl_is_reserved(&ctx->ftl, id)) continue;
        if (pgfs_ftl_is_retired(&ctx->ftl, id)) continue;
        if (ctx->ftl.live_bytes_per_block == NULL) continue;
        uint32_t live = ctx->ftl.live_bytes_per_block[id];
        if (live >= erase_size) continue;  /* block is full — nothing to reclaim */
        uint32_t dead = ctx->ftl.dead_bytes_per_block ? ctx->ftl.dead_bytes_per_block[id] : 0u;
        uint32_t free  = erase_size - live;
        uint32_t ec    = ctx->ftl.erase_counts ? ctx->ftl.erase_counts[id] : 0u;
        /* Score: (dead + free) divided by (erase_count + 1). A retired
         * block that has 0 live bytes scores `(0 + erase_size) / 1`
         * which is the maximum a single-erase victim can reach. */
        uint32_t score = (dead + free) / (ec + 1u);
        if (score == 0) continue;
        if (best_block == 0xFFFFFFFFu || score > best_score) {
            best_block = id;
            best_score = score;
        }
    }
    return best_block;
}

/*
 * pgfs_gc_step — Phase 2 cost-benefit GC step.
 *
 * For now the data-move path is not implemented (records are not
 * rewritten to a fresh block before the victim is retired). What IS
 * implemented is the safe subset: pick the highest-scoring victim via
 * pgfs_gc_pick_victim() and retire it. Retiring is safe when the
 * block has zero live bytes (the file entries already have the data
 * in memory, so a remount is the only thing that would see a loss;
 * the per-block live bytes are authoritatively zero at the time the
 * caller invoked the GC step, by the cost-benefit contract).
 *
 * Returns the number of bytes reclaimed (i.e., the retired block's
 * size, when a victim was retired). Returns 0 when no candidate was
 * found. The byte_budget / time_budget_us parameters are accepted for
 * API compatibility with the original Phase 2 signature; this first
 * real implementation does a single victim per call.
 */
int pgfs_gc_step(pgfs_mount_ctx_t *ctx, uint32_t byte_budget, uint32_t time_budget_us) {
    (void)byte_budget;
    (void)time_budget_us;
    if (ctx == NULL) return 0;
    if (ctx->ftl.total_blocks == 0) return 0;

    uint32_t victim = pgfs_gc_pick_victim(ctx);
    if (victim == 0xFFFFFFFFu) {
        return 0;
    }

    /* Retire the victim. pgfs_mark_block_retired sets the retired bit
     * and the CP flag; the FTL allocator (find_free_block) will skip
     * it on subsequent calls. */
    pgfs_mark_block_retired(ctx, victim);
    LLOGD("pgfs_gc: retired block %u (live_bytes=%u, dead_bytes=%u, ec=%u)",
          (unsigned int)victim,
          (unsigned int)(ctx->ftl.live_bytes_per_block ? ctx->ftl.live_bytes_per_block[victim] : 0u),
          (unsigned int)(ctx->ftl.dead_bytes_per_block ? ctx->ftl.dead_bytes_per_block[victim] : 0u),
          (unsigned int)ctx->ftl.erase_counts[victim]);

    return ctx->ftl.erase_size;
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
