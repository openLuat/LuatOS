#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"

typedef struct luat_wlan_config
{
    uint32_t mode;
}luat_wlan_config_t;

typedef struct luat_wlan_conninfo
{
    char ssid[36];
    char password[64];
    char bssid[8];
    uint32_t authmode;
    uint32_t auto_reconnection;
    uint32_t auto_reconnection_delay_sec;
}luat_wlan_conninfo_t;

typedef struct luat_wlan_apinfo
{
    char ssid[36];
    char password[64];
}luat_wlan_apinfo_t;

enum LUAT_WLAN_MODE {
    LUAT_WLAN_MODE_NULL,
    LUAT_WLAN_MODE_STA,
    LUAT_WLAN_MODE_AP,
    LUAT_WLAN_MODE_APSTA,
    LUAT_WLAN_MODE_MAX
};

typedef struct luat_wlan_scan_result
{
    char ssid[33];
    char bssid[6];
    int16_t rssi;
    int8_t ch;
}luat_wlan_scan_result_t;



int luat_wlan_init(luat_wlan_config_t *conf);
int luat_wlan_mode(luat_wlan_config_t *conf);
int luat_wlan_ready(void);
int luat_wlan_connect(luat_wlan_conninfo_t* info);
int luat_wlan_disconnect(void);
int luat_wlan_scan(void);
int luat_wlan_scan_get_result(luat_wlan_scan_result_t *results, int ap_limit);

// 配网相关
// --- smartconfig 配网
enum LUAT_WLAN_SC_TYPE {
    LUAT_SC_TYPE_STOP = 0,
    LUAT_SC_TYPE_ESPTOUCH,
    LUAT_SC_TYPE_AIRKISS,
    LUAT_SC_TYPE_ESPTOUCH_AIRKISS,
    LUAT_SC_TYPE_ESPTOUCH_V2
};

int luat_wlan_smartconfig_start(int tp);
int luat_wlan_smartconfig_stop(void);

// 数据类
int luat_wlan_get_mac(int id, char* mac);
int luat_wlan_set_mac(int id, char* mac);
int luat_wlan_get_ip(int type, char* data);

// 设置和获取省电模式
int luat_wlan_set_ps(int mode);
int luat_wlan_get_ps(void);

int luat_wlan_get_ap_bssid(char* buff);
int luat_wlan_get_ap_rssi(void);
int luat_wlan_get_ap_gateway(char* buff);

// AP类
int luat_wlan_ap_start(luat_wlan_apinfo_t *apinfo);

