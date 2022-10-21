/*
@module  nimble
@summary 蓝牙BLE库(nimble版)
@version 1.0
@date    2022.10.21
@demo    nimble
@usage
-- 本库当前支持Air101/Air103/ESP32/ESP32C3
-- 理论上支持ESP32C2/ESP32S2/ESP32S3,但尚未测试

-- 本库当前仅支持BLE Peripheral, 其他模式待添加
sys.taskInit(function()
    -- 初始化nimble, 因为当仅支持作为主机,也没有其他配置项
    nimble.init("LuatOS-Wendal") -- 选取一个蓝牙设备名称
    sys.wait(1000)

    --local data = string.char(0x5A, 0xA5, 0x12, 0x34, 0x56)
    local data = "1234567890"
    while 1 do
        sys.wait(5000)
        -- Central端建立连接并订阅后, 可上报数据
        nimble.send_msg(1, 0, data)
    end
end
sys.subscribe("BLE_GATT_WRITE_CHR", function(info, data)
    -- Central端建立连接后, 可往设备写入数据
    log.info("ble", "Data Got", data:toHex())
end)

-- 配合微信小程序 "LuatOS蓝牙调试"
-- 1. 若开发板无天线, 将手机尽量靠近芯片也能搜到
-- 2. 该小程序是开源的, 每次write会自动分包
-- https://gitee.com/openLuat/luatos-miniapps
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_spi.h"

#include "luat_nimble.h"

#define LUAT_LOG_TAG "nimble"
#include "luat_log.h"

static uint32_t nimble_mode = 0;

/*
初始化BLE上下文,开始对外广播/扫描
@api nimble.init(name)
@string 蓝牙设备名称,可选,建议填写
@return bool 成功与否
@usage
-- 参考 demo/nimble
*/
static int l_nimble_init(lua_State* L) {
    int rc = 0;
    size_t len = 0;
    const char* name = NULL;
    if(lua_isstring(L, 1)) {
        name = luaL_checklstring(L, 1, &len);
    }
    LLOGD("init name %s mode %d", name, nimble_mode);
    rc = luat_nimble_init(0xFF, name, nimble_mode);
    if (rc) {
        lua_pushboolean(L, 0);
        lua_pushinteger(L, rc);
        return 2;
    }
    else {
        lua_pushboolean(L, 1);
        return 1;
    }
}

/*
关闭BLE上下文
@api nimble.deinit()
@return bool 成功与否
@usage
-- 仅部分设备支持,当前可能都不支持
*/
static int l_nimble_deinit(lua_State* L) {
    int rc = 0;
    rc = luat_nimble_deinit();
    if (rc) {
        lua_pushboolean(L, 0);
        lua_pushinteger(L, rc);
        return 2;
    }
    else {
        lua_pushboolean(L, 1);
        return 1;
    }
}

static int l_nimble_debug(lua_State* L) {
    int level = 0;
    // if (lua_gettop(L) > 0)
    //     level = luat_nimble_trace_level(luaL_checkinteger(L, 1));
    // else
    //     level = luat_nimble_trace_level(-1);
    lua_pushinteger(L, level);
    return 1;
}

static int l_nimble_server_init(lua_State* L) {
    LLOGI("nimble.server_init is removed");
    return 0;
}


static int l_nimble_server_deinit(lua_State* L) {
    LLOGI("nimble.server_deinit is removed");
    return 0;
}

/*
发送信息
@api nimble.send_msg(conn, handle, data)
@int 连接id, 当前固定填1
@int 处理id, 当前固定填0
@string 数据字符串,可包含不可见字符
@return bool 成功与否
@usage
-- 参考 demo/nimble
*/
static int l_nimble_send_msg(lua_State *L) {
    int conn_id = luaL_checkinteger(L, 1);
    int handle_id = luaL_checkinteger(L, 2);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 3, &len);
    int ret = 0;
    if (len == 0) {
        LLOGI("send emtry msg? ignored");
    }
    else {
        ret = luat_nimble_server_send(0, data, len);
    }

    lua_pushboolean(L, ret == 0 ? 1 : 0);
    // lua_pushinteger(L, ret);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_nimble[] =
{
	{ "init",           ROREG_FUNC(l_nimble_init)},
    { "deinit",         ROREG_FUNC(l_nimble_deinit)},
    { "debug",          ROREG_FUNC(l_nimble_debug)},
    { "server_init",    ROREG_FUNC(l_nimble_server_init)},
    { "server_deinit",  ROREG_FUNC(l_nimble_server_deinit)},
    { "send_msg",       ROREG_FUNC(l_nimble_send_msg)},

    // 放一些常量
    { "STATE_OFF",           ROREG_INT(BT_STATE_OFF)},
    { "STATE_ON",            ROREG_INT(BT_STATE_ON)},
    { "STATE_CONNECTED",     ROREG_INT(BT_STATE_CONNECTED)},
    { "STATE_DISCONNECT",    ROREG_INT(BT_STATE_DISCONNECT)},

    // 模式
    { "MODE_BLE_SERVER",           ROREG_INT(BT_MODE_BLE_SERVER)},
    { "MODE_BLE_CLIENT",           ROREG_INT(BT_MODE_BLE_CLIENT)},
    { "MODE_BLE_BEACON",           ROREG_INT(BT_MODE_BLE_BEACON)},
    { "MODE_BLE_MESH",             ROREG_INT(BT_MODE_BLE_MESH)},
    { "SERVER",                    ROREG_INT(BT_MODE_BLE_SERVER)},
    { "CLIENT",                    ROREG_INT(BT_MODE_BLE_CLIENT)},
    { "BEACON",                    ROREG_INT(BT_MODE_BLE_BEACON)},
    { "MESH",                      ROREG_INT(BT_MODE_BLE_MESH)},

	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_nimble( lua_State *L ) {
    rotable2_newlib(L, reg_nimble);
    return 1;
}

