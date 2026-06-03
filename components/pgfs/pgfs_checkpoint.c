#include "luat_base.h"
#include <string.h>
#include "luat_crypto.h"
#include "pgfs_internal.h"

#define LUAT_LOG_TAG "pgfs"
#include "luat_log.h"

#ifdef LUAT_USE_PGFS_COMPONENT

/* pgfs_layout_compute — fill a layout struct from a flash geometry.
 *
 * Block 0..4 are reserved (SB-A, SB-B, CP-A, CP-B, FTL state). The data
 * log spans [5, total_blocks-1]. Returns -1 if the geometry is too
 * small to host the required reserved blocks (< 5 blocks total). */
/* Phase 4b: consistency check between CP and FTL state.
 * The CP carries a (log_tail_block, log_tail_offset) pair that records
 * the data log position at the moment the CP was committed. The FTL
 * state carries the same pair (write_head_block, write_head_offset).
 * If they match, the data log has not been touched since the CP was
 * committed, and pgfs_replay_data_log can be skipped on mount. */
bool pgfs_checkpoint_is_consistent_with_ftl(const pgfs_checkpoint_t* cp,
                                          const pgfs_nand_ftl_ctx_t* ftl) {
    if (cp == NULL || ftl == NULL || ftl->flash_opts == NULL) {
        return false;
    }
    /* The CP's log_tail_* is the data log position at the moment of the
     * last CP commit. The FTL's write_head_* is the position persisted
     * alongside the CP (and refreshed by pgfs_ftl_on_checkpoint_commit
     * before the persist). If they match, the data log is consistent
     * with the CP and the replay can be skipped. */
    if (cp->log_tail_block != ftl->write_head_block) {
        return false;
    }
    if (cp->log_tail_offset != ftl->write_head_offset) {
        return false;
    }
    /* Sanity: a CP recorded with both log_tail fields as zero on a
     * v2-record means it was written before Phase 4b plumbing was in
     * place. Treat as inconsistent to force the safer replay path. */
    if (cp->log_tail_block == 0 && cp->log_tail_offset == 0) {
        return false;
    }
    return true;
}

int pgfs_layout_compute(const pgfs_flash_geometry_t* geo, pgfs_layout_t* out) {
    if (geo == NULL || out == NULL) {
        return -1;
    }
    if (geo->erase_size == 0 || geo->capacity < geo->erase_size) {
        return -1;
    }
    uint32_t total_blocks = geo->capacity / geo->erase_size;
    if (total_blocks < PGFS_LAYOUT_RESERVED_BLOCKS) {
        return -1;
    }
    out->erase_size = geo->erase_size;
    out->prog_size = geo->prog_size != 0 ? geo->prog_size : 1u;
    out->total_blocks = total_blocks;
    out->sb_a_block = 0;
    out->sb_b_block = 1;
    out->cp_a_block = 2;
    out->cp_b_block = 3;
    out->ftl_state_block = 4;
    out->data_log_first_block = PGFS_LAYOUT_RESERVED_BLOCKS;
    out->data_log_last_block = total_blocks - 1u;
    out->reserved_block_count = PGFS_LAYOUT_RESERVED_BLOCKS;
    return 0;
}

static uint32_t pgfs_crc32_calc(const void* data, size_t len) {
    return luat_crc32(data, (uint32_t)len, 0xFFFFFFFFu, 0);
}

static int pgfs_superblock_valid(const pgfs_superblock_t* sb) {
    pgfs_superblock_t tmp = {0};
    uint32_t crc = 0;
    if (sb == NULL) {
        return 0;
    }
    if (sb->magic != PGFS_SUPERBLOCK_MAGIC || sb->version != PGFS_ONDISK_VERSION) {
        return 0;
    }
    memcpy(&tmp, sb, sizeof(tmp));
    crc = tmp.crc32;
    tmp.crc32 = 0;
    return crc == pgfs_crc32_calc(&tmp, sizeof(tmp));
}

static int pgfs_checkpoint_valid(const pgfs_checkpoint_t* cp) {
    pgfs_checkpoint_t tmp = {0};
    uint32_t crc = 0;
    if (cp == NULL) {
        return 0;
    }
    if (cp->magic != PGFS_CHECKPOINT_MAGIC || cp->version != PGFS_ONDISK_VERSION) {
        return 0;
    }
    memcpy(&tmp, cp, sizeof(tmp));
    crc = tmp.crc32;
    tmp.crc32 = 0;
    return crc == pgfs_crc32_calc(&tmp, sizeof(tmp));
}

int pgfs_pick_latest_valid_sb(const pgfs_superblock_t* a, const pgfs_superblock_t* b, pgfs_superblock_t* out) {
    int valid_a = pgfs_superblock_valid(a);
    int valid_b = pgfs_superblock_valid(b);
    if (out == NULL) {
        return -1;
    }
    if (!valid_a && !valid_b) {
        memset(out, 0, sizeof(*out));
        return -1;
    }
    if (valid_a && !valid_b) {
        *out = *a;
        return 0;
    }
    if (!valid_a && valid_b) {
        *out = *b;
        return 0;
    }
    if (b->seq >= a->seq) {
        *out = *b;
    }
    else {
        *out = *a;
    }
    return 0;
}

static int pgfs_flash_read(pgfs_mount_ctx_t* ctx, uint32_t addr, void* buf, size_t len) {
    if (ctx == NULL || ctx->flash_opts == NULL || ctx->flash_opts->read == NULL || buf == NULL || len == 0) {
        return -1;
    }
    return ctx->flash_opts->read(ctx->flash_opts->ctx, addr, (uint8_t*)buf, len);
}

static int pgfs_flash_write(pgfs_mount_ctx_t* ctx, uint32_t addr, const void* buf, size_t len) {
    if (ctx == NULL || ctx->flash_opts == NULL || ctx->flash_opts->write == NULL || buf == NULL || len == 0) {
        return -1;
    }
    return ctx->flash_opts->write(ctx->flash_opts->ctx, addr, (const uint8_t*)buf, len);
}

static int pgfs_load_checkpoint_by_sb(pgfs_mount_ctx_t* ctx, const pgfs_superblock_t* sb, pgfs_checkpoint_t* cp) {
    if (ctx == NULL || sb == NULL || cp == NULL) {
        return -1;
    }
    if (!pgfs_superblock_valid(sb)) {
        return -1;
    }
    if (sb->checkpoint_len != sizeof(pgfs_checkpoint_t)) {
        return -1;
    }
    if (pgfs_flash_read(ctx, sb->checkpoint_addr, cp, sizeof(*cp)) != 0) {
        return -1;
    }
    if (!pgfs_checkpoint_valid(cp)) {
        return -1;
    }
    if (cp->seq != sb->seq || cp->crc32 != sb->checkpoint_crc) {
        return -1;
    }
    return 0;
}

int pgfs_checkpoint_load(void* fs, pgfs_checkpoint_t* cp) {
    pgfs_mount_ctx_t* ctx = (pgfs_mount_ctx_t*)fs;
    pgfs_superblock_t sb_a = {0};
    pgfs_superblock_t sb_b = {0};
    pgfs_superblock_t picked = {0};
    int prefer_b = 0;
    int loaded = -1;

    if (ctx == NULL || cp == NULL) {
        return -1;
    }
    if (pgfs_flash_read(ctx, PGFS_SUPERBLOCK_A_ADDR, &sb_a, sizeof(sb_a)) != 0) {
        return -1;
    }
    if (pgfs_flash_read(ctx, PGFS_SUPERBLOCK_B_ADDR, &sb_b, sizeof(sb_b)) != 0) {
        return -1;
    }
    if (ctx->inject_corrupt_latest_cp) {
        int valid_a = pgfs_superblock_valid(&sb_a);
        int valid_b = pgfs_superblock_valid(&sb_b);
        if (valid_a || valid_b) {
            if (!valid_a || (valid_b && sb_b.seq >= sb_a.seq)) {
                sb_b.magic = 0;
            }
            else {
                sb_a.magic = 0;
            }
        }
        ctx->inject_corrupt_latest_cp = 0;
    }

    if (pgfs_pick_latest_valid_sb(&sb_a, &sb_b, &picked) != 0) {
        return -1;
    }

    prefer_b = (picked.seq == sb_b.seq && pgfs_superblock_valid(&sb_b) && (!pgfs_superblock_valid(&sb_a) || sb_b.seq >= sb_a.seq));

    if (prefer_b) {
        if (pgfs_load_checkpoint_by_sb(ctx, &sb_b, cp) == 0) {
            loaded = 0;
            goto done;
        }
        if (pgfs_load_checkpoint_by_sb(ctx, &sb_a, cp) == 0) {
            ctx->stats.checkpoint_fallback_count++;
            loaded = 0;
            goto done;
        }
    }
    else {
        if (pgfs_load_checkpoint_by_sb(ctx, &sb_a, cp) == 0) {
            loaded = 0;
            goto done;
        }
        if (pgfs_load_checkpoint_by_sb(ctx, &sb_b, cp) == 0) {
            ctx->stats.checkpoint_fallback_count++;
            loaded = 0;
            goto done;
        }
    }
done:
    return loaded;
}

int pgfs_checkpoint_store_next(void* fs, const pgfs_checkpoint_t* current, pgfs_checkpoint_t* next) {
    pgfs_mount_ctx_t* ctx = (pgfs_mount_ctx_t*)fs;
    pgfs_checkpoint_t tmp = {0};
    pgfs_superblock_t sb = {0};
    pgfs_flash_geometry_t geo = {0};
    uint32_t cp_addr = PGFS_CHECKPOINT_A_ADDR;
    uint32_t sb_addr = PGFS_SUPERBLOCK_A_ADDR;

    if (ctx == NULL || next == NULL) {
        return -1;
    }

    if (current != NULL) {
        tmp = *current;
    }
    tmp.magic = PGFS_CHECKPOINT_MAGIC;
    tmp.version = PGFS_ONDISK_VERSION;
    tmp.seq = current ? (current->seq + 1u) : 1u;

    if (tmp.total_blocks == 0 && ctx->flash_opts && ctx->flash_opts->control) {
        if (ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 && geo.erase_size) {
            tmp.total_blocks = geo.capacity / geo.erase_size;
        }
    }

    /* Phase 4b: record the data log write head in the CP itself so the
     * mount path can compare it against the FTL's persisted log_tail_*
     * fields and skip pgfs_replay_data_log when they match. We derive
     * block/offset from ctx->data_log_write_addr; the same values are
     * also pushed to ctx->ftl.write_head_* by pgfs_ftl_on_checkpoint_commit
     * so the FTL meta records the same point. */
    if (ctx->flash_opts && ctx->flash_opts->control &&
        ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
        geo.erase_size > 0 && ctx->data_log_write_addr >= ctx->data_log_base_addr) {
        uint32_t base_block = (ctx->data_log_base_addr / geo.erase_size);
        uint32_t write_block = (ctx->data_log_write_addr / geo.erase_size);
        uint32_t write_off   = (ctx->data_log_write_addr % geo.erase_size);
        if (write_block >= base_block) {
            tmp.log_tail_block  = write_block - base_block;
            tmp.log_tail_offset = (uint16_t)write_off;
        } else {
            tmp.log_tail_block  = 0;
            tmp.log_tail_offset = 0;
        }
    } else {
        tmp.log_tail_block  = 0;
        tmp.log_tail_offset = 0;
    }
    /* Mirror into the runtime ctx so callers and the FTL layer can read
     * the value without having to round-trip through the CP. */
    ctx->log_tail_block  = tmp.log_tail_block;
    ctx->log_tail_offset = tmp.log_tail_offset;

    if ((tmp.seq & 1u) == 0) {
        cp_addr = PGFS_CHECKPOINT_B_ADDR;
        sb_addr = PGFS_SUPERBLOCK_B_ADDR;
    }

    if (ctx->flash_opts && ctx->flash_opts->control && ctx->flash_opts->erase &&
        ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
        geo.erase_size) {
        uint32_t cp_blk = (cp_addr / geo.erase_size) * geo.erase_size;
        uint32_t sb_blk = (sb_addr / geo.erase_size) * geo.erase_size;
        if (ctx->flash_opts->erase(ctx->flash_opts->ctx, cp_blk, geo.erase_size) != 0) {
            return -1;
        }
        if (sb_blk != cp_blk) {
            if (ctx->flash_opts->erase(ctx->flash_opts->ctx, sb_blk, geo.erase_size) != 0) {
                return -1;
            }
        }
    }

    /* Powercut injection: fail right after the CP/SB blocks are erased
     * but before any new content is written. Recovery should still see the
     * previous valid SB/CP pair on the alternate slot. */
    if (ctx->inject_powercut_stage == PGFS_INJECT_POWERCUT_AFTER_CP_ERASE) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_NONE;
        ctx->stats.powercut_inject_count++;
        LLOGW("CP store: powercut injected after CP/SB erase, before write");
        return -1;
    }

    tmp.crc32 = 0;
    tmp.crc32 = pgfs_crc32_calc(&tmp, sizeof(tmp));
    if (pgfs_flash_write(ctx, cp_addr, &tmp, sizeof(tmp)) != 0) {
        return -1;
    }

    /* Readback verify of CP: NAND write failures / bit-flips can leave the
     * region silently corrupt. If the readback doesn't match, abort the
     * whole store so the old SB/CP pair remains authoritative. */
    {
        pgfs_checkpoint_t verify_cp = {0};
        if (pgfs_flash_read(ctx, cp_addr, &verify_cp, sizeof(verify_cp)) != 0 ||
            !pgfs_checkpoint_valid(&verify_cp) ||
            verify_cp.seq != tmp.seq) {
            LLOGE("CP readback verify failed at addr=%u (seq=%u), store aborted",
                  (unsigned int)cp_addr, (unsigned int)tmp.seq);
            return -1;
        }
    }

    /* Powercut injection point: CP written & verified, SB not yet written.
     * Inject here to validate the CP-only recovery path on the next mount. */
    if (ctx->inject_powercut_stage == PGFS_INJECT_POWERCUT_AFTER_CP_WRITE) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_NONE;
        ctx->stats.powercut_inject_count++;
        LLOGW("CP store: powercut injected after CP write, before SB write");
        return -1;
    }

    memset(&sb, 0, sizeof(sb));
    sb.magic = PGFS_SUPERBLOCK_MAGIC;
    sb.version = PGFS_ONDISK_VERSION;
    sb.seq = tmp.seq;
    sb.checkpoint_addr = cp_addr;
    sb.checkpoint_len = sizeof(tmp);
    sb.checkpoint_crc = tmp.crc32;
    sb.crc32 = 0;
    sb.crc32 = pgfs_crc32_calc(&sb, sizeof(sb));

    if (pgfs_flash_write(ctx, sb_addr, &sb, sizeof(sb)) != 0) {
        return -1;
    }

    /* Readback verify of SB. */
    {
        pgfs_superblock_t verify_sb = {0};
        if (pgfs_flash_read(ctx, sb_addr, &verify_sb, sizeof(verify_sb)) != 0 ||
            !pgfs_superblock_valid(&verify_sb) ||
            verify_sb.seq != sb.seq) {
            LLOGE("SB readback verify failed at addr=%u (seq=%u), store aborted",
                  (unsigned int)sb_addr, (unsigned int)sb.seq);
            return -1;
        }
    }

    *next = tmp;
    /* Phase 6: observability. The CP+SB pair round-tripped cleanly,
     * so count this as a successful commit. The matching FTL persist
     * is counted separately by pgfs_ftl_on_checkpoint_commit. */
    ctx->stats.cp_commit_count += 1;
    return 0;
}

int pgfs_checkpoint_commit_pending(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL) {
        return -1;
    }
    if (ctx->pending_checkpoint_writes == 0) {
        return 0;
    }
    if (pgfs_checkpoint_store_next(ctx, &ctx->checkpoint, &ctx->checkpoint) != 0) {
        return -1;
    }
    /* Persist FTL state (bad-block bitmap + erase counts) alongside the CP
     * so that runtime-discovered bad blocks and wear-levelling counters
     * survive an unexpected power loss. FTL persist failures are logged
     * but do not roll back the CP (CP is already on flash); the in-RAM
     * FTL ctx remains usable until the next CP cycle. */
    if (pgfs_ftl_on_checkpoint_commit(ctx) != 0) {
        LLOGE("FTL persist failed after CP commit (seq=%u), will retry on next CP",
              (unsigned int)ctx->checkpoint.seq);
    }
    ctx->pending_checkpoint_writes = 0;
    ctx->checkpoint_loaded = 1;
    return 0;
}

int pgfs_rebuild_checkpoint_from_replay(pgfs_mount_ctx_t* ctx) {
    pgfs_checkpoint_t next = {0};
    pgfs_flash_geometry_t geo = {0};
    if (ctx == NULL) {
        return -1;
    }
    pgfs_file_reset_all();
    if (pgfs_replay_data_log(ctx) != 0) {
        return -1;
    }
    if (ctx->flash_opts && ctx->flash_opts->control) {
        if (ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 && geo.erase_size) {
            ctx->checkpoint.total_blocks = geo.capacity / geo.erase_size;
        }
    }
    ctx->checkpoint.magic = PGFS_CHECKPOINT_MAGIC;
    ctx->checkpoint.version = PGFS_ONDISK_VERSION;
    if (pgfs_checkpoint_store_next(ctx, &ctx->checkpoint, &next) != 0) {
        return -1;
    }
    ctx->checkpoint = next;
    ctx->checkpoint_loaded = 1;
    return 0;
}

static int pgfs_checkpoint_runtime_valid(const pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL || !ctx->checkpoint_loaded) {
        return 0;
    }
    if (ctx->checkpoint.magic != PGFS_CHECKPOINT_MAGIC || ctx->checkpoint.version != PGFS_ONDISK_VERSION) {
        return 0;
    }
    return 1;
}

static void pgfs_info_fill_from_checkpoint(const pgfs_mount_ctx_t* ctx, const pgfs_flash_geometry_t* geo, luat_fs_info_t* out) {
    uint32_t total = 0;
    uint32_t used = 0;
    if (ctx == NULL || out == NULL) {
        return;
    }
    total = ctx->checkpoint.total_blocks;
    used = ctx->checkpoint.written_blocks;
    if (total == 0 && geo != NULL && geo->erase_size != 0) {
        total = geo->capacity / geo->erase_size;
    }
    if (total != 0 && used > total) {
        used = total;
    }
    out->total_block = total;
    out->block_used = used;
}

int pgfs_info_fast(pgfs_mount_ctx_t* ctx, luat_fs_info_t* out) {
    pgfs_checkpoint_t latest = {0};
    pgfs_flash_geometry_t geo = {0};
    if (ctx == NULL || out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    memcpy(out->filesystem, "pgfs", 5);
    out->type = 0;

    if (ctx->flash_opts && ctx->flash_opts->control) {
        if (ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0) {
            out->block_size = geo.erase_size ? geo.erase_size : 4096;
        }
    }
    if (out->block_size == 0) {
        out->block_size = 4096;
    }

    if (pgfs_checkpoint_runtime_valid(ctx)) {
        pgfs_info_fill_from_checkpoint(ctx, &geo, out);
        return 0;
    }

    if (pgfs_checkpoint_load(ctx, &latest) == 0) {
        ctx->checkpoint = latest;
        ctx->checkpoint_loaded = 1;
        pgfs_info_fill_from_checkpoint(ctx, &geo, out);
        return 0;
    }

    if (pgfs_rebuild_checkpoint_from_replay(ctx) != 0) {
        return -1;
    }
    pgfs_info_fill_from_checkpoint(ctx, &geo, out);
    return 0;
}

#endif
