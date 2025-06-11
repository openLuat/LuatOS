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
CMD_DEFINE(result);


CMD_DEFINE(fota_init);
CMD_DEFINE(fota_write);
CMD_DEFINE(fota_done);
CMD_DEFINE(fota_end);
CMD_DEFINE(dev_info);
CMD_DEFINE(sdata);
CMD_DEFINE(nop);
// 通知类指令, 0x80开始
CMD_DEFINE(notify_sys_pub);
CMD_DEFINE(notify_log);

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
CMD_DEFINE(wlan_scan_result_cb);
CMD_DEFINE(wlan_set_mac);
CMD_DEFINE(wlan_set_ps);

// GPIO指令, 0x300开始
CMD_DEFINE(gpio_setup);
CMD_DEFINE(gpio_set);
CMD_DEFINE(gpio_get);
CMD_DEFINE(gpio_get_result);
CMD_DEFINE(gpio_driver_yhm27xx);
CMD_DEFINE(gpio_driver_yhm27xx_reqinfo);

// UART指令, 0x400开始
CMD_DEFINE(uart_setup);
CMD_DEFINE(uart_write);
CMD_DEFINE(uart_close);
CMD_DEFINE(uart_data_cb);
CMD_DEFINE(uart_sent_cb);

// bluetooth 蓝牙指令，0x500开始
CMD_DEFINE(bt_request);

CMD_DEFINE(bt_resp_cb);

// PM指令, 0x600开始
CMD_DEFINE(pm_request);
CMD_DEFINE(pm_power_ctrl);

// PWM指令, 0x700开始
CMD_DEFINE(pwm_setup);
CMD_DEFINE(pwm_close);

__USER_FUNC_IN_RAM__ const luat_airlink_cmd_reg_t airlink_cmds[] = {
    // 最常用的放前面
    CMD_REG(0x10,  dev_info),
    CMD_REG(0x100, ip_pkg),
    CMD_REG(0x03,  reset),
    // CMD_REG(0x08,  result),
#ifdef LUAT_USE_AIRLINK_EXEC_SDATA
    CMD_REG(0x20,  sdata),
#endif

#ifdef LUAT_USE_AIRLINK_EXEC_NOTIFY
    CMD_REG(0x80, notify_sys_pub),
    CMD_REG(0x81, notify_log),
#endif

    // CMD_REG(0x01, ping),
    // CMD_REG(0x02, pong),
#ifdef LUAT_USE_AIRLINK_EXEC_FOTA
    CMD_REG(0x04, fota_init),
    CMD_REG(0x05, fota_write),
    CMD_REG(0x06, fota_done),
    CMD_REG(0x07, fota_end),
#endif

#ifdef LUAT_USE_AIRLINK_EXEC_WIFI
    CMD_REG(0x200, wlan_init),
    CMD_REG(0x201, wlan_sta_connect),
    CMD_REG(0x202, wlan_sta_disconnect),
    CMD_REG(0x203, wlan_ap_start),
    CMD_REG(0x204, wlan_ap_stop),
    CMD_REG(0x205, wlan_scan),
    CMD_REG(0x207, wlan_set_mac),
    CMD_REG(0x208, wlan_set_ps),
#else
    CMD_REG(0x206, wlan_scan_result_cb),
#endif

#ifdef LUAT_USE_AIRLINK_EXEC_GPIO
    CMD_REG(0x300, gpio_setup),
    CMD_REG(0x301, gpio_set),
    // CMD_REG(0x302, gpio_get),
    CMD_REG(0x304, gpio_driver_yhm27xx),
    CMD_REG(0x305, gpio_driver_yhm27xx_reqinfo),
#endif

#ifdef LUAT_USE_AIRLINK_EXEC_UART
    CMD_REG(0x400, uart_setup),
    CMD_REG(0x401, uart_write),
    CMD_REG(0x402, uart_close),
#else
    CMD_REG(0x410, uart_data_cb),
    CMD_REG(0x411, uart_sent_cb),
#endif

#ifdef LUAT_USE_AIRLINK_EXEC_BLUETOOTH
    CMD_REG(0x500, bt_request),
#endif
#ifdef LUAT_USE_AIRLINK_EXEC_BLUETOOTH_RESP
    CMD_REG(0x510, bt_resp_cb),
#endif

#ifdef LUAT_USE_AIRLINK_EXEC_PM
    CMD_REG(0x600, pm_request),
    CMD_REG(0x601, pm_power_ctrl),
#endif

#ifdef LUAT_USE_AIRLINK_EXEC_PWM
    CMD_REG(0x700, pwm_setup),
    CMD_REG(0x701, pwm_close),
#endif

    CMD_REG(0x21, nop),
    {0, NULL}
};
