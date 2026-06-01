#include "little_flash_ftl_internal.h"
#include "luat_malloc.h"
#include <string.h>

static lf_err_t little_flash_ftl_wait_ready(const little_flash_t *lf, uint32_t timeout_us) {
    uint8_t status = 0;
    uint32_t waited = 0;
    lf_err_t ret;
    if (!lf) {
        return LF_ERR_BAD_ADDRESS;
    }
    while (waited < timeout_us) {
        ret = little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
        if (ret != LF_ERR_OK) {
            return ret;
        }
        if ((status & LF_STATUS_REGISTER_BUSY) == 0) {
            return LF_ERR_OK;
        }
        if (lf->wait_10us) {
            lf->wait_10us(1);
        }
        waited += 10u;
    }
    return LF_ERR_TIMEOUT;
}

static lf_err_t little_flash_ftl_read_oob_marker(const little_flash_t *lf, uint32_t page_addr, uint8_t *marker) {
    uint8_t cmd_data[4];
    lf_err_t ret;
    if (!lf || !marker) {
        return LF_ERR_BAD_ADDRESS;
    }
    cmd_data[0] = LF_NANDFLASH_PAGE_DATA_READ;
    cmd_data[1] = (uint8_t)(page_addr >> 16);
    cmd_data[2] = (uint8_t)(page_addr >> 8);
    cmd_data[3] = (uint8_t)(page_addr);
    ret = lf->spi.transfer(lf, cmd_data, 4, LF_NULL, 0);
    if (ret != LF_ERR_OK) {
        return ret;
    }
    ret = little_flash_ftl_wait_ready(lf, 1000u);
    if (ret != LF_ERR_OK) {
        return ret;
    }
    cmd_data[0] = LF_CMD_READ_DATA;
    cmd_data[1] = (uint8_t)(lf->chip_info.read_size >> 8);
    cmd_data[2] = (uint8_t)(lf->chip_info.read_size);
    cmd_data[3] = 0;
    return lf->spi.transfer(lf, cmd_data, 4, marker, 1);
}

static void little_flash_ftl_mark_bad_block(little_flash_ftl_ctx_t *ctx, uint32_t block_index) {
    uint32_t start = block_index * ctx->pages_per_block;
    uint32_t end = start + ctx->pages_per_block;
    uint32_t i;
    for (i = start; i < end && i < ctx->page_count; i++) {
        ctx->bad[i] = 1;
    }
}

static void little_flash_ftl_scan_bad_blocks(little_flash_t *lf, little_flash_ftl_ctx_t *ctx) {
    uint32_t block_index;
    if (!lf || !ctx || !lf->spi.transfer) {
        return;
    }
    for (block_index = 0; block_index < ctx->block_count; block_index++) {
        uint32_t first_page = block_index * ctx->pages_per_block;
        uint32_t second_page = first_page + 1u;
        uint8_t marker0 = 0xFF;
        uint8_t marker1 = 0xFF;
        int is_bad = 0;
        if (little_flash_ftl_read_oob_marker(lf, first_page, &marker0) != LF_ERR_OK) {
            is_bad = 1;
        }
        if (!is_bad && second_page < ctx->page_count &&
            little_flash_ftl_read_oob_marker(lf, second_page, &marker1) != LF_ERR_OK) {
            is_bad = 1;
        }
        if (!is_bad && (marker0 != 0xFF || marker1 != 0xFF)) {
            is_bad = 1;
        }
        if (is_bad) {
            little_flash_ftl_mark_bad_block(ctx, block_index);
            ctx->bad_blocks++;
            ctx->bad_pages += ctx->pages_per_block;
        }
    }
}

static int little_flash_ftl_page_used(const little_flash_ftl_ctx_t *ctx, uint32_t page) {
    return ctx->p2l[page] != LF_FTL_INVALID_PAGE;
}

static int little_flash_ftl_find_spare(const little_flash_ftl_ctx_t *ctx, uint32_t *page) {
    uint32_t start = 0;
    uint32_t i = 0;
    if (ctx->reserve_pages == 0 || ctx->reserve_pages >= ctx->page_count) {
        return -1;
    }
    start = ctx->spare_begin;
    for (i = start; i < ctx->spare_end; i++) {
        if (!ctx->bad[i] && !little_flash_ftl_page_used(ctx, i)) {
            *page = i;
            return 0;
        }
    }
    return -1;
}

static int little_flash_ftl_select_metadata_region(little_flash_ftl_ctx_t *ctx, uint32_t metadata_pages) {
    uint32_t metadata_blocks = 0;
    int32_t start_block = 0;
    if (!ctx || ctx->pages_per_block == 0 || metadata_pages == 0) {
        return -1;
    }
    if ((metadata_pages % ctx->pages_per_block) != 0u) {
        return -1;
    }
    metadata_blocks = metadata_pages / ctx->pages_per_block;
    if (metadata_blocks == 0u || ctx->block_count <= metadata_blocks) {
        return -1;
    }
    for (start_block = (int32_t)(ctx->block_count - metadata_blocks); start_block >= 1; start_block--) {
        uint32_t b = 0;
        uint32_t bad_found = 0;
        for (b = 0; b < metadata_blocks; b++) {
            uint32_t page = ((uint32_t)start_block + b) * ctx->pages_per_block;
            if (page >= ctx->page_count || ctx->bad[page]) {
                bad_found = 1;
                break;
            }
        }
        if (!bad_found) {
            ctx->meta_start_page = (uint32_t)start_block * ctx->pages_per_block;
            ctx->meta_page_count = metadata_pages;
            ctx->spare_end = ctx->meta_start_page;
            return 0;
        }
    }
    return -1;
}

lf_err_t little_flash_ftl_init(little_flash_t *lf, uint8_t op_percent) {
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t pages_per_block = 0;
    uint32_t metadata_pages = 0;
    uint32_t min_reserve = 0;
    uint32_t safety_margin = 0;
    uint32_t good_pages = 0;
    uint32_t logical_target = 0;
    uint32_t i = 0;
    lf_err_t recover_ret = LF_ERR_OK;
    if (!lf || lf->chip_info.type != LF_DRIVER_NAND_FLASH) {
        return LF_ERR_OK;
    }
    if (lf->chip_info.read_size == 0) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (!lf->malloc || !lf->free) {
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->malloc(sizeof(little_flash_ftl_ctx_t));
    if (!ctx) {
        return LF_ERR_NO_MEM;
    }
    memset(ctx, 0, sizeof(*ctx));
    ctx->raw_capacity = lf->chip_info.capacity;
    ctx->page_count = lf->chip_info.capacity / lf->chip_info.read_size;
    pages_per_block = lf->chip_info.erase_size / lf->chip_info.read_size;
    metadata_pages = pages_per_block * 2u;
    if (ctx->page_count <= metadata_pages || pages_per_block == 0) {
        lf->free(ctx);
        return LF_ERR_BAD_ADDRESS;
    }
    ctx->pages_per_block = pages_per_block;
    ctx->block_count = ctx->page_count / pages_per_block;
    ctx->reserve_pages = ((ctx->page_count - metadata_pages) * op_percent) / 100;
    min_reserve = 8u;
    if (ctx->reserve_pages < min_reserve) {
        ctx->reserve_pages = min_reserve;
    }
    if (ctx->reserve_pages > ((ctx->page_count - metadata_pages) / 2u)) {
        ctx->reserve_pages = (ctx->page_count - metadata_pages) / 2u;
    }
    ctx->spare_begin = 0;
    ctx->spare_end = ctx->page_count;
    ctx->meta_start_page = 0;
    ctx->meta_page_count = 0;
    ctx->gc_low_watermark = 2u;
    ctx->gc_high_watermark = 6u;
    ctx->gc_ratio = 2u;
    ctx->recover_state = LF_FTL_RECOVER_STATE_IDLE;
    ctx->recover_retries = 0;
    ctx->l2p = (uint32_t *)lf->malloc(sizeof(uint32_t) * ctx->page_count);
    ctx->p2l = (uint32_t *)lf->malloc(sizeof(uint32_t) * ctx->page_count);
    ctx->bad = (uint8_t *)lf->malloc(ctx->page_count);
    if (!ctx->l2p || !ctx->p2l || !ctx->bad) {
        if (ctx->l2p) {
            lf->free(ctx->l2p);
        }
        if (ctx->p2l) {
            lf->free(ctx->p2l);
        }
        if (ctx->bad) {
            lf->free(ctx->bad);
        }
        lf->free(ctx);
        return LF_ERR_NO_MEM;
    }
    memset(ctx->bad, 0, ctx->page_count);
    for (i = 0; i < ctx->page_count; i++) {
        ctx->p2l[i] = LF_FTL_INVALID_PAGE;
    }
    little_flash_ftl_scan_bad_blocks(lf, ctx);
    if (little_flash_ftl_select_metadata_region(ctx, metadata_pages) != 0 || ctx->spare_begin >= ctx->spare_end) {
        lf->free(ctx->bad);
        lf->free(ctx->p2l);
        lf->free(ctx->l2p);
        lf->free(ctx);
        return LF_ERR_NO_MEM;
    }
    for (i = 0; i < ctx->spare_end; i++) {
        if (!ctx->bad[i]) {
            good_pages++;
        }
    }
    safety_margin = ctx->pages_per_block * LF_FTL_RECOVER_RETRY_MAX;
    if (safety_margin > (ctx->spare_end / 2u)) {
        safety_margin = ctx->spare_end / 2u;
    }
    ctx->safety_margin_pages = safety_margin;
    if (good_pages <= (ctx->reserve_pages + ctx->safety_margin_pages)) {
        lf->free(ctx->bad);
        lf->free(ctx->p2l);
        lf->free(ctx->l2p);
        lf->free(ctx);
        return LF_ERR_NO_MEM;
    }
    logical_target = good_pages - ctx->reserve_pages - ctx->safety_margin_pages;
    ctx->logical_pages = 0;
    for (i = 0; i < ctx->spare_end && ctx->logical_pages < logical_target; i++) {
        if (!ctx->bad[i]) {
            ctx->l2p[ctx->logical_pages] = i;
            ctx->p2l[i] = ctx->logical_pages;
            ctx->logical_pages++;
        }
    }
    ctx->free_spares = 0;
    for (i = 0; i < ctx->spare_end; i++) {
        if (!ctx->bad[i] && !little_flash_ftl_page_used(ctx, i)) {
            ctx->free_spares++;
        }
    }
    if (lf->spi.transfer) {
        recover_ret = little_flash_ftl_meta_recover(lf, ctx);
        if (recover_ret != LF_ERR_OK && recover_ret != LF_ERR_READ) {
            lf->free(ctx->bad);
            lf->free(ctx->p2l);
            lf->free(ctx->l2p);
            lf->free(ctx);
            return LF_ERR_NO_MEM;
        }
        if (recover_ret == LF_ERR_READ) {
            LF_WARNING("little_flash ftl metadata degraded, identity fallback applied");
        }
        little_flash_ftl_refresh_free_spares(ctx);
    }
    if (recover_ret != LF_ERR_READ &&
        ctx->cp_a.generation == 0u && ctx->cp_b.generation == 0u &&
        little_flash_ftl_meta_checkpoint(lf, ctx) != LF_ERR_OK) {
        lf->free(ctx->bad);
        lf->free(ctx->p2l);
        lf->free(ctx->l2p);
        lf->free(ctx);
        return LF_ERR_NO_MEM;
    }
    lf->ftl_ctx = ctx;
    lf->ftl_enabled = 1;
    lf->chip_info.capacity = ctx->logical_pages * lf->chip_info.read_size;
    LF_INFO("little_flash ftl init: blocks=%lu bad_blocks=%lu bad_pages=%lu logical_pages=%lu reserve_pages=%lu",
            (unsigned long)ctx->block_count,
            (unsigned long)ctx->bad_blocks,
            (unsigned long)ctx->bad_pages,
            (unsigned long)ctx->logical_pages,
            (unsigned long)ctx->reserve_pages);
    LF_INFO("little_flash ftl space: usable=%lu bytes reserve_free=%lu bytes reserve_total=%lu bytes raw=%lu bytes",
            (unsigned long)(ctx->logical_pages * lf->chip_info.read_size),
            (unsigned long)(ctx->free_spares * lf->chip_info.read_size),
            (unsigned long)(ctx->reserve_pages * lf->chip_info.read_size),
            (unsigned long)ctx->raw_capacity);
    return LF_ERR_OK;
}

void little_flash_ftl_deinit(little_flash_t *lf) {
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t raw_capacity = 0;
    if (!lf || !lf->ftl_ctx || !lf->free) {
        return;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    raw_capacity = ctx->raw_capacity;
    if (ctx->l2p) {
        lf->free(ctx->l2p);
    }
    if (ctx->p2l) {
        lf->free(ctx->p2l);
    }
    if (ctx->bad) {
        lf->free(ctx->bad);
    }
    lf->free(ctx);
    if (lf->chip_info.type == LF_DRIVER_NAND_FLASH && raw_capacity) {
        lf->chip_info.capacity = raw_capacity;
    }
    if (lf) {
        lf->ftl_ctx = NULL;
        lf->ftl_enabled = 0;
    }
}

lf_err_t little_flash_ftl_map_page(const little_flash_t *lf, uint32_t logical_page, uint32_t *physical_page) {
    little_flash_ftl_ctx_t *ctx = NULL;
    if (!lf || !physical_page) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (!lf->ftl_enabled || !lf->ftl_ctx || lf->chip_info.type != LF_DRIVER_NAND_FLASH) {
        *physical_page = logical_page;
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    if (logical_page >= ctx->logical_pages) {
        return LF_ERR_BAD_ADDRESS;
    }
    *physical_page = ctx->l2p[logical_page];
    if (*physical_page >= ctx->page_count || ctx->bad[*physical_page] || ctx->p2l[*physical_page] != logical_page) {
        return LF_ERR_BAD_ADDRESS;
    }
    return LF_ERR_OK;
}

lf_err_t little_flash_ftl_mark_bad_and_remap(little_flash_t *lf, uint32_t logical_page, uint32_t bad_physical_page) {
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t spare_page = 0;
    uint32_t current_physical = 0;
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_BAD_ADDRESS;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    if (logical_page >= ctx->logical_pages || bad_physical_page >= ctx->page_count) {
        ctx->recover_state = LF_FTL_RECOVER_STATE_FAILED;
        return LF_ERR_BAD_ADDRESS;
    }
    ctx->recover_state = LF_FTL_RECOVER_STATE_RECOVERING;
    current_physical = ctx->l2p[logical_page];
    if (current_physical >= ctx->page_count) {
        ctx->recover_state = LF_FTL_RECOVER_STATE_FAILED;
        return LF_ERR_BAD_ADDRESS;
    }
    if (ctx->bad[bad_physical_page]) {
        if (current_physical != bad_physical_page) {
            ctx->recover_state = LF_FTL_RECOVER_STATE_IDLE;
            return LF_ERR_OK;
        }
    }
    if (current_physical != bad_physical_page) {
        ctx->recover_state = LF_FTL_RECOVER_STATE_FAILED;
        return LF_ERR_BAD_ADDRESS;
    }
    ctx->p2l[bad_physical_page] = LF_FTL_INVALID_PAGE;
    ctx->bad[bad_physical_page] = 1;
    if (little_flash_ftl_find_spare(ctx, &spare_page) != 0) {
        if (ctx->recover_retries < LF_FTL_RECOVER_RETRY_MAX) {
            ctx->recover_retries++;
            ctx->recover_state = LF_FTL_RECOVER_STATE_RETRY;
        } else {
            ctx->recover_state = LF_FTL_RECOVER_STATE_FAILED;
        }
        return LF_ERR_ERASE;
    }
    ctx->p2l[current_physical] = LF_FTL_INVALID_PAGE;
    ctx->l2p[logical_page] = spare_page;
    ctx->p2l[spare_page] = logical_page;
    if (little_flash_ftl_meta_append_journal(lf, ctx, logical_page, spare_page) != LF_ERR_OK) {
        ctx->recover_state = LF_FTL_RECOVER_STATE_FAILED;
        return LF_ERR_ERASE;
    }
    if (ctx->free_spares > 0) {
        ctx->free_spares--;
    }
    if (ctx->free_spares <= ctx->gc_low_watermark) {
        little_flash_ftl_gc_collect(lf, 0);
    }
    ctx->recover_retries = 0;
    ctx->recover_state = LF_FTL_RECOVER_STATE_IDLE;
    return LF_ERR_OK;
}

lf_err_t little_flash_ftl_sync(little_flash_t *lf) {
    little_flash_ftl_ctx_t *ctx = NULL;
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    return little_flash_ftl_meta_checkpoint(lf, ctx);
}

lf_err_t little_flash_ftl_recover(little_flash_t *lf) {
    little_flash_ftl_ctx_t *ctx = NULL;
    lf_err_t ret = LF_ERR_OK;
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    ret = little_flash_ftl_meta_recover(lf, ctx);
    little_flash_ftl_refresh_free_spares(ctx);
    return ret;
}

#ifdef LUAT_USE_UTEST
static int little_flash_ftl_utest_identity_map(void) {
    little_flash_t lf;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    {
        little_flash_ftl_ctx_t *ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
        uint32_t i = 0;
        for (i = 0; i < ctx->logical_pages; i++) {
            uint32_t p = 0;
            if (little_flash_ftl_map_page(&lf, i, &p) != LF_ERR_OK || p != i) {
                little_flash_ftl_deinit(&lf);
                return -1;
            }
        }
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_badblock_remap(void) {
    little_flash_t lf;
    uint32_t p = 0;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf, 5, 5) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf, 5, &p) != LF_ERR_OK || p == 5) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_powerfail_recovery(void) {
    little_flash_t lf;
    uint32_t p = 0;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf, 9, 9) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (little_flash_ftl_sync(&lf) != LF_ERR_OK || little_flash_ftl_recover(&lf) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf, 9, &p) != LF_ERR_OK || p == 9) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_gc_trigger(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    ctx->journal_count = LF_FTL_JOURNAL_MAX - 1u;
    if (little_flash_ftl_gc_collect(&lf, 0) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (ctx->journal_count != 0u) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

typedef enum {
    LF_UTEST_FAULT_NONE = 0,
    LF_UTEST_FAULT_BLOCK1_BAD,
    LF_UTEST_FAULT_OOB_READ_FAIL_BLOCK0,
    LF_UTEST_FAULT_STATUS_BUSY_ALWAYS
} little_flash_ftl_utest_fault_t;

#define LF_UTEST_NAND_PAGE_SIZE  (2048u)
#define LF_UTEST_NAND_PAGE_COUNT (512u)

typedef struct {
    little_flash_ftl_utest_fault_t fault;
    uint32_t current_page;
    uint32_t bad_block_mask;
    uint8_t persistent_mode;
    uint8_t write_enabled;
    uint8_t prog_pending;
    uint16_t prog_column;
    uint16_t prog_len;
} little_flash_ftl_utest_state_t;

static little_flash_ftl_utest_state_t g_lf_ftl_utest_state;
static uint8_t g_lf_ftl_utest_nand[LF_UTEST_NAND_PAGE_SIZE * LF_UTEST_NAND_PAGE_COUNT];
static uint8_t g_lf_ftl_utest_prog_buf[LF_UTEST_NAND_PAGE_SIZE];

static void little_flash_ftl_utest_state_reset(little_flash_ftl_utest_fault_t fault) {
    memset(&g_lf_ftl_utest_state, 0, sizeof(g_lf_ftl_utest_state));
    g_lf_ftl_utest_state.fault = fault;
}

static void little_flash_ftl_utest_nand_reset(void) {
    memset(g_lf_ftl_utest_nand, 0xFF, sizeof(g_lf_ftl_utest_nand));
}

static void little_flash_ftl_utest_nand_corrupt(uint32_t page, uint32_t offset, uint8_t mask) {
    uint32_t idx = 0;
    if (page >= LF_UTEST_NAND_PAGE_COUNT || offset >= LF_UTEST_NAND_PAGE_SIZE) {
        return;
    }
    idx = page * LF_UTEST_NAND_PAGE_SIZE + offset;
    g_lf_ftl_utest_nand[idx] ^= mask;
}

static void little_flash_ftl_utest_set_bad_block_mask(uint32_t mask) {
    g_lf_ftl_utest_state.bad_block_mask = mask;
}

static void little_flash_ftl_utest_wait_10us(uint32_t count) {
    (void)count;
}

static void little_flash_ftl_utest_wait_ms(uint32_t count) {
    (void)count;
}

static lf_err_t little_flash_ftl_utest_spi_transfer(const little_flash_t *lf, uint8_t *tx_buf, uint32_t tx_len, uint8_t *rx_buf, uint32_t rx_len) {
    (void)lf;
    if (!tx_buf) {
        return LF_ERR_TRANSFER;
    }
    if (tx_buf[0] == LF_NANDFLASH_PAGE_DATA_READ && tx_len >= 4) {
        g_lf_ftl_utest_state.current_page = ((uint32_t)tx_buf[1] << 16) | ((uint32_t)tx_buf[2] << 8) | tx_buf[3];
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_CMD_WRITE_ENABLE) {
        g_lf_ftl_utest_state.write_enabled = 1;
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_CMD_WRITE_DISABLE) {
        g_lf_ftl_utest_state.write_enabled = 0;
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_CMD_NANDFLASH_READ_STATUS_REGISTER && tx_len >= 2 && rx_buf && rx_len >= 1) {
        uint8_t status = 0;
        if (g_lf_ftl_utest_state.fault == LF_UTEST_FAULT_STATUS_BUSY_ALWAYS) {
            status |= LF_STATUS_REGISTER_BUSY;
        }
        if (g_lf_ftl_utest_state.write_enabled) {
            status |= LF_STATUS_REGISTER_WEL;
        }
        rx_buf[0] = status;
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_CMD_BLOCK_ERASE && tx_len >= 4) {
        if (g_lf_ftl_utest_state.persistent_mode) {
            uint32_t page = ((uint32_t)tx_buf[1] << 16) | ((uint32_t)tx_buf[2] << 8) | tx_buf[3];
            uint32_t block = page / 64u;
            uint32_t start_page = block * 64u;
            uint32_t byte_offset = start_page * LF_UTEST_NAND_PAGE_SIZE;
            uint32_t byte_count = 64u * LF_UTEST_NAND_PAGE_SIZE;
            if (start_page + 64u <= LF_UTEST_NAND_PAGE_COUNT) {
                memset(&g_lf_ftl_utest_nand[byte_offset], 0xFF, byte_count);
            }
        }
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_CMD_READ_DATA && tx_len >= 4 && rx_buf && rx_len >= 1) {
        if (g_lf_ftl_utest_state.persistent_mode) {
            uint32_t col = ((uint32_t)tx_buf[1] << 8) | tx_buf[2];
            uint32_t page = g_lf_ftl_utest_state.current_page;
            if (page >= LF_UTEST_NAND_PAGE_COUNT) {
                return LF_ERR_BAD_ADDRESS;
            }
            if (col + rx_len <= LF_UTEST_NAND_PAGE_SIZE) {
                memcpy(rx_buf, &g_lf_ftl_utest_nand[page * LF_UTEST_NAND_PAGE_SIZE + col], rx_len);
                return LF_ERR_OK;
            }
        }
        uint32_t block = g_lf_ftl_utest_state.current_page / 64u;
        if (g_lf_ftl_utest_state.fault == LF_UTEST_FAULT_OOB_READ_FAIL_BLOCK0 && block == 0u) {
            return LF_ERR_TRANSFER;
        }
        if ((g_lf_ftl_utest_state.bad_block_mask & (1u << block)) != 0u ||
            (g_lf_ftl_utest_state.fault == LF_UTEST_FAULT_BLOCK1_BAD && block == 1u)) {
            rx_buf[0] = 0x00;
        } else {
            rx_buf[0] = 0xFF;
        }
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_CMD_PROG_DATA && tx_len >= 3) {
        if (g_lf_ftl_utest_state.persistent_mode && tx_len > 3) {
            g_lf_ftl_utest_state.prog_column = (uint16_t)(((uint16_t)tx_buf[1] << 8) | tx_buf[2]);
            g_lf_ftl_utest_state.prog_len = (uint16_t)(tx_len - 3u);
            g_lf_ftl_utest_state.prog_pending = 1;
            memset(g_lf_ftl_utest_prog_buf, 0xFF, sizeof(g_lf_ftl_utest_prog_buf));
            if ((uint32_t)g_lf_ftl_utest_state.prog_column + g_lf_ftl_utest_state.prog_len <= LF_UTEST_NAND_PAGE_SIZE) {
                memcpy(&g_lf_ftl_utest_prog_buf[g_lf_ftl_utest_state.prog_column], &tx_buf[3], g_lf_ftl_utest_state.prog_len);
            }
        }
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_NANDFLASH_PAGE_PROG_EXEC && tx_len >= 4) {
        if (g_lf_ftl_utest_state.persistent_mode && g_lf_ftl_utest_state.prog_pending) {
            uint32_t page = ((uint32_t)tx_buf[1] << 16) | ((uint32_t)tx_buf[2] << 8) | tx_buf[3];
            if (page >= LF_UTEST_NAND_PAGE_COUNT) {
                return LF_ERR_BAD_ADDRESS;
            }
            memcpy(&g_lf_ftl_utest_nand[page * LF_UTEST_NAND_PAGE_SIZE], g_lf_ftl_utest_prog_buf, LF_UTEST_NAND_PAGE_SIZE);
            g_lf_ftl_utest_state.prog_pending = 0;
            g_lf_ftl_utest_state.prog_len = 0;
        }
        return LF_ERR_OK;
    }
    return LF_ERR_OK;
}

static void little_flash_ftl_utest_prepare_lf(little_flash_t *lf, little_flash_ftl_utest_fault_t fault) {
    memset(lf, 0, sizeof(*lf));
    little_flash_ftl_utest_state_reset(fault);
    lf->chip_info.type = LF_DRIVER_NAND_FLASH;
    lf->chip_info.capacity = 2048 * 512;
    lf->chip_info.read_size = 2048;
    lf->chip_info.prog_size = 2048;
    lf->chip_info.erase_size = 131072;
    lf->chip_info.erase_cmd = LF_CMD_BLOCK_ERASE;
    lf->chip_info.erase_times = 1;
    lf->malloc = luat_heap_malloc;
    lf->free = luat_heap_free;
    lf->wait_10us = little_flash_ftl_utest_wait_10us;
    lf->wait_ms = little_flash_ftl_utest_wait_ms;
    lf->spi.transfer = little_flash_ftl_utest_spi_transfer;
}

static void little_flash_ftl_utest_prepare_persistent_lf(little_flash_t *lf) {
    little_flash_ftl_utest_prepare_lf(lf, LF_UTEST_FAULT_NONE);
    g_lf_ftl_utest_state.persistent_mode = 1;
}

static int little_flash_ftl_utest_init_stats(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_BLOCK1_BAD);
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (!ctx || ctx->bad_blocks != 1u || ctx->logical_pages == 0u || ctx->free_spares == 0u) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_oob_read_error_scan(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_OOB_READ_FAIL_BLOCK0);
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (!ctx || ctx->bad_blocks == 0u) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_wait_ready_timeout(void) {
    little_flash_t lf;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_STATUS_BUSY_ALWAYS);
    return little_flash_ftl_wait_ready(&lf, 50u) == LF_ERR_TIMEOUT ? 0 : -1;
}

static int little_flash_ftl_utest_recover_crc_invalid(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t metadata_page = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx || little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    metadata_page = ctx->spare_end;
    little_flash_ftl_deinit(&lf_first);
    little_flash_ftl_utest_nand_corrupt(metadata_page, 0, 0x3Cu);
    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_recover(&lf_second) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_recover_journal_out_of_range(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t p = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    ctx->journal_count = 1;
    ctx->journal[0].logical_page = ctx->logical_pages + 1u;
    ctx->journal[0].physical_page = 0u;
    if (little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    little_flash_ftl_deinit(&lf_first);
    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_recover(&lf_second) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf_second, 0, &p) != LF_ERR_OK || p != 0u) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_repeat_mark_bad_idempotent(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t first_mapping = 0;
    uint32_t free_spares_before = 0;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (little_flash_ftl_mark_bad_and_remap(&lf, 7, 7) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    first_mapping = ctx->l2p[7];
    free_spares_before = ctx->free_spares;
    if (little_flash_ftl_mark_bad_and_remap(&lf, 7, 7) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (ctx->l2p[7] != first_mapping || ctx->free_spares != free_spares_before) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_capacity_safety_margin(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t good_pages = 0;
    uint32_t i = 0;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_NONE);
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (!ctx || ctx->safety_margin_pages == 0u) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    for (i = 0; i < ctx->spare_end; i++) {
        if (!ctx->bad[i]) {
            good_pages++;
        }
    }
    if (good_pages <= (ctx->reserve_pages + ctx->safety_margin_pages)) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (ctx->logical_pages != (good_pages - ctx->reserve_pages - ctx->safety_margin_pages)) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_recover_state_machine(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_NONE);
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    ctx->reserve_pages = ctx->page_count;
    if (little_flash_ftl_mark_bad_and_remap(&lf, 5, ctx->l2p[5]) != LF_ERR_ERASE) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (ctx->recover_state != LF_FTL_RECOVER_STATE_RETRY) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_metadata_persist_replay(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t remapped_page = 0;
    uint32_t recovered_page = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf_first, 9, ctx->l2p[9]) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    remapped_page = ctx->l2p[9];
    if (little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    little_flash_ftl_deinit(&lf_first);

    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_recover(&lf_second) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf_second, 9, &recovered_page) != LF_ERR_OK || recovered_page != remapped_page) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_metadata_corrupt_fallback(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t metadata_page = 0;
    uint32_t slot_pages = 0;
    uint32_t recovered_page = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf_first, 9, ctx->l2p[9]) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    if (little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    metadata_page = ctx->spare_end;
    slot_pages = ctx->meta_page_count / 2u;
    little_flash_ftl_deinit(&lf_first);
    little_flash_ftl_utest_nand_corrupt(metadata_page, 0, 0x5Au);
    if (slot_pages > 0u) {
        little_flash_ftl_utest_nand_corrupt(metadata_page + slot_pages, 0, 0xA5u);
    }

    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_recover(&lf_second) != LF_ERR_READ) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf_second, 9, &recovered_page) != LF_ERR_OK || recovered_page != 9u) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_metadata_latest_valid_slot(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t slot_pages = 0;
    uint32_t newest_slot = 0;
    uint32_t newest_slot_page = 0;
    uint32_t remapped_page_9 = 0;
    uint32_t recovered_page = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf_first, 9, ctx->l2p[9]) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    remapped_page_9 = ctx->l2p[9];
    if (little_flash_ftl_mark_bad_and_remap(&lf_first, 10, ctx->l2p[10]) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    if (ctx->cp_a.generation == 0u && ctx->cp_b.generation == 0u) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    newest_slot = (ctx->cp_a.generation > ctx->cp_b.generation) ? 0u : 1u;
    slot_pages = ctx->meta_page_count / LF_FTL_META_SLOT_COUNT;
    newest_slot_page = ctx->meta_start_page + newest_slot * slot_pages;
    little_flash_ftl_deinit(&lf_first);

    little_flash_ftl_utest_nand_corrupt(newest_slot_page, sizeof(little_flash_ftl_checkpoint_hdr_t), 0x5Au);

    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_map_page(&lf_second, 9, &recovered_page) != LF_ERR_OK || recovered_page != remapped_page_9) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf_second, 10, &recovered_page) != LF_ERR_OK || recovered_page != 10u) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_metadata_corrupt_apply_fallback_sane(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t i = 0;
    uint32_t page = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx || ctx->logical_pages < 16u) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    ctx->l2p[0] = ctx->page_count + 3u;
    if (little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    little_flash_ftl_deinit(&lf_first);

    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_second.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    for (i = 0; i < 16u; i++) {
        if (little_flash_ftl_map_page(&lf_second, i, &page) != LF_ERR_OK ||
            page != i ||
            page >= ctx->page_count ||
            ctx->bad[page]) {
            little_flash_ftl_deinit(&lf_second);
            return -1;
        }
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_metadata_slot_overflow_guard(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t remapped_page = 0;
    uint32_t metadata_start_page = 0;
    uint32_t metadata_page_count = 0;
    uint32_t metadata_offset = 0;
    uint32_t metadata_len = 0;
    uint8_t *metadata_before = NULL;
    uint8_t *metadata_after = NULL;
    uint32_t recovered_page = 0;
    uint32_t i = 0;
    lf_err_t sync_ret = LF_ERR_OK;

    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf_first, 9, ctx->l2p[9]) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    remapped_page = ctx->l2p[9];
    if (little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }

    metadata_start_page = ctx->meta_start_page;
    metadata_page_count = ctx->meta_page_count;
    metadata_offset = metadata_start_page * LF_UTEST_NAND_PAGE_SIZE;
    metadata_len = metadata_page_count * LF_UTEST_NAND_PAGE_SIZE;
    metadata_before = (uint8_t *)luat_heap_malloc(metadata_len);
    metadata_after = (uint8_t *)luat_heap_malloc(metadata_len);
    if (!metadata_before || !metadata_after) {
        if (metadata_before) {
            luat_heap_free(metadata_before);
        }
        if (metadata_after) {
            luat_heap_free(metadata_after);
        }
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    memcpy(metadata_before, &g_lf_ftl_utest_nand[metadata_offset], metadata_len);

    ctx->meta_page_count = LF_FTL_META_SLOT_COUNT;
    ctx->journal_count = LF_FTL_JOURNAL_MAX;
    for (i = 0; i < LF_FTL_JOURNAL_MAX; i++) {
        uint32_t logical = i % ctx->logical_pages;
        ctx->journal[i].logical_page = logical;
        ctx->journal[i].physical_page = ctx->l2p[logical];
    }
    sync_ret = little_flash_ftl_sync(&lf_first);
    memcpy(metadata_after, &g_lf_ftl_utest_nand[metadata_offset], metadata_len);
    if (sync_ret != LF_ERR_BAD_ADDRESS || memcmp(metadata_before, metadata_after, metadata_len) != 0) {
        luat_heap_free(metadata_after);
        luat_heap_free(metadata_before);
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    luat_heap_free(metadata_after);
    luat_heap_free(metadata_before);
    little_flash_ftl_deinit(&lf_first);

    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_recover(&lf_second) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf_second, 9, &recovered_page) != LF_ERR_OK || recovered_page != remapped_page) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_gc_checkpoint_failure_keeps_journal(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t old_journal_count = 0;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_NONE);
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    ctx->journal_count = LF_FTL_JOURNAL_MAX - 1u;
    old_journal_count = ctx->journal_count;
    g_lf_ftl_utest_state.fault = LF_UTEST_FAULT_STATUS_BUSY_ALWAYS;
    if (little_flash_ftl_gc_collect(&lf, 1) != LF_ERR_ERASE) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (ctx->journal_count != old_journal_count) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_metadata_tail_bad_blocks_fallback(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t slot_pages = 0;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_NONE);
    little_flash_ftl_utest_set_bad_block_mask((1u << 6) | (1u << 7));
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    slot_pages = ctx->meta_page_count / LF_FTL_META_SLOT_COUNT;
    if (ctx->meta_start_page != (4u * ctx->pages_per_block) ||
        ctx->spare_end != ctx->meta_start_page ||
        ctx->bad[ctx->meta_start_page] ||
        ctx->bad[ctx->meta_start_page + slot_pages]) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_metadata_region_continuity_on_tail_bad(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t remapped_page = 0;
    uint32_t recovered_page = 0;
    uint32_t old_meta_start = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    old_meta_start = ctx->meta_start_page;
    if (little_flash_ftl_mark_bad_and_remap(&lf_first, 9, ctx->l2p[9]) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    remapped_page = ctx->l2p[9];
    /* Flush twice so both slots carry the latest mapping before one metadata block turns bad. */
    if (little_flash_ftl_sync(&lf_first) != LF_ERR_OK || little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    little_flash_ftl_deinit(&lf_first);

    /* Simulate one tail metadata block becoming bad after metadata was already persisted. */
    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    little_flash_ftl_utest_set_bad_block_mask(1u << 7);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_second.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    if (ctx->meta_start_page == old_meta_start) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf_second, 9, &recovered_page) != LF_ERR_OK || recovered_page != remapped_page) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_metadata_recover_ignores_historical_bad_journal(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t remapped_page = 0;
    uint32_t historical_page = 0;
    uint32_t recovered_page = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf_first, 9, ctx->l2p[9]) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    remapped_page = ctx->l2p[9];
    if (remapped_page == 9u) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    historical_page = ctx->logical_pages + 1u;
    if (historical_page >= ctx->spare_end || historical_page == remapped_page) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    ctx->journal[1] = ctx->journal[0];
    ctx->journal[0].logical_page = 9u;
    ctx->journal[0].physical_page = historical_page;
    ctx->journal_count = 2u;
    if (little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    little_flash_ftl_deinit(&lf_first);

    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_second.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    ctx->bad[historical_page] = 1;
    if (little_flash_ftl_recover(&lf_second) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf_second, 9, &recovered_page) != LF_ERR_OK || recovered_page != remapped_page) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

static int little_flash_ftl_utest_init_refreshes_free_spares_after_recover(void) {
    little_flash_t lf_first;
    little_flash_t lf_second;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t released_page = 0;
    uint32_t duplicated_page = 0;
    uint32_t i = 0;
    uint32_t expected_free = 0;
    little_flash_ftl_utest_nand_reset();
    little_flash_ftl_utest_prepare_persistent_lf(&lf_first);
    if (little_flash_ftl_init(&lf_first, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_first.ftl_ctx;
    if (!ctx || ctx->logical_pages < 2u) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    released_page = ctx->l2p[1];
    duplicated_page = ctx->l2p[0];
    ctx->l2p[1] = duplicated_page;
    ctx->p2l[released_page] = LF_FTL_INVALID_PAGE;
    ctx->p2l[duplicated_page] = 1u;
    if (little_flash_ftl_sync(&lf_first) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf_first);
        return -1;
    }
    little_flash_ftl_deinit(&lf_first);

    little_flash_ftl_utest_prepare_persistent_lf(&lf_second);
    if (little_flash_ftl_init(&lf_second, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf_second.ftl_ctx;
    if (!ctx) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    for (i = ctx->spare_begin; i < ctx->spare_end; i++) {
        if (!ctx->bad[i] && ctx->p2l[i] == LF_FTL_INVALID_PAGE) {
            expected_free++;
        }
    }
    if (ctx->free_spares != expected_free) {
        little_flash_ftl_deinit(&lf_second);
        return -1;
    }
    little_flash_ftl_deinit(&lf_second);
    return 0;
}

int little_flash_ftl_utest_case(const char *case_name) {
    if (!case_name || strcmp(case_name, "ftl_identity_map") == 0) {
        return little_flash_ftl_utest_identity_map();
    }
    if (strcmp(case_name, "ftl_badblock_remap") == 0) {
        return little_flash_ftl_utest_badblock_remap();
    }
    if (strcmp(case_name, "ftl_powerfail_recovery") == 0) {
        return little_flash_ftl_utest_powerfail_recovery();
    }
    if (strcmp(case_name, "ftl_gc_trigger") == 0) {
        return little_flash_ftl_utest_gc_trigger();
    }
    if (strcmp(case_name, "ftl_init_stats") == 0) {
        return little_flash_ftl_utest_init_stats();
    }
    if (strcmp(case_name, "ftl_oob_read_error_scan") == 0) {
        return little_flash_ftl_utest_oob_read_error_scan();
    }
    if (strcmp(case_name, "ftl_wait_ready_timeout") == 0) {
        return little_flash_ftl_utest_wait_ready_timeout();
    }
    if (strcmp(case_name, "ftl_recover_crc_invalid") == 0) {
        return little_flash_ftl_utest_recover_crc_invalid();
    }
    if (strcmp(case_name, "ftl_recover_journal_out_of_range") == 0) {
        return little_flash_ftl_utest_recover_journal_out_of_range();
    }
    if (strcmp(case_name, "ftl_repeat_mark_bad_idempotent") == 0) {
        return little_flash_ftl_utest_repeat_mark_bad_idempotent();
    }
    if (strcmp(case_name, "ftl_capacity_safety_margin") == 0) {
        return little_flash_ftl_utest_capacity_safety_margin();
    }
    if (strcmp(case_name, "ftl_recover_state_machine") == 0) {
        return little_flash_ftl_utest_recover_state_machine();
    }
    if (strcmp(case_name, "ftl_metadata_persist_replay") == 0) {
        return little_flash_ftl_utest_metadata_persist_replay();
    }
    if (strcmp(case_name, "ftl_metadata_corrupt_fallback") == 0) {
        return little_flash_ftl_utest_metadata_corrupt_fallback();
    }
    if (strcmp(case_name, "ftl_metadata_latest_valid_slot") == 0) {
        return little_flash_ftl_utest_metadata_latest_valid_slot();
    }
    if (strcmp(case_name, "ftl_metadata_corrupt_apply_fallback_sane") == 0) {
        return little_flash_ftl_utest_metadata_corrupt_apply_fallback_sane();
    }
    if (strcmp(case_name, "ftl_metadata_slot_overflow_guard") == 0) {
        return little_flash_ftl_utest_metadata_slot_overflow_guard();
    }
    if (strcmp(case_name, "ftl_gc_checkpoint_failure_keeps_journal") == 0) {
        return little_flash_ftl_utest_gc_checkpoint_failure_keeps_journal();
    }
    if (strcmp(case_name, "ftl_metadata_tail_bad_blocks_fallback") == 0) {
        return little_flash_ftl_utest_metadata_tail_bad_blocks_fallback();
    }
    if (strcmp(case_name, "ftl_metadata_region_continuity_on_tail_bad") == 0) {
        return little_flash_ftl_utest_metadata_region_continuity_on_tail_bad();
    }
    if (strcmp(case_name, "ftl_metadata_recover_ignores_historical_bad_journal") == 0) {
        return little_flash_ftl_utest_metadata_recover_ignores_historical_bad_journal();
    }
    if (strcmp(case_name, "ftl_init_refreshes_free_spares_after_recover") == 0) {
        return little_flash_ftl_utest_init_refreshes_free_spares_after_recover();
    }
    return -1;
}
#endif
