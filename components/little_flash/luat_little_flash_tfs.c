#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef LUAT_USE_LITTLE_FLASH

#include "little_flash.h"
#include "../tfs/inc/tfs.h"
#include "../tfs/inc/tfs_config.h"
#include "../tfs/inc/tfs_port.h"
#include "../tfs/inc/tfs_types.h"
#include "../tfs/src/tfs_core.h"

#include <string.h>

#define LF_TFS_BLANK_PROBE_BLOCKS 2U
#define LF_TFS_NAME_MARKER        ".tfs_fullname_tnode2_cache1_ckpt2"
#define LF_TFS_NAME_MARKER_TEXT   "TFS_FULL_NAME=1;TNODE_LEVEL_FIX=2;CACHE_DROP_CLEAN=1;CHECKPOINT_LATEST=2\n"
#define LF_TFS_RAW_MARKER_TEXT    "LFTFS1;TFS_FULL_NAME=1;TNODE_LEVEL_FIX=2;CACHE_DROP_CLEAN=1;CHECKPOINT_LATEST=2\n"
#define LF_TFS_MARKER_BUF_SIZE    128U
#define LF_TFS_RAW_MARKER_MISSING 0
#define LF_TFS_RAW_MARKER_CURRENT 2
#define LF_TFS_ANCHOR_MAGIC       0x314B4343U
#define LF_TFS_ANCHOR_OFFSET      256U
#define LF_TFS_BAD_TABLE_OFFSET   512U
#define LF_TFS_BAD_TABLE_MAGIC    0x31444242U
#define LF_TFS_BAD_TABLE_VERSION  1U
#define LF_TFS_READ_RETRY_COUNT   3U
#define LF_TFS_BAD_MAX_BLOCKS     256U
#define LF_TFS_READ_RETRY_10US    20U
#define LF_TFS_READ_WAIT_10US     1000U

typedef struct {
    uint32_t magic;
    uint32_t seq;
    uint32_t chunk;
    uint32_t check;
} lf_tfs_anchor_slot_t;

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t count;
    uint32_t check;
} lf_tfs_bad_table_hdr_t;

typedef struct {
    little_flash_t *flash;
    uint32_t        offset;
    uint32_t        maxsize;
    char            dev_name[16];
    int             is_mounted;
    int             is_nand;
    uint8_t        *oob_ram;
    uint32_t        oob_per_chunk;
    uint32_t        total_chunks;
    uint32_t        marker_addr;
    uint32_t        read_error_count;
    uint32_t        read_ecc_corrected_count;
    uint32_t        read_ecc_refresh_count;
    uint32_t        anchor_log_count;
    uint32_t        write_verify_error_count;
    uint32_t        bad_blocks[LF_TFS_BAD_MAX_BLOCKS];
    uint32_t        bad_block_count;
} luat_lf_tfs_ctx_t;

static luat_lf_tfs_ctx_t s_tfs_ctx;
static int               s_tfs_inited = 0;

static lf_err_t lf_tfs_read_flash(luat_lf_tfs_ctx_t *ctx, uint32_t addr,
                                  uint8_t *data, uint32_t len,
                                  uint8_t *last_status);

static uint32_t lf_tfs_region_size(const luat_lf_tfs_ctx_t *ctx)
{
    uint32_t total_size;

    if (!ctx || !ctx->flash || ctx->offset >= ctx->flash->chip_info.capacity) {
        return 0;
    }

    total_size = ctx->flash->chip_info.capacity - ctx->offset;
    if (ctx->maxsize > 0 && ctx->maxsize < total_size) {
        total_size = ctx->maxsize;
    }
    return total_size;
}

static int lf_tfs_is_all_ff(const uint8_t *data, size_t len)
{
    size_t i;

    if (!data) {
        return 0;
    }
    for (i = 0; i < len; i++) {
        if (data[i] != 0xFF) {
            return 0;
        }
    }
    return 1;
}

static uint32_t lf_tfs_block_count(const luat_lf_tfs_ctx_t *ctx)
{
    uint32_t cpb;

    if (!ctx || !ctx->flash ||
        ctx->flash->chip_info.prog_size == 0 ||
        ctx->flash->chip_info.erase_size == 0) {
        return 0;
    }
    cpb = ctx->flash->chip_info.erase_size / ctx->flash->chip_info.prog_size;
    return cpb ? (ctx->total_chunks / cpb) : 0;
}

static int lf_tfs_bad_block_valid(const luat_lf_tfs_ctx_t *ctx, uint32_t block)
{
    uint32_t blocks = lf_tfs_block_count(ctx);
    return blocks > 0 && block < blocks;
}

static int lf_tfs_bad_block_index(const luat_lf_tfs_ctx_t *ctx, uint32_t block)
{
    uint32_t i;

    if (!ctx) {
        return -1;
    }
    for (i = 0; i < ctx->bad_block_count; i++) {
        if (ctx->bad_blocks[i] == block) {
            return (int)i;
        }
    }
    return -1;
}

static uint32_t lf_tfs_bad_table_check_values(const uint32_t *blocks,
                                              uint32_t count)
{
    uint32_t acc = LF_TFS_BAD_TABLE_MAGIC ^
                   LF_TFS_BAD_TABLE_VERSION ^
                   count;
    uint32_t i;

    for (i = 0; i < count; i++) {
        acc = (acc << 5) | (acc >> 27);
        acc ^= blocks[i] + 0x9E3779B9U + i;
    }
    return ~acc;
}

static uint32_t lf_tfs_bad_table_check_raw(const uint8_t *entries,
                                           uint32_t count)
{
    uint32_t acc = LF_TFS_BAD_TABLE_MAGIC ^
                   LF_TFS_BAD_TABLE_VERSION ^
                   count;
    uint32_t i;

    for (i = 0; i < count; i++) {
        uint32_t block = 0;
        memcpy(&block, entries + i * sizeof(block), sizeof(block));
        acc = (acc << 5) | (acc >> 27);
        acc ^= block + 0x9E3779B9U + i;
    }
    return ~acc;
}

static int lf_tfs_bad_table_add_ram(luat_lf_tfs_ctx_t *ctx, uint32_t block)
{
    if (!ctx || !lf_tfs_bad_block_valid(ctx, block)) {
        return -1;
    }
    if (lf_tfs_bad_block_index(ctx, block) >= 0) {
        return 0;
    }
    if (ctx->bad_block_count >= LF_TFS_BAD_MAX_BLOCKS) {
        return -1;
    }
    ctx->bad_blocks[ctx->bad_block_count++] = block;
    return 1;
}

static void lf_tfs_bad_table_write_page(luat_lf_tfs_ctx_t *ctx,
                                        uint8_t *page,
                                        uint32_t page_size)
{
    lf_tfs_bad_table_hdr_t hdr;
    uint32_t bytes;

    if (!ctx || !page || ctx->bad_block_count == 0 ||
        page_size < LF_TFS_BAD_TABLE_OFFSET + sizeof(hdr)) {
        return;
    }

    bytes = ctx->bad_block_count * sizeof(ctx->bad_blocks[0]);
    if (page_size < LF_TFS_BAD_TABLE_OFFSET + sizeof(hdr) + bytes) {
        return;
    }

    hdr.magic = LF_TFS_BAD_TABLE_MAGIC;
    hdr.version = LF_TFS_BAD_TABLE_VERSION;
    hdr.count = ctx->bad_block_count;
    hdr.check = lf_tfs_bad_table_check_values(ctx->bad_blocks, hdr.count);

    memcpy(page + LF_TFS_BAD_TABLE_OFFSET, &hdr, sizeof(hdr));
    memcpy(page + LF_TFS_BAD_TABLE_OFFSET + sizeof(hdr),
           ctx->bad_blocks,
           bytes);
}

static int lf_tfs_bad_table_load_page(luat_lf_tfs_ctx_t *ctx,
                                      const uint8_t *page,
                                      uint32_t page_size)
{
    lf_tfs_bad_table_hdr_t hdr;
    const uint8_t *entries;
    uint32_t i;

    if (!ctx || !page ||
        page_size < LF_TFS_BAD_TABLE_OFFSET + sizeof(hdr)) {
        return 0;
    }

    memcpy(&hdr, page + LF_TFS_BAD_TABLE_OFFSET, sizeof(hdr));
    if (lf_tfs_is_all_ff((const uint8_t *)&hdr, sizeof(hdr))) {
        ctx->bad_block_count = 0;
        return 1;
    }
    if (hdr.magic != LF_TFS_BAD_TABLE_MAGIC ||
        hdr.version != LF_TFS_BAD_TABLE_VERSION ||
        hdr.count > LF_TFS_BAD_MAX_BLOCKS ||
        page_size < LF_TFS_BAD_TABLE_OFFSET + sizeof(hdr) +
                    hdr.count * sizeof(uint32_t)) {
        return 0;
    }

    entries = page + LF_TFS_BAD_TABLE_OFFSET + sizeof(hdr);
    if (lf_tfs_bad_table_check_raw(entries, hdr.count) != hdr.check) {
        return 0;
    }

    ctx->bad_block_count = 0;
    for (i = 0; i < hdr.count; i++) {
        uint32_t block = 0;
        memcpy(&block, entries + i * sizeof(block), sizeof(block));
        (void)lf_tfs_bad_table_add_ram(ctx, block);
    }
    return 1;
}

static void lf_tfs_bad_table_load(luat_lf_tfs_ctx_t *ctx)
{
    uint32_t page_size;
    uint8_t *page;
    uint8_t status = 0;

    if (!ctx || !ctx->flash || ctx->marker_addr == 0) {
        return;
    }

    page_size = ctx->flash->chip_info.prog_size;
    page = (uint8_t *)luat_heap_malloc(page_size);
    if (!page) {
        LLOGW("tfs: bad table alloc failed");
        return;
    }

    if (lf_tfs_read_flash(ctx, ctx->marker_addr, page, page_size, &status) != LF_ERR_OK ||
        !lf_tfs_bad_table_load_page(ctx, page, page_size)) {
        ctx->bad_block_count = 0;
        LLOGW("tfs: bad table missing or invalid status=0x%02X",
              (unsigned int)status);
    } else if (ctx->bad_block_count > 0) {
        LLOGD("tfs: loaded bad block table count=%u",
              (unsigned int)ctx->bad_block_count);
    }
    luat_heap_free(page);
}

static int lf_tfs_looks_blank(luat_lf_tfs_ctx_t *ctx)
{
    uint32_t page_size;
    uint32_t probe_size;
    uint32_t total_size;
    uint32_t offset;
    uint8_t *page_buf;
    int blank = 0;

    if (!ctx || !ctx->flash) {
        return 0;
    }

    page_size = ctx->flash->chip_info.prog_size;
    if (page_size == 0) {
        return 0;
    }

    total_size = lf_tfs_region_size(ctx);
    if (total_size == 0) {
        return 0;
    }

    probe_size = ctx->flash->chip_info.erase_size * LF_TFS_BLANK_PROBE_BLOCKS;
    if (probe_size == 0 || probe_size > total_size) {
        probe_size = total_size;
    }

    page_buf = (uint8_t *)luat_heap_malloc(page_size);
    if (!page_buf) {
        LLOGW("tfs: blank probe alloc failed");
        return 0;
    }

    blank = 1;
    for (offset = 0; offset < probe_size; offset += page_size) {
        uint8_t status = 0;

        if (lf_tfs_read_flash(ctx,
                              ctx->offset + offset,
                              page_buf,
                              page_size,
                              &status) != LF_ERR_OK) {
            LLOGW("tfs: blank probe read failed offset=%u status=0x%02X",
                  (unsigned int)offset,
                  (unsigned int)status);
            blank = 0;
            break;
        }
        if (!lf_tfs_is_all_ff(page_buf, page_size)) {
            blank = 0;
            break;
        }
    }

    luat_heap_free(page_buf);
    return blank;
}

static int lf_tfs_raw_marker_state(luat_lf_tfs_ctx_t *ctx)
{
    uint8_t marker[LF_TFS_MARKER_BUF_SIZE];
    uint8_t status = 0;
    size_t len;

    if (!ctx || !ctx->flash || ctx->marker_addr == 0) {
        return LF_TFS_RAW_MARKER_MISSING;
    }

    memset(marker, 0xFF, sizeof(marker));
    if (lf_tfs_read_flash(ctx,
                          ctx->marker_addr,
                          marker,
                          (uint32_t)sizeof(marker),
                          &status) != LF_ERR_OK) {
        return LF_TFS_RAW_MARKER_MISSING;
    }
    len = strlen(LF_TFS_RAW_MARKER_TEXT);
    if (memcmp(marker, LF_TFS_RAW_MARKER_TEXT, len) == 0) {
        return LF_TFS_RAW_MARKER_CURRENT;
    }
    return LF_TFS_RAW_MARKER_MISSING;
}

static int lf_tfs_write_marker_page(luat_lf_tfs_ctx_t *ctx,
                                    const lf_tfs_anchor_slot_t *anchor)
{
    uint32_t erase_size;
    uint32_t page_size;
    uint8_t *page;
    int ok = 0;

    if (!ctx || !ctx->flash || ctx->marker_addr == 0) {
        return 0;
    }

    erase_size = ctx->flash->chip_info.erase_size;
    page_size = ctx->flash->chip_info.prog_size;
    if (erase_size == 0 || page_size < strlen(LF_TFS_RAW_MARKER_TEXT)) {
        return 0;
    }
    if (anchor && page_size < LF_TFS_ANCHOR_OFFSET + sizeof(*anchor)) {
        return 0;
    }

    page = (uint8_t *)luat_heap_malloc(page_size);
    if (!page) {
        LLOGW("tfs: raw marker page alloc failed");
        return 0;
    }
    memset(page, 0xFF, page_size);
    memcpy(page, LF_TFS_RAW_MARKER_TEXT, strlen(LF_TFS_RAW_MARKER_TEXT));
    if (anchor) {
        memcpy(page + LF_TFS_ANCHOR_OFFSET, anchor, sizeof(*anchor));
    }
    lf_tfs_bad_table_write_page(ctx, page, page_size);

    if (little_flash_erase(ctx->flash, ctx->marker_addr, erase_size) != LF_ERR_OK) {
        LLOGW("tfs: raw marker erase failed");
        goto done;
    }
    if (little_flash_write(ctx->flash,
                           ctx->marker_addr,
                           page,
                           page_size) != LF_ERR_OK) {
        LLOGW("tfs: raw marker write failed");
        goto done;
    }
    if (ctx->is_nand) {
        uint8_t *verify = (uint8_t *)luat_heap_malloc(page_size);
        uint8_t status = 0;

        if (!verify) {
            LLOGW("tfs: raw marker verify alloc failed");
            goto done;
        }
        if (lf_tfs_read_flash(ctx,
                              ctx->marker_addr,
                              verify,
                              page_size,
                              &status) != LF_ERR_OK ||
            memcmp(verify, page, page_size) != 0) {
            LLOGW("tfs: raw marker verify failed status=0x%02X",
                  (unsigned int)status);
            luat_heap_free(verify);
            goto done;
        }
        luat_heap_free(verify);
    }
    ok = 1;

done:
    luat_heap_free(page);
    return ok;
}

static int lf_tfs_write_raw_marker(luat_lf_tfs_ctx_t *ctx)
{
    return lf_tfs_write_marker_page(ctx, NULL);
}

static int lf_tfs_sync(luat_lf_tfs_ctx_t *ctx)
{
    int ret;

    if (!ctx) {
        return TFS_FAIL;
    }

    ret = tfs_sync(ctx->dev_name);
    if (ret != TFS_OK) {
        LLOGW("tfs: sync ret=%d", ret);
    } else {
        LLOGD("tfs: synced");
    }
    return ret;
}

static int lf_tfs_marker_path(luat_lf_tfs_ctx_t *ctx, char *path, size_t size)
{
    int ret;

    if (!ctx || !path || size == 0) {
        return 0;
    }

    ret = snprintf(path, size, "/%s/%s", ctx->dev_name, LF_TFS_NAME_MARKER);
    return ret > 0 && (size_t)ret < size;
}

static int lf_tfs_write_name_marker(luat_lf_tfs_ctx_t *ctx)
{
    char path[64];
    int fd;
    int ok;

    if (!lf_tfs_marker_path(ctx, path, sizeof(path))) {
        return 0;
    }

    fd = tfs_open(path, TFS_O_CREAT | TFS_O_RDWR | TFS_O_TRUNC, 0644);
    if (fd < 0) {
        LLOGW("tfs: open name marker failed");
        return 0;
    }

    ok = (tfs_write(fd,
                    LF_TFS_NAME_MARKER_TEXT,
                    (int)(sizeof(LF_TFS_NAME_MARKER_TEXT) - 1)) ==
          (int)(sizeof(LF_TFS_NAME_MARKER_TEXT) - 1));
    if (tfs_close(fd) != 0) {
        ok = 0;
    }
    if (!ok) {
        LLOGW("tfs: write name marker failed");
    }
    return ok;
}

static int lf_tfs_name_marker_ok(luat_lf_tfs_ctx_t *ctx)
{
    char path[64];
    char marker[LF_TFS_MARKER_BUF_SIZE] = {0};
    int fd;
    int read_len;

    if (!lf_tfs_marker_path(ctx, path, sizeof(path))) {
        return 0;
    }

    fd = tfs_open(path, TFS_O_RDONLY, 0);
    if (fd < 0) {
        return 0;
    }

    read_len = tfs_read(fd, marker, (int)(sizeof(marker) - 1));
    tfs_close(fd);
    if (read_len < 0) {
        return 0;
    }
    marker[sizeof(marker) - 1] = '\0';
    return strcmp(marker, LF_TFS_NAME_MARKER_TEXT) == 0;
}

static int lf_tfs_write_page(void *ctx, uint32_t page,
                             const uint8_t *data, uint32_t data_len,
                             const uint8_t *oob, uint32_t oob_len)
{
    luat_lf_tfs_ctx_t *c = (luat_lf_tfs_ctx_t *)ctx;
    uint32_t addr;

    if (!c || !c->flash) {
        return TFS_FAIL;
    }

    addr = c->offset + page * c->flash->chip_info.prog_size;
    if (data && data_len > 0) {
        uint8_t *verify = NULL;
        uint8_t status = 0;

        if (c->is_nand) {
            uint32_t mismatch = data_len;
            uint32_t i;

            verify = (uint8_t *)luat_heap_malloc(data_len);
            if (!verify) {
                LLOGE("tfs: write verify alloc failed page=%u len=%u",
                      (unsigned int)page,
                      (unsigned int)data_len);
                return TFS_ENOMEM;
            }

            if (lf_tfs_read_flash(c, addr, verify, data_len, &status) != LF_ERR_OK) {
                c->write_verify_error_count++;
                if (c->write_verify_error_count <= 8) {
                    LLOGW("tfs: write precheck read error page=%u status=0x%02X count=%u",
                          (unsigned int)page,
                          (unsigned int)status,
                          (unsigned int)c->write_verify_error_count);
                }
                luat_heap_free(verify);
                return TFS_EFLASH;
            }

            for (i = 0; i < data_len; i++) {
                if (verify[i] != 0xff) {
                    mismatch = i;
                    break;
                }
            }

            if (mismatch < data_len) {
                c->write_verify_error_count++;
                if (c->write_verify_error_count <= 8) {
                    LLOGW("tfs: write target not blank page=%u off=%u val=%02X count=%u",
                          (unsigned int)page,
                          (unsigned int)mismatch,
                          (unsigned int)verify[mismatch],
                          (unsigned int)c->write_verify_error_count);
                }
                luat_heap_free(verify);
                return TFS_EFLASH;
            }
        }

        if (little_flash_write(c->flash, addr, data, data_len) != LF_ERR_OK) {
            LLOGE("tfs: write_page failed page=%u", (unsigned int)page);
            if (verify) {
                luat_heap_free(verify);
            }
            return TFS_EFLASH;
        }

        if (c->is_nand) {
            int verify_ok = 0;
            uint32_t mismatch = data_len;
            uint32_t i;

            if (lf_tfs_read_flash(c, addr, verify, data_len, &status) == LF_ERR_OK &&
                memcmp(verify, data, data_len) == 0) {
                verify_ok = 1;
            } else {
                for (i = 0; i < data_len; i++) {
                    if (verify[i] != data[i]) {
                        mismatch = i;
                        break;
                    }
                }
            }

            if (!verify_ok) {
                c->write_verify_error_count++;
                if (c->write_verify_error_count <= 8) {
                    if (mismatch < data_len) {
                        LLOGW("tfs: write verify mismatch page=%u status=0x%02X off=%u exp=%02X got=%02X count=%u",
                              (unsigned int)page,
                              (unsigned int)status,
                              (unsigned int)mismatch,
                              (unsigned int)data[mismatch],
                              (unsigned int)verify[mismatch],
                              (unsigned int)c->write_verify_error_count);
                    } else {
                        LLOGW("tfs: write verify mismatch page=%u status=0x%02X count=%u",
                              (unsigned int)page,
                              (unsigned int)status,
                              (unsigned int)c->write_verify_error_count);
                    }
                }
                luat_heap_free(verify);
                return TFS_EFLASH;
            }
            luat_heap_free(verify);
        }
    }

    if (oob && oob_len > 0 && c->oob_ram && page < c->total_chunks) {
        uint32_t copy = (oob_len < c->oob_per_chunk) ? oob_len : c->oob_per_chunk;
        memcpy(c->oob_ram + page * c->oob_per_chunk, oob, copy);
    }
    return TFS_OK;
}

static lf_err_t lf_tfs_wait_nand_ready(little_flash_t *flash, uint8_t *status)
{
    uint32_t wait_left = LF_TFS_READ_WAIT_10US;
    lf_err_t ret;

    if (!flash || !status) {
        return LF_ERR_READ;
    }

    do {
        ret = little_flash_read_status(flash, LF_NANDFLASH_STATUS_REGISTER3, status);
        if (ret == LF_ERR_OK && ((*status & LF_STATUS_REGISTER_BUSY) == 0)) {
            return LF_ERR_OK;
        }
        if (flash->wait_10us) {
            flash->wait_10us(1);
        }
    } while (wait_left-- > 0);

    return LF_ERR_TIMEOUT;
}

static int lf_tfs_nand_ecc_ok(luat_lf_tfs_ctx_t *ctx, uint32_t page, uint8_t status)
{
    uint8_t ecc = (status & 0x30) >> 4;

    if (ecc == 0) {
        return 1;  /* No errors */
    }
    if (ecc == 1) {
        if (ctx->read_ecc_corrected_count < 8) {
            ctx->read_ecc_corrected_count++;
            LLOGW("tfs: nand ecc corrected page=%u status=0x%02X",
                  (unsigned int)page,
                  (unsigned int)status);
        }
        return 1;  /* 1-2 bit corrected: still usable */
    }
    if (ecc == 2) {
        return 0;  /* Multiple bit flips were not corrected. */
    }
    if (ctx->read_ecc_refresh_count < 8) {
        ctx->read_ecc_refresh_count++;
        LLOGW("tfs: nand ecc corrected over threshold page=%u status=0x%02X",
              (unsigned int)page,
              (unsigned int)status);
    }
    return 1;
}

static lf_err_t lf_tfs_read_flash(luat_lf_tfs_ctx_t *ctx, uint32_t addr,
                                  uint8_t *data, uint32_t len,
                                  uint8_t *last_status)
{
    little_flash_t *flash;
    uint32_t base_addr = addr;

    if (!ctx || !ctx->flash || !data || len == 0) {
        return LF_ERR_READ;
    }

    flash = ctx->flash;
    if (flash->chip_info.type != LF_DRIVER_NAND_FLASH) {
        return little_flash_read(flash, addr, data, len);
    }

    if (flash->lock) {
        flash->lock(flash);
    }

    while (len > 0) {
        uint8_t cmd_data[4];
        uint8_t status = 0;
        uint32_t page_addr = addr / flash->chip_info.read_size;
        uint16_t column_addr = addr % flash->chip_info.read_size;
        uint32_t read_len = flash->chip_info.read_size - column_addr;
        uint8_t *read_ptr = data + (addr - base_addr);
        lf_err_t ret;
        int ecc_ok;

        if (read_len > len) {
            read_len = len;
        }

        cmd_data[0] = LF_NANDFLASH_PAGE_DATA_READ;
        cmd_data[1] = (uint8_t)(page_addr >> 16);
        cmd_data[2] = (uint8_t)(page_addr >> 8);
        cmd_data[3] = (uint8_t)page_addr;
        ret = flash->spi.transfer(flash, cmd_data, 4, LF_NULL, 0);
        if (ret != LF_ERR_OK) {
            /* FIX A: SPI bus error may leave peripheral in bad state */
            (void)flash->spi.transfer(flash, (uint8_t[]){0xFFu}, 1, LF_NULL, 0);
            (void)lf_tfs_wait_nand_ready(flash, &(uint8_t){0});
            if (flash->unlock) {
                flash->unlock(flash);
            }
            return ret;
        }

        ret = lf_tfs_wait_nand_ready(flash, &status);
        if (last_status) {
            *last_status = status;
        }
        if (ret != LF_ERR_OK) {
            /* Reset after ready/status failure before caller retries. */
            (void)flash->spi.transfer(flash, (uint8_t[]){0xFFu}, 1, LF_NULL, 0);
            (void)lf_tfs_wait_nand_ready(flash, &(uint8_t){0});
            if (flash->unlock) {
                flash->unlock(flash);
            }
            return LF_ERR_READ;
        }
        ecc_ok = lf_tfs_nand_ecc_ok(ctx, page_addr, status);

        cmd_data[0] = LF_CMD_READ_DATA;
        cmd_data[1] = (uint8_t)(column_addr >> 8);
        cmd_data[2] = (uint8_t)column_addr;
        cmd_data[3] = 0;
        ret = flash->spi.transfer(flash, cmd_data, 4, read_ptr, read_len);
        if (ret != LF_ERR_OK ||
            (!ecc_ok && !lf_tfs_is_all_ff(read_ptr, read_len))) {
            /* ECC fail is acceptable only for erased all-0xFF data. */
            (void)flash->spi.transfer(flash, (uint8_t[]){0xFFu}, 1, LF_NULL, 0);
            (void)lf_tfs_wait_nand_ready(flash, &(uint8_t){0});
            if (flash->unlock) {
                flash->unlock(flash);
            }
            return LF_ERR_READ;
        }

        len -= read_len;
        addr += read_len;
    }

    if (flash->unlock) {
        flash->unlock(flash);
    }
    return LF_ERR_OK;
}

static uint32_t lf_tfs_anchor_check(uint32_t seq, uint32_t chunk)
{
    return ~(LF_TFS_ANCHOR_MAGIC ^ seq ^ chunk);
}

static int lf_tfs_anchor_slot_valid(const lf_tfs_anchor_slot_t *slot)
{
    return slot &&
           slot->magic == LF_TFS_ANCHOR_MAGIC &&
           slot->check == lf_tfs_anchor_check(slot->seq, slot->chunk);
}

static int lf_tfs_anchor_slot_erased(const lf_tfs_anchor_slot_t *slot)
{
    return slot && lf_tfs_is_all_ff((const uint8_t *)slot, sizeof(*slot));
}

static int lf_tfs_checkpoint_anchor_read(void *drv_ctx,
                                         uint32_t *chunk,
                                         uint32_t *seq)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)drv_ctx;
    uint32_t erase_size;
    uint32_t off;
    uint32_t best_seq = 0;
    uint32_t best_chunk = 0;
    int found = 0;

    if (!ctx || !ctx->flash || !chunk || !seq || ctx->marker_addr == 0) {
        return TFS_EINVAL;
    }

    erase_size = ctx->flash->chip_info.erase_size;
    if (erase_size > LF_TFS_BAD_TABLE_OFFSET) {
        erase_size = LF_TFS_BAD_TABLE_OFFSET;
    }
    if (erase_size <= LF_TFS_ANCHOR_OFFSET + sizeof(lf_tfs_anchor_slot_t)) {
        return TFS_EINVAL;
    }

    for (off = LF_TFS_ANCHOR_OFFSET;
         off + sizeof(lf_tfs_anchor_slot_t) <= LF_TFS_BAD_TABLE_OFFSET &&
         off + sizeof(lf_tfs_anchor_slot_t) <= erase_size;
         off += sizeof(lf_tfs_anchor_slot_t)) {
        lf_tfs_anchor_slot_t slot;
        uint8_t status = 0;

        if (lf_tfs_read_flash(ctx,
                              ctx->marker_addr + off,
                              (uint8_t *)&slot,
                              sizeof(slot),
                              &status) != LF_ERR_OK) {
            if (ctx->anchor_log_count < 8) {
                LLOGW("tfs: anchor read failed off=%u status=0x%02X",
                      (unsigned int)off,
                      (unsigned int)status);
                ctx->anchor_log_count++;
            }
            break;
        }
        if (lf_tfs_anchor_slot_erased(&slot)) {
            break;
        }
        if (lf_tfs_anchor_slot_valid(&slot) &&
            (!found || slot.seq > best_seq)) {
            best_seq = slot.seq;
            best_chunk = slot.chunk;
            found = 1;
        }
    }

    if (!found) {
        if (ctx->anchor_log_count < 8) {
            LLOGD("tfs: anchor missing");
            ctx->anchor_log_count++;
        }
        return TFS_EINVAL;
    }

    *chunk = best_chunk;
    *seq = best_seq;
    if (ctx->anchor_log_count < 8) {
        LLOGD("tfs: anchor read chunk=%u seq=%u",
              (unsigned int)best_chunk,
              (unsigned int)best_seq);
        ctx->anchor_log_count++;
    }
    return TFS_OK;
}

static int lf_tfs_checkpoint_anchor_write(void *drv_ctx,
                                          uint32_t chunk,
                                          uint32_t seq)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)drv_ctx;
    uint32_t old_chunk;
    uint32_t old_seq;
    lf_tfs_anchor_slot_t slot;

    if (!ctx || !ctx->flash || ctx->marker_addr == 0) {
        return TFS_EINVAL;
    }
    if (ctx->flash->chip_info.prog_size < LF_TFS_ANCHOR_OFFSET + sizeof(slot)) {
        return TFS_EINVAL;
    }

    if (lf_tfs_checkpoint_anchor_read(ctx, &old_chunk, &old_seq) == TFS_OK &&
        old_chunk == chunk &&
        old_seq == seq) {
        return TFS_OK;
    }

    slot.magic = LF_TFS_ANCHOR_MAGIC;
    slot.seq = seq;
    slot.chunk = chunk;
    slot.check = lf_tfs_anchor_check(seq, chunk);

    if (!lf_tfs_write_marker_page(ctx, &slot)) {
        LLOGW("tfs: anchor write failed chunk=%u seq=%u",
              (unsigned int)chunk,
              (unsigned int)seq);
        return TFS_EIO;
    }
    LLOGD("tfs: anchor written chunk=%u seq=%u",
          (unsigned int)chunk,
          (unsigned int)seq);
    return TFS_OK;
}

static int lf_tfs_read_page(void *ctx, uint32_t page,
                            uint8_t *data, uint32_t data_len,
                            uint8_t *oob, uint32_t oob_len)
{
    luat_lf_tfs_ctx_t *c = (luat_lf_tfs_ctx_t *)ctx;
    uint32_t addr;

    if (!c || !c->flash) {
        return TFS_FAIL;
    }

    addr = c->offset + page * c->flash->chip_info.prog_size;
    if (data && data_len > 0) {
        uint32_t attempt;
        lf_err_t ret = LF_ERR_READ;
        uint8_t status = 0;

        for (attempt = 0; attempt <= LF_TFS_READ_RETRY_COUNT; attempt++) {
            ret = lf_tfs_read_flash(c, addr, data, data_len, &status);
            if (ret == LF_ERR_OK) {
                break;
            }
            if (attempt < LF_TFS_READ_RETRY_COUNT && c->flash->wait_10us) {
                c->flash->wait_10us(LF_TFS_READ_RETRY_10US);
            }
        }

        if (ret != LF_ERR_OK) {
            c->read_error_count++;
            if (c->read_error_count <= 8) {
                uint32_t page_size = c->flash->chip_info.prog_size;
                uint32_t erase_size = c->flash->chip_info.erase_size;
                uint32_t pages_per_block = (page_size > 0) ? (erase_size / page_size) : 0;
                uint32_t block = pages_per_block ? (page / pages_per_block) : 0;
                uint32_t page_in_block = pages_per_block ? (page % pages_per_block) : 0;
                int all_ff = (data && data_len > 0) ? lf_tfs_is_all_ff(data, data_len) : 0;
                uint8_t b0 = (data_len > 0) ? data[0] : 0xFF;
                uint8_t b1 = (data_len > 1) ? data[1] : 0xFF;
                uint8_t b2 = (data_len > 2) ? data[2] : 0xFF;
                uint8_t b3 = (data_len > 3) ? data[3] : 0xFF;

                LLOGW("tfs: read_page failed page=%u block=%u page_in_block=%u addr=%u len=%u status=0x%02X retries=%u all_ff=%d first=%02X%02X%02X%02X",
                      (unsigned int)page,
                      (unsigned int)block,
                      (unsigned int)page_in_block,
                      (unsigned int)addr,
                      (unsigned int)data_len,
                      (unsigned int)status,
                      (unsigned int)LF_TFS_READ_RETRY_COUNT,
                      all_ff,
                      (unsigned int)b0,
                      (unsigned int)b1,
                      (unsigned int)b2,
                      (unsigned int)b3);
            }
            return TFS_EFLASH;
        }
    }

    if (oob && oob_len > 0 && c->oob_ram && page < c->total_chunks) {
        uint32_t copy = (oob_len < c->oob_per_chunk) ? oob_len : c->oob_per_chunk;
        memcpy(oob, c->oob_ram + page * c->oob_per_chunk, copy);
    } else if (oob && oob_len > 0) {
        memset(oob, 0xFF, oob_len);
    }
    return TFS_OK;
}

static int lf_tfs_erase_block(void *ctx, uint32_t block)
{
    luat_lf_tfs_ctx_t *c = (luat_lf_tfs_ctx_t *)ctx;
    uint32_t block_size;
    uint32_t addr;

    if (!c || !c->flash) {
        return TFS_FAIL;
    }

    block_size = c->flash->chip_info.erase_size;
    addr = c->offset + block * block_size;

    if (little_flash_erase(c->flash, addr, block_size) != LF_ERR_OK) {
        LLOGE("tfs: erase_block failed block=%u", (unsigned int)block);
        return TFS_EFLASH;
    }

    if (c->is_nand) {
        uint32_t page_size = c->flash->chip_info.prog_size;
        uint32_t cpb = page_size ? (block_size / page_size) : 0;
        uint8_t *page_buf;
        uint32_t i;

        if (page_size == 0 || cpb == 0) {
            return TFS_EFLASH;
        }

        page_buf = (uint8_t *)luat_heap_malloc(page_size);
        if (!page_buf) {
            LLOGE("tfs: erase verify alloc failed block=%u",
                  (unsigned int)block);
            return TFS_ENOMEM;
        }

        for (i = 0; i < cpb; i++) {
            uint32_t page_addr = addr + i * page_size;
            uint8_t status = 0;

            memset(page_buf, 0x00, page_size);
            if (lf_tfs_read_flash(c,
                                  page_addr,
                                  page_buf,
                                  page_size,
                                  &status) != LF_ERR_OK ||
                !lf_tfs_is_all_ff(page_buf, page_size)) {
                LLOGE("tfs: erase verify failed block=%u page=%u status=0x%02X first=%02X%02X%02X%02X",
                      (unsigned int)block,
                      (unsigned int)i,
                      (unsigned int)status,
                      (unsigned int)page_buf[0],
                      (unsigned int)page_buf[1],
                      (unsigned int)page_buf[2],
                      (unsigned int)page_buf[3]);
                luat_heap_free(page_buf);
                return TFS_EFLASH;
            }
        }

        luat_heap_free(page_buf);
    }

    if (c->oob_ram && c->oob_per_chunk > 0) {
        uint32_t cpb = block_size / c->flash->chip_info.prog_size;
        uint32_t i;

        for (i = 0; i < cpb; i++) {
            uint32_t idx = block * cpb + i;
            if (idx < c->total_chunks) {
                memset(c->oob_ram + idx * c->oob_per_chunk, 0xFF, c->oob_per_chunk);
            }
        }
    }
    return TFS_OK;
}

static int lf_tfs_mark_bad(void *ctx, uint32_t block)
{
    luat_lf_tfs_ctx_t *c = (luat_lf_tfs_ctx_t *)ctx;
    uint32_t chunk = 0;
    uint32_t seq = 0;
    lf_tfs_anchor_slot_t anchor;
    lf_tfs_anchor_slot_t *anchor_ptr = NULL;
    int add_ret;

    if (!c || !c->flash || !lf_tfs_bad_block_valid(c, block)) {
        return TFS_EINVAL;
    }

    add_ret = lf_tfs_bad_table_add_ram(c, block);
    if (add_ret < 0) {
        LLOGW("tfs: bad block table full or invalid block=%u",
              (unsigned int)block);
        return TFS_ENOSPC;
    }
    if (add_ret == 0) {
        return TFS_OK;
    }

    if (lf_tfs_checkpoint_anchor_read(c, &chunk, &seq) == TFS_OK) {
        anchor.magic = LF_TFS_ANCHOR_MAGIC;
        anchor.seq = seq;
        anchor.chunk = chunk;
        anchor.check = lf_tfs_anchor_check(seq, chunk);
        anchor_ptr = &anchor;
    }

    if (!lf_tfs_write_marker_page(c, anchor_ptr)) {
        LLOGW("tfs: persist bad block failed block=%u",
              (unsigned int)block);
        return TFS_EIO;
    }
    LLOGW("tfs: persisted bad block=%u count=%u",
          (unsigned int)block,
          (unsigned int)c->bad_block_count);
    return TFS_OK;
}

static int lf_tfs_check_bad(void *ctx, uint32_t block)
{
    luat_lf_tfs_ctx_t *c = (luat_lf_tfs_ctx_t *)ctx;
    return (lf_tfs_bad_block_index(c, block) >= 0) ? 1 : 0;
}

static void *lf_tfs_malloc(void *ctx, uint32_t size)
{
    (void)ctx;
    return luat_heap_malloc((size_t)size);
}

static void lf_tfs_free(void *ctx, void *ptr)
{
    (void)ctx;
    luat_heap_free(ptr);
}

static void lf_tfs_lock(void *ctx)
{
    (void)ctx;
}

static void lf_tfs_unlock(void *ctx)
{
    (void)ctx;
}

static uint32_t lf_tfs_get_time(void)
{
    return 0;
}

static void lf_tfs_trace(const char *fmt, ...)
{
    (void)fmt;
}

static void lf_tfs_fill_drv(tfs_drv_t *drv, luat_lf_tfs_ctx_t *ctx)
{
    memset(drv, 0, sizeof(*drv));
    drv->ctx = ctx;
    drv->write_page = lf_tfs_write_page;
    drv->read_page = lf_tfs_read_page;
    drv->erase_block = lf_tfs_erase_block;
    drv->mark_bad = lf_tfs_mark_bad;
    drv->check_bad = lf_tfs_check_bad;
    drv->malloc = lf_tfs_malloc;
    drv->free = lf_tfs_free;
    drv->lock = lf_tfs_lock;
    drv->unlock = lf_tfs_unlock;
    drv->get_time = lf_tfs_get_time;
    drv->trace = lf_tfs_trace;
    drv->checkpt_anchor_read = lf_tfs_checkpoint_anchor_read;
    drv->checkpt_anchor_write = lf_tfs_checkpoint_anchor_write;
}

static void lf_tfs_fill_geo(tfs_geo_t *geo, luat_lf_tfs_ctx_t *ctx)
{
    little_flash_t *flash = ctx->flash;
    uint32_t page_size = flash->chip_info.prog_size;
    uint32_t erase_size = flash->chip_info.erase_size;
    uint32_t total_size = lf_tfs_region_size(ctx);
    uint32_t block_count;
    uint32_t inband_tags = 1;
    uint32_t spare_size = inband_tags ? 0 : 64;

    memset(geo, 0, sizeof(*geo));

    block_count = erase_size ? (total_size / erase_size) : 0;
    if (block_count == 0) {
        block_count = 1;
    }
    if (block_count > 1) {
        block_count--;
        ctx->marker_addr = ctx->offset + block_count * erase_size;
    }

    ctx->oob_per_chunk = spare_size;
    ctx->total_chunks = block_count * (erase_size / page_size);

    geo->data_bytes_per_chunk = page_size;
    geo->spare_bytes_per_chunk = spare_size;
    geo->chunks_per_block = erase_size / page_size;
    geo->start_block = 0;
    geo->end_block = block_count - 1;
    geo->inband_tags = (int)inband_tags;
    geo->stored_endian = 0;

    LLOGD("tfs geo: chunksize=%u spare=%u inband=%u cpb=%u blocks=%u oob_ram=%u",
          (unsigned int)page_size,
          (unsigned int)spare_size,
          (unsigned int)inband_tags,
          (unsigned int)(erase_size / page_size),
          (unsigned int)block_count,
          (unsigned int)(ctx->total_chunks * spare_size));
}

static int lf_tfs_probe_write(luat_lf_tfs_ctx_t *ctx)
{
    char path[64];
    int fd;

    snprintf(path, sizeof(path), "/%s/.tfs_probe", ctx->dev_name);
    fd = tfs_open(path, TFS_O_CREAT | TFS_O_RDWR | TFS_O_TRUNC, 0);
    if (fd >= 0) {
        int ok = (tfs_write(fd, "ok", 2) == 2);
        tfs_close(fd);
        tfs_unlink(path);
        if (ok) {
            return 1;
        }
    }
    return 0;
}

static int lf_tfs_format_and_mount(luat_lf_tfs_ctx_t *ctx)
{
    int ret;

    ctx->read_error_count = 0;
    ret = tfs_format(ctx->dev_name);
    LLOGD("tfs: format ret=%d read_errors=%u",
          ret,
          (unsigned int)ctx->read_error_count);
    if (ret != TFS_OK) {
        return ret;
    }
    if (ctx->read_error_count > 0) {
        LLOGW("tfs: format saw read_errors=%u",
              (unsigned int)ctx->read_error_count);
    }
    if (!lf_tfs_write_name_marker(ctx)) {
        return TFS_EIO;
    }
    if (!lf_tfs_write_raw_marker(ctx)) {
        return TFS_EIO;
    }

    /*
     * tfs_format() leaves the freshly formatted device mounted.  Calling
     * tfs_mount() again would reinitialise and rescan the same device.
     */
    ctx->read_error_count = 0;
    ret = lf_tfs_sync(ctx);
    if (ret == TFS_OK && ctx->read_error_count > 0) {
        LLOGW("tfs: sync after format saw read_errors=%u",
              (unsigned int)ctx->read_error_count);
    }
    return ret;
}

void *flash_tfs_lf(little_flash_t *flash, size_t offset, size_t maxsize)
{
    luat_lf_tfs_ctx_t *ctx;
    tfs_drv_t drv;
    tfs_geo_t geo;
    int ret;
    int marker_state;

    if (!flash) {
        LLOGE("tfs: flash is null");
        return NULL;
    }

    if (!s_tfs_inited) {
        tfs_init();
        s_tfs_inited = 1;
    }

    ctx = &s_tfs_ctx;
    memset(ctx, 0, sizeof(*ctx));
    ctx->flash = flash;
    ctx->offset = (uint32_t)offset;
    ctx->maxsize = (uint32_t)maxsize;
    ctx->is_nand = (flash->chip_info.type == LF_DRIVER_NAND_FLASH);
    snprintf(ctx->dev_name, sizeof(ctx->dev_name), "tfs0");

    lf_tfs_fill_drv(&drv, ctx);
    lf_tfs_fill_geo(&geo, ctx);

    if (ctx->oob_per_chunk > 0 && ctx->total_chunks > 0) {
        size_t size = (size_t)ctx->total_chunks * ctx->oob_per_chunk;

        ctx->oob_ram = (uint8_t *)luat_heap_malloc(size);
        if (!ctx->oob_ram) {
            LLOGE("tfs: oob_ram alloc failed");
            return NULL;
        }
        memset(ctx->oob_ram, 0xFF, size);
        LLOGD("tfs: oob_ram allocated %u bytes", (unsigned int)size);
    }

    LLOGD("tfs: adding device '%s' offset=%u maxsize=%u",
          ctx->dev_name,
          (unsigned int)offset,
          (unsigned int)maxsize);

    ret = tfs_add_device(ctx->dev_name, &drv, &geo);
    if (ret != TFS_OK) {
        LLOGE("tfs: add_device failed %d", ret);
        return NULL;
    }
    {
        tfs_dev_t *dev = tfs_core_find_dev(ctx->dev_name);
        if (dev) {
            dev->param.always_check_erased = 1;
        }
    }

    marker_state = lf_tfs_raw_marker_state(ctx);
    if (marker_state != LF_TFS_RAW_MARKER_CURRENT) {
        if (lf_tfs_looks_blank(ctx)) {
            LLOGD("tfs: blank region detected, format fast path");
        } else {
            LLOGW("tfs: raw marker mismatch, format before scan");
        }
        ret = lf_tfs_format_and_mount(ctx);
        if (ret != TFS_OK) {
            LLOGE("tfs: format mount failed");
            goto fail;
        }
    } else {
        int marker_upgraded = 0;
        int need_probe = 0;
        int need_sync = 0;

        if (marker_state == LF_TFS_RAW_MARKER_CURRENT) {
            lf_tfs_bad_table_load(ctx);
        }
        ctx->read_error_count = 0;
        ret = tfs_mount(ctx->dev_name);
        LLOGD("tfs: mount ret=%d read_errors=%u",
              ret,
              (unsigned int)ctx->read_error_count);

        if (ret == TFS_OK && ctx->read_error_count > 0) {
            LLOGW("tfs: mount saw flash read errors, continue with marker/probe checks");
            need_probe = 1;
        }
        if (ret == TFS_OK) {
            tfs_dev_t *dev = tfs_core_find_dev(ctx->dev_name);
            if (dev && !dev->is_checkpointed) {
                LLOGD("tfs: checkpoint missing or old, sync after full scan");
                need_sync = 1;
            }
        }
        if (ret == TFS_OK && !lf_tfs_name_marker_ok(ctx)) {
            LLOGW("tfs: name marker missing or old, upgrading");
            if (!lf_tfs_write_name_marker(ctx)) {
                LLOGW("tfs: name marker upgrade failed");
                need_probe = 1;
            } else {
                marker_upgraded = 1;
                need_sync = 1;
            }
        }

        if (ret == TFS_OK) {
            if (need_probe) {
                if (lf_tfs_probe_write(ctx)) {
                    LLOGD("tfs: reuse existing filesystem");
                    lf_tfs_sync(ctx);
                } else {
                    LLOGD("tfs: probe failed, reformatting");
                    tfs_unmount(ctx->dev_name);
                    ret = lf_tfs_format_and_mount(ctx);
                    if (ret != TFS_OK) {
                        LLOGE("tfs: format or mount failed");
                        goto fail;
                    }
                }
            } else {
                LLOGD("tfs: reuse existing filesystem");
                if (marker_upgraded || need_sync) {
                    lf_tfs_sync(ctx);
                }
            }
        } else {
            ret = lf_tfs_format_and_mount(ctx);
            if (ret != TFS_OK) {
                LLOGE("tfs: format or mount failed");
                goto fail;
            }
        }
    }

    ctx->is_mounted = 1;
    LLOGD("tfs: device '%s' ready", ctx->dev_name);
    return ctx;

fail:
    tfs_remove_device(ctx->dev_name);
    if (ctx->oob_ram) {
        luat_heap_free(ctx->oob_ram);
        ctx->oob_ram = NULL;
    }
    return NULL;
}

#endif
