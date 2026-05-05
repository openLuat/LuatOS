#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_devinfo.h"
#include "luat_mcu.h"

// 对端设备的信息, TODO 支持多个对端设备
luat_airlink_dev_info_t g_airlink_ext_dev_info;
// 自身设备的信息 — 不得直接访问, 须通过下方 API 操作
static luat_airlink_dev_info_t g_airlink_self_dev_info;
// 最后一次修改时间 (ms)
static uint64_t g_airlink_self_dev_info_mtime = 0;

luat_airlink_dev_info_t* luat_airlink_self_dev_info_ptr(void) {
    return &g_airlink_self_dev_info;
}

void luat_airlink_self_dev_info_notify(void) {
    g_airlink_self_dev_info_mtime = luat_mcu_tick64_ms();
    AIRLINK_DEV_INFO_UPDATE_CB cb = luat_airlink_mode_dev_info_update_cb_get();
    if (cb) {
        cb();
    }
}

uint64_t luat_airlink_self_dev_info_get_mtime(void) {
    return g_airlink_self_dev_info_mtime;
}

