
#include "luat_fs.h"
#define LUAT_LOG_TAG "luat.fs"
#include "luat_log.h"

#define TAG "luat.fs"

// fs的默认实现, 指向poisx的stdio.h声明的方法

LUAT_WEAK FILE* luat_fs_fopen(const char *filename, const char *mode) {
    //LLOGD("fopen %s %s", filename, mode);
    return fopen(filename, mode);
}

LUAT_WEAK char luat_fs_getc(FILE* stream) {
    return getc(stream);
}

LUAT_WEAK int luat_fs_fseek(FILE* stream, long int offset, int origin) {
    return fseek(stream, offset, origin);
}

LUAT_WEAK int luat_fs_ftell(FILE* stream) {
    return ftell(stream);
}

LUAT_WEAK int luat_fs_fclose(FILE* stream) {
    return fclose(stream);
}
LUAT_WEAK int luat_fs_feof(FILE* stream) {
    return feof(stream);
}
LUAT_WEAK int luat_fs_ferror(FILE *stream) {
    return ferror(stream);
}
LUAT_WEAK size_t luat_fs_fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return fread(ptr, size, nmemb, stream);
}
LUAT_WEAK size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return fwrite(ptr, size, nmemb, stream);
}
LUAT_WEAK int luat_fs_remove(const char *filename) {
    return remove(filename);
}
LUAT_WEAK int luat_fs_rename(const char *old_filename, const char *new_filename) {
    return rename(old_filename, new_filename);
}
