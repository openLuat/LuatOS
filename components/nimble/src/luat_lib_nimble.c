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

-- 名称解释:
-- peripheral 外设模式, 或者成为从机模式, 是被连接的设备
-- central    中心模式, 或者成为主机模式, 是扫描并连接其他设备
-- ibeacon    周期性的beacon广播

-- UUID       设备的服务(service)和特征(characteristic)会以UUID作为标识,支持 2字节/4字节/16字节,通常用2字节的缩短版本
-- chr        设备的服务(service)由多个特征(characteristic)组成, 简称chr
-- characteristic 特征由UUID和flags组成, 其中UUID做标识, flags代表该特征可以支持的功能
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_spi.h"


#include "host/ble_gatt.h"
#include "host/ble_hs_id.h"
#include "host/util/util.h"
#include "host/ble_hs_adv.h"
#include "host/ble_gap.h"

#include "luat_nimble.h"

#define LUAT_LOG_TAG "nimble"
#include "luat_log.h"

#define CFG_ADDR_ORDER 1

static uint32_t nimble_mode = 0;
uint16_t g_ble_state;
uint16_t g_ble_conn_handle;

// peripheral, 被扫描, 被连接设备的UUID配置
ble_uuid_any_t ble_peripheral_srv_uuid;
uint16_t s_chr_flags[LUAT_BLE_MAX_CHR];
uint16_t s_chr_val_handles[LUAT_BLE_MAX_CHR];
ble_uuid_any_t s_chr_uuids[LUAT_BLE_MAX_CHR];
uint8_t s_chr_notify_states[LUAT_BLE_MAX_CHR];
uint8_t s_chr_indicate_states[LUAT_BLE_MAX_CHR];

#define WM_GATT_SVC_UUID      0x180D
// #define WM_GATT_SVC_UUID      0xFFF0
#define WM_GATT_INDICATE_UUID 0xFFF1
#define WM_GATT_WRITE_UUID    0xFFF2
#define WM_GATT_NOTIFY_UUID    0xFFF3


uint8_t luat_ble_dev_name[32];
size_t  luat_ble_dev_name_len;

uint8_t adv_buff[128];
int adv_buff_len = 0;
struct ble_hs_adv_fields adv_fields;
struct ble_gap_adv_params adv_params = {0};

static uint8_t ble_uuid_addr_conv = 0; // BLE的地址需要反序, 就蛋疼了

struct ble_gatt_svc *peer_servs[MAX_PER_SERV];
struct ble_gatt_chr *peer_chrs[MAX_PER_SERV*MAX_PER_SERV];

static int buff2uuid(ble_uuid_any_t* uuid, const char* data, size_t data_len) {
    if (data_len > 16)
        return -1;
    char tmp[16];
    for (size_t i = 0; i < data_len; i++)
    {
        if (ble_uuid_addr_conv == 0)
            tmp[i] = data[i];
        else
            tmp[i] = data[data_len - i - 1];
    }
    return ble_uuid_init_from_buf(uuid, tmp, data_len);
}


//              通用API, 适合全部模式
//--------------------------------------------------

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

    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_gc(L, LUA_GCCOLLECT, 0);

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
    LLOGI("nimble.debug is removed");
    lua_pushinteger(L, 0);
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

/*
是否已经建立连接
@api nimble.connok()
@return bool 已连接返回true,否则返回false
@usage
log.info("ble", "connected?", nimble.connok())
-- 从机peripheral模式, 设备是否已经被连接
-- 主机central模式, 是否已经连接到设备
-- ibeacon模式, 无意义
*/
static int l_nimble_connok(lua_State *L) {
    lua_pushboolean(L, g_ble_state == BT_STATE_CONNECTED ? 1 : 0);
    return 1;
}


//--------------------------------------------------
//             从机peripheral模式系列API

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
    int ret = buff2uuid(&tmp, (const void*)uuid, len);
    if (ret != 0) {
        LLOGW("invaild UUID, len must be 2/4/16");
        return 0;
    }
    if (!strcmp("srv", key)) {
        memcpy(&ble_peripheral_srv_uuid, &tmp, sizeof(ble_uuid_any_t));
    }
    else if (!strcmp("write", key)) {
        memcpy(&s_chr_uuids[0], &tmp, sizeof(ble_uuid_any_t));
    }
    else if (!strcmp("indicate", key)) {
        memcpy(&s_chr_uuids[1], &tmp, sizeof(ble_uuid_any_t));
    }
    else if (!strcmp("notify", key)) {
        memcpy(&s_chr_uuids[2], &tmp, sizeof(ble_uuid_any_t));
    }
    else {
        LLOGW("only support srv/write/indicate/notify");
        return 0;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/*
获取蓝牙MAC
@api nimble.mac(mac)
@string 待设置的MAC地址, 6字节, 不传就是单获取
@return string 蓝牙MAC地址,6字节
@usage
-- 参考 demo/nimble, 2023-02-25之后编译的固件支持本API
-- 本函数对所有模式都适用
local mac = nimble.mac()
log.info("ble", "mac", mac and mac:toHex() or "Unknwn")

-- 修改MAC地址, 2024.06.05 新增, 当前仅Air601支持, 修改后重启生效
nimble.mac(string.fromHex("1234567890AB"))
*/
static int l_nimble_mac(lua_State *L) {
    int rc = 0;
    uint8_t own_addr_type = 0;
    uint8_t addr_val[6] = {0};
    if (lua_type(L, 1) == LUA_TSTRING) {
        size_t len = 0;
        const char* tmac = luaL_checklstring(L, 1, &len);
        if (len != 6) {
            LLOGW("mac len must be 6");
            return 0;
        }
        luat_nimble_mac_set(tmac);
    }
    #ifdef TLS_CONFIG_CPU_XT804
    if (1) {
        extern int luat_nimble_mac_get(uint8_t* mac);
        luat_nimble_mac_get(addr_val);
        lua_pushlstring(L, (const char*)addr_val, 6);
        return 1;
    }
    #endif
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
    
    rc = ble_hs_id_copy_addr(own_addr_type, addr_val, NULL);
    if (rc == 0) {
        lua_pushlstring(L, (const char*)addr_val, 6);
        return 1;
    }
    LLOGW("fail to fetch BLE MAC, rc %d", rc);
    return 0;
}


/*
发送notify
@api nimble.sendNotify(srv_uuid, chr_uuid, data)
@string 服务的UUID,预留,当前填nil就行
@string 特征的UUID,必须填写
@string 数据, 必填, 跟MTU大小相关, 一般不要超过256字节
@return bool 成功返回true,否则返回false
@usage
-- 本API于 2023.07.31 新增
-- 本函数对peripheral模式适用
nimble.sendNotify(nil, string.fromHex("FF01"), string.char(0x31, 0x32, 0x33, 0x34, 0x35))
*/
static int l_nimble_send_notify(lua_State *L) {
    size_t tmp_size = 0;
    size_t data_len = 0;
    ble_uuid_any_t chr_uuid;
    const char* tmp = luaL_checklstring(L, 2, &tmp_size);
    int ret = buff2uuid(&chr_uuid, tmp, tmp_size);
    if (ret) {
        LLOGE("ble_uuid_init_from_buf rc %d", ret);
        return 0;
    }
    const char* data = luaL_checklstring(L, 3, &data_len);
    ret = luat_nimble_server_send_notify(NULL, &chr_uuid, data, data_len);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
发送indicate
@api nimble.sendIndicate(srv_uuid, chr_uuid, data)
@string 服务的UUID,预留,当前填nil就行
@string 特征的UUID,必须填写
@string 数据, 必填, 跟MTU大小相关, 一般不要超过256字节
@return bool 成功返回true,否则返回false
@usage
-- 本API于 2023.07.31 新增
-- 本函数对peripheral模式适用
nimble.sendIndicate(nil, string.fromHex("FF01"), string.char(0x31, 0x32, 0x33, 0x34, 0x35))
*/
static int l_nimble_send_indicate(lua_State *L) {
    size_t tmp_size = 0;
    size_t data_len = 0;
    ble_uuid_any_t chr_uuid;
    const char* tmp = luaL_checklstring(L, 2, &tmp_size);
    int ret = buff2uuid(&chr_uuid, tmp, tmp_size);
    if (ret) {
        LLOGE("ble_uuid_init_from_buf rc %d", ret);
        return 0;
    }
    const char* data = luaL_checklstring(L, 3, &data_len);
    ret = luat_nimble_server_send_indicate(NULL, &chr_uuid, data, data_len);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
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

/*
设置chr的特征
@api nimble.setChr(index, uuid, flags)
@int chr的索引, 默认0-3
@int chr的UUID, 可以是2/4/16字节
@int chr的FLAGS, 请查阅常量表
@return nil 无返回值
@usage
-- 仅peripheral/从机可使用
nimble.setChr(0, string.fromHex("FF01"), nimble.CHR_F_WRITE_NO_RSP | nimble.CHR_F_NOTIFY)
nimble.setChr(1, string.fromHex("FF02"), nimble.CHR_F_READ | nimble.CHR_F_NOTIFY)
nimble.setChr(2, string.fromHex("FF03"), nimble.CHR_F_WRITE_NO_RSP)
-- 可查阅 demo/nimble/kt6368a
*/
static int l_nimble_set_chr(lua_State *L) {
    size_t tmp_size = 0;
    // ble_uuid_any_t srv_uuid = {0};
    ble_uuid_any_t chr_uuid = {0};
    const char* tmp;
    int ret = 0;
    int index = luaL_checkinteger(L, 1);
    tmp = luaL_checklstring(L, 2, &tmp_size);
    // LLOGD("chr? %02X%02X %d", tmp[0], tmp[1], tmp_size);
    ret = buff2uuid(&chr_uuid, tmp, tmp_size);
    if (ret) {
        LLOGE("ble_uuid_init_from_buf rc %d", ret);
        return 0;
    }
    int flags = luaL_checkinteger(L, 3);

    luat_nimble_peripheral_set_chr(index, &chr_uuid, flags);
    return 0;
}

/*
设置chr的特征
@api nimble.config(id, value)
@int 配置的id,请查阅常量表
@any 根据配置的不同, 有不同的可选值
@return nil 无返回值
@usage
-- 本函数在任意模式可用
-- 本API于 2023.07.31 新增
-- 例如设置地址转换的大小端, 默认是0, 兼容老的代码
-- 设置成1, 服务UUID和chr的UUID更直观
nimble.config(nimble.CFG_ADDR_ORDER, 1)
*/
static int l_nimble_config(lua_State *L) {
    int conf = luaL_checkinteger(L, 1);
    if (conf == CFG_ADDR_ORDER) {
        if (lua_isboolean(L, 2))
            ble_uuid_addr_conv = lua_toboolean(L, 2);
        else if (lua_isinteger(L, 2))
            ble_uuid_addr_conv = lua_tointeger(L, 2);
    }
    return 0;
}

//-------------------------------------
//              ibeacon系列API


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

//-----------------------------------------------------
//              主机central模式API

/*
扫描从机
@api nimble.scan(timeout)
@int 超时时间,单位秒,默认28秒
@return bool 启动扫描成功与否
@usage
-- 参考 demo/nimble/scan
-- 本函数对central/主机模式适用
-- 本函数会直接返回, 然后通过异步回调返回结果

-- 调用本函数前, 需要先确保已经nimble.init()
nimble.scan()
-- timeout参数于 2023.7.11 添加
*/
static int l_nimble_scan(lua_State *L) {
    int timeout = luaL_optinteger(L, 1, 28);
    if (timeout < 1)
        timeout = 1;
    int ret = luat_nimble_blecent_scan(timeout);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    // lua_pushinteger(L, ret);
    return 1;
}

/*
连接到从机
@api nimble.connect(mac)
@string 设备的MAC地址
@return bool 启动连接成功与否
@usage
-- 本函数对central/主机模式适用
-- 本函数会直接返回, 然后通过异步回调返回结果
*/
static int l_nimble_connect(lua_State *L) {
    size_t len = 0;
    const char* addr = luaL_checklstring(L, 1, &len);
    if (addr == NULL)
        return 0;
    luat_nimble_blecent_connect(addr);
    return 0;
}

/*
断开与从机的连接
@api nimble.disconnect()
@return nil 无返回值
@usage
-- 本函数对central/主机模式适用
-- 本函数会直接返回
*/
static int l_nimble_disconnect(lua_State *L) {
    int id = luaL_optinteger(L, 1, 0);
    luat_nimble_blecent_disconnect(id);
    return 0;
}

/*
扫描从机的服务列表
@api nimble.discSvr()
@return nil 无返回值
@usage
-- 本函数对central/主机模式适用
-- 本函数会直接返回,然后异步返回结果
-- 这个API通常不需要调用, 在连接从机完成后,会主动调用一次
*/
static int l_nimble_disc_svr(lua_State *L) {
    int id = luaL_optinteger(L, 1, 0);
    luat_nimble_central_disc_srv(id);
    return 0;
}

/*
获取从机的服务列表
@api nimble.listSvr()
@return table 服务UUID的数组
@usage
-- 本函数对central/主机模式适用
*/
static int l_nimble_list_svr(lua_State *L) {
    lua_newtable(L);
    char buff[64];
    size_t i;
    for (i = 0; i < MAX_PER_SERV; i++)
    {
        if (peer_servs[i] == NULL)
            break;
        lua_pushstring(L, ble_uuid_to_str(&peer_servs[i]->uuid, buff));
        lua_seti(L, -2, i+1);
    }
    return 1;
}

/*
扫描从机的指定服务的特征值
@api nimble.discChr(svr_uuid)
@string 指定服务的UUID值
@return boolean 成功启动扫描与否
@usage
-- 本函数对central/主机模式适用
*/
static int l_nimble_disc_chr(lua_State *L) {
    size_t tmp_size = 0;
    size_t data_len = 0;
    ble_uuid_any_t svr_uuid;
    const char* tmp = luaL_checklstring(L, 1, &tmp_size);
    int ret = buff2uuid(&svr_uuid, tmp, tmp_size);
    if (ret) {
        return 0;
    }
    size_t i;
    char buff[64];
    for (i = 0; i < MAX_PER_SERV; i++)
    {
        if (peer_servs[i] == NULL)
            break;
        if (0 == ble_uuid_cmp(&peer_servs[i]->uuid, &svr_uuid)) {
            // LLOGD("找到匹配的UUID, 查询其特征值");
            lua_pushboolean(L, 1);
            luat_nimble_central_disc_chr(0, peer_servs[i]);
            return 1;
        }
        // LLOGD("期望的服务id %s", ble_uuid_to_str(&svr_uuid, buff));
        // LLOGD("实际的服务id %s", ble_uuid_to_str(&peer_servs[i]->uuid, buff));
    }
    return 0;
}

/*
获取从机的指定服务的特征值列表
@api nimble.listChr(svr_uuid)
@string 指定服务的UUID值
@return table 特征值列表,包含UUID和flags
@usage
-- 本函数对central/主机模式适用
*/
static int l_nimble_list_chr(lua_State *L) {
    size_t tmp_size = 0;
    size_t data_len = 0;
    ble_uuid_any_t svr_uuid;
    const char* tmp = luaL_checklstring(L, 1, &tmp_size);
    int ret = buff2uuid(&svr_uuid, tmp, tmp_size);
    if (ret) {
        return 0;
    }
    size_t i;
    char buff[64];
    lua_newtable(L);
    for (i = 0; i < MAX_PER_SERV; i++)
    {
        if (peer_servs[i] == NULL)
            continue;
        if (0 == ble_uuid_cmp(&peer_servs[i]->uuid, &svr_uuid)) {
            for (size_t j = 0; j < MAX_PER_SERV; j++)
            {
                if (peer_chrs[i*MAX_PER_SERV + j] == NULL)
                    break;
                lua_newtable(L);
                lua_pushstring(L, ble_uuid_to_str(&(peer_chrs[i*MAX_PER_SERV+j]->uuid), buff));
                lua_setfield(L, -2, "uuid");
                lua_pushinteger(L, peer_chrs[i*MAX_PER_SERV+j]->properties);
                lua_setfield(L, -2, "flags");

                lua_seti(L, -2, j + 1);
            }
            return 1;
        }
    }
    return 1;
}

static int find_chr(lua_State *L, struct ble_gatt_svc **svc, struct ble_gatt_chr **chr) {
    size_t tmp_size = 0;
    int32_t ret = 0;
    const char* tmp;
    ble_uuid_any_t svr_uuid;
    ble_uuid_any_t chr_uuid;
    // 服务的UUID
    tmp = luaL_checklstring(L, 1, &tmp_size);
    ret = buff2uuid(&svr_uuid, tmp, tmp_size);
    if (ret) {
        return -1;
    }
    // 特征的UUUID
    tmp = luaL_checklstring(L, 2, &tmp_size);
    ret = buff2uuid(&chr_uuid, tmp, tmp_size);
    if (ret) {
        return -1;
    }
    for (size_t i = 0; i < MAX_PER_SERV; i++)
    {
        if (peer_servs[i] == NULL)
            continue;
        if (0 == ble_uuid_cmp(&peer_servs[i]->uuid, &svr_uuid)) {
            *svc = peer_servs[i];
            for (size_t j = 0; j < MAX_PER_SERV; j++)
            {
                if (peer_chrs[i*MAX_PER_SERV + j] == NULL)
                    break;
                if (0 == ble_uuid_cmp(&peer_chrs[i*MAX_PER_SERV + j]->uuid, &chr_uuid)) {
                    *chr = peer_chrs[i*MAX_PER_SERV + j];
                    return 0;
                }
            }
        }
    }
    return -1;
}

/*
扫描从机的指定服务的特征值的其他属性
@api nimble.discDsc(svr_uuid, chr_uuid)
@string 指定服务的UUID值
@string 特征值的UUID值
@return boolean 成功启动扫描与否
@usage
-- 本函数对central/主机模式适用
*/
static int l_nimble_disc_dsc(lua_State *L) {
    int ret;
    struct ble_gatt_svc *svc;
    struct ble_gatt_chr *chr;
    ret = find_chr(L, &svc, &chr);
    if (ret) {
        LLOGW("bad svr/chr UUID");
        return 0;
    }
    ret = luat_nimble_central_disc_dsc(0, svc, chr);
    if (ret == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}


/*
往指定的服务的指定特征值写入数据
@api nimble.writeChr(svr_uuid, chr_uuid, data)
@string 指定服务的UUID值
@string 指定特征值的UUID值
@string 待写入的数据
@return boolean 成功启动写入与否
@usage
-- 本函数对central/主机模式适用
*/
static int l_nimble_write_chr(lua_State *L) {
    size_t tmp_size = 0;
    int32_t ret = 0;
    const char* tmp;
    struct ble_gatt_svc *svc;
    struct ble_gatt_chr *chr;
    ret = find_chr(L, &svc, &chr);
    if (ret) {
        LLOGW("bad svr/chr UUID");
        return 0;
    }
    // 数据
    tmp = luaL_checklstring(L, 3, &tmp_size);
    ret = luat_nimble_central_write(0, chr, tmp, tmp_size);
    if (ret == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

/*
从指定的服务的指定特征值读取数据(异步)
@api nimble.readChr(svr_uuid, chr_uuid)
@string 指定服务的UUID值
@string 指定特征值的UUID值
@return boolean 成功启动写入与否
@usage
-- 本函数对central/主机模式适用
-- 详细用法请参数 demo/nimble/central
*/
static int l_nimble_read_chr(lua_State *L) {
    int32_t ret = 0;
    struct ble_gatt_svc *svc;
    struct ble_gatt_chr *chr;
    ret = find_chr(L, &svc, &chr);
    if (ret) {
        LLOGW("bad svr/chr UUID");
        return 0;
    }
    ret = luat_nimble_central_read(0, chr);
    if (ret == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

/*
订阅指定的服务的指定特征值
@api nimble.subChr(svr_uuid, chr_uuid)
@string 指定服务的UUID值
@string 指定特征值的UUID值
@return boolean 成功启动订阅与否
@usage
-- 本函数对central/主机模式适用
-- 详细用法请参数 demo/nimble/central
*/
static int l_nimble_subscribe_chr(lua_State *L) {
    int32_t ret = 0;
    struct ble_gatt_svc *svc;
    struct ble_gatt_chr *chr;
    ret = find_chr(L, &svc, &chr);
    if (ret) {
        LLOGW("bad svr/chr UUID");
        return 0;
    }
    ret = luat_nimble_central_subscribe(0, chr, 1);
    if (ret == 0) {
        LLOGD("订阅成功");
        lua_pushboolean(L, 1);
        return 1;
    }
    LLOGD("订阅失败 %d", ret);
    return 0;
}

/*
取消订阅指定的服务的指定特征值
@api nimble.unsubChr(svr_uuid, chr_uuid)
@string 指定服务的UUID值
@string 指定特征值的UUID值
@return boolean 成功启动取消订阅与否
@usage
-- 本函数对central/主机模式适用
-- 详细用法请参数 demo/nimble/central
*/
static int l_nimble_unsubscribe_chr(lua_State *L) {
    int32_t ret = 0;
    struct ble_gatt_svc *svc;
    struct ble_gatt_chr *chr;
    ret = find_chr(L, &svc, &chr);
    if (ret) {
        LLOGW("bad svr/chr UUID");
        return 0;
    }
    ret = luat_nimble_central_subscribe(0, chr, 0);
    if (ret == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
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
    { "config",         ROREG_FUNC(l_nimble_config)},

    // 外设模式, 广播并等待连接
    { "send_msg",       ROREG_FUNC(l_nimble_send_msg)},
    { "sendNotify",     ROREG_FUNC(l_nimble_send_notify)},
    { "sendIndicate",   ROREG_FUNC(l_nimble_send_indicate)},
    { "setUUID",        ROREG_FUNC(l_nimble_set_uuid)},
    { "setChr",         ROREG_FUNC(l_nimble_set_chr)},
    { "mac",            ROREG_FUNC(l_nimble_mac)},
    { "server_init",    ROREG_FUNC(l_nimble_server_init)},
    { "server_deinit",  ROREG_FUNC(l_nimble_server_deinit)},

    // 中心模式, 扫描并连接外设
    { "scan",           ROREG_FUNC(l_nimble_scan)},
    { "connect",        ROREG_FUNC(l_nimble_connect)},
    { "disconnect",     ROREG_FUNC(l_nimble_disconnect)},
    { "discSvr",        ROREG_FUNC(l_nimble_disc_svr)},
    { "discChr",        ROREG_FUNC(l_nimble_disc_chr)},
    { "discDsc",        ROREG_FUNC(l_nimble_disc_dsc)},
    { "listSvr",        ROREG_FUNC(l_nimble_list_svr)},
    { "listChr",        ROREG_FUNC(l_nimble_list_chr)},
    { "readChr",        ROREG_FUNC(l_nimble_read_chr)},
    { "writeChr",       ROREG_FUNC(l_nimble_write_chr)},
    { "subChr",         ROREG_FUNC(l_nimble_subscribe_chr)},
    { "unsubChr",       ROREG_FUNC(l_nimble_unsubscribe_chr)},

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

    // FLAGS
    //@const CHR_F_WRITE number chr的FLAGS值, 可写, 且需要响应
    {"CHR_F_WRITE",                ROREG_INT(BLE_GATT_CHR_F_WRITE)},
    //@const CHR_F_READ number chr的FLAGS值, 可读
    {"CHR_F_READ",                 ROREG_INT(BLE_GATT_CHR_F_READ)},
    //@const CHR_F_WRITE_NO_RSP number chr的FLAGS值, 可写, 不需要响应
    {"CHR_F_WRITE_NO_RSP",         ROREG_INT(BLE_GATT_CHR_F_WRITE_NO_RSP)},
    //@const CHR_F_NOTIFY number chr的FLAGS值, 可订阅, 不需要回复
    {"CHR_F_NOTIFY",               ROREG_INT(BLE_GATT_CHR_F_NOTIFY)},
    //@const CHR_F_INDICATE number chr的FLAGS值, 可订阅, 需要回复
    {"CHR_F_INDICATE",             ROREG_INT(BLE_GATT_CHR_F_INDICATE)},

    // CONFIG
    //@const CFG_ADDR_ORDER number UUID的转换的大小端, 结合config函数使用, 默认0, 可选0/1
    {"CFG_ADDR_ORDER",                ROREG_INT(CFG_ADDR_ORDER)},

	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_nimble( lua_State *L ) {
    memcpy(&ble_peripheral_srv_uuid, BLE_UUID16_DECLARE(WM_GATT_SVC_UUID), sizeof(ble_uuid16_t));
    memcpy(&s_chr_uuids[0], BLE_UUID16_DECLARE(WM_GATT_WRITE_UUID), sizeof(ble_uuid16_t));
    memcpy(&s_chr_uuids[1], BLE_UUID16_DECLARE(WM_GATT_INDICATE_UUID), sizeof(ble_uuid16_t));
    memcpy(&s_chr_uuids[2], BLE_UUID16_DECLARE(WM_GATT_NOTIFY_UUID), sizeof(ble_uuid16_t));

    s_chr_flags[0] = BLE_GATT_CHR_F_WRITE;
    s_chr_flags[1] = BLE_GATT_CHR_F_INDICATE;
    s_chr_flags[2] = BLE_GATT_CHR_F_NOTIFY;

    rotable2_newlib(L, reg_nimble);
    return 1;
}

