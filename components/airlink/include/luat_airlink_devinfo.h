#ifndef LUAT_AIRLINK_DEVINFO_H
#define LUAT_AIRLINK_DEVINFO_H

#include "luat_airlink.h"

// =====================================================================
// 设备信息结构体
// =====================================================================

typedef struct luat_airlink_dev_wifi_info {
    uint8_t sta_mac[6];
    uint8_t ap_mac[6];
    uint8_t bt_mac[6];
    uint8_t sta_state;
    uint8_t ap_state;
    uint8_t reserved[32];
    uint8_t version[4];
    uint8_t fw_type[2];
    uint8_t unique_id_len;
    uint8_t unique_id[24];

    // 2025.5.29 新增
    uint8_t sta_ap_bssid[6]; // AP的MAC地址(BSSID)
    int32_t sta_ap_rssi;     // AP信号强度
    uint8_t sta_ap_channel;  // AP所属的通道
} luat_airlink_dev_wifi_info_t;

typedef struct luat_airlink_dev_cat_info {
    uint8_t ipv4[4];
    uint8_t ipv6[16];
    uint8_t cat_state;
    uint8_t sim_state;
    uint8_t imei[16];
    uint8_t iccid[20];
    uint8_t imsi[16];
    uint8_t reserved[32];
    uint8_t version[4];
    uint8_t fw_type[4];
    uint8_t unique_id_len;
    uint8_t unique_id[32];
} luat_airlink_dev_wifi_cat_t;

typedef struct luat_airlink_dev_info
{
    uint8_t tp;
    union
    {
        luat_airlink_dev_wifi_info_t wifi;
        luat_airlink_dev_wifi_cat_t cat1;
    };
} luat_airlink_dev_info_t;

extern luat_airlink_dev_info_t g_airlink_ext_dev_info;

// =====================================================================
// syspub — 系统发布数据构建 API
// =====================================================================

int luat_airlink_syspub_addstring(const char* str, size_t len, uint8_t *dst, uint32_t limit);
int luat_airlink_syspub_addfloat32(const float val, uint8_t *dst, uint32_t limit);
int luat_airlink_syspub_addint32(const int32_t val, uint8_t *dst, uint32_t limit);
int luat_airlink_syspub_addnil(uint8_t *dst, uint32_t limit);
int luat_airlink_syspub_addbool(const uint8_t b, uint8_t *dst, uint32_t limit);

int luat_airlink_syspub_send(uint8_t* buff, size_t len);

#endif /* LUAT_AIRLINK_DEVINFO_H */
