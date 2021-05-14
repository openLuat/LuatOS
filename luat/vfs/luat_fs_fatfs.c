
#include "luat_base.h"
#include "luat_fs.h"

#ifdef LUAT_VFS_USE_FATFS

#error "no complete yet"
// 参考 luat_lib_fatfs 里面操作fatfs的方法, 实现vfs封装.

#include "ff.h"
#include "diskio.h"

extern FATFS *fs;

FILE* luat_vfs_fatfs_fopen(void* userdata, const char *filename, const char *mode) {
    //LLOGD("fopen %s %s", filename + (filename[0] == '/' ? 1 : 0), mode);
    return fopen(filename + (filename[0] == '/' ? 1 : 0), mode);
}

int luat_vfs_fatfs_getc(void* userdata, FILE* stream) {
    //LLOGD("posix_getc %p", stream);
    return getc(stream);
}

int luat_vfs_fatfs_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    return fseek(stream, offset, origin);
}

int luat_vfs_fatfs_ftell(void* userdata, FILE* stream) {
    return ftell(stream);
}

int luat_vfs_fatfs_fclose(void* userdata, FILE* stream) {
    return fclose(stream);
}
int luat_vfs_fatfs_feof(void* userdata, FILE* stream) {
    return feof(stream);
}
int luat_vfs_fatfs_ferror(void* userdata, FILE *stream) {
    return ferror(stream);
}
size_t luat_vfs_fatfs_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    
    return fread(ptr, size, nmemb, stream);
}
size_t luat_vfs_fatfs_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return fwrite(ptr, size, nmemb, stream);
}
int luat_vfs_fatfs_remove(void* userdata, const char *filename) {
    return remove(filename + (filename[0] == '/' ? 1 : 0));
}
int luat_vfs_fatfs_rename(void* userdata, const char *old_filename, const char *new_filename) {
    return rename(old_filename + (old_filename[0] == '/' ? 1 : 0), new_filename + (new_filename[0] == '/' ? 1 : 0));
}

int luat_vfs_fatfs_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_fatfs_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_fatfs_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_fatfs_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_fatfs_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_fatfs_fseek(userdata, fd, 0, SEEK_END);
        size = luat_vfs_fatfs_ftell(userdata, fd); 
        luat_vfs_fatfs_fclose(userdata, fd);
    }
    return size;
}

int luat_vfs_fatfs_mkfs(void* userdata, luat_fs_conf_t *conf) {
    LLOGE("not support yet : mkfs");
    return -1;
}
int luat_vfs_fatfs_mount(void** userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : mount");
    return 0;
}
int luat_vfs_fatfs_umount(void* userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : umount");
    return 0;
}

int luat_vfs_fatfs_mkdir(void* userdata, char const* _DirName) {
    return mkdir(_DirName);
}
int luat_vfs_fatfs_rmdir(void* userdata, char const* _DirName) {
    return rmdir(_DirName);
}

#define T(name) .name = luat_vfs_fatfs_##name
const struct luat_vfs_filesystem vfs_fs_fatfs = {
    .name = "fatfs",
    .opts = {
        T(mkfs),
        T(mount),
        T(umount),
        T(mkdir),
        T(rmdir),
        T(remove),
        T(rename),
        T(fsize),
        T(fexist)
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
