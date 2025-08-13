#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"

#ifdef LUAT_USE_AIRLINK_EXEC_MOBILE
#include "luat_mobile.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"


extern luat_airlink_dev_info_t g_airlink_ext_dev_info;

int luat_airlink_cmd_exec_mobile_imei(luat_airlink_cmd_t* cmd, void* userdata) {
    int ret = 0;
    uint8_t index = cmd->data[8];
    
    char imei[16] = {0};
    ret = luat_mobile_get_imei(index, imei, 16);
    if (ret > 0) {
        memcpy(g_airlink_ext_dev_info.cat1.imei, imei, 16);
    }

    return 0;
}

int luat_airlink_cmd_exec_mobile_imsi(luat_airlink_cmd_t* cmd, void* userdata) {
    int ret = 0;
    uint8_t index = cmd->data[8];
    
    char imsi[16] = {0};
    ret = luat_mobile_get_imsi(index, imsi, 16);
    if (ret > 0) {
        memcpy(g_airlink_ext_dev_info.cat1.imsi, imsi, 16);
    }

    return 0;
}

int luat_airlink_cmd_exec_mobile_iccid(luat_airlink_cmd_t* cmd, void* userdata) {
    int ret = 0;
    uint8_t index = cmd->data[8];
    
    char iccid[20] = {0};
    ret = luat_mobile_get_imei(index, iccid, 20);
    if (ret > 0) {
        memcpy(g_airlink_ext_dev_info.cat1.iccid, iccid, 20);
    }

    return 0;
}

int luat_airlink_cmd_exec_mobile_muid(luat_airlink_cmd_t* cmd, void* userdata) {
    int ret = 0;
    
    char muid[33] = {0};
    ret = luat_mobile_get_muid(muid, 32);
    // 暂时先不传
    // if (ret > 0) {
    //     g_airlink_ext_dev_info.cat1.unique_id_len = 32;
    //     memcpy(g_airlink_ext_dev_info.cat1.unique_id, muid, g_airlink_ext_dev_info.cat1.unique_id_len);
    // }

    return 0;
}

#endif
