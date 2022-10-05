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
    char password[48];
    char bssid[36];
    uint32_t authmode;
    uint32_t auto_reconnection;
    uint32_t auto_reconnection_delay_sec;
}luat_wlan_conninfo_t;

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
