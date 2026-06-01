
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef LUAT_USE_LITTLE_FLASH

#ifdef LUAT_USE_FS_VFS
#ifdef LUAT_USE_LFSV3_COMPONENT

#include "lfs3.h"
#include "little_flash.h"

/*
 * NOR flash: byte-addressable, small page (256 B), small erase (4 KB)
 *
 *   lfs3 uses rbyd (Radix B-yield) trees for metadata — NOT linear directory
 *   traversal. Each tree node lives in one mdir block. The rcache is a
 *   single-slot buffer: the optimal size is block_size (erase_size), so the
 *   entire tree node is read in ONE SPI transaction. Smaller rcache forces
 *   multiple reads per node (e.g., rcache=256 → 16 reads per 4KB block).
 *
 *   - read_size  = prog_size       (page-aligned SPI transactions)
 *   - rcache     = erase_size      (= block_size; 1 read per rbyd tree node)
 *   - pcache     = prog_size       (write unit, minimum)
 *   - fcache     = erase_size      (large sequential write buffer per file)
 *   - lookahead  = 64 B            (tracks 512 blocks per scan)
 *   - block_recycles = 500         (NOR: 100K cycles)
 *
 * NAND flash: page-addressable, large page (2048 B), large erase (128+ KB)
 *   - read_size = prog_size        (must read/write full NAND page)
 *   - rcache    = prog_size        (NAND page buffer in device handles caching)
 *   - pcache    = prog_size        (minimum)
 *   - fcache    = prog_size        (minimum)
 *   - lookahead = 32 B             (tracks 256 blocks; NAND has fewer blocks)
 *   - block_recycles = 100         (NAND: 10K cycles, tighter wear-leveling)
 */
#define LFS3_NOR_LOOKAHEAD_SIZE   64
#define LFS3_NOR_BLOCK_RECYCLES   500

#define LFS3_NAND_LOOKAHEAD_SIZE  32
#define LFS3_NAND_BLOCK_RECYCLES  100

/* Static lookahead buffer large enough for both NOR and NAND */
#define LFS3_LF_LOOKAHEAD_SIZE_MAX  64

typedef struct {
    lfs3_t          lfs3;
    struct lfs3_cfg cfg;
    little_flash_t *flash;
    size_t          offset;
    uint8_t        *rcache_buffer;
    uint8_t        *pcache_buffer;
    uint8_t         lookahead_buffer[LFS3_LF_LOOKAHEAD_SIZE_MAX];
} lf_lfs3_ctx_t;

static int lf3_read(const struct lfs3_cfg *cfg, lfs3_block_t block,
                    lfs3_off_t off, void *buffer, lfs3_size_t size) {
    lf_lfs3_ctx_t *ctx = (lf_lfs3_ctx_t *)cfg->context;
    return little_flash_read(ctx->flash,
        (uint32_t)(ctx->offset + (size_t)block * ctx->flash->chip_info.erase_size + (size_t)off),
        (uint8_t *)buffer, (uint32_t)size);
}

static int lf3_prog(const struct lfs3_cfg *cfg, lfs3_block_t block,
                    lfs3_off_t off, const void *buffer, lfs3_size_t size) {
    lf_lfs3_ctx_t *ctx = (lf_lfs3_ctx_t *)cfg->context;
    return little_flash_write(ctx->flash,
        (uint32_t)(ctx->offset + (size_t)block * ctx->flash->chip_info.erase_size + (size_t)off),
        (const uint8_t *)buffer, (uint32_t)size);
}

static int lf3_erase(const struct lfs3_cfg *cfg, lfs3_block_t block) {
    lf_lfs3_ctx_t *ctx = (lf_lfs3_ctx_t *)cfg->context;
    return little_flash_erase(ctx->flash,
        (uint32_t)(ctx->offset + (size_t)block * ctx->flash->chip_info.erase_size),
        (uint32_t)ctx->flash->chip_info.erase_size);
}

static int lf3_sync(const struct lfs3_cfg *cfg) {
    (void)cfg;
    return LFS3_ERR_OK;
}

lfs3_t *flash_lfs3_lf(little_flash_t *flash, size_t offset, size_t maxsize) {
    if (flash == NULL) {
        LLOGE("flash is null");
        return NULL;
    }

    lf_lfs3_ctx_t *ctx = (lf_lfs3_ctx_t *)luat_heap_malloc(sizeof(lf_lfs3_ctx_t));
    if (ctx == NULL)
        return NULL;
    memset(ctx, 0, sizeof(lf_lfs3_ctx_t));

    ctx->flash  = flash;
    ctx->offset = offset;

    /* ------------------------------------------------------------------ *
     * Tune read/prog/cache parameters per flash type.                     *
     * NOR:  byte-addressable, 256 B pages, 4 KB erase.                   *
     *       Larger caches reduce SPI round-trips on metadata.             *
     * NAND: page-addressable, 2048 B pages, large erase blocks.          *
     *       Caches must equal page size; device has its own page buffer.  *
     * ------------------------------------------------------------------ */
    int is_nand = (flash->chip_info.type == LF_DRIVER_NAND_FLASH);
    lfs3_size_t prog_size = (lfs3_size_t)flash->chip_info.prog_size;
    lfs3_size_t read_size, rcache_size, fcache_size;
    lfs3_size_t lookahead_size;
    int32_t     block_recycles;

    if (is_nand) {
        /* NAND: page is both read and write unit; caches must be >= page */
        read_size      = prog_size;
        rcache_size    = prog_size;
        fcache_size    = 4 * prog_size;   /* 8KB: buffer 4 pages per file; reduces PROGRAM_EXEC calls */
        lookahead_size = LFS3_NAND_LOOKAHEAD_SIZE;
        block_recycles = LFS3_NAND_BLOCK_RECYCLES;
        LLOGD("lfs3 nand cfg: prog=%u rcache=%u fcache=%u lookahead=%u",
              (unsigned)prog_size, (unsigned)rcache_size,
              (unsigned)fcache_size, (unsigned)lookahead_size);
    } else {
        /* NOR: lfs3 rbyd tree nodes live in one mdir block (= erase_size).
         * Caching the entire block eliminates multiple SPI reads per tree
         * node traversal. rcache = fcache = block_size for best perf.     */
        lfs3_size_t block_size = (lfs3_size_t)flash->chip_info.erase_size;
        read_size      = prog_size;
        rcache_size    = block_size;   /* 1 SPI read per rbyd tree node */
        fcache_size    = block_size;   /* large write buffer per file   */
        lookahead_size = LFS3_NOR_LOOKAHEAD_SIZE;
        block_recycles = LFS3_NOR_BLOCK_RECYCLES;
        LLOGD("lfs3 nor cfg: prog=%u block=%u rcache=%u fcache=%u lookahead=%u",
              (unsigned)prog_size, (unsigned)block_size,
              (unsigned)rcache_size, (unsigned)fcache_size,
              (unsigned)lookahead_size);
    }

    ctx->rcache_buffer = (uint8_t *)luat_heap_malloc(rcache_size);
    ctx->pcache_buffer = (uint8_t *)luat_heap_malloc(prog_size);
    if (ctx->rcache_buffer == NULL || ctx->pcache_buffer == NULL) {
        luat_heap_free(ctx->rcache_buffer);
        luat_heap_free(ctx->pcache_buffer);
        luat_heap_free(ctx);
        return NULL;
    }

    struct lfs3_cfg *cfg = &ctx->cfg;
    cfg->context      = ctx;
    cfg->read         = lf3_read;
    cfg->prog         = lf3_prog;
    cfg->erase        = lf3_erase;
    cfg->sync         = lf3_sync;

    cfg->read_size    = read_size;
    cfg->prog_size    = prog_size;
    cfg->block_size   = (lfs3_size_t)flash->chip_info.erase_size;
    cfg->block_count  = (lfs3_block_t)(
        (maxsize > 0 ? maxsize : (flash->chip_info.capacity - offset))
        / flash->chip_info.erase_size);

    cfg->block_recycles   = block_recycles;
    cfg->rcache_size      = rcache_size;
    cfg->pcache_size      = prog_size;
    cfg->fcache_size      = fcache_size;
    cfg->lookahead_size   = lookahead_size;
    cfg->rcache_buffer    = ctx->rcache_buffer;
    cfg->pcache_buffer    = ctx->pcache_buffer;
    cfg->lookahead_buffer = ctx->lookahead_buffer;
    cfg->name_limit       = 63;
    cfg->file_limit       = 0;

    int err = lfs3_mount(&ctx->lfs3, 0, cfg);
    if (err) {
        LLOGW("lfs3_mount failed err=%d, formatting...", err);
        err = lfs3_format(&ctx->lfs3, 0, cfg);
        if (err) {
            LLOGW("lfs3_format failed err=%d", err);
            goto fail;
        }
        err = lfs3_mount(&ctx->lfs3, 0, cfg);
        if (err) {
            LLOGW("lfs3_mount after format failed err=%d", err);
            goto fail;
        }
    }
    LLOGD("lfs3 mounted ok block_count=%u block_size=%u",
          (unsigned)cfg->block_count, (unsigned)cfg->block_size);
    return &ctx->lfs3;

fail:
    luat_heap_free(ctx->rcache_buffer);
    luat_heap_free(ctx->pcache_buffer);
    luat_heap_free(ctx);
    return NULL;
}

#endif /* LUAT_USE_LFSV3_COMPONENT */
#endif /* LUAT_USE_FS_VFS */
#endif /* LUAT_USE_LITTLE_FLASH */
