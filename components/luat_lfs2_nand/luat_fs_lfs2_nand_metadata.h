#ifndef LUAT_FS_LFS2_NAND_METADATA_H
#define LUAT_FS_LFS2_NAND_METADATA_H

#include <stddef.h>
#include <stdint.h>

#define LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT 2u

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

typedef struct {
    void* ctx;
    luat_lfs2_nand_space_meta_read_slot_t read_slot;
    luat_lfs2_nand_space_meta_write_slot_t write_slot;
    luat_lfs2_nand_space_meta_scan_t scan;
    luat_lfs2_nand_space_meta_log_t log;
} luat_lfs2_nand_space_meta_ops_t;

void luat_lfs2_nand_space_meta_init(luat_lfs2_nand_space_meta_t* meta, uint32_t seq, uint32_t used, uint32_t total);
int luat_lfs2_nand_space_meta_validate(const luat_lfs2_nand_space_meta_t* meta);
int luat_lfs2_nand_space_meta_select_latest(const luat_lfs2_nand_space_meta_t* slots, uint32_t slot_count, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot);
int luat_lfs2_nand_space_meta_load_or_rebuild(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot, uint8_t* rebuilt);
int luat_lfs2_nand_space_meta_load_prefer_fast(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint8_t* rebuilt, uint8_t* persisted);
int luat_lfs2_nand_space_meta_refresh(const luat_lfs2_nand_space_meta_ops_t* ops, const luat_lfs2_nand_space_meta_t* previous, uint32_t previous_slot, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot);

#endif
