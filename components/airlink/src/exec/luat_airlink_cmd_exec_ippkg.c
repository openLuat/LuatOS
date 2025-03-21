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
#include "luat_netdrv.h"
#include "luat_netdrv_napt.h"
#include "luat_network_adapter.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

int luat_airlink_cmd_exec_ip_pkg(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t adapter_id = cmd->data[0];
    // LLOGD("收到IP包 长度 %d 适配器 %d", cmd->len - 1, adapter_id);
    // luat_airlink_print_mac_pkg(cmd->data + 1, cmd->len - 1);
    // luat_airlink_hexdump("收到IP包", cmd->data + 1, cmd->len - 1);
    // 首先, NAPT处理一下
    int ret = 0;
    luat_netdrv_t* drv = NULL;

    ret = luat_netdrv_napt_pkg_input(adapter_id, cmd->data + 1, cmd->len - 1);
    if (ret != 0) {
        // LLOGD("NAPT说已经处理完成, 不需要转发给具体的netdrv了");
        return 0;
    }
    drv = luat_netdrv_get(adapter_id);
    if (drv == NULL || drv->netif == NULL) {
        LLOGD("没有找到适配器 %d, 无法处理其IP包", adapter_id);
        return 0;
    }
    
    // 这里开始就复杂了
    // 首先, 如果是平台的包, 那就直接交给平台处理
    //      例如wifi的包, 在wifi平台, 那就应该输出到硬件去
    // 否则, 那就应该转给lwip处理
    #ifdef __BK72XX__
    if (drv->id == NW_ADAPTER_INDEX_LWIP_WIFI_STA || drv->id == NW_ADAPTER_INDEX_LWIP_WIFI_AP) {
        // 这里是wifi的包, 直接输出到硬件去
        // LLOGD("收到wifi的IP包, 直接输出到硬件去 %p %d", cmd->data + 1, cmd->len - 1);
        drv->dataout(drv, drv->userdata, cmd->data + 1, cmd->len - 1);
        return 0;
    }
    #endif

    // luat_airlink_hexdump("收到IP包且要注入LWIP", cmd->data + 1, cmd->len - 1);
    luat_netdrv_netif_input_proxy(drv->netif, cmd->data + 1, cmd->len - 1);

    return 0;
}
