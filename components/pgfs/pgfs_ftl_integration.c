/*
 * pgfs_ftl_integration.c — FTL integration helpers
 *
 * Bridges pgfs core (checkpoint, mount) with the NAND FTL layer.
 */
#ifdef LUAT_USE_PGFS_COMPONENT

#include "pgfs_internal.h"  /* includes pgfs_nand_ftl.h internally */

#include <stdio.h>

#define LUAT_LOG_TAG "pgfs.ftl"
#include "luat_log.h"

/* Forward declaration of the progress callback used during scan */
static void pgfs_ftl_scan_progress(uint32_t done, uint32_t total) {
    /* Emit a log every ~5% or every 64 blocks, whichever is more frequent */
    static uint32_t last_pct = 0;
    uint32_t pct = (done * 100) / total;
    if (pct >= last_pct + 5 || done == total || (done & 63) == 0) {
        LLOGD("pgfs_ftl scan: %u/%u blocks (%u%%)",
              (unsigned int)done, (unsigned int)total, (unsigned int)pct);
        last_pct = pct;
    }
    (void)last_pct; /* suppress unused warning when logging is quiet */
}

int pgfs_ftl_on_mount(pgfs_mount_ctx_t *ctx) {
    if (!ctx || !ctx->flash_opts) return -1;

    /* Read geometry to get block count */
    pgfs_flash_geometry_t geo = {0};
    if (!ctx->flash_opts->control ||
        ctx->flash_opts->control(ctx->flash_opts->ctx,
                                 PGFS_CTRL_GET_GEOMETRY, &geo) != 0 ||
        geo.erase_size == 0 || geo.capacity == 0) {
        LLOGE("pgfs_ftl: cannot read flash geometry");
        return -1;
    }
    uint32_t total_blocks = geo.capacity / geo.erase_size;

    /* Init FTL context */
    if (pgfs_ftl_init(&ctx->ftl, ctx->flash_opts, geo.erase_size, total_blocks) != 0) {
        LLOGE("pgfs_ftl: init failed");
        return -1;
    }

    /* Transfer inject_bad_block_once from mount ctx → FTL ctx */
    if (ctx->inject_bad_block_once) {
        pgfs_ftl_inject_bad_block_once(&ctx->ftl, 0); /* default to block 0; caller overrides */
        ctx->inject_bad_block_once = 0;
    }

    /* Try loading persisted FTL state */
    int load_ret = pgfs_ftl_load(&ctx->ftl);
    if (load_ret == 0) {
        LLOGI("pgfs_ftl: loaded %u bad blocks from flash",
               (unsigned int)ctx->ftl.bad_block_count);
    } else if (load_ret == 1) {
        /*
         * No FTL record found (first boot after FTL upgrade, or fresh flash).
         * Only scan if the flash is fresh (no existing pgfs superblocks).
         * Erasing all blocks during a scan is destructive for existing data.
         */
        pgfs_superblock_t sb_test = {0};
        int has_sb_a = 0, has_sb_b = 0;
        if (ctx->flash_opts && ctx->flash_opts->read &&
            ctx->flash_opts->read(ctx->flash_opts->ctx, PGFS_SUPERBLOCK_A_ADDR,
                                  (uint8_t *)&sb_test, sizeof(sb_test)) == 0 &&
            sb_test.magic == PGFS_SUPERBLOCK_MAGIC) {
            has_sb_a = 1;
        }
        memset(&sb_test, 0, sizeof(sb_test));
        if (ctx->flash_opts && ctx->flash_opts->read &&
            ctx->flash_opts->read(ctx->flash_opts->ctx, PGFS_SUPERBLOCK_B_ADDR,
                                  (uint8_t *)&sb_test, sizeof(sb_test)) == 0 &&
            sb_test.magic == PGFS_SUPERBLOCK_MAGIC) {
            has_sb_b = 1;
        }

        if (has_sb_a || has_sb_b) {
            /* Existing installation — skip destructive scan.
             * Bad blocks will be discovered lazily on erase failure. */
            LLOGI("pgfs_ftl: existing installation detected (SB present), "
                  "skipping destructive bad-block scan. "
                  "Bad blocks will be marked on erase failure.");
        } else {
            /* Fresh flash — safe to scan */
            LLOGI("pgfs_ftl: fresh flash, scanning factory bad blocks...");
            if (pgfs_ftl_scan_bad_blocks(&ctx->ftl, pgfs_ftl_scan_progress) != 0) {
                LLOGE("pgfs_ftl: bad block scan failed");
                pgfs_ftl_deinit(&ctx->ftl);
                return -1;
            }
            LLOGI("pgfs_ftl: scan complete, %u bad blocks found",
               (unsigned int)ctx->ftl.bad_block_count);
        }
        /* Persist immediately so next mount can load */
        if (pgfs_ftl_persist(&ctx->ftl, ctx->checkpoint.seq) != 0) {
            LLOGW("pgfs_ftl: first persist failed (non-fatal)");
        }
    } else {
        LLOGE("pgfs_ftl: load error");
        pgfs_ftl_deinit(&ctx->ftl);
        return -1;
    }
    return 0;
}

int pgfs_ftl_on_checkpoint_commit(pgfs_mount_ctx_t *ctx) {
    if (!ctx || !ctx->mounted) return 0;
    return pgfs_ftl_persist(&ctx->ftl, ctx->checkpoint.seq);
}

void pgfs_ftl_on_erase_success(pgfs_mount_ctx_t *ctx, uint32_t block_id) {
    if (!ctx) return;

    /* Handle inject_bad_block_once: mark the injected block bad AFTER
     * the erase command completes (so the erase still runs in tests) */
    pgfs_nand_ftl_ctx_t *ftl = &ctx->ftl;
    if (ftl->inject_bad_block_once && !ftl->inject_bad_block_flag) {
        ftl->inject_bad_block_flag = 1;
        pgfs_ftl_mark_block_bad(ftl, ftl->inject_bad_block_id);
        ftl->inject_bad_block_once = 0;
        LLOGD("pgfs_ftl: injected bad block %u (erasures still proceeded)",
               (unsigned int)ftl->inject_bad_block_id);
    }

    pgfs_ftl_block_erased(ftl, block_id);
}

void pgfs_ftl_on_erase_failure(pgfs_mount_ctx_t *ctx, uint32_t block_id) {
    if (!ctx) return;
    pgfs_ftl_mark_block_bad(&ctx->ftl, block_id);
    LLOGW("pgfs_ftl: block %u marked bad (erase failed)",
           (unsigned int)block_id);
}

int pgfs_ftl_erase_block(pgfs_mount_ctx_t *ctx, uint32_t block_addr,
                          uint32_t erase_size, uint32_t block_id) {
    if (!ctx || !ctx->flash_opts || !ctx->flash_opts->erase) return -1;

    /* Handle inject_bad_block_once: inject BEFORE issuing erase so the
     * block gets marked bad even if the erase appears to succeed */
    pgfs_nand_ftl_ctx_t *ftl = &ctx->ftl;
    if (ftl->inject_bad_block_once && !ftl->inject_bad_block_flag) {
        ftl->inject_bad_block_flag = 1;
        pgfs_ftl_mark_block_bad(ftl, ftl->inject_bad_block_id);
        ftl->inject_bad_block_once = 0;
        LLOGD("pgfs_ftl: inject_bad_block_once triggered for block %u",
               (unsigned int)ftl->inject_bad_block_id);
        /* Don't return error — let the erase run so tests can observe behaviour */
    }

    int ret = ctx->flash_opts->erase(ctx->flash_opts->ctx, block_addr, erase_size);
    if (ret == 0) {
        pgfs_ftl_block_erased(ftl, block_id);
    } else {
        pgfs_ftl_mark_block_bad(ftl, block_id);
        LLOGW("pgfs_ftl: erase block %u failed, marked bad",
               (unsigned int)block_id);
    }
    return ret;
}

#endif /* LUAT_USE_PGFS_COMPONENT */
