#include "little_flash_ftl_internal.h"

void little_flash_ftl_refresh_free_spares(little_flash_ftl_ctx_t *ctx) {
    uint32_t i = 0;
    uint32_t free_pages = 0;
    if (!ctx) {
        return;
    }
    for (i = ctx->spare_begin; i < ctx->spare_end; i++) {
        if (!ctx->bad[i] && ctx->p2l[i] == LF_FTL_INVALID_PAGE) {
            free_pages++;
        }
    }
    ctx->free_spares = free_pages;
}

lf_err_t little_flash_ftl_gc_collect(little_flash_t *lf, uint8_t force) {
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t journal_trigger = 0;
    uint32_t old_journal_count = 0;
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    little_flash_ftl_refresh_free_spares(ctx);
    journal_trigger = LF_FTL_JOURNAL_MAX / (ctx->gc_ratio + 1u);
    if (journal_trigger == 0u) {
        journal_trigger = 1u;
    }
    if (!force && ctx->free_spares > ctx->gc_low_watermark && ctx->journal_count < journal_trigger) {
        return LF_ERR_OK;
    }
    old_journal_count = ctx->journal_count;
    ctx->journal_count = 0;
    if (little_flash_ftl_meta_checkpoint(lf, ctx) != LF_ERR_OK) {
        ctx->journal_count = old_journal_count;
        return LF_ERR_ERASE;
    }
    return LF_ERR_OK;
}
