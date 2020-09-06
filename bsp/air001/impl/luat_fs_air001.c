
#include "luat_base.h"
#include "luat_fs.h"

int luat_fs_init(void) {
    return 0;
}

FILE* luat_fs_fopen(const char *filename, const char *mode) {
    char buff[256] = {0};
    snprintf(buff, 256, "disk/%s", filename);
    return fopen(buff, mode);
}

int luat_fs_remove(const char *filename) {
    char buff[256] = {0};
    snprintf(buff, 256, "disk/%s", filename);
    return remove(buff);
}

int luat_fs_rename(const char *old_filename, const char *new_filename) {
    char buff[256] = {0};
    char buff2[256] = {0};
    snprintf(buff, 256, "disk/%s", old_filename);
    snprintf(buff2, 256, "disk/%s", new_filename);
    return rename(buff, buff2);
}

int luat_fs_info(const char* path, luat_fs_info_t *conf) {
    return -1;
}

