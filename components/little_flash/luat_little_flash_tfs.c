/*
 * luat_little_flash_tfs.c — TFS (Tiny File System) adapter for little_flash
 *
 * Bridges the little_flash SPI/NAND hardware layer to TFS's tfs_drv_t
 * callback interface.  Provides the factory function flash_tfs_lf().
 *
 * little_flash does not expose persistent OOB (spare) access, so this
 * adapter uses TFS inband tags mode and stores packed tags in the tail
 * of each page's main area.
 */

#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef LUAT_USE_LITTLE_FLASH

#include "little_flash.h"
#include "../tfs/inc/tfs.h"
#include "../tfs/inc/tfs_port.h"
#include "../tfs/inc/tfs_types.h"

/*===================================================================
 *  Context
 *===================================================================*/

typedef struct {
    little_flash_t *flash;
    uint32_t        offset;
    uint32_t        maxsize;
    char            dev_name[16]; /* "tfs0" */
    int             is_mounted;
    int             is_nand;
    uint8_t        *oob_ram;
    uint32_t        oob_per_chunk;
    uint32_t        total_chunks;
} luat_lf_tfs_ctx_t;

static luat_lf_tfs_ctx_t s_tfs_ctx;
static int               s_tfs_inited = 0;

/*===================================================================
 *  NAND callbacks — bridge little_flash → tfs_drv_t
 *===================================================================*/

static int lf_tfs_write_page(void *ctx, uint32_t page,
                             const uint8_t *data, uint32_t data_len,
                             const uint8_t *oob,  uint32_t oob_len)
{
    luat_lf_tfs_ctx_t *c = (luat_lf_tfs_ctx_t *)ctx;
    if (c == NULL || c->flash == NULL) return TFS_FAIL;

    uint32_t addr = c->offset + page * c->flash->chip_info.prog_size;

    if (data && data_len > 0) {
        if (little_flash_write(c->flash, addr, data, data_len) != LF_ERR_OK) {
            LLOGE("tfs: write_page FAILED page=%u", (unsigned int)page);
            return TFS_EFLASH;
        }
    }
    if (oob && oob_len > 0 && c->oob_ram && page < c->total_chunks) {
        uint32_t n = oob_len < c->oob_per_chunk ? oob_len : c->oob_per_chunk;
        memcpy(c->oob_ram + page * c->oob_per_chunk, oob, n);
    }
    return TFS_OK;
}

static int lf_tfs_read_page(void *ctx, uint32_t page,
                            uint8_t *data, uint32_t data_len,
                            uint8_t *oob,  uint32_t oob_len)
{
    luat_lf_tfs_ctx_t *c = (luat_lf_tfs_ctx_t *)ctx;
    if (c == NULL || c->flash == NULL) return TFS_FAIL;

    uint32_t addr = c->offset + page * c->flash->chip_info.prog_size;

    if (data && data_len > 0) {
        if (little_flash_read(c->flash, addr, data, data_len) != LF_ERR_OK)
            return TFS_EFLASH;
    }
    if (oob && oob_len > 0 && c->oob_ram && page < c->total_chunks) {
        uint32_t n = oob_len < c->oob_per_chunk ? oob_len : c->oob_per_chunk;
        memcpy(oob, c->oob_ram + page * c->oob_per_chunk, n);
    } else if (oob && oob_len > 0) {
        memset(oob, 0xFF, oob_len);
    }
    return TFS_OK;
}

static int lf_tfs_erase_block(void *ctx, uint32_t block)
{
    luat_lf_tfs_ctx_t *c = (luat_lf_tfs_ctx_t *)ctx;
    if (c == NULL || c->flash == NULL) return TFS_FAIL;

    uint32_t bs = c->flash->chip_info.erase_size;
    uint32_t addr = c->offset + block * bs;

    if (little_flash_erase(c->flash, addr, bs) != LF_ERR_OK) {
        LLOGE("tfs: erase_block FAILED block=%u", (unsigned int)block);
        return TFS_EFLASH;
    }

    if (c->oob_ram && c->oob_per_chunk > 0) {
        uint32_t cpb = bs / c->flash->chip_info.prog_size;
        for (uint32_t i = 0; i < cpb; i++) {
            uint32_t idx = block * cpb + i;
            if (idx < c->total_chunks)
                memset(c->oob_ram + idx * c->oob_per_chunk, 0xFF, c->oob_per_chunk);
        }
    }
    return TFS_OK;
}

static int lf_tfs_mark_bad(void *ctx, uint32_t block)
{ (void)ctx; (void)block; return TFS_OK; }

static int lf_tfs_check_bad(void *ctx, uint32_t block)
{ (void)ctx; (void)block; return 0; }

/*===================================================================
 *  OS callbacks
 *===================================================================*/

static void *lf_tfs_malloc(void *ctx, uint32_t size)
{ (void)ctx; return luat_heap_malloc((size_t)size); }

static void lf_tfs_free(void *ctx, void *ptr)
{ (void)ctx; luat_heap_free(ptr); }

static void lf_tfs_lock(void *ctx)   { (void)ctx; }
static void lf_tfs_unlock(void *ctx) { (void)ctx; }
static uint32_t lf_tfs_get_time(void) { return 0; }
static void lf_tfs_trace(const char *fmt, ...) { (void)fmt; }

/*===================================================================
 *  Driver factory
 *===================================================================*/

static void lf_tfs_fill_drv(tfs_drv_t *drv, luat_lf_tfs_ctx_t *ctx)
{
    memset(drv, 0, sizeof(*drv));
    drv->ctx         = ctx;
    drv->write_page  = lf_tfs_write_page;
    drv->read_page   = lf_tfs_read_page;
    drv->erase_block = lf_tfs_erase_block;
    drv->mark_bad    = lf_tfs_mark_bad;
    drv->check_bad   = lf_tfs_check_bad;
    drv->malloc      = lf_tfs_malloc;
    drv->free        = lf_tfs_free;
    drv->lock        = lf_tfs_lock;
    drv->unlock      = lf_tfs_unlock;
    drv->get_time    = lf_tfs_get_time;
    drv->trace       = lf_tfs_trace;
}

/*===================================================================
 *  Geometry
 *===================================================================*/

static void lf_tfs_fill_geo(tfs_geo_t *geo, luat_lf_tfs_ctx_t *ctx)
{
    little_flash_t *flash = ctx->flash;
    uint32_t ps = flash->chip_info.prog_size;
    uint32_t es = flash->chip_info.erase_size;
    uint32_t capacity = flash->chip_info.capacity;
    uint32_t inband_tags = 1;
    uint32_t spare_size = inband_tags ? 0 : 64;

    memset(geo, 0, sizeof(*geo));

    uint32_t total_size = capacity - ctx->offset;
    if (ctx->maxsize > 0 && ctx->maxsize < total_size)
        total_size = ctx->maxsize;

    uint32_t block_count = total_size / es;
    if (block_count == 0) block_count = 1;

    ctx->oob_per_chunk = spare_size;
    ctx->total_chunks  = block_count * (es / ps);

    geo->data_bytes_per_chunk  = ps;
    geo->spare_bytes_per_chunk = spare_size;
    geo->chunks_per_block      = es / ps;
    geo->start_block           = 0;
    geo->end_block             = block_count - 1;
    geo->inband_tags           = (int)inband_tags;
    geo->stored_endian         = 0;

    LLOGD("tfs geo: chunksize=%u spare=%u inband=%u cpb=%u blocks=%u oob_ram=%u",
          (unsigned int)ps, (unsigned int)spare_size,
          (unsigned int)inband_tags,
          (unsigned int)(es / ps), (unsigned int)block_count,
          (unsigned int)(ctx->total_chunks * spare_size));
}

/*===================================================================
 *  Mount-first write-probe
 *===================================================================*/

static int lf_tfs_probe_write(luat_lf_tfs_ctx_t *ctx)
{
    char path[64];
    snprintf(path, sizeof(path), "/%s/.tfs_probe", ctx->dev_name);
    int fd = tfs_open(path, TFS_O_CREAT | TFS_O_RDWR | TFS_O_TRUNC, 0);
    if (fd >= 0) {
        int ok = (tfs_write(fd, "ok", 2) == 2);
        tfs_close(fd);
        tfs_unlink(path);
        if (ok) return 1;
    }
    return 0;
}

/*===================================================================
 *  Factory: flash_tfs_lf()
 *===================================================================*/

void *flash_tfs_lf(little_flash_t *flash, size_t offset, size_t maxsize)
{
    if (flash == NULL) { LLOGE("tfs: flash is null"); return NULL; }

    if (!s_tfs_inited) { tfs_init(); s_tfs_inited = 1; }

    luat_lf_tfs_ctx_t *ctx = &s_tfs_ctx;
    memset(ctx, 0, sizeof(*ctx));
    ctx->flash   = flash;
    ctx->offset  = (uint32_t)offset;
    ctx->maxsize = (uint32_t)maxsize;
    ctx->is_nand = (flash->chip_info.type == LF_DRIVER_NAND_FLASH);
    snprintf(ctx->dev_name, sizeof(ctx->dev_name), "tfs0");

    tfs_drv_t drv;
    tfs_geo_t geo;
    lf_tfs_fill_drv(&drv, ctx);
    lf_tfs_fill_geo(&geo, ctx);

    if (ctx->oob_per_chunk > 0 && ctx->total_chunks > 0) {
        size_t sz = (size_t)ctx->total_chunks * ctx->oob_per_chunk;
        ctx->oob_ram = (uint8_t *)luat_heap_malloc(sz);
        if (!ctx->oob_ram) { LLOGE("tfs: oob_ram alloc failed"); return NULL; }
        memset(ctx->oob_ram, 0xFF, sz);
        LLOGD("tfs: oob_ram allocated %u bytes", (unsigned int)sz);
    }

    LLOGD("tfs: adding device '%s' offset=%u maxsize=%u",
          ctx->dev_name, (unsigned int)offset, (unsigned int)maxsize);

    int ret = tfs_add_device(ctx->dev_name, &drv, &geo);
    if (ret != TFS_OK) { LLOGE("tfs: add_device failed %d", ret); return NULL; }

    ret = tfs_mount(ctx->dev_name);
    LLOGD("tfs: mount ret=%d", ret);

    if (ret == TFS_OK && lf_tfs_probe_write(ctx)) {
        LLOGD("tfs: reuse existing filesystem");
    } else {
        if (ret == TFS_OK) {
            LLOGD("tfs: probe failed, reformatting");
            tfs_unmount(ctx->dev_name);
        }
        ret = tfs_format(ctx->dev_name);
        LLOGD("tfs: format ret=%d", ret);
        if (ret != TFS_OK) { LLOGE("tfs: format failed"); goto fail; }
        ret = tfs_mount(ctx->dev_name);
        LLOGD("tfs: mount after format ret=%d", ret);
        if (ret != TFS_OK) { LLOGE("tfs: mount after format failed"); goto fail; }
    }

    ctx->is_mounted = 1;
    LLOGD("tfs: device '%s' ready", ctx->dev_name);
    return ctx;

fail:
    tfs_remove_device(ctx->dev_name);
    if (ctx->oob_ram) { luat_heap_free(ctx->oob_ram); ctx->oob_ram = NULL; }
    return NULL;
}

#endif /* LUAT_USE_LITTLE_FLASH */
