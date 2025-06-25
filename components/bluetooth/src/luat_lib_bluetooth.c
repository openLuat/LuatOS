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

#include "luat_log.h"
#define LUAT_LOG_TAG "bluetooth"

extern void luat_ble_cb(luat_ble_t* luat_ble, luat_ble_event_t ble_event, luat_ble_param_t* ble_param);

static int s_bt_ref;
int g_bt_ble_ref;
int g_ble_lua_cb_ref;

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
    void* bt = lua_newuserdata(L, 4);
    if (bt) {
        luat_bluetooth_init(NULL);
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
    -- ble.EVENT_WRITE_REQ: 收到写请求
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
    elseif evt == ble.EVENT_WRITE_REQ then
        -- 收到写请求
        log.info("ble", "接收到写请求", param.uuid_service:toHex(), param.uuid_characteristic:toHex(), param.data:toHex())
    end
end
-- 创建BLE对象
ble_device = bluetooth_device:ble(ble_event_cb)
*/
static int l_bluetooth_create_ble(lua_State* L) {
    int ret = 0;
    
    if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		g_ble_lua_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}else{
        LLOGE("error cb");
        return 0;
    }

    ret = luat_ble_init(NULL, luat_ble_cb);
    if (ret) {
        LLOGE("ble init %d", ret);
        return 0;
    }

    lua_newuserdata(L, sizeof(luat_ble_t));
    luaL_setmetatable(L, LUAT_BLE_TYPE);
    lua_pushvalue(L, -1);
    g_bt_ble_ref = luaL_ref(L, LUA_REGISTRYINDEX);
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
    {"ble",                         ROREG_FUNC(l_bluetooth_create_ble)},
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
