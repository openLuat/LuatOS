
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_spi.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "vfs.lfs2"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS

// #ifdef LUAT_VFS_USE_LFS2

#include "lfs.h"

FILE* luat_vfs_lfs2_fopen(void* userdata, const char *filename, const char *mode) {
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t *file = (lfs_file_t*)luat_heap_malloc(sizeof(lfs_file_t));
    if (file == NULL) {
        LLOGD("out of memory when open file %s", filename);
        return NULL;
    }
    memset(file, 0, sizeof(lfs_file_t));
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
    int ret = lfs_file_open(fs, file, filename, flag);
    if (ret < 0) {
        luat_heap_free(file);
        return 0;
    }
    return (FILE*)file;
}

int luat_vfs_lfs2_getc(void* userdata, FILE* stream) {
    //LLOGD("posix_getc %p", stream);
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t* file = (lfs_file_t*)stream;
    char buff = 0;
    int ret = lfs_file_read(fs, file, &buff, 1);
    if (ret != 1)
        return -1;
    return (int)buff;
}

int luat_vfs_lfs2_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t* file = (lfs_file_t*)stream;
    int ret = lfs_file_seek(fs, file, offset, origin);
    return ret < 0 ? -1 : 0;
}

int luat_vfs_lfs2_ftell(void* userdata, FILE* stream) {
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t* file = (lfs_file_t*)stream;
    int ret = lfs_file_tell(fs, file);
    return ret < 0 ? -1 : ret;
}

int luat_vfs_lfs2_fclose(void* userdata, FILE* stream) {
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t* file = (lfs_file_t*)stream;
    lfs_file_close(fs, file);
    if (file != NULL)
        luat_heap_free(file);
    return 0;
}

int luat_vfs_lfs2_feof(void* userdata, FILE* stream) {
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t* file = (lfs_file_t*)stream;
    if (lfs_file_size(fs, file) <= lfs_file_tell(fs, file))
        return 1;
    return 0;
}

int luat_vfs_lfs2_ferror(void* userdata, FILE *stream) {
    return 0;
}

size_t luat_vfs_lfs2_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t* file = (lfs_file_t*)stream;
    int ret = lfs_file_read(fs, file, ptr, size*nmemb);
    return ret < 0 ? 0 : ret;
}

size_t luat_vfs_lfs2_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t* file = (lfs_file_t*)stream;
    if ((file->flags & LFS_O_WRONLY) != LFS_O_WRONLY && (file->flags & LFS_O_APPEND) != LFS_O_APPEND) {
        LLOGE("open file at readonly mode, reject for write flags=%08X", file->flags);
        return 0;
    }
    int ret = lfs_file_write(fs, file, ptr, size*nmemb);
    return ret < 0 ? 0 : ret;
}

int luat_vfs_lfs2_fflush(void* userdata, FILE *stream) {
    lfs_t* fs = (lfs_t*)userdata;
    lfs_file_t* file = (lfs_file_t*)stream;
    int ret = lfs_file_sync(fs, file);
    return ret < 0 ? 0 : ret;
}

int luat_vfs_lfs2_remove(void* userdata, const char *filename) {
    lfs_t* fs = (lfs_t*)userdata;
    return lfs_remove(fs, filename);
}

int luat_vfs_lfs2_rename(void* userdata, const char *old_filename, const char *new_filename) {
    lfs_t* fs = (lfs_t*)userdata;
    return lfs_rename(fs, old_filename, new_filename);
}

int luat_vfs_lfs2_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_lfs2_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_lfs2_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_lfs2_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_lfs2_fopen(userdata, filename, "rb");
    if (fd) {
        size = lfs_file_size((lfs_t*)userdata, (lfs_file_t*)fd);
        luat_vfs_lfs2_fclose(userdata, fd);
    }
    return size;
}

int luat_vfs_lfs2_mkfs(void* userdata, luat_fs_conf_t *conf) {
    int ret = 0;
    lfs_t* fs = (lfs_t*)userdata;
    if (fs != NULL && fs->cfg != NULL) {
        ret = lfs_format(fs, fs->cfg);
        // LLOGD("lfs2 format ret %d", ret);
        if (ret < 0)
            return ret;
        ret = lfs_mount(fs, fs->cfg);
        // LLOGD("lfs2 mount ret %d", ret);
        return ret;
    }
    return -1;
}

int luat_vfs_lfs2_mount(void** userdata, luat_fs_conf_t *conf) {
    *userdata = (void*)conf->busname;
    return 0;
}

int luat_vfs_lfs2_umount(void* userdata, luat_fs_conf_t *conf) {
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

int luat_vfs_lfs2_mkdir(void* userdata, char const* _DirName) {
    lfs_t* fs = (lfs_t*)userdata;
    char buff[64] = {0};
    if (dir2name(buff, _DirName)) {
        return -1;
    }
    int ret = lfs_mkdir(fs, buff);
    return ret == LFS_ERR_OK ? 0 : -1;
}

int luat_vfs_lfs2_rmdir(void* userdata, char const* _DirName) {
    lfs_t* fs = (lfs_t*)userdata;

    char buff[64] = {0};
    if (dir2name(buff, _DirName)) {
        return -1;
    }
    int ret = lfs_remove(fs, buff);
    return ret == LFS_ERR_OK ? 0 : -1;
}

int luat_vfs_lfs2_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    lfs_t* fs = (lfs_t*)userdata;
    int ret , num = 0;
    lfs_dir_t *dir;
    struct lfs_info info;
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
        dir = luat_heap_malloc(sizeof(lfs_dir_t));
        if (dir == NULL) {
            // LLOGE("out of memory when lsdir");
            return 0;
        }
        ret = lfs_dir_open(fs, dir, buff);
        if (ret < 0) {
            luat_heap_free(dir);
            // LLOGE("no such dir %s _DirName");
            return 0;
        }

        // TODO 使用seek/tell组合更快更省
        for (size_t i = 0; i < offset; i++)
        {
            ret = lfs_dir_read(fs, dir, &info);
            if (ret <= 0) {
                lfs_dir_close(fs, dir);
                luat_heap_free(dir);
                return 0;
            }
        }

        while (num < len)
        {
            ret = lfs_dir_read(fs, dir, &info);
            if (ret < 0) {
                lfs_dir_close(fs, dir);
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
        lfs_dir_close(fs, dir);
        luat_heap_free(dir);
        return num;
    // }
    return 0;
}

int luat_vfs_lfs2_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    //LLOGD("why ? luat_vfs_lfs2_info %p", userdata);
    lfs_t* fs = (lfs_t*)userdata;
    memcpy(conf->filesystem, "lfs", strlen("lfs")+1);
    conf->type = 0;
    conf->total_block = fs->cfg->block_count;
    conf->block_used = lfs_fs_size(fs);
    conf->block_size = fs->cfg->block_size;
    //LLOGD("total %d used %d size %d", conf->total_block, conf->block_used, conf->block_size);
    return 0;
}

int luat_vfs_lfs2_truncate(void* userdata, const char *filename, size_t len) {
    FILE *fd;
    int ret = -1;
    fd = luat_vfs_lfs2_fopen(userdata, filename, "wb");
    if (fd) {
        ret = lfs_file_truncate((lfs_t*)userdata, (lfs_file_t*)fd ,(lfs_off_t)len);
        luat_vfs_lfs2_fclose(userdata, fd);
    }
    return ret;
}

#define T(name) .name = luat_vfs_lfs2_##name

const struct luat_vfs_filesystem vfs_fs_lfs2 = {
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
        T(truncate)
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

