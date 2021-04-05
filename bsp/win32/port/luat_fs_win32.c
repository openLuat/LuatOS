
#include "luat_fs.h"
#define LUAT_LOG_TAG "luat.fs"
#include "luat_log.h"

#define TAG "luat.fs"

// fs的默认实现, 指向poisx的stdio.h声明的方法

FILE* luat_fs_fopen(const char *filename, const char *mode) {
    LLOGD("fopen %s %s", filename+1, mode);
    return fopen(filename+1, mode);
}

char luat_fs_getc(FILE* stream) {
    return getc(stream);
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
    return fread(ptr, size, nmemb, stream);
}
size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return fwrite(ptr, size, nmemb, stream);
}
int luat_fs_remove(const char *filename) {
    return remove(filename+1);
}
int luat_fs_rename(const char *old_filename, const char *new_filename) {
    return rename(old_filename+1, new_filename);
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

int luat_fs_mkfs(luat_fs_conf_t *conf) {
    LLOGE("not support yet : mkfs");
    return -1;
}
int luat_fs_mount(luat_fs_conf_t *conf) {
    LLOGE("not support yet : mount");
    return -1;
}
int luat_fs_umount(luat_fs_conf_t *conf) {
    LLOGE("not support yet : umount");
    return -1;
}

int luat_fs_mkdir(char const* _DirName) {
    LLOGE("not support yet : mkdir");
    return -1;
}
int luat_fs_rmdir(char const* _DirName) {
    LLOGE("not support yet : rmdir");
    return -1;
}
