#ifndef _LITTLE_FLASH_FTL_INTERNAL_H_
#define _LITTLE_FLASH_FTL_INTERNAL_H_

#include "little_flash_ftl.h"

#define LF_FTL_INVALID_PAGE (0xFFFFFFFFu)
#define LF_FTL_JOURNAL_MAX (256u)
#define LF_FTL_RECOVER_RETRY_MAX (2u)
#define LF_FTL_META_MAGIC (0x4C46544Cu)
#define LF_FTL_META_VERSION (1u)
#define LF_FTL_META_SLOT_COUNT (2u)

typedef enum {
    LF_FTL_RECOVER_STATE_IDLE = 0,
    LF_FTL_RECOVER_STATE_RECOVERING,
    LF_FTL_RECOVER_STATE_RETRY,
    LF_FTL_RECOVER_STATE_FAILED
} little_flash_ftl_recover_state_t;

typedef struct {
    uint32_t logical_page;
    uint32_t physical_page;
} little_flash_ftl_journal_entry_t;

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t generation;
    uint32_t logical_pages;
    uint32_t l2p_crc;
    uint32_t journal_count;
    uint32_t journal_crc;
    uint32_t image_crc;
} little_flash_ftl_checkpoint_hdr_t;

typedef struct {
    uint32_t page_count;
    uint32_t pages_per_block;
    uint32_t block_count;
    uint32_t logical_pages;
    uint32_t reserve_pages;
    uint32_t safety_margin_pages;
    uint32_t spare_begin;
    uint32_t spare_end;
    uint32_t free_spares;
    uint32_t bad_blocks;
    uint32_t bad_pages;
    uint32_t gc_low_watermark;
    uint32_t gc_high_watermark;
    uint32_t gc_ratio;
    uint32_t raw_capacity;
    uint32_t meta_start_page;
    uint32_t meta_page_count;
    uint32_t recover_retries;
    little_flash_ftl_recover_state_t recover_state;
    uint32_t *l2p;
    uint32_t *p2l;
    uint8_t *bad;
    little_flash_ftl_journal_entry_t journal[LF_FTL_JOURNAL_MAX];
    uint32_t journal_count;
    little_flash_ftl_checkpoint_hdr_t cp_a;
    little_flash_ftl_checkpoint_hdr_t cp_b;
} little_flash_ftl_ctx_t;

lf_err_t little_flash_ftl_meta_checkpoint(little_flash_t *lf, little_flash_ftl_ctx_t *ctx);
lf_err_t little_flash_ftl_meta_append_journal(little_flash_t *lf, little_flash_ftl_ctx_t *ctx, uint32_t logical_page, uint32_t physical_page);
lf_err_t little_flash_ftl_meta_recover(little_flash_t *lf, little_flash_ftl_ctx_t *ctx);
void little_flash_ftl_refresh_free_spares(little_flash_ftl_ctx_t *ctx);

#endif
