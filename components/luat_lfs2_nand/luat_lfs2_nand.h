#ifndef LUAT_LFS2_NAND_H
#define LUAT_LFS2_NAND_H

#include <stddef.h>

// lfs2_nand write-cache knobs (compile-time tunable, hard-capped at 128KB per file stream).
#ifndef LUAT_LFS2N_CACHE_POOL_BUDGET
#define LUAT_LFS2N_CACHE_POOL_BUDGET (128u * 1024u)
#endif

#ifndef LUAT_LFS2N_CACHE_POOL_SLOTS
#define LUAT_LFS2N_CACHE_POOL_SLOTS 8u
#endif

#ifndef LUAT_LFS2N_CACHE_POOL_CHUNK
#define LUAT_LFS2N_CACHE_POOL_CHUNK 4096u
#endif

#ifndef LUAT_LFS2N_FILE_CACHE_LIMIT
#define LUAT_LFS2N_FILE_CACHE_LIMIT (96u * 1024u)
#endif

void luat_lfs2_nand_vfs_init(void);
void* luat_fs_lfs2_nand_default_bus(void* flash, size_t offset, size_t maxsize);
size_t luat_lfs2_nand_set_file_cache_limit(size_t bytes);
size_t luat_lfs2_nand_get_file_cache_limit(void);

#endif
