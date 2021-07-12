
#include "luat_base.h"
#include "luat_fs.h"

int luat_fs_init(void) {
    return 0;
}

int luat_fs_info(const char* path, luat_fs_info_t *conf) {
    return -1;
}

int luat_fs_getc(FILE* stream) {
    // uint8_t buff = 0;
    // int ret = luat_fs_fread(&buff, 1, 1, stream);
    // if (ret == 1) {
    //     return buff;
    // }
    return -1;
}

