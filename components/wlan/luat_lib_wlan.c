#include "luat_base.h"
#include "luat_wlan.h"

#define LUAT_LOG_TAG "wlan"
#include "luat_log.h"

static int l_wlan_init(lua_State* L){
    luat_wlan_init(NULL);
    return 0;
}

static int l_wlan_mode(lua_State* L){
    int mode = LUAT_WLAN_MODE_STA;
    if (lua_isinteger(L, 1)) {
        mode = lua_tointeger(L, 1);
    }
    else if (lua_isinteger(L, 2)) {
        mode = lua_tointeger(L, 2);
    }

    if (mode <= LUAT_WLAN_MODE_NULL || mode >= LUAT_WLAN_MODE_MAX) {
        mode = LUAT_WLAN_MODE_STA;
    }

    // switch (mode)
    // {
    // case LUAT_WLAN_MODE_NULL:
    //     LLOGD("wlan mode NULL");
    //     break;
    // case LUAT_WLAN_MODE_STA:
    //     LLOGD("wlan mode STATION");
    //     break;
    // case LUAT_WLAN_MODE_AP:
    //     LLOGD("wlan mode AP");
    //     break;
    // case LUAT_WLAN_MODE_APSTA:
    //     LLOGD("wlan mode AP-STATION");
    //     break;
    
    // default:
    //     break;
    // }
    luat_wlan_config_t conf = {
        .mode = mode
    };
    luat_wlan_mode(&conf);
    return 0;
}

static int l_wlan_ready(lua_State* L){
    lua_pushboolean(L, luat_wlan_ready());
    return 1;
}

static int l_wlan_connect(lua_State* L){
    const char* ssid = luaL_checkstring(L, 1);
    const char* password = luaL_optstring(L, 2, "");
    luat_wlan_conninfo_t info = {0};
    memcpy(info.ssid, ssid, strlen(ssid));
    memcpy(info.password, password, strlen(password));

    luat_wlan_connect(&info);
    return 0;
}

static int l_wlan_disconnect(lua_State* L){
    luat_wlan_disconnect();
    return 0;
}

static int l_wlan_scan(lua_State* L){
    luat_wlan_scan();
    return 0;
}

static int l_wlan_scan_result(lua_State* L) {
    int ap_limit = luaL_optinteger(L, 1, 20);
    if (ap_limit > 32)
        ap_limit = 32;
    else if (ap_limit < 8)
        ap_limit = 8;
    lua_newtable(L);
    luat_wlan_scan_result_t *results = luat_heap_malloc(sizeof(luat_wlan_scan_result_t) * ap_limit);
    if (results == NULL) {
        LLOGE("out of memory when malloc scan result");
        return 1;
    }
    memset(results, 0, sizeof(luat_wlan_scan_result_t) * ap_limit);
    int len = luat_wlan_scan_get_result(results, ap_limit);
    for (size_t i = 0; i < len; i++)
    {
        lua_newtable(L);

        lua_pushstring(L, (const char *)results[i].ssid);
        lua_setfield(L, -2, "ssid");

        // lua_pushfstring(L, "%02X%02X%02X%02X%02X%02X", results[i].bssid[0], 
        //                                                results[i].bssid[1], 
        //                                                results[i].bssid[2], 
        //                                                results[i].bssid[3], 
        //                                                results[i].bssid[4], 
        //                                                results[i].bssid[5]);
        lua_pushlstring(L, (const char *)results[i].bssid, 6);
        lua_setfield(L, -2, "bssid");

        lua_pushinteger(L, results[i].ch);
        lua_setfield(L, -2, "channel");

        lua_pushinteger(L, results[i].rssi);
        lua_setfield(L, -2, "rssi");

        lua_seti(L, -2, i + 1);
    }
    luat_heap_free(results);
    return 1;
}

static int l_wlan_smartconfig(lua_State *L) {
    int tp = luaL_optinteger(L, 1, LUAT_SC_TYPE_ESPTOUCH);
    if (tp == LUAT_SC_TYPE_STOP) {
        luat_wlan_smartconfig_stop();
        return 0;
    }
    else {
        int ret = luat_wlan_smartconfig_start(tp);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        return 1;
    }
}

// 获取mac
static int l_wlan_get_mac(lua_State* L){
    char tmp[6] = {0};
    char tmpbuff[16] = {0};
    luat_wlan_get_mac(luaL_optinteger(L, 1, 0), tmp);
    sprintf_(tmpbuff, "%02X%02X%02X%02X%02X%02X", tmp[0], tmp[1], tmp[2], tmp[3], tmp[4], tmp[5]);
    lua_pushstring(L, tmpbuff);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_wlan[] =
{
    { "init",               ROREG_FUNC(l_wlan_init)},
    { "mode",               ROREG_FUNC(l_wlan_mode)},
    { "setMode",            ROREG_FUNC(l_wlan_mode)},
    // { "setMode",           ROREG_FUNC(l_wlan_set_mode)},
    // { "getMode",           ROREG_FUNC(l_wlan_get_mode)},
    { "ready",              ROREG_FUNC(l_wlan_ready)},
    { "connect",            ROREG_FUNC(l_wlan_connect)},
    { "disconnect",         ROREG_FUNC(l_wlan_disconnect)},
    { "scan",               ROREG_FUNC(l_wlan_scan)},
    { "scanResult",         ROREG_FUNC(l_wlan_scan_result)},

    // 配网相关
    { "smartconfig",         ROREG_FUNC(l_wlan_smartconfig)},

    { "getMac",              ROREG_FUNC(l_wlan_get_mac)},

    // 常数
    {"NONE",                ROREG_INT(LUAT_WLAN_MODE_NULL)},
    {"STATION",             ROREG_INT(LUAT_WLAN_MODE_STA)},
    {"AP",                  ROREG_INT(LUAT_WLAN_MODE_AP)},
    {"STATIONAP",           ROREG_INT(LUAT_WLAN_MODE_APSTA)},

    // smartconfig 配网
    {"STOP",                ROREG_INT(0)},
    {"ESPTOUCH",            ROREG_INT(LUAT_SC_TYPE_ESPTOUCH)},
    {"AIRKISS",             ROREG_INT(LUAT_SC_TYPE_AIRKISS)},
    {"ESPTOUCH_AIRKISS",    ROREG_INT(LUAT_SC_TYPE_ESPTOUCH_AIRKISS)},
    {"ESPTOUCH_V2",         ROREG_INT(LUAT_SC_TYPE_ESPTOUCH_V2)},
	{ NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_wlan( lua_State *L ) {
    luat_newlib2(L, reg_wlan);
    return 1;
}
