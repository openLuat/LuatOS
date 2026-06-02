/*
 * little_flash FTL implementation — stripped to identity-mapping stubs.
 *
 * Real NAND FTL (bad-block management, wear-levelling, GC, checkpoint/journal)
 * has been removed from little_flash.  The FTL layer is now owned by pgfs.
 *
 * All little_flash NAND operations use direct identity-address translation:
 *   logical_page == physical_page
 *
 * External callers:
 *   little_flash.c     — init / deinit / map_page / mark_bad_and_remap / sync / recover
 *   little_flash_ftl_gc.c  (deleted) — refresh_free_spares / gc_collect
 *   little_flash_ftl_meta.c (deleted) — meta_checkpoint / meta_append_journal / meta_recover
 */
#include "little_flash_ftl_internal.h"
#include "luat_malloc.h"
#include <string.h>

/* ── Public API ──────────────────────────────────────────────────────────── */

/*
 * little_flash_ftl_init — stub.
 * Real FTL init is deferred to pgfs at mount time.
 * Returns OK unconditionally; no state is allocated.
 */
lf_err_t little_flash_ftl_init(little_flash_t *lf, uint8_t op_percent) {
    (void)lf;
    (void)op_percent;
    return LF_ERR_OK;
}

/*
 * little_flash_ftl_deinit — stub.
 * No state to tear down.
 */
void little_flash_ftl_deinit(little_flash_t *lf) {
    (void)lf;
}

/*
 * little_flash_ftl_map_page — identity mapping.
 * logical_page is returned as-is as physical_page.
 */
lf_err_t little_flash_ftl_map_page(const little_flash_t *lf, uint32_t logical_page, uint32_t *physical_page) {
    if (!lf || !physical_page) {
        return LF_ERR_BAD_ADDRESS;
    }
    *physical_page = logical_page;
    return LF_ERR_OK;
}

/*
 * little_flash_ftl_mark_bad_and_remap — stub.
 * Real bad-block handling lives in pgfs. Returns OK so little_flash.c
 * erase/write error paths treat the operation as handled.
 */
lf_err_t little_flash_ftl_mark_bad_and_remap(little_flash_t *lf,
                                             uint32_t logical_page,
                                             uint32_t bad_physical_page) {
    (void)lf;
    (void)logical_page;
    (void)bad_physical_page;
    return LF_ERR_OK;
}

/*
 * little_flash_ftl_sync — stub.
 * Checkpoint is pgfs's responsibility.
 */
lf_err_t little_flash_ftl_sync(little_flash_t *lf) {
    (void)lf;
    return LF_ERR_OK;
}

/*
 * little_flash_ftl_recover — stub.
 * Recovery is pgfs's responsibility.
 */
lf_err_t little_flash_ftl_recover(little_flash_t *lf) {
    (void)lf;
    return LF_ERR_OK;
}

/*
 * little_flash_ftl_gc_collect — stub.
 * GC is pgfs's responsibility.
 */
lf_err_t little_flash_ftl_gc_collect(little_flash_t *lf, uint8_t force) {
    (void)lf;
    (void)force;
    return LF_ERR_OK;
}

/* ── Internal helpers (were in little_flash_ftl_meta.c) ──────────────────── */

/*
 * little_flash_ftl_refresh_free_spares — stub.
 * Was used by gc_collect; no longer relevant.
 */
void little_flash_ftl_refresh_free_spares(little_flash_ftl_ctx_t *ctx) {
    (void)ctx;
}

/*
 * little_flash_ftl_meta_checkpoint — stub.
 * Checkpoint is pgfs's responsibility.
 */
lf_err_t little_flash_ftl_meta_checkpoint(little_flash_t *lf, little_flash_ftl_ctx_t *ctx) {
    (void)lf;
    (void)ctx;
    return LF_ERR_OK;
}

/*
 * little_flash_ftl_meta_append_journal — stub.
 * Journal is pgfs's responsibility.
 */
lf_err_t little_flash_ftl_meta_append_journal(little_flash_t *lf,
                                             little_flash_ftl_ctx_t *ctx,
                                             uint32_t logical_page,
                                             uint32_t physical_page) {
    (void)lf;
    (void)ctx;
    (void)logical_page;
    (void)physical_page;
    return LF_ERR_OK;
}

/*
 * little_flash_ftl_meta_recover — stub.
 * Recovery is pgfs's responsibility.
 */
lf_err_t little_flash_ftl_meta_recover(little_flash_t *lf, little_flash_ftl_ctx_t *ctx) {
    (void)lf;
    (void)ctx;
    return LF_ERR_OK;
}

/* ── Utest entry point (FTL tests removed) ─────────────────────────────── */

/*
 * little_flash_ftl_utest_case — all FTL-specific tests have been removed.
 * Returns -1 so the test runner reports "case not found".
 */
#ifdef LUAT_USE_UTEST
int little_flash_ftl_utest_case(const char *case_name) {
    (void)case_name;
    return -1;  /* not found / skipped */
}
#endif
