#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_fota.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

int luat_airlink_cmd_exec_ping(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到ping指令,返回pong");
    // TODO 返回PONG
    return 0;
}

int luat_airlink_cmd_exec_pong(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到pong指令,检查数据是否匹配!!");
    return 0;
}

int luat_airlink_cmd_exec_reset(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到reset指令!!!");
    luat_pm_reset();
    return 0;
}

int luat_airlink_cmd_exec_fota_init(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到FOTA初始化指令!!!");
    int ret = luat_fota_init(0, 0, NULL, NULL, 0);
    LLOGD("fota_init ret %d", ret);
    return 0;
}

int luat_airlink_cmd_exec_fota_data(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到FOTA数据!!!");
    int ret = luat_fota_write(cmd->data, cmd->len);
    LLOGD("fota_write ret %d", ret);
    return 0;
}

int luat_airlink_cmd_exec_fota_done(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到FOTA传输完毕指令!!!");
    int ret = luat_fota_done();
    LLOGD("fota_write ret %d", ret);
    return 0;
}
