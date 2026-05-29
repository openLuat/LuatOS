
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_spi.h"
#include "luat_mem.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "vfs.lfs2_nand_core"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS

// #ifdef LUAT_VFS_USE_LFS2

#include "luat_lfs2.h"

#ifndef LUAT_LFS2N_CORE_TRACE_LOG
#define LUAT_LFS2N_CORE_TRACE_LOG 0
#endif

#define LFS2N_CORE_TRACE(...) do { if (LUAT_LFS2N_CORE_TRACE_LOG) { LLOGD(__VA_ARGS__); } } while (0)

#define LFS2_TRACE_SLOW_US (5000u)

static uint64_t luat_vfs_lfs2_nand_base_now_us(void) {
    uint64_t tick = luat_mcu_tick64();
    uint32_t tick_per_us = luat_mcu_us_period();
    if (tick_per_us == 0) {
        tick_per_us = 1;
    }
    return tick / tick_per_us;
}

FILE* luat_vfs_lfs2_nand_base_fopen(void* userdata, const char *filename, const char *mode) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t *file = (luat_lfs2_file_t*)luat_heap_malloc(sizeof(luat_lfs2_file_t));
    if (file == NULL) {
        LLOGD("out of memory when open file %s", filename);
        return NULL;
    }
    memset(file, 0, sizeof(luat_lfs2_file_t));
    int flag = 0;
/*
"r": 读模式（默认）；
"w": 写模式；
"a": 追加模式；
"r+": 更新模式，所有之前的数据都保留；
"w+": 更新模式，所有之前的数据都删除；
"a+": 追加更新模式，所有之前的数据都保留，只允许在文件尾部做写入。
*/
    if (!strcmp("r+", mode) || !strcmp("r+b", mode) || !strcmp("rb+", mode)) {
        flag = LFS_O_RDWR | LFS_O_CREAT;
    }
    else if(!strcmp("w+", mode) || !strcmp("w+b", mode) || !strcmp("wb+", mode)) {
        flag = LFS_O_RDWR | LFS_O_CREAT | LFS_O_TRUNC;
    }
    else if(!strcmp("a+", mode) || !strcmp("a+b", mode) || !strcmp("ab+", mode)) {
        flag = LFS_O_APPEND | LFS_O_CREAT | LFS_O_WRONLY;
    }
    else if(!strcmp("w", mode) || !strcmp("wb", mode)) {
        flag = LFS_O_RDWR | LFS_O_CREAT | LFS_O_TRUNC;
    }
    else if(!strcmp("r", mode) || !strcmp("rb", mode)) {
        flag = LFS_O_RDONLY;
    }
    else if(!strcmp("a", mode) || !strcmp("ab", mode)) {
        flag = LFS_O_APPEND | LFS_O_CREAT | LFS_O_WRONLY;
    }
    else {
        LLOGW("bad file open mode %s, fallback to 'r'", mode);
        flag = LFS_O_RDONLY;
    }
    int ret = luat_lfs2_file_open(fs, file, filename, flag);
    if (ret < 0) {
        luat_heap_free(file);
        return 0;
    }
    return (FILE*)file;
}

int luat_vfs_lfs2_nand_base_getc(void* userdata, FILE* stream) {
    //LLOGD("posix_getc %p", stream);
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    char buff = 0;
    int ret = luat_lfs2_file_read(fs, file, &buff, 1);
    if (ret != 1)
        return -1;
    return (int)buff;
}

int luat_vfs_lfs2_nand_base_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    int ret = luat_lfs2_file_seek(fs, file, offset, origin);
    return ret < 0 ? -1 : 0;
}

int luat_vfs_lfs2_nand_base_ftell(void* userdata, FILE* stream) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    int ret = luat_lfs2_file_tell(fs, file);
    return ret < 0 ? -1 : ret;
}

int luat_vfs_lfs2_nand_base_fclose(void* userdata, FILE* stream) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    uint64_t start_us = luat_vfs_lfs2_nand_base_now_us();
    int ret = luat_lfs2_file_close(fs, file);
    uint64_t cost_us = luat_vfs_lfs2_nand_base_now_us() - start_us;
    if (cost_us >= LFS2_TRACE_SLOW_US || ret < 0) {
        LFS2N_CORE_TRACE("LFS2_TRACE_FCLOSE ret=%d cost_us=%llu", ret, (unsigned long long)cost_us);
    }
    if (file != NULL)
        luat_heap_free(file);
    return ret < 0 ? -1 : 0;
}

int luat_vfs_lfs2_nand_base_feof(void* userdata, FILE* stream) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    if (luat_lfs2_file_size(fs, file) <= luat_lfs2_file_tell(fs, file))
        return 1;
    return 0;
}

int luat_vfs_lfs2_nand_base_ferror(void* userdata, FILE *stream) {
    return 0;
}

size_t luat_vfs_lfs2_nand_base_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    int ret = luat_lfs2_file_read(fs, file, ptr, size*nmemb);
    return ret < 0 ? 0 : ret;
}

size_t luat_vfs_lfs2_nand_base_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    size_t total = size * nmemb;
    uint64_t start_us = 0;
    uint64_t cost_us = 0;
    int ret = 0;
    if ((file->flags & LFS_O_WRONLY) != LFS_O_WRONLY && (file->flags & LFS_O_APPEND) != LFS_O_APPEND) {
        LLOGE("open file at readonly mode, reject for write flags=%08X", file->flags);
        return 0;
    }
    start_us = luat_vfs_lfs2_nand_base_now_us();
    ret = luat_lfs2_file_write(fs, file, ptr, total);
    cost_us = luat_vfs_lfs2_nand_base_now_us() - start_us;
    if (cost_us >= LFS2_TRACE_SLOW_US || ret < 0) {
        LFS2N_CORE_TRACE("LFS2_TRACE_FWRITE req=%u ret=%d flags=0x%08X cost_us=%llu",
                         (unsigned int)total, ret, file->flags, (unsigned long long)cost_us);
    }
    return ret < 0 ? 0 : ret;
}

int luat_vfs_lfs2_nand_base_fflush(void* userdata, FILE *stream) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    uint64_t start_us = luat_vfs_lfs2_nand_base_now_us();
    int ret = luat_lfs2_file_sync(fs, file);
    uint64_t cost_us = luat_vfs_lfs2_nand_base_now_us() - start_us;
    if (cost_us >= LFS2_TRACE_SLOW_US || ret < 0) {
        LFS2N_CORE_TRACE("LFS2_TRACE_FFLUSH ret=%d flags=0x%08X cost_us=%llu",
                         ret, file->flags, (unsigned long long)cost_us);
    }
    return ret < 0 ? 0 : ret;
}

int luat_vfs_lfs2_nand_base_remove(void* userdata, const char *filename) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    return luat_lfs2_remove(fs, filename);
}

int luat_vfs_lfs2_nand_base_rename(void* userdata, const char *old_filename, const char *new_filename) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    return luat_lfs2_rename(fs, old_filename, new_filename);
}

int luat_vfs_lfs2_nand_base_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_lfs2_nand_base_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_lfs2_nand_base_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_lfs2_nand_base_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_lfs2_nand_base_fopen(userdata, filename, "rb");
    if (fd) {
        size = luat_lfs2_file_size((luat_lfs2_t*)userdata, (luat_lfs2_file_t*)fd);
        luat_vfs_lfs2_nand_base_fclose(userdata, fd);
    }
    return size;
}

int luat_vfs_lfs2_nand_base_mkfs(void* userdata, luat_fs_conf_t *conf) {
    int ret = 0;
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    if (fs != NULL && fs->cfg != NULL) {
        ret = luat_lfs2_format(fs, fs->cfg);
        // LLOGD("lfs2 format ret %d", ret);
        if (ret < 0)
            return ret;
        ret = luat_lfs2_mount(fs, fs->cfg);
        // LLOGD("lfs2 mount ret %d", ret);
        return ret;
    }
    return -1;
}

int luat_vfs_lfs2_nand_base_mount(void** userdata, luat_fs_conf_t *conf) {
    *userdata = (void*)conf->busname;
    return 0;
}

int luat_vfs_lfs2_nand_base_umount(void* userdata, luat_fs_conf_t *conf) {
    LLOGE("not support yet : umount");
    return 0;
}

static int dir2name(char* buff, char const* _DirName) {
    size_t dirlen = strlen(_DirName);
    if (dirlen > 63) {
        LLOGE("dir too long!! %s", _DirName);
        return -1;
    }
    else if (dirlen < 1) {
        LLOGE("dir too short!! %s", _DirName);
        return -1;
    }
    memcpy(buff, _DirName, dirlen);
    if (buff[dirlen -1] == '/') {
        buff[dirlen -1] = 0;
    }
    return 0;
}

int luat_vfs_lfs2_nand_base_mkdir(void* userdata, char const* _DirName) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    char buff[64] = {0};
    if (_DirName == NULL) {
        return -1;
    }
    if (_DirName[0] == 0) {
        return 0;
    }
    if (dir2name(buff, _DirName)) {
        return -1;
    }
    if (buff[0] == 0) {
        return 0;
    }
    int ret = luat_lfs2_mkdir(fs, buff);
    return ret == LFS_ERR_OK ? 0 : -1;
}

int luat_vfs_lfs2_nand_base_rmdir(void* userdata, char const* _DirName) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;

    char buff[64] = {0};
    if (dir2name(buff, _DirName)) {
        return -1;
    }
    int ret = luat_lfs2_remove(fs, buff);
    return ret == LFS_ERR_OK ? 0 : -1;
}

int luat_vfs_lfs2_nand_base_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    int ret , num = 0;
    luat_lfs2_dir_t *dir;
    struct luat_lfs2_info info;
    char buff[64] = {0};
    if (strlen(_DirName) == 0) {
        // OK的, 根目录嘛
    }
    else if (dir2name(buff, _DirName)) {
        return -1;
    }
    // if (fs->filecount > offset) {
        // if (offset + len > fs->filecount)
            // len = fs->filecount - offset;
        dir = luat_heap_malloc(sizeof(luat_lfs2_dir_t));
        if (dir == NULL) {
            // LLOGE("out of memory when lsdir");
            return 0;
        }
        ret = luat_lfs2_dir_open(fs, dir, buff);
        if (ret < 0) {
            luat_heap_free(dir);
            // LLOGE("no such dir %s _DirName");
            return 0;
        }

        // TODO 使用seek/tell组合更快更省
        for (size_t i = 0; i < offset; i++)
        {
            ret = luat_lfs2_dir_read(fs, dir, &info);
            if (ret <= 0) {
                luat_lfs2_dir_close(fs, dir);
                luat_heap_free(dir);
                return 0;
            }
        }

        while (num < len)
        {
            ret = luat_lfs2_dir_read(fs, dir, &info);
            if (ret < 0) {
                luat_lfs2_dir_close(fs, dir);
                luat_heap_free(dir);
                return 0;
            }
            if (ret == 0) {
                break;
            }
            if (info.type == 2 && (memcmp(info.name, ".", 2) ==0 ||memcmp(info.name, "..", 3)==0))
                continue;
            ents[num].d_type = info.type - 1; // lfs file =1, dir=2
            strcpy(ents[num].d_name, info.name);
            num++;
        }
        luat_lfs2_dir_close(fs, dir);
        luat_heap_free(dir);
        return num;
    // }
    return 0;
}

int luat_vfs_lfs2_nand_base_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    //LLOGD("why ? luat_vfs_lfs2_nand_base_info %p", userdata);
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    memcpy(conf->filesystem, "lfs", strlen("lfs")+1);
    conf->type = 0;
    conf->total_block = fs->cfg->block_count;
    conf->block_used = luat_lfs2_fs_size(fs);
    conf->block_size = fs->cfg->block_size;
    //LLOGD("total %d used %d size %d", conf->total_block, conf->block_used, conf->block_size);
    return 0;
}

int luat_vfs_lfs2_nand_base_truncate(void* userdata, const char *filename, size_t len) {
    FILE *fd;
    int ret = -1;
    fd = luat_vfs_lfs2_nand_base_fopen(userdata, filename, "wb");
    if (fd) {
        ret = luat_lfs2_file_truncate((luat_lfs2_t*)userdata, (luat_lfs2_file_t*)fd ,(luat_lfs2_off_t)len);
        luat_vfs_lfs2_nand_base_fclose(userdata, fd);
    }
    return ret;
}

void* luat_vfs_lfs2_nand_base_opendir(void* userdata, const char *_DirName) {
    luat_lfs2_dir_t *dir = (luat_lfs2_dir_t*)luat_heap_malloc(sizeof(luat_lfs2_dir_t));
    if (dir == NULL) {
        LLOGD("out of memory when open file %s", dir);
        return NULL;
    }
    memset(dir, 0, sizeof(luat_lfs2_dir_t));
    int ret = luat_lfs2_dir_open((luat_lfs2_t*)userdata, dir, _DirName);
    if (ret < 0) {
        luat_heap_free(dir);
        return NULL;
    }
    return (void*)dir;
}

int luat_vfs_lfs2_nand_base_closedir(void* userdata, void* dir) {
    luat_lfs2_dir_close((luat_lfs2_t*)userdata, (luat_lfs2_dir_t *)dir);
    if (dir)luat_heap_free(dir);
    return 0;
}

#define T(name) .name = luat_vfs_lfs2_nand_base_##name

static const struct luat_vfs_filesystem vfs_fs_lfs2_nand_base = {
    .name = "lfs2",
    .opts = {
        T(mkfs),
        T(mount),
        T(umount),
        T(mkdir),
        T(rmdir),
        T(lsdir),
        T(remove),
        T(rename),
        T(fsize),
        T(fexist),
        T(info),
        T(truncate),
        T(opendir),
        T(closedir)
    },
    .fopts = {
        T(fopen),
        T(getc),
        T(fseek),
        T(ftell),
        T(fclose),
        T(feof),
        T(ferror),
        T(fread),
        T(fwrite),
        T(fflush)
    }
};

// #endif

#endif
