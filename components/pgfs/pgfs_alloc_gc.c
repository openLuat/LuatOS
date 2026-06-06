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
uint32_t pgfs_gc_pick_victim(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL || ctx->ftl.total_blocks == 0) return 0xFFFFFFFFu;
    uint32_t erase_size = ctx->ftl.erase_size;
    if (erase_size == 0) return 0xFFFFFFFFu;

    /* First pass: compute average erase count across eligible blocks.
     * Eligible blocks are those that are not bad, not reserved, not
     * retired, and not completely full (live < erase_size). This
     * average is used below to detect heavily-worn blocks that need
     * a wear-leveling score boost. */
    uint64_t sum_ec = 0;
    uint32_t ec_count = 0;
    for (uint32_t id = 0; id < ctx->ftl.total_blocks; id++) {
        if (pgfs_ftl_is_block_bad(&ctx->ftl, id)) continue;
        if (pgfs_ftl_is_reserved(&ctx->ftl, id)) continue;
        if (pgfs_ftl_is_retired(&ctx->ftl, id)) continue;
        if (ctx->ftl.live_bytes_per_block == NULL) continue;
        uint32_t live = ctx->ftl.live_bytes_per_block[id];
        if (live >= erase_size) continue;
        sum_ec += ctx->ftl.erase_counts ? ctx->ftl.erase_counts[id] : 0u;
        ec_count++;
    }
    if (ec_count == 0) return 0xFFFFFFFFu;
    uint32_t avg_ec = (uint32_t)(sum_ec / ec_count);

    /* Second pass: score each block with a wear-leveling boost. */
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

        /* Wear-leveling boost: when a block's erase count is above the
         * average of eligible peers, add a bonus proportional to how
         * far above average the block is. This incentivises the GC to
         * reclaim heavily-worn blocks (the opposite of the old cost-
         * benefit formula without this boost, which deprioritised
         * high-EC blocks). The boost only applies when the block still
         * has live data; empty blocks do not need a motivating push
         * because they cost nothing to retire. */
        if (ec > avg_ec && avg_ec > 0 && live > 0) {
            uint32_t boost = (uint32_t)(
                ((uint64_t)(ec - avg_ec) * erase_size) / (uint64_t)avg_ec
            );
            score += boost;
        }

        if (score == 0) continue;
        if (best_block == 0xFFFFFFFFu || score > best_score) {
            best_block = id;
            best_score = score;
        }
    }
    return best_block;
}

typedef struct pgfs_gc_rewrite_ctx {
    pgfs_mount_ctx_t* gc_ctx;
    uint32_t gc_victim;
    int gc_moved;
} pgfs_gc_rewrite_ctx_t;

static int pgfs_gc_rewrite_visitor(pgfs_file_entry_t* e, void* user_data) {
    pgfs_gc_rewrite_ctx_t* r = (pgfs_gc_rewrite_ctx_t*)user_data;
    if (e == NULL || r == NULL) return 0;
    if (e->last_written_block != r->gc_victim) return 0;
    if (e->data == NULL || e->len == 0) return 0;
    /* Force the new record into a DIFFERENT block. Without this, the
     * data log would just append the rewrite into the tail of the
     * same block the victim came from, and the move would not
     * actually free the victim's live bytes. Aligning to the next
     * erase boundary gives the GC a real "this block is now empty"
     * signal. The skipped tail is reclaimed when the data log wraps
     * back to it (it's in the now-retired block, so the allocator
     * won't touch it). */
    uint32_t erase_size = r->gc_ctx->ftl.erase_size;
    if (erase_size > 0) {
        uint32_t cur_block = r->gc_ctx->data_log_write_addr / erase_size;
        if (cur_block == r->gc_victim) {
            uint32_t next = (r->gc_ctx->data_log_write_addr / erase_size + 1u) * erase_size;
            r->gc_ctx->data_log_write_addr = next;
            r->gc_ctx->data_log_prepared_until = next;
        }
    }
    pgfs_file_t shadow = {0};
    shadow.ctx = r->gc_ctx;
    shadow.entry = e;
    shadow.cache.data = e->data;
    shadow.cache.len = e->len;
    if (pgfs_append_data_record(r->gc_ctx, &shadow) == 0) {
        r->gc_moved++;
    }
    return 0;
}

/*
 * pgfs_gc_rewrite_victim — Phase 2 GC data-move step.
 *
 * For each file_entry whose `last_written_block` is the victim, re-append
 * the entry's data to the data log (which lands in a new block). This
 * moves the current record out of the victim so the block is safe to
 * retire. Shadowed records left in the victim are dead and will be lost
 * on retirement — by definition, their data is no longer reachable
 * through the file_entry.
 *
 * Returns the number of records moved. Returns 0 if no entries pointed
 * to the victim (caller can choose to skip retirement in that case).
 */
static int pgfs_gc_rewrite_victim(pgfs_mount_ctx_t* ctx, uint32_t victim) {
    if (ctx == NULL) return 0;
    pgfs_gc_rewrite_ctx_t r = { ctx, victim, 0 };
    (void)pgfs_file_table_visit(pgfs_gc_rewrite_visitor, &r);
    return r.gc_moved;
}

/*
 * pgfs_gc_step — Phase 2 cost-benefit GC step.
 *
 * 1. Pick the highest-scoring victim via pgfs_gc_pick_victim.
 * 2. If the victim has live records (i.e. some file_entry's
 *    last_written_block == victim), move them out via
 *    pgfs_gc_rewrite_victim. Each moved record is re-appended to
 *    the data log and credited to its new block by
 *    pgfs_account_live_block.
 * 3. Zero the victim's live_bytes and dead_bytes (the moved records
 *    are no longer "here", the remaining shadowed records are dead
 *    and will be lost on retirement).
 * 4. Retire the victim via pgfs_mark_block_retired.
 *
 * Returns the number of bytes reclaimed (= erase_size) on success,
 * 0 when no candidate was found or the move failed. byte_budget and
 * time_budget_us are accepted for API compatibility; this first real
 * implementation does a single victim per call.
 */
int pgfs_gc_step(pgfs_mount_ctx_t *ctx, uint32_t byte_budget, uint32_t time_budget_us) {
    (void)byte_budget;
    (void)time_budget_us;
    if (ctx == NULL) return 0;
    if (ctx->ftl.total_blocks == 0) return 0;

    uint32_t victim = pgfs_gc_pick_victim(ctx);
    int moved = 0;
    if (victim == 0xFFFFFFFFu) {
        return 0;
    }

    /* Move live data out before retiring. If the move fails for any
     * reason, abandon the retirement so the data stays reachable. */
    if (ctx->ftl.live_bytes_per_block != NULL &&
        ctx->ftl.live_bytes_per_block[victim] > 0) {
        moved = pgfs_gc_rewrite_victim(ctx, victim);
        if (moved == 0) {
            LLOGW("pgfs_gc: victim %u has live_bytes=%u but no entries to move; skipping",
                  (unsigned int)victim,
                  (unsigned int)ctx->ftl.live_bytes_per_block[victim]);
            return 0;
        }
        /* The moved records are now credited to their new blocks by
         * pgfs_account_live_block. The victim's stats are zeroed. */
        ctx->ftl.live_bytes_per_block[victim] = 0;
        ctx->ftl.dead_bytes_per_block[victim] = 0;
    }

    pgfs_mark_block_retired(ctx, victim);
    LLOGD("pgfs_gc: retired block %u (live_bytes=%u, dead_bytes=%u, ec=%u)",
          (unsigned int)victim,
          (unsigned int)(ctx->ftl.live_bytes_per_block ? ctx->ftl.live_bytes_per_block[victim] : 0u),
          (unsigned int)(ctx->ftl.dead_bytes_per_block ? ctx->ftl.dead_bytes_per_block[victim] : 0u),
          (unsigned int)ctx->ftl.erase_counts[victim]);

    /* Phase 6: observability counters. The step returned a real
     * erase_size and a non-zero `moved` (or 0 for empty blocks);
     * either way we count the step and the reclaimed bytes. */
    ctx->stats.gc_step_count += 1;
    ctx->stats.gc_bytes_reclaimed += ctx->ftl.erase_size;
    if (moved > 0) {
        ctx->stats.gc_records_moved += (uint32_t)moved;
    }

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
