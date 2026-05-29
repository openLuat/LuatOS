#include "luat_base.h"
#include <string.h>
#include "luat_crypto.h"
#include "pgfs_internal.h"

#ifdef LUAT_USE_PGFS_COMPONENT

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

    if ((tmp.seq & 1u) == 0) {
        cp_addr = PGFS_CHECKPOINT_B_ADDR;
        sb_addr = PGFS_SUPERBLOCK_B_ADDR;
    }

    tmp.crc32 = 0;
    tmp.crc32 = pgfs_crc32_calc(&tmp, sizeof(tmp));
    if (pgfs_flash_write(ctx, cp_addr, &tmp, sizeof(tmp)) != 0) {
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

    *next = tmp;
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

    if (pgfs_checkpoint_load(ctx, &latest) == 0) {
        ctx->checkpoint = latest;
        ctx->checkpoint_loaded = 1;
        out->total_block = latest.total_blocks;
        out->block_used = latest.used_blocks;
        if (out->total_block == 0 && geo.erase_size) {
            out->total_block = geo.capacity / geo.erase_size;
        }
        return 0;
    }

    if (pgfs_rebuild_checkpoint_from_replay(ctx) != 0) {
        return -1;
    }
    out->total_block = ctx->checkpoint.total_blocks;
    out->block_used = ctx->checkpoint.used_blocks;
    return 0;
}

#endif
