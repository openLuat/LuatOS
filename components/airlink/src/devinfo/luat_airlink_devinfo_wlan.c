#include "luat_base.h"
#include "luat_airlink.h"

#if defined(LUAT_USE_AIRLINK_EXEC_WLAN)
#include "luat_wlan.h"
#endif

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

extern luat_airlink_dev_info_t g_airlink_self_dev_info;
extern luat_airlink_wlan_evt_cb g_airlink_wlan_evt_cb;
extern int luat_airlink_drv_wlan_scan_result_cb(void);

static AIRLINK_DEV_INFO_UPDATE_CB send_devinfo_update_evt = NULL;

#if defined(LUAT_USE_AIRLINK_EXEC_WLAN)
int wifi_evt_handler(void *arg, luat_event_module_t event_module, int event_id, void *event_data) {
    luat_wifi_event_sta_disconnected_t *sta_disconnected;
	luat_wifi_event_sta_connected_t *sta_connected;
	luat_wifi_event_ap_disconnected_t *ap_disconnected;
	luat_wifi_event_ap_connected_t *ap_connected;
	luat_wifi_event_network_found_t *network_found;

    // luat_airlink_dev_info_t *devinfo = self_devinfo();
    uint8_t buff[256] = {0};
    int ret = 0;
    int remain = 256;
    uint8_t *ptr = buff;
    switch (event_id)
    {
    case LUAT_WLAN_EVENT_WIFI_SCAN_DONE:
        LLOGD("scan done");
        luat_airlink_drv_wlan_scan_result_cb();
        send_devinfo_update_evt();
        break;
    case LUAT_WLAN_EVENT_WIFI_STA_CONNECTED:
        // // 通知主机
        g_airlink_self_dev_info.wifi.sta_state = 1;
        sta_connected = (luat_wifi_event_sta_connected_t *)event_data;
        LLOGD("STA connected %s", sta_connected->ssid);

        ret = luat_airlink_syspub_addstring("WLAN_STA_INC", strlen("WLAN_STA_INC"), ptr, remain);
        ptr += ret;
        remain -= ret;

        ret = luat_airlink_syspub_addstring("CONNECTED", strlen("CONNECTED"), ptr, remain);
        ptr += ret;
        remain -= ret;

        ret = luat_airlink_syspub_addstring(sta_connected->ssid, strlen(sta_connected->ssid), ptr, remain);
        ptr += ret;
        remain -= ret;

        ret = luat_airlink_syspub_addstring((const char*)sta_connected->bssid, 6, ptr, remain);
        ptr += ret;
        remain -= ret;

        luat_airlink_syspub_send(buff, ptr - buff);
        send_devinfo_update_evt();
        break;

    case LUAT_WLAN_EVENT_WIFI_STA_DISCONNECTED:
        g_airlink_self_dev_info.wifi.sta_state = 0;
        sta_disconnected = (luat_wifi_event_sta_disconnected_t *)event_data;
        if (sta_disconnected->disconnect_reason > 0) {
            LLOGD("STA disconnected, reason(%d) is_local %d", sta_disconnected->disconnect_reason, sta_disconnected->local_generated); 
            
            ret = luat_airlink_syspub_addstring("WLAN_STA_INC", strlen("WLAN_STA_INC"), ptr, remain);
            ptr += ret;
            remain -= ret;

            ret = luat_airlink_syspub_addstring("DISCONNECTED", strlen("DISCONNECTED"), ptr, remain);
            ptr += ret;
            remain -= ret;

            ret = luat_airlink_syspub_addint32(sta_disconnected->disconnect_reason, ptr, remain);
            ptr += ret;
            remain -= ret;

            luat_airlink_syspub_send(buff, ptr - buff);
            send_devinfo_update_evt();
        }
        else {
            send_devinfo_update_evt();
            return 0; // reason == 0 的时候不需要发消息
        }
        break;
    case LUAT_WLAN_EVENT_WIFI_AP_CONNECTED:
        ap_connected = (luat_wifi_event_ap_connected_t *)event_data;
        // LLOGD(BK_MAC_FORMAT" connected to AP", BK_MAC_STR(ap_connected->mac));

        ret = luat_airlink_syspub_addstring("WLAN_AP_INC", strlen("WLAN_AP_INC"), ptr, remain);
        ptr += ret;
        remain -= ret;
        
        ret = luat_airlink_syspub_addstring("CONNECTED", strlen("CONNECTED"), ptr, remain);
        ptr += ret;
        remain -= ret;

        ret = luat_airlink_syspub_addstring((const char*)ap_connected->mac, 6, ptr, remain);
        ptr += ret;
        remain -= ret;
        
        luat_airlink_syspub_send(buff, ptr - buff);
        send_devinfo_update_evt();
        break;
    case LUAT_WLAN_EVENT_WIFI_AP_DISCONNECTED:
        ap_disconnected = (luat_wifi_event_ap_disconnected_t *)event_data;
        // LLOGD(BK_MAC_FORMAT" disconnected from AP", BK_MAC_STR(ap_disconnected->mac));
        
        ret = luat_airlink_syspub_addstring("WLAN_AP_INC", strlen("WLAN_AP_INC"), ptr, remain);
        ptr += ret;
        remain -= ret;
        
        ret = luat_airlink_syspub_addstring("DISCONNECTED", strlen("DISCONNECTED"), ptr, remain);
        ptr += ret;
        remain -= ret;

        ret = luat_airlink_syspub_addstring((const char*)ap_disconnected->mac, 6, ptr, remain);
        ptr += ret;
        remain -= ret;

        luat_airlink_syspub_send(buff, ptr - buff);
        send_devinfo_update_evt();
        break;
    case LUAT_WLAN_EVENT_WIFI_NETWORK_FOUND:
        network_found = (luat_wifi_event_network_found_t *)event_data;
        LLOGD(" target AP: %s, bssid %p found", network_found->ssid, network_found->bssid);
        send_devinfo_update_evt();
        break;
    }
    return 0;
}

void luat_bk72xx_update_ap(uint8_t state) {
    LLOGI("AP状态变化 %d", state);
    g_airlink_self_dev_info.wifi.ap_state = state;
    send_devinfo_update_evt();
}

void luat_airlink_devinfo_init(AIRLINK_DEV_INFO_UPDATE_CB cb) 
{
    send_devinfo_update_evt = cb;
    g_airlink_self_dev_info.tp = 0x01;
    uint32_t fw_version = 20;
    memcpy(g_airlink_self_dev_info.wifi.version, &fw_version, sizeof(uint32_t));   // 版本
    g_airlink_wlan_evt_cb = wifi_evt_handler;
    send_devinfo_update_evt();
}
#endif
