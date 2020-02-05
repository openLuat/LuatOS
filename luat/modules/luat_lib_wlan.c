
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

#ifdef WM_USING_ONESHOT
#include "oneshot.h"
#endif

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

typedef struct join_info
{
    char ssid[64];
    char passwd[64];
} join_info_t;
static join_info_t jinfo = {0};


static void _wlan_connect(void* params) {
    rt_wlan_connect(jinfo.ssid, jinfo.passwd);
}
static int l_wlan_connect(lua_State *L) {
    //强制GC一次
    lua_gc(L, LUA_GCCOLLECT, 0);
    // 更新参数
    size_t len;
    const char* _ssid = luaL_checklstring(L, 1, &len);
    rt_strncpy(jinfo.ssid, _ssid, len);
    jinfo.ssid[len] = 0x00;
    if (lua_isstring(L, 2)) {
        const char* _passwd = luaL_checklstring(L, 2, &len);
        rt_strncpy(jinfo.passwd, _passwd, len);
        jinfo.passwd[len] = 0x00;
    }
    else {
        jinfo.passwd[0] = 0x00;
    }
    rt_thread_t t = rt_thread_create("wlanj", _wlan_connect, RT_NULL, 1024, 20, 20);
    if (t == RT_NULL) {
        lua_pushinteger(L, 1);
        lua_pushstring(L, "fail to create wlan thread");
        return 2;
    }
    if (rt_thread_startup(t) != RT_EOK) {
        lua_pushinteger(L, 2);
        lua_pushstring(L, "fail to start wlan thread");
        return 2;
    }
    return 0;
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

//MAC地址
static int l_wlan_get_mac(lua_State *L) {
    rt_uint8_t mac[6];
    char buff[14];
    mac[0] = 0x00;
    rt_wlan_get_mac(mac);
    if (mac[0] != 0x00) {
        rt_snprintf(buff, 14, "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        lua_pushlstring(L, buff, 12);
        return 1;
    }
    return 0;
}

//MAC地址
static int l_wlan_get_mac_raw(lua_State *L) {
    rt_uint8_t mac[6];
    mac[0] = 0x00;
    rt_wlan_get_mac(mac);
    if (mac[0] != 0x00) {
        lua_pushlstring(L, mac, 6);
        return 1;
    }
    return 0;
}

static int l_wlan_ready(lua_State *L) {
    lua_pushinteger(L, rt_wlan_is_ready());
    return 1;
}

static int l_wlan_handler(lua_State* L, void* ptr) {
    int event = (int)ptr;
    lua_getglobal(L, "sys_pub");
    if (lua_isnil(L, -1)) {
        lua_pushinteger(L, 0);
        return 1;
    }
    switch (event)
    {
    case RT_WLAN_EVT_READY:
        lua_pushstring(L, "WLAN_READY");
        lua_call(L, 1, 0);
        break;
    case RT_WLAN_EVT_SCAN_DONE:
        lua_pushstring(L, "WLAN_SCAN_DONE");
        lua_call(L, 1, 0);
        break;
    case RT_WLAN_EVT_STA_CONNECTED:
        lua_pushstring(L, "WLAN_STA_CONNECTED");
        lua_pushinteger(L, 1);
        lua_call(L, 2, 0);
        break;
    case RT_WLAN_EVT_STA_CONNECTED_FAIL:
        lua_pushstring(L, "WLAN_STA_CONNECTED");
        lua_pushinteger(L, 0);
        lua_call(L, 2, 0);
        break;
    case RT_WLAN_EVT_STA_DISCONNECTED:
        lua_pushstring(L, "WLAN_STA_DISCONNECTED");
        lua_call(L, 1, 0);
        break;
    case RT_WLAN_EVT_AP_START:
        lua_pushstring(L, "WLAN_AP_START");
        lua_call(L, 1, 0);
        break;
    case RT_WLAN_EVT_AP_STOP:
        lua_pushstring(L, "WLAN_AP_STOP");
        lua_call(L, 1, 0);
        break;
    case RT_WLAN_EVT_AP_ASSOCIATED:
        lua_pushstring(L, "WLAN_AP_ASSOCIATED");
        lua_call(L, 1, 0);
        break;
    case RT_WLAN_EVT_AP_DISASSOCIATED:
        lua_pushstring(L, "WLAN_AP_DISASSOCIATED");
        lua_call(L, 1, 0);
        break;
    
    default:
        break;
    }
    lua_pushinteger(L, 0);
    return 1;
}

// 注册回调
static void wlan_cb(int event, struct rt_wlan_buff *buff, void *parameter) {
    rt_kprintf("wlan event -> %d\n", event);
    rtos_msg_t msg;
    msg.handler = l_wlan_handler;
    msg.ptr = (void*)event;
    luat_msgbus_put(&msg, 1);
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

// ----------------------------
//-----------------------------
static int luat_PW_msghandler(lua_State *L, void* ptr) {
    lua_getglobal(L, "sys_pub");
    if (!lua_isnil(L, -1)) {
        lua_pushstring(L, "WLAN_PW_RE");
        if (ptr == RT_NULL) {
            lua_call(L, 1, 0);
        }
        else {
            lua_pushstring(L, jinfo.ssid);
            lua_pushstring(L, jinfo.passwd);
            lua_call(L, 3, 0);
        }
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

static void _PW_callback(int state, unsigned char *_ssid, unsigned char *_passwd) {
    rt_kprintf("oneshot/airkiss callback state=%ld\n", state);
    if (_ssid != RT_NULL) {
        rt_kprintf("oneshot/airkiss ssid %s\n", _ssid);
    }
    if (_passwd != RT_NULL) {
        rt_kprintf("oneshot/airkiss key %s\n", _passwd);
    }
    rt_memset(&jinfo, 0, sizeof(struct join_info));
    if (state == 0) {
        rt_strncpy(jinfo.ssid, _ssid, rt_strlen(_ssid));
        if (_passwd)
        {
            rt_strncpy(jinfo.passwd, _passwd, rt_strlen(_passwd));
        }
    }
    
    // 发送msgbus消息
    rtos_msg_t msg;
    msg.handler = luat_PW_msghandler;
    msg.ptr = state == 0 ? (void*)1 : RT_NULL;
    luat_msgbus_put(&msg, 1);
}

//--------------------------
#ifdef WM_USING_ONESHOT
static int32_t oneshot_autojoin = 0;
static int32_t oneshot_re;


static int l_wlan_oneshot_start(lua_State *L) {
    WM_ONESHOT_MODE mode = (WM_ONESHOT_MODE)luaL_optinteger(L, 1, WM_UDP);
    oneshot_autojoin = luaL_optinteger(L, 2, 1);
    rt_kprintf("oneshot mode=%d\n", mode);
    int re = wm_oneshot_start(mode, _PW_callback);
    rt_kprintf("oneshot re=%ld\n", re);
    lua_pushinteger(L, re);
    return 1;
}
static int l_wlan_oneshot_stop(lua_State *L) {
    wm_oneshot_stop();
    return 0;
}
static int l_wlan_oneshot_state(lua_State *L) {
    lua_pushinteger(L, wm_oneshot_get());
    return 1;
}
#endif
//--------------------------

static int l_wlan_join_info(lua_State *L) {
    if (jinfo.ssid[0] != RT_NULL) {
        lua_pushstring(L, jinfo.ssid);
        if (jinfo.passwd[0] != RT_NULL) {
            lua_pushstring(L, jinfo.passwd);
            return 2;
        }
        return 1;
    }
    return 0;
}

// airkiss open

static int l_wlan_airkiss_start(lua_State* L){
    rt_wlan_set_mode("wlan0", RT_WLAN_STATION);
    airkiss_set_callback(_PW_callback);
    lua_pushinteger(L, airkiss_start());
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_wlan[] =
{
    { "getMode" ,  l_wlan_get_mode , 0},
    { "setMode" ,  l_wlan_set_mode , 0},
    { "connect" ,     l_wlan_connect , 0},
    { "disconnect",l_wlan_disconnect , 0},
    { "connected" ,l_wlan_connected , 0},
    { "ready" ,    l_wlan_ready , 0},
    { "autoreconnect", l_wlan_autoreconnect, 0},
    { "scan",      l_wlan_scan, 0},
    { "scan_get_info_num", l_wlan_scan_get_info_num, 0},
    { "scan_get_info", l_wlan_scan_get_info, 0},
    { "get_mac", l_wlan_get_mac, 0},
    { "get_mac_raw", l_wlan_get_mac_raw, 0},
    //{ "set_mac", l_wlan_set_mac},
    // ---- oneshot
    #ifdef WM_USING_ONESHOT
    { "oneshotStart" ,  l_wlan_oneshot_start , 0},
    { "oneshotStop" ,   l_wlan_oneshot_stop ,  0},
    { "oneshotState" ,  l_wlan_oneshot_state , 0},
    #endif
    { "lastInfo" ,      l_wlan_join_info , 0},
    { "airkiss_start",  l_wlan_airkiss_start, 0},
    // ---
    
    { "NONE",      NULL , RT_WLAN_NONE},
    { "STATION",   NULL , RT_WLAN_STATION},
    { "AP",        NULL , RT_WLAN_AP},
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_wlan( lua_State *L ) {
    reg_wlan_callbacks();

    rotable_newlib(L, reg_wlan);

    return 1;
}

#endif
