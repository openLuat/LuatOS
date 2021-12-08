
#include "luat_base.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "fs.LFS"
#include "luat_log.h"

#include "rtthread.h"
#include <dfs_fs.h>

#ifdef LUAT_USE_FS_VFS

#else

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
        LLOGW("dfs_statfs return != 0");
    }
    return -1;
}

// int luat_fs_mkdir(char const* _DirName) {
//     return mkdir(_DirName, 0);
// }
// int luat_fs_rmdir(char const* _DirName) {
//     return rmdir(_DirName);
// }

int luat_fs_mount(luat_fs_conf_t *conf) {
    // SPI Flash, 需要SFUD支持
    #ifdef RT_USING_SFUD
    if (!rt_strcmp(conf->type, "flash")) {
        if (rt_sfud_flash_probe("w25q", conf->busname) == RT_NULL) {
            if (!dfs_mount("w25q", conf->mount_point, conf->filesystem, 0, 0)) {
                LLOGD("flash mount success");
                return 0;
            }
            else {
                LLOGD("flash mount fail");
                return -1;
            }
        }
        else {
            LLOGD("flash probe fail");
            return -1;
        }
    }
    #endif

    // SDCard系列
    #if defined(RT_USING_SPI_MSD)
    if (!rt_strcmp(conf->type, "sd")) {
        if (msd_init("sd0", conf->busname) == RT_NULL) {
            if (!dfs_mount("sd0", conf->mount_point, conf->filesystem, 0, 0)) {
                LLOGD("sdcard mount success");
                return 0;
            }
            else {
                LLOGD("sdcard mount fail");
                return -1;
            }
        }
        else {
            LLOGD("sdcard init fail");
            return -1;
        }
    }
    #endif

    LLOGD("not support type: %s", conf->type);
    return -1;
}

#endif
