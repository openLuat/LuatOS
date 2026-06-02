#ifndef _LITTLE_FLASH_FTL_H_
#define _LITTLE_FLASH_FTL_H_

#include "little_flash.h"

/**
 * @file little_flash_ftl.h
 * @brief Static bad-block replacement layer for little_flash.
 *
 * SCOPE & HONESTY (read before assuming any FTL semantics):
 *
 * This module is named "FTL" but is **NOT** a true flash translation layer
 * with dynamic remap / wear-leveling / GC victim move. It is a
 * "static bad-block replacement + double-slot checkpoint + remap journal"
 * implementation, semantically closer to MTD skipbadblocks than to a
 * page/block/hybrid mapping FTL.
 *
 * Provides:
 *  - l2p / p2l mapping built once at init (identity + remap hooks)
 *  - mark_bad_and_remap() as the only runtime remap entry (triggered on
 *    erase/write failure by little_flash.c)
 *  - Double-slot checkpoint image + remap journal (append-only)
 *  - Per-page bitmap of bad/used pages for O(1) find_spare (since F-10)
 *
 * Does NOT provide (planned, see docs/audit/track_b_ftl_layer.md §10):
 *  - Dynamic block reclaim / garbage collection
 *  - erase_count[] wear-leveling (F-03 is the WL evolution track)
 *  - GC stall for write backpressure (F-07)
 *  - l2p/p2l compression (F-08)
 *
 * Upper FS (e.g. pgfs) MUST NOT assume any write-amplification control
 * or block reclaim from this layer. Treat it as MTD + journal, not FTL.
 * Callers needing real FTL/WL behavior should migrate to little_flash_v3
 * (F-02/F-03 evolution track) once available.
 *
 * Scope: see docs/audit/track_b_ftl_layer.md for the full audit including
 * the 10 deep issues (F-01..F-10) and the 5-phase implementation plan.
 */

#ifdef __cplusplus
extern "C" {
#endif

lf_err_t little_flash_ftl_init(little_flash_t *lf, uint8_t op_percent);
void little_flash_ftl_deinit(little_flash_t *lf);
lf_err_t little_flash_ftl_map_page(const little_flash_t *lf, uint32_t logical_page, uint32_t *physical_page);
lf_err_t little_flash_ftl_mark_bad_and_remap(little_flash_t *lf, uint32_t logical_page, uint32_t bad_physical_page);
lf_err_t little_flash_ftl_sync(little_flash_t *lf);
lf_err_t little_flash_ftl_recover(little_flash_t *lf);
lf_err_t little_flash_ftl_gc_collect(little_flash_t *lf, uint8_t force);

#ifdef LUAT_USE_UTEST
int little_flash_ftl_utest_case(const char *case_name);
#endif

#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_FTL_H_ */
