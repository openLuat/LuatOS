
#include "luat_base.h"
#include "luat_fs.h"

int luat_fs_init(void) {
    return 0;
}

FILE* luat_fs_fopen(const char *filename, const char *mode) {
    //LLOGD("fopen %s %s", filename, mode);
    return NULL;
}

int luat_fs_info(const char* path, luat_fs_info_t *conf) {
    return -1;
}

int luat_fs_getc(FILE* stream) {
    return -1;
}

int luat_fs_fseek(FILE* stream, long int offset, int origin) {
    return 0;
}

int luat_fs_ftell(FILE* stream) {
    return 0;
}

int luat_fs_fclose(FILE* stream) {
    return 0;
}
int luat_fs_feof(FILE* stream) {
    return 0;
}
int luat_fs_ferror(FILE *stream) {
    return 0;
}
size_t luat_fs_fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return 0;
}
size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return 0;
}
int luat_fs_remove(const char *filename) {
    return 0;
}
int luat_fs_rename(const char *old_filename, const char *new_filename) {
    return 0;
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
    return -1;
}
int luat_fs_mount(luat_fs_conf_t *conf) {
    return -1;
}
int luat_fs_umount(luat_fs_conf_t *conf) {
    return -1;
}

int luat_fs_mkdir(char const* _DirName) {
    return -1;
}
int luat_fs_rmdir(char const* _DirName) {
    return -1;
}