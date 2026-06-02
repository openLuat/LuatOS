/*
 * luat_little_flash_nfs.c — NFS (NAND File System) adapter for little_flash
 *
 * Bridges the little_flash SPI/NAND hardware layer to NFS's nfs_drv_t
 * callback interface.  Provides the factory function flash_nfs_lf() which
 * registers an NFS device, formats if needed, and mounts it.
 *
 * OOB handling:  SPI NAND flash does not expose the OOB (spare) area
 * through the SPI command set.  NFS requires OOB for chunk tags.  To
 * bridge this gap, we allocate a RAM buffer for OOB storage and
 * side-load it alongside little_flash data reads/writes.
 *
 * Limitation:  OOB data is NOT persistent across power cycles in this
 * configuration.  On real hardware, either use a raw NAND controller
 * with true OOB support or enable NFS in-band tags (inband_tags=1)
 * once that code path is validated.
 */

#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef LUAT_USE_LITTLE_FLASH

#include "little_flash.h"
#include "../nfs/inc/nfs.h"
#include "../nfs/inc/nfs_port.h"
#include "../nfs/inc/nfs_types.h"

/*===================================================================
 *  Context structure — passed as userdata to VFS and stored
 *  internally for NFS device lifetime management.
 *===================================================================*/

typedef struct {
    little_flash_t *flash;
    uint32_t        offset;       /* byte offset within flash */
    uint32_t        maxsize;      /* 0 = use remaining capacity */
    char            dev_name[16]; /* NFS device name, e.g. "nfs0" */
    int             is_mounted;   /* 1 after successful nfs_mount */
    int             is_nand;      /* 1 = NAND flash, 0 = NOR */

    /* OOB RAM buffer — SPI NAND has no OOB path, so we keep OOB in RAM.
     * size = total_chunks * spare_bytes_per_chunk */
    uint8_t        *oob_ram;
    uint32_t        oob_per_chunk;
    uint32_t        total_chunks;
} luat_lf_nfs_ctx_t;

/*===================================================================
 *  Static context (single-device for now; matches PGFS/LFS pattern)
 *===================================================================*/

static luat_lf_nfs_ctx_t s_nfs_ctx;
static int               s_nfs_inited = 0;

/*===================================================================
 *  NAND hardware callbacks — bridge little_flash → nfs_drv_t
 *===================================================================*/

/**
 * write_page — write data to little_flash, OOB to RAM buffer.
 */
static int lf_nfs_write_page(void *ctx, nfs_u32 page,
                             const nfs_u8 *data, nfs_u32 data_len,
                             const nfs_u8 *oob,  nfs_u32 oob_len)
{
    luat_lf_nfs_ctx_t *c = (luat_lf_nfs_ctx_t *)ctx;
    uint32_t chunk_size = c->flash->chip_info.prog_size;
    uint32_t addr;

    if (c == NULL || c->flash == NULL)
        return NFS_FAIL;

    addr = c->offset + (uint32_t)page * chunk_size;

    if (data && data_len > 0) {
        lf_err_t wret = little_flash_write(c->flash, addr, data, data_len);
        if (wret != LF_ERR_OK) {
            LLOGE("nfs: write_page FAILED page=%u addr=0x%X len=%u ret=%d",
                  (unsigned int)page, (unsigned int)addr,
                  (unsigned int)data_len, wret);
            return NFS_EFLASH;
        }
    }

    /* Store OOB in RAM buffer */
    if (oob && oob_len > 0 && c->oob_ram && page < c->total_chunks) {
        nfs_u32 copy = oob_len < c->oob_per_chunk ? oob_len : c->oob_per_chunk;
        memcpy(c->oob_ram + page * c->oob_per_chunk, oob, copy);
    }

    return NFS_OK;
}

/**
 * read_page — read data from little_flash, OOB from RAM buffer.
 */
static int lf_nfs_read_page(void *ctx, nfs_u32 page,
                            nfs_u8 *data, nfs_u32 data_len,
                            nfs_u8 *oob,  nfs_u32 oob_len)
{
    luat_lf_nfs_ctx_t *c = (luat_lf_nfs_ctx_t *)ctx;
    uint32_t chunk_size = c->flash->chip_info.prog_size;
    uint32_t addr;

    if (c == NULL || c->flash == NULL)
        return NFS_FAIL;

    addr = c->offset + (uint32_t)page * chunk_size;

    if (data && data_len > 0) {
        if (little_flash_read(c->flash, addr, data, data_len) != LF_ERR_OK)
            return NFS_EFLASH;
    }

    /* Read OOB from RAM buffer */
    if (oob && oob_len > 0 && c->oob_ram && page < c->total_chunks) {
        nfs_u32 copy = oob_len < c->oob_per_chunk ? oob_len : c->oob_per_chunk;
        memcpy(oob, c->oob_ram + page * c->oob_per_chunk, copy);
    } else if (oob && oob_len > 0) {
        /* No OOB RAM — fill with 0xFF (erased state) */
        memset(oob, 0xFF, oob_len);
    }

    return NFS_OK;
}

/**
 * erase_block — erase one flash block via little_flash,
 * and reset OOB RAM for all chunks in that block to 0xFF.
 */
static int lf_nfs_erase_block(void *ctx, nfs_u32 block)
{
    luat_lf_nfs_ctx_t *c = (luat_lf_nfs_ctx_t *)ctx;
    uint32_t block_size;
    uint32_t addr;
    uint32_t chunks_per_block;
    uint32_t start_chunk, i;

    if (c == NULL || c->flash == NULL)
        return NFS_FAIL;

    block_size = c->flash->chip_info.erase_size;
    addr = c->offset + (uint32_t)block * block_size;

    if (little_flash_erase(c->flash, addr, block_size) != LF_ERR_OK) {
        LLOGE("nfs: erase_block FAILED block=%u addr=0x%X size=%u",
              (unsigned int)block, (unsigned int)addr, (unsigned int)block_size);
        return NFS_EFLASH;
    }

    /* Reset OOB RAM for all chunks in this block */
    if (c->oob_ram && c->oob_per_chunk > 0) {
        chunks_per_block = block_size / c->flash->chip_info.prog_size;
        start_chunk = block * chunks_per_block;
        for (i = 0; i < chunks_per_block; i++) {
            nfs_u32 idx = start_chunk + i;
            if (idx < c->total_chunks)
                memset(c->oob_ram + idx * c->oob_per_chunk, 0xFF, c->oob_per_chunk);
        }
    }

    return NFS_OK;
}

/**
 * mark_bad / check_bad — stub implementations.
 * For PC simulator testing, bad block management is not needed.
 * Real NAND hardware would check OOB byte 0.
 */
static int lf_nfs_mark_bad(void *ctx, nfs_u32 block)
{
    (void)ctx;
    (void)block;
    LLOGD("nfs mark_bad block=%u (stub)", (unsigned int)block);
    return NFS_OK;
}

static int lf_nfs_check_bad(void *ctx, nfs_u32 block)
{
    (void)ctx;
    (void)block;
    return 0; /* always good */
}

/*===================================================================
 *  OS / memory callbacks
 *===================================================================*/

static void *lf_nfs_malloc(void *ctx, nfs_u32 size)
{
    (void)ctx;
    return luat_heap_malloc((size_t)size);
}

static void lf_nfs_free(void *ctx, void *ptr)
{
    (void)ctx;
    luat_heap_free(ptr);
}

static void lf_nfs_lock(void *ctx)
{
    (void)ctx;
    /* single-threaded event loop — no lock needed on PC */
}

static void lf_nfs_unlock(void *ctx)
{
    (void)ctx;
}

static nfs_u32 lf_nfs_get_time(void)
{
    /* Return 0 — NFS will use internal sequence numbers instead */
    return 0;
}

static void lf_nfs_trace(const char *fmt, ...)
{
    (void)fmt;
    /* Suppress NFS internal trace; enable via NFS_CFG_TRACE_MASK if desired */
}

/*===================================================================
 *  Driver table factory
 *===================================================================*/

static void lf_nfs_fill_drv(nfs_drv_t *drv, luat_lf_nfs_ctx_t *ctx)
{
    memset(drv, 0, sizeof(*drv));
    drv->ctx         = ctx;
    drv->write_page  = lf_nfs_write_page;
    drv->read_page   = lf_nfs_read_page;
    drv->erase_block = lf_nfs_erase_block;
    drv->mark_bad    = lf_nfs_mark_bad;
    drv->check_bad   = lf_nfs_check_bad;
    drv->malloc      = lf_nfs_malloc;
    drv->free        = lf_nfs_free;
    drv->lock        = lf_nfs_lock;
    drv->unlock      = lf_nfs_unlock;
    drv->get_time    = lf_nfs_get_time;
    drv->trace       = lf_nfs_trace;
}

/*===================================================================
 *  NAND geometry derivation from little_flash chip_info
 *===================================================================*/

static void lf_nfs_fill_geo(nfs_geo_t *geo, luat_lf_nfs_ctx_t *ctx)
{
    little_flash_t *flash = ctx->flash;
    uint32_t prog_size  = flash->chip_info.prog_size;
    uint32_t erase_size = flash->chip_info.erase_size;
    uint32_t capacity   = flash->chip_info.capacity;
    uint32_t total_size;
    uint32_t block_count;
    uint32_t spare_size = 64;  /* Standard NAND OOB size */

    memset(geo, 0, sizeof(*geo));

    total_size = capacity - ctx->offset;
    if (ctx->maxsize > 0 && ctx->maxsize < total_size)
        total_size = ctx->maxsize;

    block_count = total_size / erase_size;
    if (block_count == 0)
        block_count = 1;

    /* Use standard OOB geometry with RAM-based OOB storage */
    ctx->oob_per_chunk = spare_size;
    ctx->total_chunks  = block_count * (erase_size / prog_size);

    geo->data_bytes_per_chunk  = prog_size;
    geo->spare_bytes_per_chunk = spare_size;
    geo->chunks_per_block      = erase_size / prog_size;
    geo->start_block           = 0;
    geo->end_block             = block_count - 1;
    geo->inband_tags           = 0;   /* OOB in RAM, not in-band */
    geo->stored_endian         = 0;

    LLOGD("nfs geo: chunksize=%u spare=%u chunks_per_block=%u blocks=%u"
          " oob_ram=%u bytes",
          (unsigned int)geo->data_bytes_per_chunk,
          (unsigned int)geo->spare_bytes_per_chunk,
          (unsigned int)geo->chunks_per_block,
          (unsigned int)block_count,
          (unsigned int)(ctx->total_chunks * ctx->oob_per_chunk));
}

/*===================================================================
 *  Factory: flash_nfs_lf()
 *
 *  Called by luat_little_flash_named_bus() when fs="nfs".
 *  Returns a luat_lf_nfs_ctx_t* (cast to void*) on success, NULL on failure.
 *
 *  Lifecycle:
 *    1. Fill context with flash handle, offset, maxsize.
 *    2. Derive NAND geometry from chip_info.
 *    3. Build nfs_drv_t callback table.
 *    4. Call nfs_init() (once).
 *    5. Call nfs_add_device() to register the device.
 *    6. Try nfs_mount() first.
 *       a) If mount fails → nfs_format() + retry nfs_mount().
 *       b) If mount succeeds → verify with a write-probe:
 *          create a temp file; if it works the FS is valid (reuse).
 *          If write fails, the mount was "RAM-only" (erased flash had
 *          no on-flash structures) → unmount, format, remount.
 *===================================================================*/

/**
 * lf_nfs_probe_write — quick smoke test after mount to verify the
 * filesystem has valid on-flash structures (not just RAM objects).
 * Returns 1 if the FS is functional, 0 if it needs formatting.
 */
static int lf_nfs_probe_write(luat_lf_nfs_ctx_t *ctx)
{
    char probe_path[64];
    int  fd;
    int  ok = 0;

    snprintf(probe_path, sizeof(probe_path), "/%s/.nfs_probe", ctx->dev_name);

    fd = nfs_open(probe_path, NFS_O_CREAT | NFS_O_RDWR | NFS_O_TRUNC, 0);
    if (fd >= 0) {
        const char *data = "ok";
        if (nfs_write(fd, data, 2) == 2) {
            ok = 1;
        }
        nfs_close(fd);
        nfs_unlink(probe_path);
    }

    return ok;
}

void *flash_nfs_lf(little_flash_t *flash, size_t offset, size_t maxsize)
{
    nfs_drv_t drv;
    nfs_geo_t geo;
    int       ret;
    luat_lf_nfs_ctx_t *ctx = &s_nfs_ctx;

    if (flash == NULL) {
        LLOGE("nfs: flash is null");
        return NULL;
    }

    /* One-shot init */
    if (!s_nfs_inited) {
        nfs_init();
        s_nfs_inited = 1;
    }

    memset(ctx, 0, sizeof(*ctx));
    ctx->flash   = flash;
    ctx->offset  = (uint32_t)offset;
    ctx->maxsize = (uint32_t)maxsize;
    ctx->is_nand = (flash->chip_info.type == LF_DRIVER_NAND_FLASH);
    snprintf(ctx->dev_name, sizeof(ctx->dev_name), "nfs0");

    /* Build driver and geometry */
    lf_nfs_fill_drv(&drv, ctx);
    lf_nfs_fill_geo(&geo, ctx);

    /* Allocate OOB RAM buffer */
    if (ctx->oob_per_chunk > 0 && ctx->total_chunks > 0) {
        size_t oob_size = (size_t)ctx->total_chunks * ctx->oob_per_chunk;
        ctx->oob_ram = (uint8_t *)luat_heap_malloc(oob_size);
        if (ctx->oob_ram == NULL) {
            LLOGE("nfs: oob_ram alloc failed (%u bytes)", (unsigned int)oob_size);
            return NULL;
        }
        memset(ctx->oob_ram, 0xFF, oob_size);
        LLOGD("nfs: oob_ram allocated %u bytes", (unsigned int)oob_size);
    }

    LLOGD("nfs: adding device '%s' offset=%u maxsize=%u",
          ctx->dev_name, (unsigned int)offset, (unsigned int)maxsize);

    ret = nfs_add_device(ctx->dev_name, &drv, &geo);
    if (ret != NFS_OK) {
        LLOGE("nfs: nfs_add_device failed ret=%d", ret);
        return NULL;
    }

    /* Try mount first.  If it succeeds and a write-probe passes,
     * the filesystem was already formatted — reuse it.
     * Otherwise format from scratch. */
    ret = nfs_mount(ctx->dev_name);
    LLOGD("nfs: nfs_mount ret=%d", ret);

    if (ret == NFS_OK && lf_nfs_probe_write(ctx)) {
        /* Existing valid filesystem — reuse */
        LLOGD("nfs: reuse existing filesystem on '%s'", ctx->dev_name);
    } else {
        /* Mount failed or filesystem was RAM-only on erased flash */
        if (ret == NFS_OK) {
            LLOGD("nfs: mount succeeded but write-probe failed, reformatting");
            nfs_unmount(ctx->dev_name);
        } else {
            LLOGD("nfs: mount failed, need format");
        }

        ret = nfs_format(ctx->dev_name);
        LLOGD("nfs: nfs_format ret=%d", ret);
        if (ret != NFS_OK) {
            LLOGE("nfs: nfs_format failed ret=%d", ret);
            goto fail_cleanup;
        }

        ret = nfs_mount(ctx->dev_name);
        LLOGD("nfs: nfs_mount after format ret=%d", ret);
        if (ret != NFS_OK) {
            LLOGE("nfs: nfs_mount after format failed ret=%d", ret);
            goto fail_cleanup;
        }
    }

    ctx->is_mounted = 1;
    LLOGD("nfs: device '%s' ready", ctx->dev_name);
    return ctx;

fail_cleanup:
    nfs_remove_device(ctx->dev_name);
    if (ctx->oob_ram) {
        luat_heap_free(ctx->oob_ram);
        ctx->oob_ram = NULL;
    }
    return NULL;
}

#endif /* LUAT_USE_LITTLE_FLASH */
