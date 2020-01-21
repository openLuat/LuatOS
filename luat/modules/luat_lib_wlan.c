
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "rtthread.h"

#ifdef RT_WLAN_MANAGE_ENABLE
#include "wlan_dev.h"
#include <wlan_mgnt.h>
#include <wlan_prot.h>
#include <wlan_cfg.h>

static int l_wlan_get_mode(lua_State *L) {
    rt_device_t dev = rt_device_find(luaL_checkstring(L, 1));
    if (dev == RT_NULL) {
        return 0;
    }
    int mode = rt_wlan_get_mode(dev);
    lua_pushinteger(L, mode);
    return 1;
}

static int l_wlan_set_mode(lua_State *L) {
    rt_device_t dev = rt_device_find(luaL_checkstring(L, 1));
    if (dev == RT_NULL) {
        return 0;
    }
    int mode = luaL_checkinteger(L, 2);
    int re = rt_wlan_set_mode(dev, mode);
    lua_pushinteger(L, re);
    return 1;
}

static int l_wlan_join(lua_State *L) {
    const char* ssid = luaL_checkstring(L, 1);
    if (lua_isstring(L, 2)) {
        const char* passwd = luaL_checkstring(L, 2);
        int re = rt_wlan_connect(ssid, passwd);
        lua_pushinteger(L, re);
    }
    else {
        int re = rt_wlan_connect(ssid, RT_NULL);
        lua_pushinteger(L, re);
    }
    return 1;
}

static int l_wlan_disconnect(lua_State *L) {
    if (rt_wlan_is_connected()) {
        rt_wlan_disconnect();
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

static int l_wlan_connected(lua_State *L) {
    lua_pushboolean(L, rt_wlan_is_connected() == 1 ? 1 : 0);
    return 1;
}

static int l_wlan_autoreconnect(lua_State *L) {
    if (lua_gettop(L) > 0) {
        rt_wlan_config_autoreconnect(luaL_checkinteger(L, 1));
        return 0;
    }
    else {
        lua_pushboolean(L, rt_wlan_get_autoreconnect_mode());
        return 1;
    }
}

static int l_wlan_scan(lua_State *L) {
    lua_pushinteger(L, rt_wlan_scan());
    return 1;
}

static int l_wlan_scan_get_info_num(lua_State *L) {
    lua_pushinteger(L, rt_wlan_scan_get_info_num());
    return 1;
}

static int l_wlan_scan_get_info(lua_State *L) {
    //rt_wlan_ap_get_sta_info();
    return 0;
}

// MAC地址
// static int l_wlan_get_mac(lua_State *L) {
//     char mac[16] = {0};
//     rt_wlan_get_mac(&mac[0]);
//     if (mac[0] != 0x00) {
//         lua_pushstring(L, mac);
//         return 1;
//     }
//     return 0;
// }

static int l_wlan_ready(lua_State *L) {
    lua_pushinteger(L, rt_wlan_is_ready());
    return 1;
}

// 注册回调
static void wlan_cb(int event, struct rt_wlan_buff *buff, void *parameter) {
    rt_kprintf("wlan event -> %d\n", event);
}
static void reg_wlan_callbacks(void) {
    rt_wlan_register_event_handler(RT_WLAN_EVT_READY, wlan_cb, RT_NULL);
    rt_wlan_register_event_handler(RT_WLAN_EVT_SCAN_DONE, wlan_cb, RT_NULL);
    //rt_wlan_register_event_handler(RT_WLAN_EVT_SCAN_REPORT, wlan_cb, RT_NULL);
    rt_wlan_register_event_handler(RT_WLAN_EVT_STA_CONNECTED, wlan_cb, RT_NULL);
    rt_wlan_register_event_handler(RT_WLAN_EVT_STA_CONNECTED_FAIL, wlan_cb, RT_NULL);
    rt_wlan_register_event_handler(RT_WLAN_EVT_STA_DISCONNECTED, wlan_cb, RT_NULL);
    rt_wlan_register_event_handler(RT_WLAN_EVT_AP_START, wlan_cb, RT_NULL);
    rt_wlan_register_event_handler(RT_WLAN_EVT_AP_STOP, wlan_cb, RT_NULL);
    rt_wlan_register_event_handler(RT_WLAN_EVT_AP_ASSOCIATED, wlan_cb, RT_NULL);
    rt_wlan_register_event_handler(RT_WLAN_EVT_AP_DISASSOCIATED, wlan_cb, RT_NULL);
}


static const luaL_Reg reg_wlan[] =
{
    { "getMode" ,  l_wlan_get_mode },
    { "setMode" ,  l_wlan_set_mode },
    { "join" ,     l_wlan_join },
    { "disconnect",l_wlan_disconnect },
    { "connected" ,l_wlan_connected },
    { "ready" ,    l_wlan_ready },
    { "autoreconnect", l_wlan_autoreconnect},
    { "scan",      l_wlan_scan},
    { "scan_get_info_num", l_wlan_scan_get_info_num},
    { "scan_get_info", l_wlan_scan_get_info},
    // { "get_mac", l_wlan_get_mac},
    //{ "set_mac", l_wlan_set_mac},
    
    { "NONE",      NULL },
    { "STATION",   NULL },
    { "AP",        NULL },
	{ NULL, NULL }
};

LUAMOD_API int luaopen_wlan( lua_State *L ) {
    reg_wlan_callbacks();

    luaL_newlib(L, reg_wlan);

    // netmode
    lua_pushnumber(L, RT_WLAN_NONE);
    lua_setfield(L, -2, "NONE");
    lua_pushnumber(L, RT_WLAN_STATION);
    lua_setfield(L, -2, "STATION");
    lua_pushnumber(L, RT_WLAN_AP);
    lua_setfield(L, -2, "AP");

    return 1;
}

#else

static const luaL_Reg reg_wlan[] =
{
	{ NULL, NULL }
};

LUAMOD_API int luaopen_wlan( lua_State *L ) {
    luaL_newlib(L, reg_wlan);
    return 1;
}

#endif
