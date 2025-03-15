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

#define CMD_DEFINE(func) extern int luat_airlink_cmd_exec_##func(luat_airlink_cmd_t* cmd, void* userdata)
#define CMD_REG(id,func) {id, luat_airlink_cmd_exec_##func}

// 基础指令0x01开始
CMD_DEFINE(ping);
CMD_DEFINE(pong);
CMD_DEFINE(reset);
CMD_DEFINE(fota_init);
CMD_DEFINE(fota_write);
CMD_DEFINE(fota_done);
CMD_DEFINE(dev_info);

// MAC和IP包指令, 0x100开始
CMD_DEFINE(ip_pkg);
CMD_DEFINE(set_mac);
CMD_DEFINE(link_up);
CMD_DEFINE(link_down);

// WIFI指令, 0x200开始
CMD_DEFINE(wlan_init);
CMD_DEFINE(wlan_sta_connect);
CMD_DEFINE(wlan_sta_disconnect);
CMD_DEFINE(wlan_ap_start);
CMD_DEFINE(wlan_ap_stop);
CMD_DEFINE(wlan_scan);
CMD_DEFINE(wlan_scan_result);

const luat_airlink_cmd_reg_t airlink_cmds[] = {
    // CMD_REG(0x01, ping),
    // CMD_REG(0x02, pong),
    // CMD_REG(0x03, reset),
    // CMD_REG(0x04, fota_init),
    // CMD_REG(0x05, fota_write),
    // CMD_REG(0x06, fota_done),

    CMD_REG(0x10, dev_info),

    CMD_REG(0x100, ip_pkg),
    // CMD_REG(0x101, set_mac),
    // CMD_REG(0x102, link_up),
    // CMD_REG(0x103, link_down),

    {0, NULL}
};