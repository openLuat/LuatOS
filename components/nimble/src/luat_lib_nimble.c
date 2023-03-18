/*
@module  nimble
@summary 蓝牙BLE库(nimble版)
@version 1.0
@date    2022.10.21
@demo    nimble
@tag LUAT_USE_NIMBLE
@usage
-- 本库当前支持Air101/Air103/ESP32/ESP32C3/ESP32S3
-- 用法请查阅demo, API函数会归于指定的模式
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_spi.h"

#include "luat_nimble.h"

#include "host/ble_gatt.h"
#include "host/ble_hs_id.h"
#include "host/util/util.h"
#include "host/ble_hs_adv.h"
#include "host/ble_gap.h"

#define LUAT_LOG_TAG "nimble"
#include "luat_log.h"

static uint32_t nimble_mode = 0;
uint16_t g_ble_state;
uint16_t g_ble_conn_handle;

// peripheral, 被扫描, 被连接设备的UUID配置
ble_uuid_any_t ble_peripheral_srv_uuid;
ble_uuid_any_t ble_peripheral_indicate_uuid;
ble_uuid_any_t ble_peripheral_write_uuid;

#define WM_GATT_SVC_UUID      0x180D
// #define WM_GATT_SVC_UUID      0xFFF0
#define WM_GATT_INDICATE_UUID 0xFFF1
#define WM_GATT_WRITE_UUID    0xFFF2
// #define WM_GATT_NOTIFY_UUID    0xFFF3


uint8_t luat_ble_dev_name[32];
size_t  luat_ble_dev_name_len;

uint8_t adv_buff[128];
int adv_buff_len = 0;
struct ble_hs_adv_fields adv_fields;
struct ble_gap_adv_params adv_params = {0};

/*
初始化BLE上下文,开始对外广播/扫描
@api nimble.init(name)
@string 蓝牙设备名称,可选,建议填写
@return bool 成功与否
@usage
-- 参考 demo/nimble
-- 本函数对所有模式都适用
*/
static int l_nimble_init(lua_State* L) {
    int rc = 0;
    size_t len = 0;
    const char* name = NULL;
    if(lua_isstring(L, 1)) {
        name = luaL_checklstring(L, 1, &len);
        if (len > 0) {
            memcpy(luat_ble_dev_name, name, len);
            luat_ble_dev_name_len = len;
        }
    }
    LLOGD("init name %s mode %d", name == NULL ? "-" : name, nimble_mode);
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
-- 本函数对所有模式都适用
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
-- 本函数对peripheral/从机模式适用
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

/*
扫描从机
@api nimble.scan()
@return bool 成功与否
@usage
-- 参考 demo/nimble
-- 本函数对central/主机模式适用
-- 本函数会直接返回, 然后通过异步回调返回结果
*/
static int l_nimble_scan(lua_State *L) {
    int ret = luat_nimble_blecent_scan();
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    // lua_pushinteger(L, ret);
    return 1;
}

/*
设置模式
@api nimble.mode(tp)
@int 模式, 默认server/peripheral, 可选 client/central模式 nimble.MODE_BLE_CLIENT
@return bool 成功与否
@usage
-- 参考 demo/nimble
-- 必须在nimble.init()之前调用
-- nimble.mode(nimble.MODE_BLE_CLIENT) -- 简称从机模式,未完善
*/
static int l_nimble_mode(lua_State *L) {
    if (lua_isinteger(L, 1)) {
        nimble_mode = lua_tointeger(L, 1);
    }
    lua_pushinteger(L, nimble_mode);
    return 1;
}

static int l_nimble_connect(lua_State *L) {
    size_t len = 0;
    const char* addr = luaL_checklstring(L, 1, &len);
    if (addr == NULL)
        return 0;
    luat_nimble_blecent_connect(addr);
    return 0;
}

static int l_nimble_connok(lua_State *L) {
    lua_pushboolean(L, g_ble_state == BT_STATE_CONNECTED ? 1 : 0);
    return 1;
}

/*
设置server/peripheral的UUID
@api nimble.setUUID(tp, addr)
@string 配置字符串,后面的示例有说明
@string 地址字符串
@return bool 成功与否
@usage
-- 参考 demo/nimble, 2023-02-25之后编译的固件支持本API
-- 必须在nimble.init()之前调用
-- 本函数对peripheral/从机模式适用

-- 设置SERVER/Peripheral模式下的UUID, 支持设置3个
-- 地址支持 2/4/16字节, 需要二进制数据
-- 2字节地址示例: AABB, 写 string.fromHex("AABB") ,或者 string.char(0xAA, 0xBB)
-- 4字节地址示例: AABBCCDD , 写 string.fromHex("AABBCCDD") ,或者 string.char(0xAA, 0xBB, 0xCC, 0xDD)
nimble.setUUID("srv", string.fromHex("380D"))      -- 服务主UUID         ,  默认值 180D
nimble.setUUID("write", string.fromHex("FF31"))    -- 往本设备写数据的UUID,  默认值 FFF1
nimble.setUUID("indicate", string.fromHex("FF32")) -- 订阅本设备的数据的UUID,默认值 FFF2
*/
static int l_nimble_set_uuid(lua_State *L) {
    size_t len = 0;
    ble_uuid_any_t tmp = {0};
    const char* key = luaL_checkstring(L, 1);
    const char* uuid = luaL_checklstring(L, 2, &len);
    int ret = ble_uuid_init_from_buf(&tmp, (const void*)uuid, len);
    if (ret != 0) {
        LLOGW("invaild UUID, len must be 2/4/16");
        return 0;
    }
    if (!strcmp("srv", key)) {
        memcpy(&ble_peripheral_srv_uuid, &tmp, sizeof(ble_uuid_any_t));
    }
    else if (!strcmp("write", key)) {
        memcpy(&ble_peripheral_write_uuid, &tmp, sizeof(ble_uuid_any_t));
    }
    else if (!strcmp("indicate", key)) {
        memcpy(&ble_peripheral_indicate_uuid, &tmp, sizeof(ble_uuid_any_t));
    }
    else {
        LLOGW("only support srv/write/indicate");
        return 0;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/*
获取蓝牙MAC
@api nimble.mac()
@return string 蓝牙MAC地址,6字节
@usage
-- 参考 demo/nimble, 2023-02-25之后编译的固件支持本API
-- 本函数对所有模式都适用
local mac = nimble.mac()
log.info("ble", "mac", mac and mac:toHex() or "Unknwn")
*/
static int l_nimble_mac(lua_State *L) {
    int rc;
    uint8_t own_addr_type;
    rc = ble_hs_util_ensure_addr(0);
    if (rc != 0) {
        LLOGW("fail to fetch BLE MAC, rc %d", rc);
        return 0;
    }

    /* Figure out address to use while advertising (no privacy for now) */
    rc = ble_hs_id_infer_auto(0, &own_addr_type);
    if (rc != 0) {
        LLOGE("error determining address type; rc=%d", rc);
        return 0;
    }

    /* Printing ADDR */
    uint8_t addr_val[6] = {0};
    rc = ble_hs_id_copy_addr(own_addr_type, addr_val, NULL);
    if (rc == 0) {
        lua_pushlstring(L, (const char*)addr_val, 6);
        return 1;
    }
    LLOGW("fail to fetch BLE MAC, rc %d", rc);
    return 0;
}

/*
配置iBeacon的参数,仅iBeacon模式可用
@api nimble.ibeacon(data, major, minor, measured_power)
@string 数据, 必须是16字节
@int 主版本号,默认2, 可选, 范围 0 ~ 65536
@int 次版本号,默认10,可选, 范围 0 ~ 65536
@int 名义功率, 默认0, 范围 -126 到 20 
@return bool 成功返回true,否则返回false
@usage
-- 参考 demo/nimble, 2023-02-25之后编译的固件支持本API
-- 本函数对ibeacon模式适用
nimble.ibeacon(data, 2, 10, 0)
nimble.init()
*/
static int l_nimble_ibeacon(lua_State *L) {
    size_t len = 0;
    const char* data = luaL_checklstring(L, 1, &len);
    if (len != 16) {
        LLOGE("ibeacon data MUST 16 bytes, but %d", len);
        return 0;
    }
    uint16_t major = luaL_optinteger(L, 2, 2);
    uint16_t minor = luaL_optinteger(L, 3, 10);
    int8_t measured_power = luaL_optinteger(L, 4, 0);

    int rc = luat_nimble_ibeacon_setup(data, major, minor, measured_power);
    lua_pushboolean(L, rc == 0 ? 1 : 0);
    return 1;
}

/*
配置广播数据,仅iBeacon模式可用
@api nimble.advData(data, flags)
@string 广播数据, 当前最高128字节
@int 广播标识, 可选, 默认值是 0x06,即 不支持传统蓝牙(0x04) + 普通发现模式(0x02)
@return bool 成功返回true,否则返回false
@usage
-- 参考 demo/nimble/adv_free, 2023-03-18之后编译的固件支持本API
-- 本函数对ibeacon模式适用
-- 数据来源可以多种多样
local data = string.fromHex("123487651234876512348765123487651234876512348765")
-- local data = crypto.trng(25)
-- local data = string.char(0x11, 0x13, 0xA3, 0x5A, 0x11, 0x13, 0xA3, 0x5A, 0x11, 0x13, 0xA3, 0x5A, 0x11, 0x13, 0xA3, 0x5A)
nimble.advData(data)
nimble.init()

-- nimble支持在init之后的任意时刻再次调用, 以实现数据更新
-- 例如 1分钟变一次
while 1 do
    sys.wait(60000)
    local data = crypto.trng(25)
    nimble.advData(data)
end
*/
static int l_nimble_set_adv_data(lua_State *L) {
    size_t len = 0;
    const char* data = luaL_checklstring(L, 1, &len);
    int flags = luaL_optinteger(L, 2, BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    int rc = luat_nimble_set_adv_data(data, len, flags);
    lua_pushboolean(L, rc == 0 ? 1 : 0);
    return 1;
}


/*
设置广播参数
@api nimble.advParams(conn_mode, disc_mode, itvl_min, itvl_max, channel_map, filter_policy, high_duty_cycle)
@int 广播模式, 0 - 不可连接, 1 - 定向连接, 2 - 未定向连接, 默认0
@int 发现模式, 0 - 不可发现, 1 - 限制发现, 3 - 通用发现, 默认0
@int 最小广播间隔, 0 - 使用默认值, 范围 1 - 65535, 单位0.625ms, 默认0
@int 最大广播间隔, 0 - 使用默认值, 范围 1 - 65535, 单位0.625ms, 默认0
@int 广播通道, 默认0, 一般不需要设置
@int 过滤规则, 默认0, 一般不需要设置
@int 当广播模式为"定向连接"时,是否使用高占空比模式, 默认0, 可选1
@return nil 无返回值
@usage
-- 当前仅ibeacon模式/peripheral/从机可使用
-- 例如设置 不可连接 + 限制发现
-- 需要在nimble.init之前设置好
nimble.advParams(0, 1)
-- 注意peripheral模式下自动配置 conn_mode 和 disc_mode
*/
static int l_nimble_set_adv_params(lua_State *L) {
    /** Advertising mode. Can be one of following constants:
     *  - BLE_GAP_CONN_MODE_NON (non-connectable; 3.C.9.3.2).
     *  - BLE_GAP_CONN_MODE_DIR (directed-connectable; 3.C.9.3.3).
     *  - BLE_GAP_CONN_MODE_UND (undirected-connectable; 3.C.9.3.4).
     */
    adv_params.conn_mode = luaL_optinteger(L, 1, 0);
    /** Discoverable mode. Can be one of following constants:
     *  - BLE_GAP_DISC_MODE_NON  (non-discoverable; 3.C.9.2.2).
     *  - BLE_GAP_DISC_MODE_LTD (limited-discoverable; 3.C.9.2.3).
     *  - BLE_GAP_DISC_MODE_GEN (general-discoverable; 3.C.9.2.4).
     */
    adv_params.disc_mode = luaL_optinteger(L, 2, 0);

    /** Minimum advertising interval, if 0 stack use sane defaults */
    adv_params.itvl_min = luaL_optinteger(L, 3, 0);
    /** Maximum advertising interval, if 0 stack use sane defaults */
    adv_params.itvl_max = luaL_optinteger(L, 4, 0);
    /** Advertising channel map , if 0 stack use sane defaults */
    adv_params.channel_map = luaL_optinteger(L, 5, 0);

    /** Advertising  Filter policy */
    adv_params.filter_policy = luaL_optinteger(L, 6, 0);

    /** If do High Duty cycle for Directed Advertising */
    adv_params.high_duty_cycle = luaL_optinteger(L, 7, 0);

    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_nimble[] =
{
	{ "init",           ROREG_FUNC(l_nimble_init)},
    { "deinit",         ROREG_FUNC(l_nimble_deinit)},
    { "debug",          ROREG_FUNC(l_nimble_debug)},
    { "mode",           ROREG_FUNC(l_nimble_mode)},
    { "connok",         ROREG_FUNC(l_nimble_connok)},

    // 外设模式, 广播并等待连接
    { "server_init",    ROREG_FUNC(l_nimble_server_init)},
    { "server_deinit",  ROREG_FUNC(l_nimble_server_deinit)},
    { "send_msg",       ROREG_FUNC(l_nimble_send_msg)},
    { "setUUID",        ROREG_FUNC(l_nimble_set_uuid)},
    { "mac",            ROREG_FUNC(l_nimble_mac)},

    // 中心模式, 扫描并连接外设
    { "scan",           ROREG_FUNC(l_nimble_scan)},
    { "connect",        ROREG_FUNC(l_nimble_connect)},

    // ibeacon广播模式
    { "ibeacon",        ROREG_FUNC(l_nimble_ibeacon)},

    // 广播数据
    { "advData",        ROREG_FUNC(l_nimble_set_adv_data)},
    { "advParams",        ROREG_FUNC(l_nimble_set_adv_params)},

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
    memcpy(&ble_peripheral_srv_uuid, BLE_UUID16_DECLARE(WM_GATT_SVC_UUID), sizeof(ble_uuid16_t));
    memcpy(&ble_peripheral_write_uuid, BLE_UUID16_DECLARE(WM_GATT_WRITE_UUID), sizeof(ble_uuid16_t));
    memcpy(&ble_peripheral_indicate_uuid, BLE_UUID16_DECLARE(WM_GATT_INDICATE_UUID), sizeof(ble_uuid16_t));
    rotable2_newlib(L, reg_nimble);
    return 1;
}

