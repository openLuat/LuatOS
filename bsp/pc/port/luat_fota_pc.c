// 就是完全不支持fota操作就好了

#include "luat_base.h"
#include "luat_fota.h"

int luat_fota_init(uint32_t start_address, uint32_t len, luat_spi_device_t* spi_device, const char *path, uint32_t pathlen) {
    // 初始化FOTA模块
    return -1; // 成功
}
int luat_fota_write(uint8_t *data, uint32_t len) {
    // 写入FOTA数据
    return -1; // 成功
}
int luat_fota_done(void) {
    // 结束FOTA数据写入
    return -1; // 成功
}
int luat_fota_end(uint8_t is_ok) {
    // 结束FOTA流程
    return -1; // 成功
}

