/*
 * pgfs_nand_ftl.h — PGFS NAND Flash Translation Layer
 *
 * Responsibilities:
 *   - Factory bad-block detection (OOB factory-marker scan)
 *   - Runtime bad-block tracking (erase-fail marking)
 *   - Per-block erase-count tracking (wear-levelling basis)
 *   - Checkpoint persistence of FTL state
 *
 * FTL state is RAM-resident during operation, persisted to the CP area
 * on each checkpoint commit, and rebuilt on mount by scanning + loading
 * persisted state.
 *
 * Storage layout (after each checkpoint record, 1 erase-unit):
 *   [pgfs_ftl_meta_t header] [bad_block bitmap] [erase_counts[]]
 */
#ifndef PGFS_NAND_FTL_H
#define PGFS_NAND_FTL_H

#include "luat_pgfs.h"

/* PGFS layout addresses needed by pgfs_nand_ftl.c.
 * These are duplicated from pgfs_internal.h to avoid circular includes. */
#ifndef PGFS_V1_CHECKPOINT_B_ADDR
#define PGFS_V1_CHECKPOINT_B_ADDR  0x3000u
#endif

#include <stdbool.h>
#include <stdint.h>
/* <string.h> only needed by the .c implementation — not needed in the header */

/* ── FTL metadata on-flash format ─────────────────────────────────────── */

#define PGFS_FTL_MAGIC   0x5046544Cu   /* 'PFTL' */
/* v2: adds write_head_block, write_head_offset, log_tail_block,
 * log_tail_offset, and a reserved_blocks_bitmap appended after the
 * bad-block bitmap. v1 records are rejected as "load failed → scan". */
#define PGFS_FTL_VERSION 2u

/* Bitmap helpers: 1 bit per block, block N bad iff (bitmap[N/8] & (1 << (N%8))) */
#define PGFS_FTL_BITMAP_BYTES(BLOCKS)  (((BLOCKS) + 7u) / 8u)

typedef struct pgfs_ftl_meta {
    uint32_t magic;
    uint16_t version;
    uint16_t total_blocks;   /* matches geo from control() */
    uint32_t bitmap_bytes;   /* bytes for the bad-block bitmap = PGFS_FTL_BITMAP_BYTES(total_blocks) */
    uint32_t reserved_bitmap_bytes; /* v2: bytes for the reserved-block bitmap = same as bitmap_bytes */
    uint32_t erase_count_bytes; /* bytes for the erase-count array = total_blocks * sizeof(uint16_t) */
    uint32_t write_head_block;     /* v2: current write block in the data log */
    uint16_t write_head_offset;    /* v2: offset within write_head_block (prog-aligned) */
    uint16_t log_tail_block_lo;    /* v2 low-16 of cp.log_tail_block (compat) */
    uint32_t log_tail_block;       /* v2: per-segment tail block at last CP */
    uint16_t log_tail_offset;      /* v2: tail offset at last CP */
    uint16_t reserved1;            /* v2: padding */
    uint32_t crc32;          /* CRC over [meta + bad_blocks + reserved_blocks + erase_counts] with this field = 0 */
} pgfs_ftl_meta_t;

/* ── FTL runtime context ───────────────────────────────────────────────── */

typedef struct {
    /* geometry (read from flash backend at init) */
    uint32_t total_blocks;
    uint32_t erase_size;

    /* bad-block bitmap: 1=bad, 0=good; indexed by block_id */
    uint8_t *bad_blocks_bitmap;      /* heap-allocated, (total_blocks+7)/8 bytes */
    uint32_t bad_block_count;

    /* reserved-block bitmap: 1=reserved, 0=usable; indexed by block_id.
     * Reserved blocks (SB-A/B, CP-A/B, FTL state) must never be allocated
     * for data log segments. Phase 1. */
    uint8_t *reserved_blocks_bitmap;  /* heap-allocated, (total_blocks+7)/8 bytes */
    uint32_t reserved_block_count;

    /* per-block erase counts: erase_counts[block_id] */
    uint16_t *erase_counts;          /* heap-allocated, total_blocks entries */
    uint32_t total_erase_count;     /* sum of all entries, for diagnostics */

    /* flash backend */
    const pgfs_flash_opts_t *flash_opts;

    /* bad block injection (testing) */
    uint8_t inject_bad_block_once;
    uint8_t inject_bad_block_flag;    /* 0=not-injected, 1=injected-this-session */
    uint32_t inject_bad_block_id;

    /* last successful persist snapshot (heap-owned, NULL until first persist).
     * Used by pgfs_ftl_persist to detect write failures: if readback verify
     * fails, the previous on-flash snapshot is still valid for recovery. */
    uint8_t *last_persist_buf;
    uint32_t last_persist_size;
    uint32_t persist_success_count;
    uint32_t persist_failure_count;

    /* powercut injection (testing) — propagated from mount ctx at init time */
    uint8_t powercut_inject;
} pgfs_nand_ftl_ctx_t;

/* ── Public API ────────────────────────────────────────────────────────── */

/*
 * pgfs_ftl_init — initialise FTL context.
 *   ctx          : pre-allocated context (zeroed by caller)
 *   flash_opts   : pgfs flash backend
 *   erase_size   : bytes per erase unit
 *   total_blocks : total number of erase units
 * Returns 0 on success, -1 on error.
 */
int pgfs_ftl_init(pgfs_nand_ftl_ctx_t *ctx,
                  const pgfs_flash_opts_t *flash_opts,
                  uint32_t erase_size,
                  uint32_t total_blocks);

/*
 * pgfs_ftl_deinit — free heap allocations.
 */
void pgfs_ftl_deinit(pgfs_nand_ftl_ctx_t *ctx);

/*
 * pgfs_ftl_is_block_bad — check if a block is bad.
 * Returns true if block is marked bad.
 */
bool pgfs_ftl_is_block_bad(const pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id);

/*
 * pgfs_ftl_mark_block_bad — mark a block as bad (runtime, e.g. erase failure).
 * Does NOT persist; call pgfs_ftl_persist afterwards.
 */
void pgfs_ftl_mark_block_bad(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id);

/*
 * pgfs_ftl_mark_reserved / pgfs_ftl_is_reserved — Phase 1: manage the
 * reserved-block bitmap. Reserved blocks (SB-A/B, CP-A/B, FTL state) must
 * never be allocated for data log segments. The bitmap is persisted as
 * part of the FTL state.
 */
void pgfs_ftl_mark_reserved(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id);
bool pgfs_ftl_is_reserved(const pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id);
void pgfs_ftl_clear_reserved(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id);

/*
 * pgfs_ftl_find_free_block — find the next good block from a given start.
 *   ctx       : FTL context
 *   start_id  : first block to try (inclusive)
 *   out_block : output block_id
 * Returns 0 on success, -1 if no good block found.
 */
int pgfs_ftl_find_free_block(const pgfs_nand_ftl_ctx_t *ctx,
                             uint32_t start_id,
                             uint32_t *out_block);

/*
 * pgfs_ftl_block_erased — called after a successful erase.
 * Increments erase count for that block.
 */
void pgfs_ftl_block_erased(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id);

/*
 * pgfs_ftl_persist — write FTL state to flash immediately after CP area.
 *   ctx        : FTL context (non-const so the last-good snapshot can be
 *                updated on success; preserved on failure)
 *   cp_seq     : checkpoint sequence number (for logging/debug)
 * Returns 0 on success, -1 on error.
 *
 * Layout written (one erase-unit starting at PGFS_FTL_STATE_ADDR):
 *   [pgfs_ftl_meta_t] [bad_blocks_bitmap] [erase_counts[]]
 *
 * On success: ctx->last_persist_buf is updated to a copy of the buffer
 *             just written, ctx->last_persist_size is set, and
 *             ctx->persist_success_count is incremented.
 * On failure: the previous ctx->last_persist_buf is preserved (if any) so
 *             the caller can still fall back to it. ctx->persist_failure_count
 *             is incremented.
 *
 * PGFS_FTL_STATE_ADDR is computed as the next erase-unit after the
 * two CP slots (PGFS_CHECKPOINT_B_ADDR + erase_size).
 */
int pgfs_ftl_persist(pgfs_nand_ftl_ctx_t *ctx, uint32_t cp_seq);

/*
 * pgfs_ftl_load — load FTL state from flash (called at mount time).
 *   ctx        : FTL context (must already have geometry fields set)
 * Returns 0 on success (state loaded), 1 if no valid record found (scan needed),
 *         -1 on error.
 */
int pgfs_ftl_load(pgfs_nand_ftl_ctx_t *ctx);

/*
 * pgfs_ftl_scan_bad_blocks — factory scan: try erasing every block and
 * marking failures as bad.
 *   ctx        : FTL context (geometry already known)
 *   progress_cb: optional callback(block_id, total) for progress, may be NULL
 * Returns 0 on success.
 *
 * NOTE: this is called when no persisted FTL record is found on mount,
 * or when the persisted record is corrupt.
 */
int pgfs_ftl_scan_bad_blocks(pgfs_nand_ftl_ctx_t *ctx,
                             void (*progress_cb)(uint32_t done, uint32_t total));

/*
 * pgfs_ftl_inject_bad_block_once — mark one block bad on next erase attempt.
 *   ctx     : FTL context
 *   block_id: block to fail (if >= total_blocks, ignored)
 * After the block is marked bad, inject_bad_block_flag is cleared.
 */
void pgfs_ftl_inject_bad_block_once(pgfs_nand_ftl_ctx_t *ctx, uint32_t block_id);

int pgfs_ftl_on_mount(void *ctx);
int pgfs_ftl_on_checkpoint_commit(void *ctx);
void pgfs_ftl_on_erase_success(void *ctx, uint32_t block_id);
void pgfs_ftl_on_erase_failure(void *ctx, uint32_t block_id);

/*
 * pgfs_ftl_state_addr — return the byte address of the FTL state region
 * (the erase-unit immediately after the two CP slots). Exposed so the
 * data-log prepare path can skip this region during erase.
 */
uint32_t pgfs_ftl_state_addr(uint32_t erase_size);

#endif /* PGFS_NAND_FTL_H */
