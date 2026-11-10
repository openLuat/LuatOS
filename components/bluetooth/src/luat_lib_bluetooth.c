/*
@module  bluetooth
@summary 蓝牙(总库)
@version 1.0
@date    2025.6.21
@usage
-- 本库用于初始化/反初始化整个蓝牙模块, 以及创建BLE对象(低功耗蓝牙)/BT对象(经典蓝牙)
-- 当前仅支持BLE, 经典蓝牙未实现

-- 初始化蓝牙框架
bluetooth_device = bluetooth.init()
-- 创建BLE对象
ble_device = bluetooth_device:ble(ble_event_cb)

-- 从机模式(peripheral)下, 设备会被扫描到, 并且可以被连接
-- 创建GATT描述
local att_db = { -- Service
    string.fromHex("FA00"), -- Service UUID
    -- Characteristic
    { -- Characteristic 1
        string.fromHex("EA01"), -- Characteristic UUID Value
        ble.NOTIFY | ble.READ | ble.WRITE -- Properties
    }
}
ble_device:gatt_create(att_db)
-- 创建广播信息
ble_device:adv_create({
    addr_mode = ble.PUBLIC,
    channel_map = ble.CHNLS_ALL,
    intv_min = 120,
    intv_max = 120,
    adv_data = {
        {ble.FLAGS, string.char(0x06)},
        {ble.COMPLETE_LOCAL_NAME, "LuatOS123"}, -- 广播的设备名
        {ble.SERVICE_DATA, string.fromHex("FE01")}, -- 广播的服务数据
        {ble.MANUFACTURER_SPECIFIC_DATA, string.fromHex("05F0")}
    }
})
-- 开始广播
ble_device:adv_start()
*/
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#ifdef _MSC_VER
#include <intrin.h>
#endif

#include "luat_log.h"
#define LUAT_LOG_TAG "bluetooth"

extern void luat_ble_cb(luat_ble_t* luat_ble, luat_ble_event_t ble_event, luat_ble_param_t* ble_param);
extern void luat_ble_lua_release_gatt(void);

static int s_bt_ref;
int g_bt_ble_ref;
int g_ble_lua_cb_ref;
static uint32_t s_ble_generation; /* Only the Lua task increments this counter. */
#ifdef _MSC_VER
static volatile long s_ble_active_generation;
#else
static volatile uint32_t s_ble_active_generation;
#endif

uint32_t luat_ble_lua_generation(void) {
#ifdef _MSC_VER
    return (uint32_t)_InterlockedCompareExchange(&s_ble_active_generation, 0, 0);
#else
    return __sync_val_compare_and_swap(&s_ble_active_generation, 0, 0);
#endif
}

/* Publish/invalidate with full barriers: the transport task reads this token.
 * PC critical-section hooks are no-ops, so use compiler atomics on all ports. */
static void bluetooth_publish_generation(uint32_t generation) {
#ifdef _MSC_VER
    _InterlockedExchange(&s_ble_active_generation, (long)generation);
#else
    uint32_t previous;
    do {
        previous = luat_ble_lua_generation();
    } while (__sync_val_compare_and_swap(&s_ble_active_generation, previous, generation) != previous);
#endif
}

static void bluetooth_release_ble(lua_State *L) {
    bluetooth_publish_generation(0);
    luaL_unref(L, LUA_REGISTRYINDEX, g_ble_lua_cb_ref);
    luaL_unref(L, LUA_REGISTRYINDEX, g_bt_ble_ref);
    g_ble_lua_cb_ref = 0;
    g_bt_ble_ref = 0;
}

static int bluetooth_is_current(lua_State *L, int ref) {
    if (ref <= 0) return 0;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    int same = lua_rawequal(L, 1, -1);
    lua_pop(L, 1);
    return same;
}

/* Successful teardown invalidates queued callbacks before releasing refs. */
int l_bluetooth_ble_deinit(lua_State *L) {
    int ret = -1;
    if (bluetooth_is_current(L, g_bt_ble_ref)) {
        ret = luat_ble_deinit(NULL);
        if (!ret) {
            luat_ble_lua_release_gatt();
            bluetooth_release_ble(L);
        }
    }
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
反初始化蓝牙框架, 同时释放BLE对象。可再次调用bluetooth.init()
@api bluetooth.deinit()
@return boolean 是否成功
@usage
bluetooth_device:deinit()
*/
static int l_bluetooth_deinit(lua_State *L) {
    int ret = -1;
    if (bluetooth_is_current(L, s_bt_ref)) {
        ret = g_bt_ble_ref > 0 ? luat_ble_deinit(NULL) : 0;
        if (!ret) {
            if (g_bt_ble_ref > 0) {
                luat_ble_lua_release_gatt();
                bluetooth_release_ble(L);
            }
            ret = luat_bluetooth_deinit(NULL);
            if (!ret) {
                luaL_unref(L, LUA_REGISTRYINDEX, s_bt_ref);
                s_bt_ref = 0;
            }
        }
    }
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
初始化蓝牙框架, 仅需要调用一次
@api bluetooth.init()
@return userdata 蓝牙代理对象
@usage
-- 初始化蓝牙框架, 仅需要调用一次
-- 若创建失败, 会返回nil, 请检查内存是否足够
bluetooth_device = bluetooth.init()
*/
static int l_bluetooth_init(lua_State* L) {
    if (s_bt_ref > 0) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, s_bt_ref);
        return 1;
    }
    void* bt = lua_newuserdata(L, sizeof(luat_bluetooth_t));
    if (bt) {
        memset(bt, 0, sizeof(luat_bluetooth_t));
        if (luat_bluetooth_init(NULL)) return 0;
        luaL_setmetatable(L, LUAT_BLUETOOTH_TYPE);
        lua_pushvalue(L, -1);
        s_bt_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        return 1;
    }
    else {
        LLOGE("创建BT代理对象失败,内存不足");
    }
    return 0;
}

/*
创建BLE对象, 需要先调用bluetooth.init()
@api bluetooth.ble(cb)
@function 回调函数, 用于接收BLE事件
@return userdata BLE对象
@usage
-- 创建BLE对象, 需要先调用bluetooth.init()
bluetooth_device = bluetooth.init()

-- ble_callback 是自定义函数, 用于处理BLE事件
-- BLE事件回调函数, 回调时的参数如下:
function ble_callback(dev, evt, param)
    -- dev 是BLE设备对象, 可以通过dev:adv_create()等方法进行操作
    -- evt 是BLE事件类型, 可以是以下几种:
    -- ble.EVENT_CONN: 连接成功
        -- param 是事件参数, 包含以下字段:
        -- param.addr: 对端设备的地址, 6字节的二进制数据, 代表BLE设备的MAC地址
    -- ble.EVENT_DISCONN: 断开连接
        -- param 是事件参数, 包含以下字段:
        -- param.reason: 断开连接的原因
    -- ble.EVENT_WRITE: 收到写请求
        -- param 是事件参数, 包含以下字段:
        -- param.uuid_service: 服务的UUID
        -- param.uuid_characteristic: 特征的UUID
        -- param.uuid_descriptor: 描述符的UUID, 可选, 不一定存在
        -- param.data: 写入的数据
    -- ble.EVENT_SCAN_REPORT: 扫描到设备
        -- param 是事件参数, 包含以下字段:
        -- param.rssi: 信号强度
        -- param.adv_addr: 广播地址, 6字节的二进制数据
        -- param.data: 广播数据, 二进制数据

    if evt == ble.EVENT_CONN then
        log.info("ble", "connect 成功", param, param and param.addr and param.addr:toHex() or "unknow")
        ble_stat = true
    elseif evt == ble.EVENT_DISCONN then
        log.info("ble", "disconnect")
        ble_stat = false
        -- 1秒后重新开始广播
        sys.timerStart(function() dev:adv_start() end, 1000)
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        log.info("ble", "scan report", param.rssi, param.adv_addr:toHex(), param.data:toHex())
    elseif evt == ble.EVENT_WRITE then
        -- 收到写请求
        log.info("ble", "接收到写请求", param.uuid_service:toHex(), param.uuid_characteristic:toHex(), param.data:toHex())
    end
end
-- 创建BLE对象
ble_device = bluetooth_device:ble(ble_event_cb)
*/
static int l_bluetooth_create_ble(lua_State* L) {
    if (!bluetooth_is_current(L, s_bt_ref) || !lua_isfunction(L, 2) || g_bt_ble_ref > 0) return 0;
    luat_ble_t *ble = lua_newuserdata(L, sizeof(*ble));
    memset(ble, 0, sizeof(*ble));
    luaL_setmetatable(L, LUAT_BLE_TYPE);
    lua_pushvalue(L, -1);
    g_bt_ble_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_pushvalue(L, 2);
    g_ble_lua_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    if (++s_ble_generation == 0) ++s_ble_generation;
    bluetooth_publish_generation(s_ble_generation);

    /* Both refs must exist before a synchronous INIT callback can fire. */
    int ret = luat_ble_init(NULL, luat_ble_cb);
    if (ret) {
        bluetooth_release_ble(L);
        LLOGE("ble init %d", ret);
        return 0;
    }
    return 1;
}

// 隐藏这个函数
static int l_bluetooth_get_mac(lua_State *L){
	uint8_t mac[6] = {0};
    if (luat_bluetooth_get_mac(NULL, mac)) return 0;
    luat_bluetooth_mac_swap(mac);
	lua_pushlstring(L, (const char*)mac, 6);
	return 1;
}

static int _bluetooth_struct_newindex(lua_State *L);

void luat_bluetooth_struct_init(lua_State *L) {
    luaL_newmetatable(L, LUAT_BLUETOOTH_TYPE);
    lua_pushcfunction(L, _bluetooth_struct_newindex);
    lua_setfield( L, -2, "__index" );
    lua_pop(L, 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_bluetooth[] = {
	{"init",                        ROREG_FUNC(l_bluetooth_init)},
    {"deinit",                      ROREG_FUNC(l_bluetooth_deinit)},
    {"ble",                         ROREG_FUNC(l_bluetooth_create_ble)},
    {"mac",                         ROREG_FUNC(l_bluetooth_get_mac)},
	{ NULL,                         ROREG_INT(0)}
};

static int _bluetooth_struct_newindex(lua_State *L) {
	const rotable_Reg_t* reg = reg_bluetooth;
    const char* key = luaL_checkstring(L, 2);
	while (1) {
		if (reg->name == NULL)
			return 0;
		if (!strcmp(reg->name, key)) {
			lua_pushcfunction(L, reg->value.value.func);
			return 1;
		}
		reg ++;
	}
}

LUAMOD_API int luaopen_bluetooth( lua_State *L ) {
    rotable2_newlib(L, reg_bluetooth);
    luat_bluetooth_struct_init(L);
    return 1;
}
