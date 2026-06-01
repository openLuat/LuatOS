#include "little_flash_ftl_internal.h"
#include <string.h>

static uint32_t little_flash_ftl_crc32(const uint8_t *data, uint32_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    uint32_t i = 0;
    while (i < len) {
        uint32_t b = data[i++];
        uint32_t j = 0;
        crc ^= b;
        while (j++ < 8u) {
            uint32_t mask = (uint32_t)(-(int32_t)(crc & 1u));
            crc = (crc >> 1) ^ (0xEDB88320u & mask);
        }
    }
    return ~crc;
}

static uint32_t little_flash_ftl_meta_slot_pages(const little_flash_ftl_ctx_t *ctx) {
    if (!ctx || ctx->meta_page_count < LF_FTL_META_SLOT_COUNT) {
        return 0;
    }
    return ctx->meta_page_count / LF_FTL_META_SLOT_COUNT;
}

static uint32_t little_flash_ftl_meta_slot_start_with_base(const little_flash_ftl_ctx_t *ctx, uint32_t meta_start_page, uint32_t slot) {
    uint32_t slot_pages = little_flash_ftl_meta_slot_pages(ctx);
    return meta_start_page + slot * slot_pages;
}

static uint32_t little_flash_ftl_meta_slot_start(const little_flash_ftl_ctx_t *ctx, uint32_t slot) {
    return little_flash_ftl_meta_slot_start_with_base(ctx, ctx->meta_start_page, slot);
}

static uint32_t little_flash_ftl_meta_max_image_len(const little_flash_ftl_ctx_t *ctx) {
    if (!ctx) {
        return 0;
    }
    return (uint32_t)sizeof(little_flash_ftl_checkpoint_hdr_t) +
           ctx->logical_pages * sizeof(uint32_t) +
           LF_FTL_JOURNAL_MAX * (uint32_t)sizeof(little_flash_ftl_journal_entry_t);
}

static uint32_t little_flash_ftl_meta_payload_len(const little_flash_ftl_checkpoint_hdr_t *hdr) {
    return hdr->logical_pages * (uint32_t)sizeof(uint32_t) +
           hdr->journal_count * (uint32_t)sizeof(little_flash_ftl_journal_entry_t);
}

static uint32_t little_flash_ftl_meta_l2p_crc(const little_flash_ftl_ctx_t *ctx) {
    return little_flash_ftl_crc32((const uint8_t *)ctx->l2p, ctx->logical_pages * sizeof(uint32_t));
}

static int little_flash_ftl_meta_header_is_blank(const little_flash_ftl_checkpoint_hdr_t *hdr) {
    const uint8_t *p = (const uint8_t *)hdr;
    uint32_t i = 0;
    if (!hdr) {
        return 1;
    }
    for (i = 0; i < (uint32_t)sizeof(*hdr); i++) {
        if (p[i] != 0xFFu) {
            return 0;
        }
    }
    return 1;
}

static uint32_t little_flash_ftl_meta_journal_crc(const little_flash_ftl_ctx_t *ctx, uint32_t count) {
    return little_flash_ftl_crc32((const uint8_t *)ctx->journal, count * (uint32_t)sizeof(little_flash_ftl_journal_entry_t));
}

static int little_flash_ftl_meta_mem_checkpoint_valid(const little_flash_ftl_checkpoint_hdr_t *cp, const little_flash_ftl_ctx_t *ctx) {
    if (!cp || !ctx || cp->magic != LF_FTL_META_MAGIC || cp->version != LF_FTL_META_VERSION || cp->logical_pages != ctx->logical_pages || cp->journal_count > LF_FTL_JOURNAL_MAX) {
        return 0;
    }
    if (cp->l2p_crc != little_flash_ftl_meta_l2p_crc(ctx)) {
        return 0;
    }
    if (cp->journal_crc != little_flash_ftl_meta_journal_crc(ctx, cp->journal_count)) {
        return 0;
    }
    return 1;
}

static void little_flash_ftl_meta_raw_begin(little_flash_t *lf, little_flash_ftl_ctx_t *ctx, uint8_t *saved_enabled, uint32_t *saved_capacity) {
    *saved_enabled = lf->ftl_enabled;
    *saved_capacity = lf->chip_info.capacity;
    lf->ftl_enabled = 0;
    if (ctx && ctx->raw_capacity) {
        lf->chip_info.capacity = ctx->raw_capacity;
    }
}

static void little_flash_ftl_meta_raw_end(little_flash_t *lf, uint8_t saved_enabled, uint32_t saved_capacity) {
    lf->chip_info.capacity = saved_capacity;
    lf->ftl_enabled = saved_enabled;
}

static lf_err_t little_flash_ftl_meta_raw_read(little_flash_t *lf, little_flash_ftl_ctx_t *ctx, uint32_t addr, uint8_t *buf, uint32_t len) {
    lf_err_t ret;
    uint8_t saved_enabled = 0;
    uint32_t saved_capacity = 0;
    little_flash_ftl_meta_raw_begin(lf, ctx, &saved_enabled, &saved_capacity);
    ret = little_flash_read(lf, addr, buf, len);
    little_flash_ftl_meta_raw_end(lf, saved_enabled, saved_capacity);
    return ret;
}

static lf_err_t little_flash_ftl_meta_raw_erase(little_flash_t *lf, little_flash_ftl_ctx_t *ctx, uint32_t addr, uint32_t len) {
    lf_err_t ret;
    uint8_t saved_enabled = 0;
    uint32_t saved_capacity = 0;
    little_flash_ftl_meta_raw_begin(lf, ctx, &saved_enabled, &saved_capacity);
    ret = little_flash_erase(lf, addr, len);
    little_flash_ftl_meta_raw_end(lf, saved_enabled, saved_capacity);
    return ret;
}

static lf_err_t little_flash_ftl_meta_raw_write(little_flash_t *lf, little_flash_ftl_ctx_t *ctx, uint32_t addr, const uint8_t *buf, uint32_t len) {
    lf_err_t ret;
    uint8_t saved_enabled = 0;
    uint32_t saved_capacity = 0;
    little_flash_ftl_meta_raw_begin(lf, ctx, &saved_enabled, &saved_capacity);
    ret = little_flash_write(lf, addr, buf, len);
    little_flash_ftl_meta_raw_end(lf, saved_enabled, saved_capacity);
    return ret;
}

static int little_flash_ftl_meta_prepare_image(const little_flash_ftl_ctx_t *ctx,
                                               little_flash_ftl_checkpoint_hdr_t *hdr,
                                               uint8_t *image,
                                               uint32_t image_capacity,
                                               uint32_t *image_len) {
    uint32_t l2p_len = 0;
    uint32_t journal_len = 0;
    uint8_t *payload = NULL;
    if (!ctx || !hdr || !image || !image_len) {
        return -1;
    }
    l2p_len = ctx->logical_pages * (uint32_t)sizeof(uint32_t);
    journal_len = ctx->journal_count * (uint32_t)sizeof(little_flash_ftl_journal_entry_t);
    *image_len = (uint32_t)sizeof(*hdr) + l2p_len + journal_len;
    if (*image_len > image_capacity) {
        return -1;
    }
    memset(image, 0xFF, image_capacity);
    payload = image + sizeof(*hdr);
    memcpy(payload, ctx->l2p, l2p_len);
    if (journal_len) {
        memcpy(payload + l2p_len, ctx->journal, journal_len);
    }
    hdr->magic = LF_FTL_META_MAGIC;
    hdr->version = LF_FTL_META_VERSION;
    hdr->logical_pages = ctx->logical_pages;
    hdr->journal_count = ctx->journal_count;
    hdr->l2p_crc = little_flash_ftl_crc32(payload, l2p_len);
    hdr->journal_crc = little_flash_ftl_crc32(payload + l2p_len, journal_len);
    hdr->image_crc = 0;
    memcpy(image, hdr, sizeof(*hdr));
    hdr->image_crc = little_flash_ftl_crc32(image, *image_len);
    memcpy(image, hdr, sizeof(*hdr));
    return 0;
}

static int little_flash_ftl_meta_validate_image(const little_flash_ftl_ctx_t *ctx,
                                                little_flash_ftl_checkpoint_hdr_t *hdr,
                                                uint8_t *image,
                                                uint32_t image_len) {
    uint32_t expected_payload = 0;
    uint32_t l2p_len = 0;
    uint32_t journal_len = 0;
    uint32_t crc = 0;
    uint32_t saved_image_crc = 0;
    uint8_t *payload = NULL;
    if (!ctx || !hdr || !image || image_len < sizeof(*hdr)) {
        return 0;
    }
    if (hdr->magic != LF_FTL_META_MAGIC || hdr->version != LF_FTL_META_VERSION || hdr->logical_pages == 0u ||
        hdr->logical_pages > ctx->spare_end || hdr->journal_count > LF_FTL_JOURNAL_MAX) {
        return 0;
    }
    expected_payload = little_flash_ftl_meta_payload_len(hdr);
    if (image_len != sizeof(*hdr) + expected_payload) {
        return 0;
    }
    saved_image_crc = hdr->image_crc;
    hdr->image_crc = 0;
    memcpy(image, hdr, sizeof(*hdr));
    crc = little_flash_ftl_crc32(image, image_len);
    hdr->image_crc = saved_image_crc;
    memcpy(image, hdr, sizeof(*hdr));
    if (crc != saved_image_crc) {
        return 0;
    }
    payload = image + sizeof(*hdr);
    l2p_len = hdr->logical_pages * (uint32_t)sizeof(uint32_t);
    journal_len = hdr->journal_count * (uint32_t)sizeof(little_flash_ftl_journal_entry_t);
    if (little_flash_ftl_crc32(payload, l2p_len) != hdr->l2p_crc) {
        return 0;
    }
    if (little_flash_ftl_crc32(payload + l2p_len, journal_len) != hdr->journal_crc) {
        return 0;
    }
    return 1;
}

static lf_err_t little_flash_ftl_meta_write_slot(little_flash_t *lf, little_flash_ftl_ctx_t *ctx, uint32_t slot, little_flash_ftl_checkpoint_hdr_t *hdr) {
    uint32_t slot_pages = little_flash_ftl_meta_slot_pages(ctx);
    uint32_t slot_start_page = 0;
    uint32_t slot_addr = 0;
    uint32_t slot_size = 0;
    uint32_t image_capacity = 0;
    uint32_t image_len = 0;
    uint8_t *image = NULL;
    lf_err_t ret = LF_ERR_OK;
    if (!lf || !ctx || !hdr || slot >= LF_FTL_META_SLOT_COUNT || !lf->malloc || !lf->free) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (slot_pages == 0) {
        return LF_ERR_BAD_ADDRESS;
    }
    image_capacity = little_flash_ftl_meta_max_image_len(ctx);
    image = (uint8_t *)lf->malloc(image_capacity);
    if (!image) {
        return LF_ERR_NO_MEM;
    }
    if (little_flash_ftl_meta_prepare_image(ctx, hdr, image, image_capacity, &image_len) != 0) {
        lf->free(image);
        return LF_ERR_NO_MEM;
    }
    slot_start_page = little_flash_ftl_meta_slot_start(ctx, slot);
    slot_addr = slot_start_page * lf->chip_info.read_size;
    slot_size = slot_pages * lf->chip_info.read_size;
    if (image_len > slot_size) {
        lf->free(image);
        return LF_ERR_BAD_ADDRESS;
    }
    ret = little_flash_ftl_meta_raw_erase(lf, ctx, slot_addr, slot_size);
    if (ret == LF_ERR_OK) {
        ret = little_flash_ftl_meta_raw_write(lf, ctx, slot_addr, image, image_len);
    }
    lf->free(image);
    return ret;
}

static int little_flash_ftl_meta_read_slot(little_flash_t *lf,
                                           little_flash_ftl_ctx_t *ctx,
                                           uint32_t meta_start_page,
                                           uint32_t slot,
                                           little_flash_ftl_checkpoint_hdr_t *hdr,
                                           uint8_t *image,
                                           uint32_t image_capacity,
                                           uint32_t *image_len) {
    uint32_t slot_addr = 0;
    lf_err_t ret;
    if (!lf || !ctx || !hdr || !image || !image_len || slot >= LF_FTL_META_SLOT_COUNT) {
        return 0;
    }
    slot_addr = little_flash_ftl_meta_slot_start_with_base(ctx, meta_start_page, slot) * lf->chip_info.read_size;
    ret = little_flash_ftl_meta_raw_read(lf, ctx, slot_addr, (uint8_t *)hdr, (uint32_t)sizeof(*hdr));
    if (ret != LF_ERR_OK) {
        return 0;
    }
    if (hdr->magic != LF_FTL_META_MAGIC || hdr->version != LF_FTL_META_VERSION || hdr->logical_pages == 0u ||
        hdr->logical_pages > ctx->spare_end || hdr->journal_count > LF_FTL_JOURNAL_MAX) {
        return 0;
    }
    *image_len = (uint32_t)sizeof(*hdr) + little_flash_ftl_meta_payload_len(hdr);
    if (*image_len > image_capacity) {
        return 0;
    }
    ret = little_flash_ftl_meta_raw_read(lf, ctx, slot_addr, image, *image_len);
    if (ret != LF_ERR_OK) {
        return 0;
    }
    memcpy(hdr, image, sizeof(*hdr));
    return little_flash_ftl_meta_validate_image(ctx, hdr, image, *image_len);
}

static int little_flash_ftl_meta_apply_image(little_flash_ftl_ctx_t *ctx,
                                             const little_flash_ftl_checkpoint_hdr_t *hdr,
                                             const uint8_t *image) {
    uint32_t i = 0;
    uint32_t l2p_len = 0;
    uint32_t journal_len = 0;
    const uint8_t *payload = NULL;
    if (!ctx || !hdr || !image) {
        return 0;
    }
    payload = image + sizeof(*hdr);
    l2p_len = hdr->logical_pages * (uint32_t)sizeof(uint32_t);
    journal_len = hdr->journal_count * (uint32_t)sizeof(little_flash_ftl_journal_entry_t);
    memset(ctx->l2p, 0xFF, ctx->page_count * sizeof(uint32_t));
    memcpy(ctx->l2p, payload, l2p_len);
    memset(ctx->p2l, 0xFF, ctx->page_count * sizeof(uint32_t));
    for (i = 0; i < hdr->logical_pages; i++) {
        uint32_t p = ctx->l2p[i];
        if (p >= ctx->spare_end || ctx->bad[p]) {
            return 0;
        }
        ctx->p2l[p] = i;
    }
    ctx->logical_pages = hdr->logical_pages;
    ctx->journal_count = hdr->journal_count;
    memset(ctx->journal, 0, sizeof(ctx->journal));
    if (journal_len) {
        memcpy(ctx->journal, payload + l2p_len, journal_len);
    }
    return 1;
}

static void little_flash_ftl_meta_build_identity(little_flash_ftl_ctx_t *ctx) {
    uint32_t i = 0;
    uint32_t l = 0;
    if (!ctx) {
        return;
    }
    for (i = 0; i < ctx->page_count; i++) {
        ctx->l2p[i] = LF_FTL_INVALID_PAGE;
        ctx->p2l[i] = LF_FTL_INVALID_PAGE;
    }
    for (i = ctx->spare_begin; i < ctx->spare_end && l < ctx->logical_pages; i++) {
        if (ctx->bad[i]) {
            continue;
        }
        ctx->l2p[l] = i;
        ctx->p2l[i] = l;
        l++;
    }
}

static void little_flash_ftl_meta_fallback(little_flash_ftl_ctx_t *ctx) {
    if (!ctx) {
        return;
    }
    ctx->journal_count = 0;
    memset(ctx->journal, 0, sizeof(ctx->journal));
    little_flash_ftl_meta_build_identity(ctx);
}

static lf_err_t little_flash_ftl_meta_replay_journal(little_flash_ftl_ctx_t *ctx) {
    uint32_t i = 0;
    if (!ctx) {
        return LF_ERR_BAD_ADDRESS;
    }
    for (i = 0; i < ctx->journal_count; i++) {
        uint32_t l = ctx->journal[i].logical_page;
        uint32_t p = ctx->journal[i].physical_page;
        uint32_t old_p = 0;
        if (l >= ctx->logical_pages || p >= ctx->page_count || ctx->bad[p]) {
            return LF_ERR_BAD_ADDRESS;
        }
        old_p = ctx->l2p[l];
        if (old_p < ctx->page_count && old_p != p && ctx->p2l[old_p] == l) {
            ctx->p2l[old_p] = LF_FTL_INVALID_PAGE;
        }
        ctx->l2p[l] = p;
        ctx->p2l[p] = l;
    }
    return LF_ERR_OK;
}

lf_err_t little_flash_ftl_meta_checkpoint(little_flash_t *lf, little_flash_ftl_ctx_t *ctx) {
    little_flash_ftl_checkpoint_hdr_t next;
    uint32_t generation = 0;
    uint32_t slot = 0;
    lf_err_t ret;
    if (!lf || !ctx || !ctx->l2p) {
        return LF_ERR_BAD_ADDRESS;
    }
    memset(&next, 0, sizeof(next));
    generation = (ctx->cp_a.generation > ctx->cp_b.generation ? ctx->cp_a.generation : ctx->cp_b.generation) + 1u;
    next.generation = generation;
    next.magic = LF_FTL_META_MAGIC;
    next.version = LF_FTL_META_VERSION;
    next.logical_pages = ctx->logical_pages;
    next.journal_count = ctx->journal_count;
    next.l2p_crc = little_flash_ftl_meta_l2p_crc(ctx);
    next.journal_crc = little_flash_ftl_meta_journal_crc(ctx, ctx->journal_count);
    if (!lf->spi.transfer) {
        if ((generation % LF_FTL_META_SLOT_COUNT) == 0u) {
            ctx->cp_a = next;
        } else {
            ctx->cp_b = next;
        }
        return LF_ERR_OK;
    }
    slot = generation % LF_FTL_META_SLOT_COUNT;
    ret = little_flash_ftl_meta_write_slot(lf, ctx, slot, &next);
    if (ret != LF_ERR_OK) {
        return ret;
    }
    if (slot == 0u) {
        ctx->cp_a = next;
    } else {
        ctx->cp_b = next;
    }
    return LF_ERR_OK;
}

lf_err_t little_flash_ftl_meta_append_journal(little_flash_t *lf, little_flash_ftl_ctx_t *ctx, uint32_t logical_page, uint32_t physical_page) {
    if (!ctx || ctx->journal_count >= LF_FTL_JOURNAL_MAX) {
        return LF_ERR_NO_MEM;
    }
    ctx->journal[ctx->journal_count].logical_page = logical_page;
    ctx->journal[ctx->journal_count].physical_page = physical_page;
    ctx->journal_count++;
    return little_flash_ftl_meta_checkpoint(lf, ctx);
}

lf_err_t little_flash_ftl_meta_recover(little_flash_t *lf, little_flash_ftl_ctx_t *ctx) {
    int32_t start_block = 0;
    uint32_t metadata_blocks = 0;
    uint32_t selected_meta_start_page = 0;
    uint32_t i = 0;
    uint32_t image_capacity = 0;
    uint32_t selected_slot = LF_FTL_META_SLOT_COUNT;
    uint32_t selected_generation = 0;
    little_flash_ftl_checkpoint_hdr_t hdr;
    little_flash_ftl_checkpoint_hdr_t selected_hdr;
    uint8_t *image = NULL;
    uint32_t image_len = 0;
    lf_err_t replay_ret = LF_ERR_OK;
    uint8_t slots_all_blank = 1;
    if (!lf || !ctx || !ctx->l2p || !lf->malloc || !lf->free) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (!lf->spi.transfer) {
        if (!little_flash_ftl_meta_mem_checkpoint_valid(&ctx->cp_a, ctx) && !little_flash_ftl_meta_mem_checkpoint_valid(&ctx->cp_b, ctx)) {
            return LF_ERR_READ;
        }
        replay_ret = little_flash_ftl_meta_replay_journal(ctx);
        if (replay_ret == LF_ERR_OK) {
            little_flash_ftl_refresh_free_spares(ctx);
        }
        return replay_ret;
    }
    image_capacity = little_flash_ftl_meta_max_image_len(ctx);
    image = (uint8_t *)lf->malloc(image_capacity);
    if (!image) {
        return LF_ERR_NO_MEM;
    }
    memset(&selected_hdr, 0, sizeof(selected_hdr));
    memset(&ctx->cp_a, 0, sizeof(ctx->cp_a));
    memset(&ctx->cp_b, 0, sizeof(ctx->cp_b));
    metadata_blocks = ctx->meta_page_count / ctx->pages_per_block;
    if (metadata_blocks == 0u || metadata_blocks >= ctx->block_count) {
        little_flash_ftl_meta_fallback(ctx);
        little_flash_ftl_refresh_free_spares(ctx);
        lf->free(image);
        return LF_ERR_READ;
    }
    for (start_block = (int32_t)(ctx->block_count - metadata_blocks); start_block >= 1; start_block--) {
        uint32_t candidate_meta_start = (uint32_t)start_block * ctx->pages_per_block;
        for (i = 0; i < LF_FTL_META_SLOT_COUNT; i++) {
            lf_err_t read_ret;
            uint32_t slot_page = little_flash_ftl_meta_slot_start_with_base(ctx, candidate_meta_start, i);
            if (slot_page >= ctx->page_count || ctx->bad[slot_page]) {
                continue;
            }
            memset(&hdr, 0, sizeof(hdr));
            read_ret = little_flash_ftl_meta_raw_read(lf, ctx, slot_page * lf->chip_info.read_size, (uint8_t *)&hdr, (uint32_t)sizeof(hdr));
            if (read_ret == LF_ERR_OK && !little_flash_ftl_meta_header_is_blank(&hdr)) {
                slots_all_blank = 0;
            }
            if (!little_flash_ftl_meta_read_slot(lf, ctx, candidate_meta_start, i, &hdr, image, image_capacity, &image_len)) {
                continue;
            }
            if (selected_slot == LF_FTL_META_SLOT_COUNT || hdr.generation > selected_generation) {
                selected_slot = i;
                selected_generation = hdr.generation;
                selected_meta_start_page = candidate_meta_start;
                selected_hdr = hdr;
            }
        }
    }
    if (selected_slot == LF_FTL_META_SLOT_COUNT) {
        little_flash_ftl_meta_fallback(ctx);
        little_flash_ftl_refresh_free_spares(ctx);
        lf->free(image);
        return slots_all_blank ? LF_ERR_OK : LF_ERR_READ;
    }
    if (!little_flash_ftl_meta_read_slot(lf, ctx, selected_meta_start_page, selected_slot, &selected_hdr, image, image_capacity, &image_len) ||
        !little_flash_ftl_meta_apply_image(ctx, &selected_hdr, image)) {
        little_flash_ftl_meta_fallback(ctx);
        little_flash_ftl_refresh_free_spares(ctx);
        lf->free(image);
        return LF_ERR_READ;
    }
    /* Use recovered generation for next checkpoint while keeping current write region selection. */
    if (selected_slot == 0u) {
        ctx->cp_a = selected_hdr;
    } else {
        ctx->cp_b = selected_hdr;
    }
    little_flash_ftl_refresh_free_spares(ctx);
    lf->free(image);
    return LF_ERR_OK;
}
