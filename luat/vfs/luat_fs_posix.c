
#include "luat_base.h"
#include "luat_fs.h"
#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

#define TAG "luat.fs"

#ifdef LUA_USE_VFS_FILENAME_OFFSET
#define FILENAME_OFFSET (filename[0] == '/' ? 1 : 0)
#else
#define FILENAME_OFFSET 0
#endif


// fs的默认实现, 指向poisx的stdio.h声明的方法
#ifndef LUAT_USE_FS_VFS

FILE* luat_fs_fopen(const char *filename, const char *mode) {
    //LLOGD("fopen %s %s", filename + FILENAME_OFFSET, mode);
    return fopen(filename + FILENAME_OFFSET, mode);
}

int luat_fs_getc(FILE* stream) {
    //LLOGD("posix_getc %p", stream);
    #ifdef LUAT_FS_NO_POSIX_GETC
    uint8_t buff = 0;
    int ret = luat_fs_fread(&buff, 1, 1, stream);
    if (ret == 1) {
        return buff;
    }
    return -1;
    #else
    return getc(stream);
    #endif
}

int luat_fs_fseek(FILE* stream, long int offset, int origin) {
    return fseek(stream, offset, origin);
}

int luat_fs_ftell(FILE* stream) {
    return ftell(stream);
}

int luat_fs_fclose(FILE* stream) {
    return fclose(stream);
}
int luat_fs_feof(FILE* stream) {
    return feof(stream);
}
int luat_fs_ferror(FILE *stream) {
    return ferror(stream);
}
size_t luat_fs_fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    //LLOGD("posix_fread %d %p", size*nmemb, stream);
    return fread(ptr, size, nmemb, stream);
}
size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return fwrite(ptr, size, nmemb, stream);
}
int luat_fs_remove(const char *filename) {
    return remove(filename + FILENAME_OFFSET);
}
int luat_fs_rename(const char *old_filename, const char *new_filename) {
#if LUA_USE_VFS_FILENAME_OFFSET
    return rename(old_filename + (old_filename[0] == '/' ? 1 : 0), new_filename + (new_filename[0] == '/' ? 1 : 0));
#else
    return rename(old_filename, new_filename);
#endif
}
int luat_fs_fexist(const char *filename) {
    FILE* fd = luat_fs_fopen(filename, "rb");
    if (fd) {
        luat_fs_fclose(fd);
        return 1;
    }
    return 0;
}

size_t luat_fs_fsize(const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_fs_fopen(filename, "rb");
    if (fd) {
        luat_fs_fseek(fd, 0, SEEK_END);
        size = luat_fs_ftell(fd); 
        luat_fs_fclose(fd);
    }
    return size;
}

LUAT_WEAK int luat_fs_mkfs(luat_fs_conf_t *conf) {
    LLOGE("not support yet : mkfs");
    return -1;
}
LUAT_WEAK int luat_fs_mount(luat_fs_conf_t *conf) {
    LLOGE("not support yet : mount");
    return -1;
}
LUAT_WEAK int luat_fs_umount(luat_fs_conf_t *conf) {
    LLOGE("not support yet : umount");
    return -1;
}

int luat_fs_mkdir(char const* _DirName) {
    //return mkdir(_DirName);
    return -1;
}
int luat_fs_rmdir(char const* _DirName) {
    //return rmdir(_DirName);
    return -1;
}

#else

FILE* luat_vfs_posix_fopen(void* userdata, const char *filename, const char *mode) {
    //LLOGD("fopen %s %s", filename + FILENAME_OFFSET, mode);
    return fopen(filename + FILENAME_OFFSET, mode);
}

int luat_vfs_posix_getc(void* userdata, FILE* stream) {
    //LLOGD("posix_getc %p", stream);
    #ifdef LUAT_FS_NO_POSIX_GETC
    uint8_t buff = 0;
    int ret = luat_fs_fread(&buff, 1, 1, stream);
    if (ret == 1) {
        return buff;
    }
    return -1;
    #else
    return getc(stream);
    #endif
}

int luat_vfs_posix_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    return fseek(stream, offset, origin);
}

int luat_vfs_posix_ftell(void* userdata, FILE* stream) {
    return ftell(stream);
}

int luat_vfs_posix_fclose(void* userdata, FILE* stream) {
    return fclose(stream);
}
int luat_vfs_posix_feof(void* userdata, FILE* stream) {
    return feof(stream);
}
int luat_vfs_posix_ferror(void* userdata, FILE *stream) {
    return ferror(stream);
}
size_t luat_vfs_posix_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    
    return fread(ptr, size, nmemb, stream);
}
size_t luat_vfs_posix_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return fwrite(ptr, size, nmemb, stream);
}
int luat_vfs_posix_remove(void* userdata, const char *filename) {
    return remove(filename + FILENAME_OFFSET);
}
int luat_vfs_posix_rename(void* userdata, const char *old_filename, const char *new_filename) {
#if LUA_USE_VFS_FILENAME_OFFSET
    return rename(old_filename + (old_filename[0] == '/' ? 1 : 0), new_filename + (new_filename[0] == '/' ? 1 : 0));
#else
    return rename(old_filename, new_filename);
#endif
}
int luat_vfs_posix_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_posix_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_posix_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_posix_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_posix_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_posix_fseek(userdata, fd, 0, SEEK_END);
        size = luat_vfs_posix_ftell(userdata, fd); 
        luat_vfs_posix_fclose(userdata, fd);
    }
    return size;
}

int luat_vfs_posix_mkfs(void* userdata, luat_fs_conf_t *conf) {
    LLOGE("not support yet : mkfs");
    return -1;
}
int luat_vfs_posix_mount(void** userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : mount");
    return 0;
}
int luat_vfs_posix_umount(void* userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : umount");
    return 0;
}

int luat_vfs_posix_mkdir(void* userdata, char const* _DirName) {
    //return mkdir(_DirName);
    return -1;
}
int luat_vfs_posix_rmdir(void* userdata, char const* _DirName) {
    //return rmdir(_DirName);
    return -1;
}
int luat_vfs_posix_info(void* userdata, const char* path, luat_fs_info_t *conf) {

    memcpy(conf->filesystem, "posix", strlen("posix")+1);
    conf->type = 0;
    conf->total_block = 0;
    conf->block_used = 0;
    conf->block_size = 512;
    return 0;
}

#define T(name) .name = luat_vfs_posix_##name
const struct luat_vfs_filesystem vfs_fs_posix = {
    .name = "posix",
    .opts = {
        .mkfs = NULL,
        T(mount),
        T(umount),
        .mkdir = NULL,
        .rmdir = NULL,
        .lsdir = NULL,
        T(remove),
        T(rename),
        T(fsize),
        T(fexist),
        T(info)
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
        T(fwrite)
    }
};

#endif



