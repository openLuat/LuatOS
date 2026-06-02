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
#ifndef PGFS_CHECKPOINT_B_ADDR
#define PGFS_CHECKPOINT_B_ADDR  0x3000u
#endif

#include <stdbool.h>
#include <stdint.h>
/* <string.h> only needed by the .c implementation — not needed in the header */

/* ── FTL metadata on-flash format ─────────────────────────────────────── */

#define PGFS_FTL_MAGIC   0x5046544Cu   /* 'PFTL' */
#define PGFS_FTL_VERSION 1u

/* Bitmap helpers: 1 bit per block, block N bad iff (bitmap[N/8] & (1 << (N%8))) */
#define PGFS_FTL_BITMAP_BYTES(BLOCKS)  (((BLOCKS) + 7u) / 8u)

typedef struct pgfs_ftl_meta {
    uint32_t magic;
    uint16_t version;
    uint16_t total_blocks;   /* matches geo from control() */
    uint32_t bitmap_bytes;   /* bytes following this header = PGFS_FTL_BITMAP_BYTES(total_blocks) */
    uint32_t erase_count_bytes; /* bytes following bitmap = total_blocks * sizeof(uint16_t) */
    uint32_t crc32;          /* CRC over [meta + bitmap + erase_counts] with this field = 0 */
} pgfs_ftl_meta_t;

/* ── FTL runtime context ───────────────────────────────────────────────── */

typedef struct {
    /* geometry (read from flash backend at init) */
    uint32_t total_blocks;
    uint32_t erase_size;

    /* bad-block bitmap: 1=bad, 0=good; indexed by block_id */
    uint8_t *bad_blocks_bitmap;      /* heap-allocated, (total_blocks+7)/8 bytes */
    uint32_t bad_block_count;

    /* per-block erase counts: erase_counts[block_id] */
    uint16_t *erase_counts;          /* heap-allocated, total_blocks entries */
    uint32_t total_erase_count;     /* sum of all entries, for diagnostics */

    /* flash backend */
    const pgfs_flash_opts_t *flash_opts;

    /* bad block injection (testing) */
    uint8_t inject_bad_block_once;
    uint8_t inject_bad_block_flag;    /* 0=not-injected, 1=injected-this-session */
    uint32_t inject_bad_block_id;
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
 *   ctx        : FTL context
 *   cp_seq     : checkpoint sequence number (for logging/debug)
 * Returns 0 on success, -1 on error.
 *
 * Layout written (one erase-unit starting at PGFS_FTL_STATE_ADDR):
 *   [pgfs_ftl_meta_t] [bad_blocks_bitmap] [erase_counts[]]
 *
 * PGFS_FTL_STATE_ADDR is computed as the next erase-unit after the
 * two CP slots (PGFS_CHECKPOINT_B_ADDR + erase_size).
 */
int pgfs_ftl_persist(const pgfs_nand_ftl_ctx_t *ctx, uint32_t cp_seq);

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

#endif /* PGFS_NAND_FTL_H */
