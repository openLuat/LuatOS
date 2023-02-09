#include "luat_base.h"
#include "luat_fskv.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_sfd.h"

#define LUAT_LOG_TAG "fskv"
#include "luat_log.h"

#include "lfs.h"

// TODO 应该对接vfs, 而非直接对接lfs
extern luat_sfd_lfs_t* sfd_lfs;

int luat_fskv_del(const char* key) {
    lfs_remove(&sfd_lfs->lfs, key);
    return 0;
}

int luat_fskv_set(const char* key, void* data, size_t len) {
    lfs_file_t fd = {0};
    int ret = 0;
    ret = lfs_file_open(&sfd_lfs->lfs, &fd, key, LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);
    if (ret != LFS_ERR_OK) {
        return -1;
    }
    ret = lfs_file_write(&sfd_lfs->lfs, &fd, data, len);
    lfs_file_close(&sfd_lfs->lfs, &fd);
    return ret;
}

int luat_fskv_get(const char* key, void* data, size_t len) {
    lfs_file_t fd = {0};
    int ret = 0;
    ret = lfs_file_open(&sfd_lfs->lfs, &fd, key, LFS_O_RDONLY);
    if (ret != LFS_ERR_OK) {
        return 0;
    }
    ret = lfs_file_read(&sfd_lfs->lfs, &fd, data, len);
    lfs_file_close(&sfd_lfs->lfs, &fd);
    return ret > 0 ? ret : 0;
}

int luat_fskv_clear(void) {
    int ret = 0;
    ret = lfs_format(&sfd_lfs->lfs, &sfd_lfs->conf);
    if (ret != LFS_ERR_OK) {
        LLOGE("fskv clear ret %d", ret);
        return ret;
    }
    ret = lfs_mount(&sfd_lfs->lfs, &sfd_lfs->conf);
    if (ret != LFS_ERR_OK) {
        LLOGE("fskv reinit ret %d", ret);
        return ret;
    }
    return 0;
}

int luat_fskv_stat(size_t *using_sz, size_t *total, size_t *kv_count) {
    *using_sz = lfs_fs_size(&sfd_lfs->lfs) * LFS_BLOCK_DEVICE_ERASE_SIZE;
    *total = LFS_BLOCK_DEVICE_TOTOAL_SIZE;
    lfs_dir_t dir = {0};
    int ret = lfs_dir_open(&sfd_lfs->lfs, &dir, "");
    if (ret != LFS_ERR_OK) {
        LLOGW("lfs_dir_open ret %d", ret);
        return -1;
    }
    size_t count = 0;
    struct lfs_info info = {0};
    while (1) {
        ret = lfs_dir_read(&sfd_lfs->lfs, &dir, &info);
        if (ret > 0) {
            if (info.type == LFS_TYPE_REG)
                count ++;
        }
        else
            break;
    }
    lfs_dir_close(&sfd_lfs->lfs, &dir);
    *kv_count = count;
    return 0;
}

int luat_fskv_size(const char* key, char buff[4]) {
    lfs_file_t fd = {0};
    int ret = 0;
    ret = lfs_file_open(&sfd_lfs->lfs, &fd, key, LFS_O_RDONLY);
    if (ret != LFS_ERR_OK) {
        return 0;
    }
    ret = lfs_file_size(&sfd_lfs->lfs, &fd);
    if (ret > 1 && ret < 256) {
        int ret2 = lfs_file_read(&sfd_lfs->lfs, &fd, buff, ret);
        if (ret2 != ret) {
            ret = -2; // 读取失败,肯定有问题
        }
    }
    lfs_file_close(&sfd_lfs->lfs, &fd);
    return ret;
}

int luat_fskv_next(char* buff, size_t offset) {
    lfs_dir_t dir = {0};
    struct lfs_info info = {0};
    // offset要+2, 因为前2个值是"."和".."两个dir
    offset += 2;
    int ret = lfs_dir_open(&sfd_lfs->lfs, &dir, "");
    if (ret < 0) {
        LLOGW("lfs_dir_open ret %d", ret);
        return -1;
    }
    ret = lfs_dir_seek(&sfd_lfs->lfs, &dir, offset);
    if (ret < 0) {
        lfs_dir_close(&sfd_lfs->lfs, &dir);
        return -2;
    }
    ret = lfs_dir_read(&sfd_lfs->lfs, &dir, &info);
    if (ret <= 0) {
        lfs_dir_close(&sfd_lfs->lfs, &dir);
        return -3;
    }
    memcpy(buff, info.name, strlen(info.name) + 1);
    lfs_dir_close(&sfd_lfs->lfs, &dir);
    return 0;
}
