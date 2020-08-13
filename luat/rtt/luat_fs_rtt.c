
#include "luat_base.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "luat.fs.LFS"
#include "luat_log.h"

#include "rtthread.h"
#include <dfs_fs.h>


int luat_fs_info(const char* path, luat_fs_info_t *conf) {
    struct statfs buff;
    if (!dfs_statfs(path, &buff)) {
        conf->total_block = buff.f_blocks;
        conf->block_used = buff.f_blocks - buff.f_bfree;
        conf->block_size = buff.f_bsize;
        conf->type = 0; // 位置
        memcpy(conf->filesystem, "dfs", 3);
        conf->filesystem[4] = 0;
        return 0;
    }
    else {
        LLOGW("LFS_Statfs return != 0");
    }
    return -1;
}
