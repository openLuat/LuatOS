#ifndef LUAT_LFS2_NAND_H
#define LUAT_LFS2_NAND_H

#include <stddef.h>

void luat_lfs2_nand_vfs_init(void);
void* luat_fs_lfs2_nand_default_bus(void* flash, size_t offset, size_t maxsize);

#endif
