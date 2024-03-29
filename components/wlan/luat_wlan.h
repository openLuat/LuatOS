#ifndef LUAT_WLAN_H
#define LUAT_WLAN_H

#include "luat_base.h"
#ifdef __LUATOS__
#include "luat_msgbus.h"
#include "luat_mem.h"
#endif
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
    uint8_t gateway[4];
    uint8_t netmask[4];
    uint8_t channel;
    uint8_t encrypt;
    uint8_t hidden;
    uint8_t max_conn;
}luat_wlan_apinfo_t;

enum LUAT_WLAN_MODE {
    LUAT_WLAN_MODE_NULL,
    LUAT_WLAN_MODE_STA,
    LUAT_WLAN_MODE_AP,
    LUAT_WLAN_MODE_APSTA,
    LUAT_WLAN_MODE_MAX
};


enum LUAT_WLAN_ENCRYPT_MODE {
    LUAT_WLAN_ENCRYPT_AUTO,
    LUAT_WLAN_ENCRYPT_NONE,
    LUAT_WLAN_ENCRYPT_WPA,
    LUAT_WLAN_ENCRYPT_WPA2
};

typedef struct luat_wlan_scan_result
{
    char ssid[33];
    char bssid[6];
    int16_t rssi;
    uint8_t ch;
}luat_wlan_scan_result_t;

typedef struct luat_wlan_station_info
{
    uint8_t ipv4_addr[4];
    uint8_t ipv4_netmask[4];
    uint8_t ipv4_gateway[4];
    uint8_t dhcp_enable;
}luat_wlan_station_info_t;


int luat_wlan_init(luat_wlan_config_t *conf);
int luat_wlan_mode(luat_wlan_config_t *conf);
int luat_wlan_ready(void);
int luat_wlan_connect(luat_wlan_conninfo_t* info);
int luat_wlan_disconnect(void);
int luat_wlan_scan(void);
int luat_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit);

int luat_wlan_set_station_ip(luat_wlan_station_info_t *info);

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
int luat_wlan_set_mac(int id, const char* mac);
int luat_wlan_get_ip(int type, char* data);
const char* luat_wlan_get_hostname(int id);
int luat_wlan_set_hostname(int id, const char* hostname);

// 设置和获取省电模式
int luat_wlan_set_ps(int mode);
int luat_wlan_get_ps(void);

int luat_wlan_get_ap_bssid(char* buff);
int luat_wlan_get_ap_rssi(void);
int luat_wlan_get_ap_gateway(char* buff);

// AP类
int luat_wlan_ap_start(luat_wlan_apinfo_t *apinfo);
int luat_wlan_ap_stop(void);



/**
 * @defgroup luat_wifiscan wifiscan扫描接口
 * @{
 */
#define Luat_MAX_CHANNEL_NUM     14
/// @brief wifiscan 扫描的优先级
typedef enum luat_wifiscan_set_priority
{
    LUAT_WIFISCAN_DATA_PERFERRD=0,/**< 数据优先*/
    LUAT_WIFISCAN_WIFI_PERFERRD
}luat_wifiscan_set_priority_t;

/// @brief wifiscan 控制参数结构体
typedef struct luat_wifiscan_set_info
{
    int   maxTimeOut;         //ms, 最大执行时间 取值范围4000~255000
    uint8_t   round;              //wifiscan total round 取值范围1~3
    uint8_t   maxBssidNum;        //wifiscan max report num 取值范围4~40
    uint8_t   scanTimeOut;        //s, max time of each round executed by RRC 取值范围1~255
    uint8_t   wifiPriority;       //CmiWifiScanPriority
    uint8_t   channelCount;       //channel count; if count is 1 and all channelId are 0, UE will scan all frequecny channel
    uint8_t   rsvd[3];
    uint16_t  channelRecLen;      //ms, max scantime of each channel
    uint8_t   channelId[Luat_MAX_CHANNEL_NUM];          //channel id 1-14: scan a specific channel
}luat_wifiscan_set_info_t;


#define LUAT_MAX_WIFI_BSSID_NUM      40 ///< bssid 的最大数量
#define LUAT_MAX_SSID_HEX_LENGTH     32 ///< SSID 的最大长度

/// @brief wifiscan 扫描结果
typedef struct luat_wifisacn_get_info
{
    uint8_t   bssidNum;                                   /**<wifi 个数*/
    uint8_t   rsvd;
    uint8_t   ssidHexLen[LUAT_MAX_WIFI_BSSID_NUM];        /**<SSID name 的长度*/
    uint8_t   ssidHex[LUAT_MAX_WIFI_BSSID_NUM][LUAT_MAX_SSID_HEX_LENGTH]; /**<SSID name*/
    int8_t    rssi[LUAT_MAX_WIFI_BSSID_NUM];           /**<rssi*/
    uint8_t   channel[LUAT_MAX_WIFI_BSSID_NUM];        /**<record channel index of bssid, 2412MHz ~ 2472MHz correspoding to 1 ~ 13*/ 
    uint8_t   bssid[LUAT_MAX_WIFI_BSSID_NUM][6];       /**<mac address is fixed to 6 digits*/ 
}luat_wifisacn_get_info_t;

/**
 * @brief 获取wifiscan 的信息
 * @param set_info[in] 设置控制wifiscan的参数
 * @param get_info[out] wifiscan 扫描结果 
 * @return int =0成功，其他失败
 */
int32_t luat_get_wifiscan_cell_info(luat_wifiscan_set_info_t * set_info,luat_wifisacn_get_info_t* get_info);

/**
 * @brief 获取wifiscan 的信息
 * @param set_info[in] 设置控制wifiscan的参数 
 * @return int =0成功，其他失败
 */
int luat_wlan_scan_nonblock(luat_wifiscan_set_info_t * set_info);
/** @}*/
#endif
