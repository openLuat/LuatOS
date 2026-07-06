#ifndef LUAT_LITTLE_FLASH_TFS_H
#define LUAT_LITTLE_FLASH_TFS_H

#include <stdint.h>
#include "little_flash.h"

#ifdef __cplusplus
extern "C" {
#endif

#define LF_TFS_BAD_MAX_BLOCKS 256U

typedef struct {
    little_flash_t *flash;
    uint32_t        offset;
    uint32_t        maxsize;
    char            dev_name[16];
    int             is_mounted;
    int             is_nand;
    int             use_hw_oob;
    int             hw_oob_selftest_done;
    uint8_t        *oob_ram;
    uint32_t        oob_per_chunk;
    uint32_t        total_chunks;
    uint32_t        marker_addr;
    uint32_t        read_error_count;
    uint32_t        read_ecc_corrected_count;
    uint32_t        read_ecc_refresh_count;
    uint32_t        anchor_log_count;
    uint32_t        write_verify_error_count;
    uint32_t        bad_blocks[LF_TFS_BAD_MAX_BLOCKS];
    uint32_t        bad_block_count;
#ifdef LUAT_USE_TFS_STRESS_DIAG
    uint32_t        last_mount_ms;
    uint32_t        last_mount_delta_chunks;
    uint8_t         last_mount_path;
#endif
} luat_lf_tfs_ctx_t;

#ifdef __cplusplus
}
#endif

#endif
