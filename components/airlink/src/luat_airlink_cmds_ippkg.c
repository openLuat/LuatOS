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

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

int luat_airlink_cmd_exec_ip_pkg(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t adapter_id = cmd->data[0];
    LLOGD("收到IP包 长度 %d 适配器 %d", cmd->len - 1, adapter_id);
    // 首先, NAPT处理一下
    int ret = 0;
    luat_netdrv_t* drv = NULL;

    ret = luat_netdrv_napt_pkg_input(adapter_id, cmd->data + 1, cmd->len - 1);
    if (ret != 0) {
        LLOGD("NAPT说已经处理完成, 不需要转发给具体的netdrv了");
        return 0;
    }
    drv = luat_netdrv_get(adapter_id);
    if (drv == NULL) {
        LLOGD("没有找到适配器 %d, 无法处理其IP包", adapter_id);
        return 0;
    }
    // TODO 转给LWIP
    return 0;
}