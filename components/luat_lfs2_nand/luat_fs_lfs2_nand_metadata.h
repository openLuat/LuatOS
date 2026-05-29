#ifndef LUAT_FS_LFS2_NAND_METADATA_H
#define LUAT_FS_LFS2_NAND_METADATA_H

#include <stddef.h>
#include <stdint.h>

#define LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT 2u
#define LUAT_LFS2_NAND_SPACE_META_REFRESH_STEP_BUDGET_US_DEFAULT 1500u
#define LUAT_LFS2_NAND_SPACE_META_REFRESH_RETRY_DEFAULT 4u

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t seq;
    uint32_t used;
    uint32_t total;
    uint32_t free;
    uint32_t crc;
} luat_lfs2_nand_space_meta_t;

typedef int (*luat_lfs2_nand_space_meta_read_slot_t)(void* ctx, uint32_t slot, luat_lfs2_nand_space_meta_t* out);
typedef int (*luat_lfs2_nand_space_meta_write_slot_t)(void* ctx, uint32_t slot, const luat_lfs2_nand_space_meta_t* meta);
typedef int (*luat_lfs2_nand_space_meta_scan_t)(void* ctx, uint32_t* used, uint32_t* total);
typedef void (*luat_lfs2_nand_space_meta_log_t)(void* ctx, const char* message);
typedef void (*luat_lfs2_nand_space_meta_scan_mark_t)(void* ctx,
                                                       const char* stage,
                                                       uint32_t attempt,
                                                       uint32_t step_loop,
                                                       uint32_t retry_advance_count);

typedef struct {
    void* ctx;
    luat_lfs2_nand_space_meta_read_slot_t read_slot;
    luat_lfs2_nand_space_meta_write_slot_t write_slot;
    luat_lfs2_nand_space_meta_scan_t scan;
    luat_lfs2_nand_space_meta_log_t log;
    luat_lfs2_nand_space_meta_scan_mark_t scan_mark;
} luat_lfs2_nand_space_meta_ops_t;

typedef enum {
    LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_BOOTSTRAP = 0,
    LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_SCAN,
    LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_WRITE,
    LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_VERIFY_SCAN,
    LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_RETRY_ADVANCE,
    LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_DONE,
    LUAT_LFS2_NAND_SPACE_META_REFRESH_STAGE_FAILED
} luat_lfs2_nand_space_meta_refresh_stage_t;

typedef enum {
    LUAT_LFS2_NAND_SPACE_META_STEP_ERROR = -1,
    LUAT_LFS2_NAND_SPACE_META_STEP_DONE = 0,
    LUAT_LFS2_NAND_SPACE_META_STEP_MORE = 1
} luat_lfs2_nand_space_meta_step_result_t;

typedef struct {
    uint32_t budget_us;
    uint32_t max_steps;
} luat_lfs2_nand_space_meta_step_budget_t;

typedef struct {
    luat_lfs2_nand_space_meta_refresh_stage_t stage;
    luat_lfs2_nand_space_meta_t previous;
    uint8_t has_previous;
    uint32_t previous_slot;
    uint32_t seq;
    uint32_t target_slot;
    uint32_t attempt;
    uint32_t max_retry;
    uint32_t used;
    uint32_t total;
    luat_lfs2_nand_space_meta_t candidate;
    uint8_t candidate_valid;
    uint32_t step_loops;
    uint32_t scan_calls;
    uint32_t verify_scan_calls;
    uint32_t write_calls;
    uint32_t retry_advance_count;
    uint32_t verify_mismatch_count;
    uint64_t scan_total_us;
    uint32_t scan_max_us;
    uint64_t verify_scan_total_us;
    uint32_t verify_scan_max_us;
    uint64_t write_total_us;
    uint32_t write_max_us;
} luat_lfs2_nand_space_meta_refresh_state_t;

typedef struct {
    luat_lfs2_nand_space_meta_refresh_stage_t stage;
    uint32_t attempt;
    uint32_t target_slot;
    uint32_t used;
    uint32_t total;
} luat_lfs2_nand_space_meta_refresh_marker_t;

void luat_lfs2_nand_space_meta_init(luat_lfs2_nand_space_meta_t* meta, uint32_t seq, uint32_t used, uint32_t total);
int luat_lfs2_nand_space_meta_validate(const luat_lfs2_nand_space_meta_t* meta);
int luat_lfs2_nand_space_meta_select_latest(const luat_lfs2_nand_space_meta_t* slots, uint32_t slot_count, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot);
int luat_lfs2_nand_space_meta_load_or_rebuild(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot, uint8_t* rebuilt);
int luat_lfs2_nand_space_meta_load_prefer_fast(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint8_t* rebuilt, uint8_t* persisted);
int luat_lfs2_nand_space_meta_refresh(const luat_lfs2_nand_space_meta_ops_t* ops, const luat_lfs2_nand_space_meta_t* previous, uint32_t previous_slot, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot);
void luat_lfs2_nand_space_meta_refresh_state_init(luat_lfs2_nand_space_meta_refresh_state_t* state,
                                                  const luat_lfs2_nand_space_meta_t* previous,
                                                  uint32_t previous_slot,
                                                  uint32_t max_retry);
void luat_lfs2_nand_space_meta_refresh_marker_from_state(const luat_lfs2_nand_space_meta_refresh_state_t* state,
                                                         luat_lfs2_nand_space_meta_refresh_marker_t* marker);
luat_lfs2_nand_space_meta_step_result_t luat_lfs2_nand_space_meta_refresh_step(const luat_lfs2_nand_space_meta_ops_t* ops,
                                                                                luat_lfs2_nand_space_meta_refresh_state_t* state,
                                                                                const luat_lfs2_nand_space_meta_step_budget_t* budget,
                                                                                luat_lfs2_nand_space_meta_t* out,
                                                                                uint32_t* out_slot);

#endif
