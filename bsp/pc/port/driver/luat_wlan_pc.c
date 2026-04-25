/*
 * luat_wlan_pc.c - PC simulator WLAN driver
 *
 * Two modes:
 *   1. Mock mode (default): returns fixed scan results, simulates connect/disconnect
 *   2. Native mode (LUAT_USE_WLAN_NATIVE on Windows): calls Windows Native WiFi API
 */

// uv.h must be included first to avoid LwIP vs WinSock type conflicts
#include "uv.h"

#include "luat_base.h"
#include "luat_wlan.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_network_adapter.h"

#include <string.h>

#define LUAT_LOG_TAG "wlan.pc"
#include "luat_log.h"

extern uv_loop_t *main_loop;
void free_uv_handle(void* ptr);

// ========== Internal state ==========

static uint32_t wlan_inited = 0;
static uint32_t wlan_mode = LUAT_WLAN_MODE_NULL;
static uint32_t wlan_connected = 0;
static char wlan_ssid[36] = {0};
static char wlan_password[64] = {0};
static uint8_t wlan_bssid[6] = {0};
static int16_t wlan_rssi = 0;
static uint32_t wlan_connect_seq = 0;
static char wlan_hostname[32] = "LUATOS_PC";
static uint8_t wlan_mac[6] = {0x00, 0x22, 0xEE, 0xCC, 0x23, 0x99};
static int wlan_ps_mode = 0;
static char wlan_pending_ssid[36] = {0};
static char wlan_pending_password[64] = {0};
static uint8_t wlan_pending_bssid[6] = {0};
static int16_t wlan_pending_rssi = 0;

// AP mode state
static uint32_t wlan_ap_active = 0;
static char wlan_ap_ssid[36] = {0};
static char wlan_ap_password[64] = {0};
static uint8_t wlan_ap_gateway[4] = {192, 168, 4, 1};
static uint8_t wlan_ap_netmask[4] = {255, 255, 255, 0};

#define WIFI_REASON_NO_AP_FOUND 257
#define WIFI_REASON_WRONG_PASSWORD 258
#define MOCK_CONNECT_FAIL_DELAY_MS 2000
#define MOCK_CONNECT_SUCCESS_DELAY_MS 1000
#define MOCK_IP_READY_DELAY_MS 1100

typedef struct mock_wlan_connect_timer {
    uv_timer_t timer;
    uint32_t seq;
    int reason;
} mock_wlan_connect_timer_t;

// ========== Mock scan data ==========

static const luat_wlan_scan_result_t mock_scan_results[] = {
    {.ssid = "luatos1234",     .bssid = {0xAA,0xBB,0xCC,0xDD,0xEE,0x01}, .rssi = -35, .ch = 6},
    {.ssid = "ChinaNet-XXXX",  .bssid = {0xAA,0xBB,0xCC,0xDD,0xEE,0x02}, .rssi = -55, .ch = 1},
    {.ssid = "TP-LINK_5G_ABC", .bssid = {0xAA,0xBB,0xCC,0xDD,0xEE,0x03}, .rssi = -60, .ch = 36},
    {.ssid = "Xiaomi_Router",  .bssid = {0xAA,0xBB,0xCC,0xDD,0xEE,0x04}, .rssi = -70, .ch = 11},
    {.ssid = "CMCC-FREE",      .bssid = {0xAA,0xBB,0xCC,0xDD,0xEE,0x05}, .rssi = -80, .ch = 6},
};
#define MOCK_AP_COUNT (sizeof(mock_scan_results) / sizeof(mock_scan_results[0]))

// ========== Forward declarations for native mode ==========

#if defined(LUAT_USE_WLAN_NATIVE) && defined(LUAT_USE_WINDOWS)
static int native_wlan_init(void);
static int native_wlan_scan(void);
static int native_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit);
static int native_wlan_connect(luat_wlan_conninfo_t* info);
static int native_wlan_disconnect(void);
static int native_wlan_ready(void);
#endif

// ========== Event publishing helpers ==========

static int l_wlan_scan_done_cb(lua_State *L, void *ptr) {
    (void)ptr;
    lua_getglobal(L, "sys_pub");
    if (!lua_isfunction(L, -1)) {
        return 0;
    }
    lua_pushliteral(L, "WLAN_SCAN_DONE");
    lua_call(L, 1, 0);
    return 0;
}

static int l_wlan_sta_connected_cb(lua_State *L, void *ptr) {
    (void)ptr;
    lua_getglobal(L, "sys_pub");
    if (!lua_isfunction(L, -1)) {
        return 0;
    }
    lua_pushliteral(L, "WLAN_STA_INC");
    lua_pushliteral(L, "CONNECTED");
    lua_pushstring(L, wlan_ssid);
    lua_pushlstring(L, (const char*)wlan_bssid, 6);
    lua_call(L, 4, 0);
    return 0;
}

static int l_wlan_sta_disconnected_cb(lua_State *L, void *ptr) {
    (void)ptr;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (!lua_isfunction(L, -1)) {
        return 0;
    }
    lua_pushliteral(L, "WLAN_STA_INC");
    lua_pushliteral(L, "DISCONNECTED");
    if (msg && msg->arg1 > 0) {
        lua_pushinteger(L, msg->arg1);
        lua_call(L, 3, 0);
    }
    else {
        lua_call(L, 2, 0);
    }
    return 0;
}

static int l_wlan_ip_ready_cb(lua_State *L, void *ptr) {
    (void)ptr;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (!lua_isfunction(L, -1)) {
        return 0;
    }
    lua_pushliteral(L, "IP_READY");
    uint32_t ip = msg->arg2;
    lua_pushfstring(L, "%d.%d.%d.%d", (ip) & 0xFF, (ip >> 8) & 0xFF, (ip >> 16) & 0xFF, (ip >> 24) & 0xFF);
    lua_pushinteger(L, NW_ADAPTER_INDEX_LWIP_WIFI_STA);
    lua_call(L, 3, 0);
    return 0;
}

static int l_wlan_ip_lose_cb(lua_State *L, void *ptr) {
    (void)ptr;
    lua_getglobal(L, "sys_pub");
    if (!lua_isfunction(L, -1)) {
        return 0;
    }
    lua_pushliteral(L, "IP_LOSE");
    lua_pushinteger(L, NW_ADAPTER_INDEX_LWIP_WIFI_STA);
    lua_call(L, 2, 0);
    return 0;
}

// ========== Timer callbacks for async events ==========

static void mock_scan_done_timer_cb(uv_timer_t *t) {
    free_uv_handle(t);
    rtos_msg_t msg = {0};
    msg.handler = l_wlan_scan_done_cb;
    luat_msgbus_put(&msg, 0);
}

static void mock_sta_connected_timer_cb(uv_timer_t *t) {
    free_uv_handle(t);
    rtos_msg_t msg = {0};
    msg.handler = l_wlan_sta_connected_cb;
    luat_msgbus_put(&msg, 0);
}

static void mock_ip_ready_timer_cb(uv_timer_t *t) {
    free_uv_handle(t);
    // Get host real IP via libuv
    uv_interface_address_t *info = NULL;
    int count = 0;
    uint32_t ip_addr = 0xC0A80164; // fallback: 192.168.1.100
    uv_interface_addresses(&info, &count);
    for (int i = count - 1; i >= 0; i--) {
        if (!info[i].is_internal && info[i].address.address4.sin_family == 2 /* AF_INET */) {
            ip_addr = info[i].address.address4.sin_addr.s_addr;
            break;
        }
    }
    if (info) {
        uv_free_interface_addresses(info, count);
    }
    rtos_msg_t msg = {0};
    msg.handler = l_wlan_ip_ready_cb;
    msg.arg1 = 1;
    msg.arg2 = ip_addr;
    luat_msgbus_put(&msg, 0);
}

static void mock_sta_disconnected_timer_cb(uv_timer_t *t) {
    free_uv_handle(t);
    rtos_msg_t msg = {0};
    msg.handler = l_wlan_sta_disconnected_cb;
    luat_msgbus_put(&msg, 0);
}

static void mock_ip_lose_timer_cb(uv_timer_t *t) {
    free_uv_handle(t);
    rtos_msg_t msg = {0};
    msg.handler = l_wlan_ip_lose_cb;
    luat_msgbus_put(&msg, 0);
}

// Helper: start a one-shot libuv timer
static int start_oneshot_timer(uv_timer_cb cb, uint64_t delay_ms) {
    uv_timer_t *t = luat_heap_malloc(sizeof(uv_timer_t));
    if (t == NULL) return -1;
    memset(t, 0, sizeof(uv_timer_t));
    uv_timer_init(main_loop, t);
    uv_timer_start(t, cb, delay_ms, 0);
    return 0;
}

static int start_connect_timer(uv_timer_cb cb, uint64_t delay_ms, uint32_t seq, int reason) {
    mock_wlan_connect_timer_t *t = luat_heap_malloc(sizeof(mock_wlan_connect_timer_t));
    if (t == NULL) return -1;
    memset(t, 0, sizeof(mock_wlan_connect_timer_t));
    t->seq = seq;
    t->reason = reason;
    uv_timer_init(main_loop, &t->timer);
    uv_timer_start(&t->timer, cb, delay_ms, 0);
    return 0;
}

static void mock_wlan_clear_connected_state(void) {
    wlan_connected = 0;
    memset(wlan_ssid, 0, sizeof(wlan_ssid));
    memset(wlan_password, 0, sizeof(wlan_password));
    memset(wlan_bssid, 0, sizeof(wlan_bssid));
    wlan_rssi = 0;
}

static void mock_wlan_clear_pending_state(void) {
    memset(wlan_pending_ssid, 0, sizeof(wlan_pending_ssid));
    memset(wlan_pending_password, 0, sizeof(wlan_pending_password));
    memset(wlan_pending_bssid, 0, sizeof(wlan_pending_bssid));
    wlan_pending_rssi = 0;
}

static void mock_sta_connected_guard_timer_cb(uv_timer_t *t) {
    mock_wlan_connect_timer_t *ctx = (mock_wlan_connect_timer_t *)t;
    uint32_t seq = ctx->seq;
    free_uv_handle(t);
    if (seq != wlan_connect_seq || wlan_pending_ssid[0] == 0) {
        return;
    }
    wlan_connected = 1;
    memcpy(wlan_ssid, wlan_pending_ssid, sizeof(wlan_ssid));
    memcpy(wlan_password, wlan_pending_password, sizeof(wlan_password));
    memcpy(wlan_bssid, wlan_pending_bssid, sizeof(wlan_bssid));
    wlan_rssi = wlan_pending_rssi;
    rtos_msg_t msg = {0};
    msg.handler = l_wlan_sta_connected_cb;
    luat_msgbus_put(&msg, 0);
}

static void mock_ip_ready_guard_timer_cb(uv_timer_t *t) {
    mock_wlan_connect_timer_t *ctx = (mock_wlan_connect_timer_t *)t;
    uint32_t seq = ctx->seq;
    free_uv_handle(t);
    if (seq != wlan_connect_seq || !wlan_connected) {
        return;
    }
    uv_interface_address_t *info = NULL;
    int count = 0;
    uint32_t ip_addr = 0xC0A80164;
    uv_interface_addresses(&info, &count);
    for (int i = count - 1; i >= 0; i--) {
        if (!info[i].is_internal && info[i].address.address4.sin_family == 2) {
            ip_addr = info[i].address.address4.sin_addr.s_addr;
            break;
        }
    }
    if (info) {
        uv_free_interface_addresses(info, count);
    }
    rtos_msg_t msg = {0};
    msg.handler = l_wlan_ip_ready_cb;
    msg.arg1 = 1;
    msg.arg2 = ip_addr;
    luat_msgbus_put(&msg, 0);
}

static void mock_connfail_timer_cb(uv_timer_t *t) {
    mock_wlan_connect_timer_t *ctx = (mock_wlan_connect_timer_t *)t;
    uint32_t seq = ctx->seq;
    int reason = ctx->reason;
    free_uv_handle(t);
    if (seq != wlan_connect_seq) {
        return;
    }
    mock_wlan_clear_pending_state();
    rtos_msg_t msg = {0};
    msg.handler = l_wlan_sta_disconnected_cb;
    msg.arg1 = reason;
    luat_msgbus_put(&msg, 0);
}

// ========== Mock mode implementations ==========

static int mock_wlan_init(void) {
    wlan_inited = 1;
    wlan_mode = LUAT_WLAN_MODE_STA;
    wlan_connect_seq++;
    mock_wlan_clear_connected_state();
    mock_wlan_clear_pending_state();
    LLOGI("wlan mock init ok");
    return 0;
}

static int mock_wlan_scan(void) {
    if (!wlan_inited) {
        LLOGW("wlan not inited");
        return -1;
    }
    LLOGD("wlan mock scan start, will complete in 200ms");
    start_oneshot_timer(mock_scan_done_timer_cb, 200);
    return 0;
}

static int mock_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit) {
    size_t count = MOCK_AP_COUNT;
    if (count > ap_limit) count = ap_limit;
    memcpy(results, mock_scan_results, count * sizeof(luat_wlan_scan_result_t));
    return (int)count;
}

static int mock_wlan_connect(luat_wlan_conninfo_t* info) {
    int scan_index = -1;
    uint32_t seq = 0;

    if (!wlan_inited) {
        LLOGW("wlan not inited");
        return -1;
    }

    seq = ++wlan_connect_seq;
    mock_wlan_clear_connected_state();
    mock_wlan_clear_pending_state();
    for (size_t i = 0; i < MOCK_AP_COUNT; i++) {
        if (strcmp(info->ssid, mock_scan_results[i].ssid) == 0) {
            scan_index = (int)i;
            break;
        }
    }

    if (scan_index < 0) {
        LLOGW("wlan mock connect pending fail: ssid=%s not found, reason=%d", info->ssid, WIFI_REASON_NO_AP_FOUND);
        return start_connect_timer(mock_connfail_timer_cb, MOCK_CONNECT_FAIL_DELAY_MS, seq, WIFI_REASON_NO_AP_FOUND);
    }

    if (strcmp(info->ssid, "luatos1234") != 0 || strcmp(info->password, "12341234") != 0) {
        LLOGW("wlan mock connect pending fail: ssid=%s wrong password, reason=%d", info->ssid, WIFI_REASON_WRONG_PASSWORD);
        return start_connect_timer(mock_connfail_timer_cb, MOCK_CONNECT_FAIL_DELAY_MS, seq, WIFI_REASON_WRONG_PASSWORD);
    }

    LLOGI("wlan mock connect: ssid=%s, auth ok", info->ssid);
    memcpy(wlan_pending_ssid, info->ssid, sizeof(wlan_pending_ssid));
    memcpy(wlan_pending_password, info->password, sizeof(wlan_pending_password));
    memcpy(wlan_pending_bssid, mock_scan_results[scan_index].bssid, sizeof(wlan_pending_bssid));
    wlan_pending_rssi = mock_scan_results[scan_index].rssi;

    if (start_connect_timer(mock_sta_connected_guard_timer_cb, MOCK_CONNECT_SUCCESS_DELAY_MS, seq, 0) != 0) {
        mock_wlan_clear_pending_state();
        return -1;
    }
    if (start_connect_timer(mock_ip_ready_guard_timer_cb, MOCK_IP_READY_DELAY_MS, seq, 0) != 0) {
        mock_wlan_clear_pending_state();
        return -1;
    }
    return 0;
}

static int mock_wlan_disconnect(void) {
    wlan_connect_seq++;
    if (!wlan_connected) {
        mock_wlan_clear_pending_state();
        return 0;
    }
    LLOGI("wlan mock disconnect");
    mock_wlan_clear_connected_state();
    mock_wlan_clear_pending_state();

    // Async events: disconnected after 100ms, IP lose after 200ms
    start_oneshot_timer(mock_sta_disconnected_timer_cb, 100);
    start_oneshot_timer(mock_ip_lose_timer_cb, 200);
    return 0;
}

static int mock_wlan_ready(void) {
    return wlan_connected ? 1 : 0;
}

// ========== Public API: luat_wlan_* ==========

int luat_wlan_init(luat_wlan_config_t *conf) {
#if defined(LUAT_USE_WLAN_NATIVE) && defined(LUAT_USE_WINDOWS)
    return native_wlan_init();
#else
    (void)conf;
    return mock_wlan_init();
#endif
}

int luat_wlan_mode(luat_wlan_config_t *conf) {
    if (conf) {
        wlan_mode = conf->mode;
    }
    return 0;
}

int luat_wlan_ready(void) {
#if defined(LUAT_USE_WLAN_NATIVE) && defined(LUAT_USE_WINDOWS)
    return native_wlan_ready();
#else
    return mock_wlan_ready();
#endif
}

int luat_wlan_connect(luat_wlan_conninfo_t* info) {
#if defined(LUAT_USE_WLAN_NATIVE) && defined(LUAT_USE_WINDOWS)
    return native_wlan_connect(info);
#else
    return mock_wlan_connect(info);
#endif
}

int luat_wlan_disconnect(void) {
#if defined(LUAT_USE_WLAN_NATIVE) && defined(LUAT_USE_WINDOWS)
    return native_wlan_disconnect();
#else
    return mock_wlan_disconnect();
#endif
}

int luat_wlan_scan(void) {
#if defined(LUAT_USE_WLAN_NATIVE) && defined(LUAT_USE_WINDOWS)
    return native_wlan_scan();
#else
    return mock_wlan_scan();
#endif
}

int luat_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit) {
#if defined(LUAT_USE_WLAN_NATIVE) && defined(LUAT_USE_WINDOWS)
    return native_wlan_scan_get_result(results, ap_limit);
#else
    return mock_wlan_scan_get_result(results, ap_limit);
#endif
}

int luat_wlan_set_station_ip(luat_wlan_station_info_t *info) {
    (void)info;
    LLOGI("wlan set_station_ip (mock, ignored)");
    return 0;
}

int luat_wlan_smartconfig_start(int tp) {
    (void)tp;
    LLOGW("smartconfig not supported on PC simulator");
    return -1;
}

int luat_wlan_smartconfig_stop(void) {
    LLOGW("smartconfig not supported on PC simulator");
    return -1;
}

int luat_wlan_get_mac(int id, char* mac) {
    (void)id;
    if (mac) {
        memcpy(mac, wlan_mac, 6);
    }
    return 0;
}

int luat_wlan_set_mac(int id, const char* mac) {
    (void)id;
    if (mac) {
        memcpy(wlan_mac, mac, 6);
    }
    return 0;
}

int luat_wlan_get_ip(int type, char* data) {
    (void)type;
    if (!data) return -1;
    if (!wlan_connected) {
        data[0] = 0;
        return -1;
    }
    // Get host real IP via libuv
    uv_interface_address_t *info = NULL;
    int count = 0;
    uv_interface_addresses(&info, &count);
    for (int i = count - 1; i >= 0; i--) {
        if (!info[i].is_internal && info[i].address.address4.sin_family == 2 /* AF_INET */) {
            uint32_t ip = info[i].address.address4.sin_addr.s_addr;
            sprintf_(data, "%d.%d.%d.%d", (ip) & 0xFF, (ip >> 8) & 0xFF, (ip >> 16) & 0xFF, (ip >> 24) & 0xFF);
            uv_free_interface_addresses(info, count);
            return 0;
        }
    }
    if (info) uv_free_interface_addresses(info, count);
    strcpy(data, "192.168.1.100");
    return 0;
}

const char* luat_wlan_get_hostname(int id) {
    (void)id;
    return wlan_hostname;
}

int luat_wlan_set_hostname(int id, const char* hostname) {
    (void)id;
    if (hostname && strlen(hostname) < sizeof(wlan_hostname)) {
        memset(wlan_hostname, 0, sizeof(wlan_hostname));
        strncpy(wlan_hostname, hostname, sizeof(wlan_hostname) - 1);
    }
    return 0;
}

int luat_wlan_set_ps(int mode) {
    wlan_ps_mode = mode;
    return 0;
}

int luat_wlan_get_ps(void) {
    return wlan_ps_mode;
}

int luat_wlan_get_ap_bssid(char* buff) {
    if (!wlan_connected || !buff) {
        if (buff) buff[0] = 0;
        return -1;
    }
    memcpy(buff, wlan_bssid, 6);
    return 0;
}

int luat_wlan_get_ap_rssi(void) {
    if (!wlan_connected) return 0;
    return wlan_rssi;
}

int luat_wlan_get_ap_gateway(char* buff) {
    if (!buff) return -1;
    if (!wlan_connected) {
        buff[0] = 0;
        return -1;
    }
    strcpy(buff, "192.168.1.1");
    return 0;
}

int luat_wlan_ap_start(luat_wlan_apinfo_t *apinfo) {
    if (!apinfo) return -1;
    LLOGI("wlan AP start (mock): ssid=%s", apinfo->ssid);
    wlan_ap_active = 1;
    memcpy(wlan_ap_ssid, apinfo->ssid, sizeof(wlan_ap_ssid));
    memcpy(wlan_ap_password, apinfo->password, sizeof(wlan_ap_password));
    if (apinfo->gateway[0]) memcpy(wlan_ap_gateway, apinfo->gateway, 4);
    if (apinfo->netmask[0]) memcpy(wlan_ap_netmask, apinfo->netmask, 4);
    return 0;
}

int luat_wlan_ap_stop(void) {
    LLOGI("wlan AP stop (mock)");
    wlan_ap_active = 0;
    memset(wlan_ap_ssid, 0, sizeof(wlan_ap_ssid));
    return 0;
}

// =====================================
// wifiscan stubs (for cellular modules)
// =====================================

int32_t luat_get_wifiscan_cell_info(luat_wifiscan_set_info_t *set_info, luat_wifisacn_get_info_t* get_info) {
    (void)set_info;
    (void)get_info;
    return -1;
}

int luat_wlan_scan_nonblock(luat_wifiscan_set_info_t *set_info) {
    (void)set_info;
    return -1;
}

// ============================================================
// Native mode (Windows) - controlled by LUAT_USE_WLAN_NATIVE
// ============================================================

#if defined(LUAT_USE_WLAN_NATIVE) && defined(LUAT_USE_WINDOWS)

#include <windows.h>
#include <wlanapi.h>
#include <wtypes.h>

#pragma comment(lib, "wlanapi.lib")
#pragma comment(lib, "ole32.lib")

static HANDLE hWlanClient = NULL;
static GUID wlanInterfaceGuid = {0};
static int wlanNativeInited = 0;

// Scan results cache
#define NATIVE_SCAN_MAX 32
static luat_wlan_scan_result_t native_scan_cache[NATIVE_SCAN_MAX];
static int native_scan_count = 0;

static void WINAPI wlan_notification_callback(PWLAN_NOTIFICATION_DATA pData, PVOID pCtx) {
    (void)pCtx;
    if (pData == NULL) return;
    if (pData->NotificationSource != WLAN_NOTIFICATION_SOURCE_ACM) return;

    switch (pData->NotificationCode) {
        case wlan_notification_acm_scan_complete: {
            LLOGD("native wlan scan complete");
            rtos_msg_t msg = {0};
            msg.handler = l_wlan_scan_done_cb;
            luat_msgbus_put(&msg, 0);
            break;
        }
        case wlan_notification_acm_connection_complete: {
            LLOGD("native wlan connected");
            wlan_connected = 1;
            rtos_msg_t msg = {0};
            msg.handler = l_wlan_sta_connected_cb;
            luat_msgbus_put(&msg, 0);
            // Delay IP_READY
            start_oneshot_timer(mock_ip_ready_timer_cb, 500);
            break;
        }
        case wlan_notification_acm_disconnected: {
            LLOGD("native wlan disconnected");
            wlan_connected = 0;
            rtos_msg_t msg = {0};
            msg.handler = l_wlan_sta_disconnected_cb;
            luat_msgbus_put(&msg, 0);
            rtos_msg_t msg2 = {0};
            msg2.handler = l_wlan_ip_lose_cb;
            luat_msgbus_put(&msg2, 0);
            break;
        }
        default:
            break;
    }
}

static int native_wlan_init(void) {
    DWORD dwMaxClient = 2;
    DWORD dwCurVersion = 0;
    DWORD dwResult = 0;

    dwResult = WlanOpenHandle(dwMaxClient, NULL, &dwCurVersion, &hWlanClient);
    if (dwResult != ERROR_SUCCESS) {
        LLOGE("WlanOpenHandle failed: %lu", dwResult);
        return -1;
    }

    PWLAN_INTERFACE_INFO_LIST pIfList = NULL;
    dwResult = WlanEnumInterfaces(hWlanClient, NULL, &pIfList);
    if (dwResult != ERROR_SUCCESS || pIfList == NULL || pIfList->dwNumberOfItems == 0) {
        LLOGE("No wireless interfaces found");
        if (pIfList) WlanFreeMemory(pIfList);
        WlanCloseHandle(hWlanClient, NULL);
        hWlanClient = NULL;
        return -1;
    }

    memcpy(&wlanInterfaceGuid, &pIfList->InterfaceInfo[0].InterfaceGuid, sizeof(GUID));
    LLOGI("native wlan init ok, interface: %ls", pIfList->InterfaceInfo[0].strInterfaceDescription);
    WlanFreeMemory(pIfList);

    // Register notification callback
    dwResult = WlanRegisterNotification(hWlanClient,
        WLAN_NOTIFICATION_SOURCE_ACM, TRUE,
        wlan_notification_callback, NULL, NULL, NULL);
    if (dwResult != ERROR_SUCCESS) {
        LLOGW("WlanRegisterNotification failed: %lu", dwResult);
    }

    wlanNativeInited = 1;
    wlan_inited = 1;
    wlan_mode = LUAT_WLAN_MODE_STA;
    return 0;
}

static int native_wlan_scan(void) {
    if (!wlanNativeInited) return -1;
    DWORD dwResult = WlanScan(hWlanClient, &wlanInterfaceGuid, NULL, NULL, NULL);
    if (dwResult != ERROR_SUCCESS) {
        LLOGE("WlanScan failed: %lu", dwResult);
        return -1;
    }
    LLOGD("native wlan scan started");
    return 0;
}

static int native_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit) {
    if (!wlanNativeInited) return 0;

    PWLAN_BSS_LIST pBssList = NULL;
    DWORD dwResult = WlanGetNetworkBssList(hWlanClient, &wlanInterfaceGuid,
        NULL, dot11_BSS_type_any, FALSE, NULL, &pBssList);
    if (dwResult != ERROR_SUCCESS || pBssList == NULL) {
        LLOGW("WlanGetNetworkBssList failed: %lu", dwResult);
        return 0;
    }

    int count = 0;
    for (DWORD i = 0; i < pBssList->dwNumberOfItems && (size_t)count < ap_limit; i++) {
        WLAN_BSS_ENTRY *pEntry = &pBssList->wlanBssEntries[i];
        memset(&results[count], 0, sizeof(luat_wlan_scan_result_t));

        // SSID
        size_t ssid_len = pEntry->dot11Ssid.uSSIDLength;
        if (ssid_len > 32) ssid_len = 32;
        memcpy(results[count].ssid, pEntry->dot11Ssid.ucSSID, ssid_len);

        // BSSID
        memcpy(results[count].bssid, pEntry->dot11Bssid, 6);

        // RSSI
        results[count].rssi = (int16_t)pEntry->lRssi;

        // Channel - approximate from frequency
        ULONG freq = pEntry->ulChCenterFrequency / 1000; // MHz
        if (freq >= 2412 && freq <= 2484) {
            results[count].ch = (uint8_t)((freq - 2407) / 5);
        } else if (freq >= 5180) {
            results[count].ch = (uint8_t)((freq - 5000) / 5);
        }

        count++;
    }

    WlanFreeMemory(pBssList);
    return count;
}

static int native_wlan_connect(luat_wlan_conninfo_t* info) {
    if (!wlanNativeInited) return -1;

    // Build a temporary profile XML
    char profileXml[2048] = {0};
    const char* auth = (strlen(info->password) > 0) ? "WPA2PSK" : "open";
    const char* enc = (strlen(info->password) > 0) ? "AES" : "none";
    const char* keyType = (strlen(info->password) > 0) ? "passPhrase" : "networkKey";

    if (strlen(info->password) > 0) {
        snprintf(profileXml, sizeof(profileXml),
            "<?xml version=\"1.0\"?>"
            "<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">"
            "<name>%s</name>"
            "<SSIDConfig><SSID><name>%s</name></SSID></SSIDConfig>"
            "<connectionType>ESS</connectionType>"
            "<connectionMode>manual</connectionMode>"
            "<MSM><security>"
            "<authEncryption><authentication>%s</authentication><encryption>%s</encryption><useOneX>false</useOneX></authEncryption>"
            "<sharedKey><keyType>%s</keyType><protected>false</protected><keyMaterial>%s</keyMaterial></sharedKey>"
            "</security></MSM>"
            "</WLANProfile>",
            info->ssid, info->ssid, auth, enc, keyType, info->password);
    } else {
        snprintf(profileXml, sizeof(profileXml),
            "<?xml version=\"1.0\"?>"
            "<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">"
            "<name>%s</name>"
            "<SSIDConfig><SSID><name>%s</name></SSID></SSIDConfig>"
            "<connectionType>ESS</connectionType>"
            "<connectionMode>manual</connectionMode>"
            "<MSM><security>"
            "<authEncryption><authentication>%s</authentication><encryption>%s</encryption><useOneX>false</useOneX></authEncryption>"
            "</security></MSM>"
            "</WLANProfile>",
            info->ssid, info->ssid, auth, enc);
    }

    // Convert to wide string
    int wlen = MultiByteToWideChar(CP_UTF8, 0, profileXml, -1, NULL, 0);
    WCHAR *wProfileXml = luat_heap_malloc(wlen * sizeof(WCHAR));
    if (!wProfileXml) return -1;
    MultiByteToWideChar(CP_UTF8, 0, profileXml, -1, wProfileXml, wlen);

    // Set the profile
    DWORD dwReasonCode = 0;
    DWORD dwResult = WlanSetProfile(hWlanClient, &wlanInterfaceGuid, 0, wProfileXml, NULL, TRUE, NULL, &dwReasonCode);
    luat_heap_free(wProfileXml);

    if (dwResult != ERROR_SUCCESS) {
        LLOGE("WlanSetProfile failed: %lu, reason: %lu", dwResult, dwReasonCode);
        return -1;
    }

    // Now connect
    // Convert SSID to DOT11_SSID
    DOT11_SSID dot11Ssid = {0};
    dot11Ssid.uSSIDLength = (ULONG)strlen(info->ssid);
    memcpy(dot11Ssid.ucSSID, info->ssid, dot11Ssid.uSSIDLength);

    // Convert ssid to wide string for profile name
    int wNameLen = MultiByteToWideChar(CP_UTF8, 0, info->ssid, -1, NULL, 0);
    WCHAR *wSsid = luat_heap_malloc(wNameLen * sizeof(WCHAR));
    if (!wSsid) return -1;
    MultiByteToWideChar(CP_UTF8, 0, info->ssid, -1, wSsid, wNameLen);

    WLAN_CONNECTION_PARAMETERS connParams = {0};
    connParams.wlanConnectionMode = wlan_connection_mode_profile;
    connParams.strProfile = wSsid;
    connParams.pDot11Ssid = &dot11Ssid;
    connParams.dot11BssType = dot11_BSS_type_infrastructure;

    memcpy(wlan_ssid, info->ssid, sizeof(wlan_ssid));
    memcpy(wlan_password, info->password, sizeof(wlan_password));

    dwResult = WlanConnect(hWlanClient, &wlanInterfaceGuid, &connParams, NULL);
    luat_heap_free(wSsid);

    if (dwResult != ERROR_SUCCESS) {
        LLOGE("WlanConnect failed: %lu", dwResult);
        return -1;
    }

    LLOGI("native wlan connecting to %s", info->ssid);
    return 0;
}

static int native_wlan_disconnect(void) {
    if (!wlanNativeInited) return -1;
    DWORD dwResult = WlanDisconnect(hWlanClient, &wlanInterfaceGuid, NULL);
    if (dwResult != ERROR_SUCCESS) {
        LLOGE("WlanDisconnect failed: %lu", dwResult);
        return -1;
    }
    return 0;
}

static int native_wlan_ready(void) {
    return wlan_connected ? 1 : 0;
}

#endif // LUAT_USE_WLAN_NATIVE && LUAT_USE_WINDOWS
