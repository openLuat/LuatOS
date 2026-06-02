/*
 * pgfs_nand_ftl.c — PGFS NAND FTL implementation
 *
 * Handles:
 *   - Factory bad-block detection (factory OOB marker scan)
 *   - Runtime bad-block marking (erase failure → bad)
 *   - Per-block erase-count tracking
 *   - FTL state persistence (after each checkpoint)
 *   - FTL state reload on mount
 *
 * FTL state is stored after the CP area (PGFS_FTL_STATE_ADDR), one
 * erase-unit sized region. Format:
 *   [pgfs_ftl_meta_t] [bad_blocks_bitmap] [erase_counts: uint16_t[]]
 */
#include "luat_base.h"
#include "pgfs_nand_ftl.h"
#include "pgfs_internal.h"  /* PGFS_LAYOUT_RESERVED_BLOCKS, pgfs_layout_t */
#include "luat_crypto.h"
#include "luat_mem.h"
#include <stdlib.h>

#define LUAT_LOG_TAG "pgfs.ftl"
#include "luat_log.h"

#ifdef LUAT_USE_PGFS_COMPONENT

/* ── Helpers ──────────────────────────────────────────────────────────────── */

static uint32_t pgfs_ftl_crc32(const void *data, size_t len) {
    return luat_crc32(data, (uint32_t)len, 0xFFFFFFFFu, 0);
}

/*
 * pgfs_ftl_state_addr — byte address of FTL state region.
 * Always the erase-unit immediately after the two CP slots.
 * Public (non-static) so that pgfs_core.c can skip this region when
 * erasing the data log.
 */
uint32_t pgfs_ftl_state_addr(uint32_t erase_size) {
    /* Phase 0: v2 layout always places the FTL state at
     *   data_log_first_block * erase_size - erase_size
     *   = (PGFS_LAYOUT_RESERVED_BLOCKS - 1) * erase_size
     *   = 4 * erase_size.
     * This matches the v1 formula (align_up(0x3000 + erase_size, erase_size))
     * for erase_size=4096 but differs for 128KB erase. Both produce the
     * same answer for v1-format chips; the v2 layout just makes the
     * reserved-block ordering explicit. */
    return (PGFS_LAYOUT_RESERVED_BLOCKS - 1u) * erase_size;
}

/*
 * pgfs_ftl_flash_read / _write / _erase — thin wrappers around the
 * pgfs_flash_opts_t backend (byte-granular read/write, erase-unit erase).
 */
static int pgfs_ftl_flash_read(const pgfs_flash_opts_t *opts,
                               uint32_t addr, void *buf, size_t len) {
    if (!opts || !opts->read || !buf || !len) return -1;
    return opts->read(opts->ctx, addr, (uint8_t *)buf, len);
}

static int pgfs_ftl_flash_write(const pgfs_flash_opts_t *opts,
                               uint32_t addr, const void *buf, size_t len) {
    if (!opts || !opts->write || !buf || !len) return -1;
    return opts->write(opts->ctx, addr, (const uint8_t *)buf, len);
}

static int pgfs_ftl_flash_erase(const pgfs_flash_opts_t *opts,
                                uint32_t addr, uint32_t erase_size) {
    if (!opts || !opts->erase) return -1;
    /* erase one erase-unit at addr */
    return opts->erase(opts->ctx, addr, erase_size);
}

/* ── Bitmap accessors ────────────────────────────────────────────────────── */

static inline bool pgfs_ftl_bit_get(const uint8_t *bitmap, uint32_t block_id) {
    return (bitmap[block_id >> 3] & (1u << (block_id & 7u))) != 0;
}

static inline void pgfs_ftl_bit_set(uint8_t *bitmap, uint32_t block_id) {
    bitmap[block_id >> 3] |= (1u << (block_id & 7u));
}

static inline void pgfs_ftl_bit_clear(uint8_t *bitmap, uint32_t block_id) {
    bitmap[block_id >> 3] &= (uint8_t)~(1u << (block_id & 7u));
}

/* ── Reserved-block bitmap (Phase 1) ─────────────────────────────────────── */

bool pgfs_ftl_is_reserved(const pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id) {
    if (!ctx || !ctx->reserved_blocks_bitmap || block_id >= ctx->total_blocks) {
        return false;
    }
    return pgfs_ftl_bit_get(ctx->reserved_blocks_bitmap, block_id);
}

void pgfs_ftl_mark_reserved(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id) {
    if (!ctx || !ctx->reserved_blocks_bitmap || block_id >= ctx->total_blocks) {
        return;
    }
    if (!pgfs_ftl_bit_get(ctx->reserved_blocks_bitmap, block_id)) {
        pgfs_ftl_bit_set(ctx->reserved_blocks_bitmap, block_id);
        ctx->reserved_block_count++;
    }
}

void pgfs_ftl_clear_reserved(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id) {
    if (!ctx || !ctx->reserved_blocks_bitmap || block_id >= ctx->total_blocks) {
        return;
    }
    if (pgfs_ftl_bit_get(ctx->reserved_blocks_bitmap, block_id)) {
        pgfs_ftl_bit_clear(ctx->reserved_blocks_bitmap, block_id);
        if (ctx->reserved_block_count > 0) {
            ctx->reserved_block_count--;
        }
    }
}

/* ── Public API ──────────────────────────────────────────────────────────── */

int pgfs_ftl_init(pgfs_nand_ftl_ctx_t *ctx,
                  const pgfs_flash_opts_t *flash_opts,
                  uint32_t erase_size,
                  uint32_t total_blocks) {
    if (!ctx || !flash_opts || !total_blocks) return -1;

    memset(ctx, 0, sizeof(*ctx));
    ctx->total_blocks  = total_blocks;
    ctx->erase_size    = erase_size;
    ctx->flash_opts    = flash_opts;

    size_t bitmap_bytes = PGFS_FTL_BITMAP_BYTES(total_blocks);
    ctx->bad_blocks_bitmap = (uint8_t *)calloc(1, bitmap_bytes);
    if (!ctx->bad_blocks_bitmap) return -1;

    ctx->reserved_blocks_bitmap = (uint8_t *)calloc(1, bitmap_bytes);
    if (!ctx->reserved_blocks_bitmap) {
        free(ctx->bad_blocks_bitmap);
        ctx->bad_blocks_bitmap = NULL;
        return -1;
    }

    ctx->erase_counts = (uint16_t *)calloc(total_blocks, sizeof(uint16_t));
    if (!ctx->erase_counts) {
        free(ctx->bad_blocks_bitmap);
        free(ctx->reserved_blocks_bitmap);
        ctx->bad_blocks_bitmap = NULL;
        ctx->reserved_blocks_bitmap = NULL;
        return -1;
    }
    return 0;
}

void pgfs_ftl_deinit(pgfs_nand_ftl_ctx_t *ctx) {
    if (!ctx) return;
    free(ctx->bad_blocks_bitmap);
    free(ctx->reserved_blocks_bitmap);
    free(ctx->erase_counts);
    if (ctx->last_persist_buf != NULL) {
        free(ctx->last_persist_buf);
    }
    memset(ctx, 0, sizeof(*ctx));
}

bool pgfs_ftl_is_block_bad(const pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id) {
    if (!ctx || block_id >= ctx->total_blocks) return true; /* OOB → treat as bad */
    return pgfs_ftl_bit_get(ctx->bad_blocks_bitmap, block_id);
}

void pgfs_ftl_mark_block_bad(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id) {
    if (!ctx || block_id >= ctx->total_blocks) return;
    if (!pgfs_ftl_bit_get(ctx->bad_blocks_bitmap, block_id)) {
        pgfs_ftl_bit_set(ctx->bad_blocks_bitmap, block_id);
        ctx->bad_block_count++;
    }
}

int pgfs_ftl_find_free_block(const pgfs_nand_ftl_ctx_t *ctx,
                             uint32_t start_id,
                             uint32_t *out_block) {
    if (!ctx || !out_block) return -1;
    for (uint32_t id = start_id; id < ctx->total_blocks; id++) {
        if (!pgfs_ftl_is_block_bad(ctx, id)) {
            *out_block = id;
            return 0;
        }
    }
    return -1; /* no free block */
}

void pgfs_ftl_block_erased(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id) {
    if (!ctx || block_id >= ctx->total_blocks) return;
    if (ctx->erase_counts[block_id] < 0xFFFFu) {
        ctx->erase_counts[block_id]++;
        ctx->total_erase_count++;
    }
}

void pgfs_ftl_inject_bad_block_once(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id) {
    if (!ctx) return;
    /* Out-of-range block_id is a no-op (per documented behavior) */
    if (block_id >= ctx->total_blocks) return;
    ctx->inject_bad_block_once   = 1;
    ctx->inject_bad_block_flag  = 0;
    ctx->inject_bad_block_id    = block_id;
}

/* ── Persist ─────────────────────────────────────────────────────────────── */

int pgfs_ftl_persist(pgfs_nand_ftl_ctx_t *ctx, uint32_t cp_seq) {
    (void)cp_seq;
    if (!ctx || !ctx->flash_opts) return -1;

    uint32_t erase_size   = ctx->erase_size;
    uint32_t state_addr   = pgfs_ftl_state_addr(erase_size);
    uint32_t bitmap_bytes = PGFS_FTL_BITMAP_BYTES(ctx->total_blocks);
    uint32_t ec_bytes     = ctx->total_blocks * sizeof(uint16_t);
    /* v2 layout: [meta][bad_blocks][reserved_blocks][erase_counts] */
    uint32_t total_bytes  = sizeof(pgfs_ftl_meta_t) + 2u * bitmap_bytes + ec_bytes;

    /* Powercut injection point: fail right before erasing the FTL state
     * block. The block retains its previous content, and the next mount
     * should still see the old snapshot. */
    if (ctx->powercut_inject == 1) {
        ctx->powercut_inject = 0;
        ctx->persist_failure_count++;
        LLOGW("pgfs_ftl_persist: powercut injected before FTL erase");
        return -1;
    }

    /* Allocate staging buffer (RAM) */
    uint8_t *buf = (uint8_t *)calloc(1, total_bytes);
    if (!buf) {
        ctx->persist_failure_count++;
        return -1;
    }

    /* Build header */
    pgfs_ftl_meta_t *meta = (pgfs_ftl_meta_t *)buf;
    meta->magic                 = PGFS_FTL_MAGIC;
    meta->version               = PGFS_FTL_VERSION;
    meta->total_blocks          = (uint16_t)ctx->total_blocks;
    meta->bitmap_bytes          = bitmap_bytes;
    meta->reserved_bitmap_bytes = bitmap_bytes;
    meta->erase_count_bytes     = ec_bytes;

    /* Copy bad_blocks_bitmap + reserved_blocks_bitmap + erase_counts
     * into staging buffer. v2 layout. */
    uint8_t  *bitmap_ptr    = buf + sizeof(pgfs_ftl_meta_t);
    uint8_t  *reserved_ptr  = bitmap_ptr + bitmap_bytes;
    uint16_t *ec_ptr        = (uint16_t *)(reserved_ptr + bitmap_bytes);
    memcpy(bitmap_ptr, ctx->bad_blocks_bitmap, bitmap_bytes);
    memcpy(reserved_ptr, ctx->reserved_blocks_bitmap, bitmap_bytes);
    memcpy(ec_ptr, ctx->erase_counts, ec_bytes);

    /* Compute CRC over [meta + bitmap + erase_counts] */
    meta->crc32 = 0;
    meta->crc32 = pgfs_ftl_crc32(buf, total_bytes);

    /* Erase FTL state erase-unit */
    if (pgfs_ftl_flash_erase(ctx->flash_opts, state_addr, erase_size) != 0) {
        LLOGE("pgfs_ftl_persist: erase failed at addr=%u", (unsigned int)state_addr);
        free(buf);
        ctx->persist_failure_count++;
        return -1;
    }

    /* Powercut injection point: fail right after erasing the FTL state
     * block, before writing the new content. The block is now blank —
     * recovery should still find the last_persist_buf (in RAM) or rebuild
     * from CP-driven replay. */
    if (ctx->powercut_inject == 2) {
        ctx->powercut_inject = 0;
        ctx->persist_failure_count++;
        LLOGW("pgfs_ftl_persist: powercut injected after FTL erase, before write");
        free(buf);
        return -1;
    }

    /* Write FTL state */
    if (pgfs_ftl_flash_write(ctx->flash_opts, state_addr, buf, total_bytes) != 0) {
        LLOGE("pgfs_ftl_persist: write failed at addr=%u", (unsigned int)state_addr);
        free(buf);
        ctx->persist_failure_count++;
        return -1;
    }

    /* Readback verify: read the just-written region and re-check CRC.
     * If the readback fails or the CRC doesn't match, the on-flash content
     * is corrupt; we MUST NOT update last_persist_buf in that case so the
     * next mount can still recover from the previous snapshot. */
    uint8_t *verify_buf = (uint8_t *)malloc(total_bytes);
    if (verify_buf == NULL) {
        /* Allocation failure is non-fatal for the on-flash write itself:
         * the write succeeded. Take ownership of buf for snapshot. */
        if (ctx->last_persist_buf != NULL) {
            free(ctx->last_persist_buf);
        }
        ctx->last_persist_buf = buf;
        ctx->last_persist_size = total_bytes;
        ctx->persist_success_count++;
        return 0;
    }
    int readback_ok = 0;
    if (pgfs_ftl_flash_read(ctx->flash_opts, state_addr, verify_buf, total_bytes) == 0) {
        pgfs_ftl_meta_t *verify_meta = (pgfs_ftl_meta_t *)verify_buf;
        uint32_t stored_crc = verify_meta->crc32;
        verify_meta->crc32 = 0;
        if (stored_crc == pgfs_ftl_crc32(verify_buf, total_bytes) &&
            verify_meta->magic == PGFS_FTL_MAGIC) {
            readback_ok = 1;
        }
    }
    free(verify_buf);
    if (!readback_ok) {
        LLOGE("pgfs_ftl_persist: readback verify failed at addr=%u, keeping old snapshot",
              (unsigned int)state_addr);
        free(buf);
        ctx->persist_failure_count++;
        return -1;
    }

    /* Success: take ownership of buf for the new snapshot, free the old one. */
    if (ctx->last_persist_buf != NULL) {
        free(ctx->last_persist_buf);
    }
    ctx->last_persist_buf = buf;
    ctx->last_persist_size = total_bytes;
    ctx->persist_success_count++;
    return 0;
}

/* ── Load ───────────────────────────────────────────────────────────────── */

int pgfs_ftl_load(pgfs_nand_ftl_ctx_t *ctx) {
    if (!ctx || !ctx->flash_opts) return -1;

    uint32_t erase_size   = ctx->erase_size;
    uint32_t state_addr   = pgfs_ftl_state_addr(erase_size);
    uint32_t bitmap_bytes = PGFS_FTL_BITMAP_BYTES(ctx->total_blocks);
    uint32_t ec_bytes     = ctx->total_blocks * sizeof(uint16_t);
    uint32_t total_bytes  = sizeof(pgfs_ftl_meta_t) + 2u * bitmap_bytes + ec_bytes;

    /* Read header first */
    pgfs_ftl_meta_t hdr;
    if (pgfs_ftl_flash_read(ctx->flash_opts, state_addr, &hdr, sizeof(hdr)) != 0) {
        return 1; /* no record */
    }

    /* Basic validation */
    if (hdr.magic != PGFS_FTL_MAGIC ||
        hdr.version != PGFS_FTL_VERSION ||
        hdr.total_blocks != (uint16_t)ctx->total_blocks ||
        hdr.bitmap_bytes != bitmap_bytes ||
        hdr.erase_count_bytes != ec_bytes) {
        return 1; /* invalid */
    }

    /* Read full record */
    uint8_t *buf = (uint8_t *)malloc(total_bytes);
    if (!buf) return -1;

    if (pgfs_ftl_flash_read(ctx->flash_opts, state_addr, buf, total_bytes) != 0) {
        free(buf);
        return -1;
    }

    /* Verify CRC */
    pgfs_ftl_meta_t *meta = (pgfs_ftl_meta_t *)buf;
    uint32_t stored_crc   = meta->crc32;
    meta->crc32 = 0;
    if (pgfs_ftl_crc32(buf, total_bytes) != stored_crc) {
        free(buf);
        return 1; /* corrupt */
    }

    /* Extract data — v2 layout. */
    uint8_t  *bitmap_ptr   = buf + sizeof(pgfs_ftl_meta_t);
    uint8_t  *reserved_ptr = bitmap_ptr + bitmap_bytes;
    uint16_t *ec_ptr       = (uint16_t *)(reserved_ptr + bitmap_bytes);

    memcpy(ctx->bad_blocks_bitmap, bitmap_ptr, bitmap_bytes);
    memcpy(ctx->reserved_blocks_bitmap, reserved_ptr, bitmap_bytes);
    memcpy(ctx->erase_counts, ec_ptr, ec_bytes);

    /* Recompute reserved_block_count from the loaded bitmap. */
    ctx->reserved_block_count = 0;
    for (uint32_t i = 0; i < ctx->total_blocks; i++) {
        if (pgfs_ftl_is_reserved(ctx, i)) ctx->reserved_block_count++;
    }

    /* Count bad blocks */
    ctx->bad_block_count = 0;
    ctx->total_erase_count = 0;
    for (uint32_t i = 0; i < ctx->total_blocks; i++) {
        if (pgfs_ftl_bit_get(ctx->bad_blocks_bitmap, i)) {
            ctx->bad_block_count++;
        }
        ctx->total_erase_count += ctx->erase_counts[i];
    }

    free(buf);
    return 0;
}

/* ── Factory scan ─────────────────────────────────────────────────────────── */

int pgfs_ftl_scan_bad_blocks(pgfs_nand_ftl_ctx_t *ctx,
                             void (*progress_cb)(uint32_t done, uint32_t total)) {
    if (!ctx || !ctx->flash_opts) return -1;

    /* Mark all blocks good initially */
    memset(ctx->bad_blocks_bitmap, 0, PGFS_FTL_BITMAP_BYTES(ctx->total_blocks));
    ctx->bad_block_count = 0;

    for (uint32_t block_id = 0; block_id < ctx->total_blocks; block_id++) {
        uint32_t addr = block_id * ctx->erase_size;

        /* Phase 1: skip any block marked reserved (SB-A/B, CP-A/B, FTL state).
         * The legacy heuristic that only skipped the FTL state block is
         * retained as a fallback for code paths that pre-populate the
         * reserved bitmap manually. */
        if (pgfs_ftl_is_reserved(ctx, block_id)) {
            continue;
        }
        uint32_t ftl_state_start = pgfs_ftl_state_addr(ctx->erase_size);
        if (addr < ftl_state_start + ctx->erase_size &&
            addr + ctx->erase_size > ftl_state_start) {
            continue;
        }

        /* Try erasing the block */
        if (pgfs_ftl_flash_erase(ctx->flash_opts, addr, ctx->erase_size) != 0) {
            pgfs_ftl_mark_block_bad(ctx, block_id);
        }

        if (progress_cb) {
            progress_cb(block_id + 1, ctx->total_blocks);
        }
    }
    return 0;
}

#endif /* LUAT_USE_PGFS_COMPONENT */
