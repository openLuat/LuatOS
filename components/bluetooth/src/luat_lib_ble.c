/*
@module ble
@summary 低功耗蓝牙
@version 1.0
@date    2025.6.21
@usage
-- 本库用于操作BLE对象, 需要搭配bluetooth.init()使用
-- 详细用法请查阅demo
-- UUID字符串为大端二进制字节, 如string.fromHex("FA00"), 不是文本"FA00"。
-- 也可使用整数UUID, 如0xFA00; 与二进制字符串表示的字节顺序相同。

-- 模式解释
-- 从机模式(peripheral), 设备会被扫描到, 并且可以被连接
-- 主机模式(central), 设备会扫描其他设备, 并且可以连接其他设备
-- 广播者模式(ibeacon), 设备会周期性的广播beacon信息, 但不会被扫描到, 也不会连接其他设备
-- 观察者模式(scan), 设备会扫描其他设备, 但不会连接其他设备

-- 从机模式(peripheral)的基本流程(概要描述)
-- 1. 初始化蓝牙框架
-- 2. 创建BLE对象
-- local ble_device = bluetooth_device:ble(ble_event_cb)
-- 3. 创建GATT描述
-- local att_db = {xxx}
-- 4. 创建广播信息
-- ble_device:adv_create(adv_data)
-- 5. 开始广播
-- ble_device:adv_start()
-- 6. 等待连接
-- 7. 在回调函数中处理连接事件, 如接收数据, 发送数据等

-- 主机模式(central)的基本流程(概要描述)
-- TODO

-- 广播者模式(ibeacon)的基本流程(概要描述)
-- TODO

-- 观察者模式(scan)的基本流程(概要描述)
-- 1. 初始化蓝牙框架
-- 2. 创建BLE对象
-- local ble_device = bluetooth_device:ble(ble_event_cb)
-- 3. 开始扫描
-- ble_device:scan_start()
-- 4. 在回调函数中处理扫描事件, 如接收设备信息等
-- 5. 按需停止扫描
-- ble_device:scan_stop()
*/
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_ble.h"
#include "luat_bluetooth.h"

#include "luat_log.h"
#define LUAT_LOG_TAG "bt.ble"

#define LUAT_BLE_TYPE "BLE*"

extern int g_bt_ble_ref;
extern int g_ble_lua_cb_ref;
extern uint32_t luat_ble_lua_generation(void);

/* Lua UUID strings are binary, in display (big-endian) order. Integers use
 * the same representation; the controller port performs any wire swap. */
static int ble_parse_uuid(lua_State *L, int index, luat_ble_uuid_t *uuid) {
    memset(uuid, 0, sizeof(*uuid));
    if (lua_type(L, index) == LUA_TSTRING) {
        size_t len;
        const char *data = lua_tolstring(L, index, &len);
        if (len != 2 && len != 4 && len != 16) return -1;
        uuid->uuid_type = (luat_ble_uuid_type)len;
        memcpy(uuid->uuid, data, len);
        return 0;
    }
    if (lua_isinteger(L, index)) {
        lua_Integer value = lua_tointeger(L, index);
        if (value < 0 || (uint64_t)value > UINT32_MAX) return -1;
        uuid->uuid_type = value <= UINT16_MAX ? LUAT_BLE_UUID_TYPE_16 : LUAT_BLE_UUID_TYPE_32;
        for (int i = uuid->uuid_type - 1; i >= 0; i--) {
            uuid->uuid[i] = (uint8_t)value;
            value >>= 8;
        }
        return 0;
    }
    return -1;
}

static int ble_validate_value_args(lua_State *L, int has_value) {
    static const char *fields[] = {"uuid_service", "uuid_characteristic", "uuid_descriptor"};
    if (!lua_istable(L, 2)) return 0;
    /* Snapshot once: an __index method must not change a UUID between
     * length validation and the existing value-operation wrappers' copies. */
    lua_newtable(L);
    int parsed = lua_gettop(L);
    for (size_t i = 0; i < 3; i++) {
        luat_ble_uuid_t uuid;
        lua_getfield(L, 2, fields[i]);
        if (i == 2 && lua_isnil(L, -1)) {
            lua_pop(L, 1);
            continue;
        }
        int valid = !ble_parse_uuid(L, -1, &uuid);
        lua_pop(L, 1);
        if (!valid) { lua_pop(L, 1); return 0; }
        lua_pushlstring(L, (const char *)uuid.uuid, uuid.uuid_type);
        lua_setfield(L, parsed, fields[i]);
    }
    lua_replace(L, 2);
    if (has_value) {
        size_t len;
        if (lua_type(L, 3) != LUA_TSTRING) return 0;
        lua_tolstring(L, 3, &len);
        if (len > UINT16_MAX) return 0;
    }
    return 1;
}

static void ble_free_gatt(luat_ble_gatt_service_t *gatt) {
    if (!gatt) return;
    if (gatt->characteristics) {
        for (size_t i = 0; i < gatt->characteristics_num; i++) {
            luat_ble_gatt_chara_t *ch = &gatt->characteristics[i];
            if (ch->descriptor) {
                for (size_t j = 0; j < ch->descriptors_num; j++) {
                    luat_heap_free(ch->descriptor[j].value);
                }
                luat_heap_free(ch->descriptor);
            }
            luat_heap_free(ch->value);
        }
        luat_heap_free(gatt->characteristics);
    }
    luat_heap_free(gatt);
}

#ifndef LUAT_USE_DRV_BLUETOOTH
typedef struct ble_lua_gatt {
    luat_ble_gatt_service_t *service;
    struct ble_lua_gatt *next;
} ble_lua_gatt_t;

/* Native controllers borrow these trees, even on a create timeout. Only the
 * Lua task owns this list; controller callbacks must never modify the list. */
static ble_lua_gatt_t *s_lua_gatts;
#endif

/* Call only after successful controller teardown, when all borrowing ends.
 * Read current value pointers: native write_value may have replaced them. */
void luat_ble_lua_release_gatt(void) {
#ifndef LUAT_USE_DRV_BLUETOOTH
    while (s_lua_gatts) {
        ble_lua_gatt_t *entry = s_lua_gatts;
        s_lua_gatts = entry->next;
        ble_free_gatt(entry->service);
        luat_heap_free(entry);
    }
#endif
}

static int ble_copy_bytes(uint8_t **dst, const uint8_t *src, size_t len) {
    *dst = NULL;
    if (!len) return 0;
    if (!src) return -1;
    *dst = luat_heap_malloc(len);
    if (!*dst) return -1;
    memcpy(*dst, src, len);
    return 0;
}

static luat_ble_gatt_service_t *ble_copy_gatt(const luat_ble_gatt_service_t *src) {
    if (!src || (src->characteristics_num && !src->characteristics)) return NULL;
    luat_ble_gatt_service_t *dst = luat_heap_malloc(sizeof(*dst));
    if (!dst) return NULL;
    *dst = *src;
    dst->characteristics = NULL;
    if (src->characteristics_num) {
        dst->characteristics = luat_heap_calloc(src->characteristics_num, sizeof(*dst->characteristics));
        if (!dst->characteristics) goto fail;
    }
    for (size_t i = 0; i < src->characteristics_num; i++) {
        const luat_ble_gatt_chara_t *sc = &src->characteristics[i];
        luat_ble_gatt_chara_t *dc = &dst->characteristics[i];
        *dc = *sc;
        dc->value = NULL;
        dc->descriptor = NULL;
        if (ble_copy_bytes(&dc->value, sc->value, sc->value_len)) goto fail;
        if (sc->descriptors_num) {
            if (!sc->descriptor) goto fail;
            dc->descriptor = luat_heap_calloc(sc->descriptors_num, sizeof(*dc->descriptor));
            if (!dc->descriptor) goto fail;
        }
        for (size_t j = 0; j < sc->descriptors_num; j++) {
            dc->descriptor[j] = sc->descriptor[j];
            if (ble_copy_bytes(&dc->descriptor[j].value, sc->descriptor[j].value,
                               sc->descriptor[j].value_len)) goto fail;
        }
    }
    return dst;
fail:
    ble_free_gatt(dst);
    return NULL;
}

static void ble_free_event(luat_ble_event_t evt, luat_ble_param_t *param) {
    if (!param) return;
    switch (evt) {
    case LUAT_BLE_EVENT_WRITE:
        luat_heap_free(param->write_req.value);
        break;
    case LUAT_BLE_EVENT_READ:
    case LUAT_BLE_EVENT_READ_VALUE:
        luat_heap_free(param->read_req.value);
        break;
    case LUAT_BLE_EVENT_SCAN_REPORT:
        luat_heap_free(param->adv_req.data);
        break;
    case LUAT_BLE_EVENT_GATT_ITEM:
        ble_free_gatt(param->gatt_item_ind.gatt_service);
        break;
    default:
        break;
    }
    luat_heap_free(param);
}

/* User errors must not bypass release of the queued event. */
static void ble_call_lua(lua_State *L, int nargs) {
    if (lua_pcall(L, nargs, 0, 0) != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        LLOGE("BLE callback failed: %s", error ? error : "non-string error");
        lua_pop(L, 1);
    }
}

int l_ble_callback(lua_State *L, void *ptr)
{
    (void)ptr;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    luat_ble_event_t evt = (luat_ble_event_t)msg->arg1;
    luat_ble_param_t *param = (luat_ble_param_t *)msg->ptr;
    uint8_t tmpbuff[16] = {0};

    if ((uint32_t)msg->arg2 != luat_ble_lua_generation() ||
        g_ble_lua_cb_ref <= 0 || g_bt_ble_ref <= 0) goto exit;
    lua_geti(L, LUA_REGISTRYINDEX, g_ble_lua_cb_ref);
    if (lua_isfunction(L, -1)){
        lua_geti(L, LUA_REGISTRYINDEX, g_bt_ble_ref);
        lua_pushinteger(L, evt);
    }else{
        LLOGE("用户回调函数不存在");
        lua_pop(L, 1);
        goto exit;
    }

    switch (evt){
    case LUAT_BLE_EVENT_WRITE:{
        luat_ble_write_req_t *write_req = &(param->write_req);

        lua_createtable(L, 0, 5);
        lua_pushliteral(L, "handle");
        lua_pushinteger(L, write_req->handle);
        lua_settable(L, -3);

        lua_pushliteral(L, "uuid_service");
        lua_pushlstring(L, (const char *)write_req->uuid_service.uuid, write_req->uuid_service.uuid_type);
        lua_settable(L, -3);
        lua_pushliteral(L, "uuid_characteristic");
        lua_pushlstring(L, (const char *)write_req->uuid_characteristic.uuid, write_req->uuid_characteristic.uuid_type);
        lua_settable(L, -3);
        if (write_req->uuid_descriptor.uuid[0] != 0 || write_req->uuid_descriptor.uuid[1] != 0){
            lua_pushliteral(L, "uuid_descriptor");
            lua_pushlstring(L, (const char *)write_req->uuid_descriptor.uuid, write_req->uuid_descriptor.uuid_type);
            lua_settable(L, -3);
        }

        lua_pushliteral(L, "data");
        lua_pushlstring(L, (const char *)write_req->value, write_req->value_len);
        lua_settable(L, -3);
        ble_call_lua(L, 3);
        break;
    }
    case LUAT_BLE_EVENT_READ:
    case LUAT_BLE_EVENT_READ_VALUE:{
        luat_ble_read_req_t *read_req = &(param->read_req);
        lua_createtable(L, 0, 5);
        lua_pushliteral(L, "handle");
        lua_pushinteger(L, read_req->handle);
        lua_settable(L, -3);

        lua_pushliteral(L, "uuid_service");
        lua_pushlstring(L, (const char *)read_req->uuid_service.uuid, read_req->uuid_service.uuid_type);
        lua_settable(L, -3);
        lua_pushliteral(L, "uuid_characteristic");
        lua_pushlstring(L, (const char *)read_req->uuid_characteristic.uuid, read_req->uuid_characteristic.uuid_type);
        lua_settable(L, -3);
        if (read_req->uuid_descriptor.uuid[0] != 0 || read_req->uuid_descriptor.uuid[1] != 0){
            lua_pushliteral(L, "uuid_descriptor");
            lua_pushlstring(L, (const char *)read_req->uuid_descriptor.uuid, read_req->uuid_descriptor.uuid_type);
            lua_settable(L, -3);
        }
        if (evt == LUAT_BLE_EVENT_READ_VALUE){
            lua_pushliteral(L, "data");
            lua_pushlstring(L, (const char *)read_req->value, read_req->value_len);
            lua_settable(L, -3);
        }
        ble_call_lua(L, 3);
        break;
    }case LUAT_BLE_EVENT_SCAN_REPORT:{
        luat_ble_adv_req_t *adv_req = &(param->adv_req);
        lua_createtable(L, 0, 4);

        lua_pushliteral(L, "rssi");
        lua_pushinteger(L, adv_req->rssi);
        lua_settable(L, -3);
        lua_pushliteral(L, "addr_type");
        lua_pushinteger(L, adv_req->adv_addr_type);
        lua_settable(L, -3);
        lua_pushliteral(L, "adv_addr");
        lua_pushlstring(L, (const char *)adv_req->adv_addr, 6);
        lua_settable(L, -3);
        lua_pushliteral(L, "data");
        lua_pushlstring(L, (const char *)adv_req->data, adv_req->data_len);
        lua_settable(L, -3);
        // uint8_t actv_idx;     /**< The index of the activity */
        // uint8_t evt_type;     /**< Event type (see enum \ref adv_report_info and see enum \ref adv_report_type)*/

        ble_call_lua(L, 3);
        break;
    }case LUAT_BLE_EVENT_GATT_ITEM:{
        luat_ble_gatt_service_t *gatt_service = param->gatt_item_ind.gatt_service;
        lua_newtable(L);
        // servise uuid
        lua_pushlstring(L, (const char *)gatt_service->uuid, gatt_service->uuid_type);
        lua_rawseti(L, -2, 1);
        // characteristics
        uint8_t characteristics_num = gatt_service->characteristics_num;
        for (size_t m = 0; m < characteristics_num; m++){
            luat_ble_gatt_chara_t *gatt_chara = &gatt_service->characteristics[m];
            lua_newtable(L);
            lua_pushlstring(L, (const char *)gatt_chara->uuid, gatt_chara->uuid_type);
            lua_seti(L, -2, 1);
            // Properties
            lua_pushnumber(L, gatt_chara->perm);
            lua_seti(L, -2, 2);

            lua_seti(L, -2, m + 2);
        }
        ble_call_lua(L, 3);
        break;
    }case LUAT_BLE_EVENT_GATT_DONE:{
        uint8_t gatt_service_num = param->gatt_done_ind.gatt_service_num;
        lua_newtable(L);
        lua_pushinteger(L, gatt_service_num);
        lua_setfield(L, -2, "service_num");
        ble_call_lua(L, 3);
        break;
    }case LUAT_BLE_EVENT_CONN:{
        luat_ble_conn_ind_t *conn = &(param->conn_ind);
        lua_newtable(L);
        memcpy(tmpbuff, conn->peer_addr, 6);
        luat_bluetooth_mac_swap(tmpbuff);
        lua_pushlstring(L, (const char *)tmpbuff, 6);
        lua_setfield(L, -2, "addr");
        lua_pushinteger(L, conn->peer_addr_type);
        lua_setfield(L, -2, "addr_type");
        ble_call_lua(L, 3);
        break;
    }case LUAT_BLE_EVENT_DISCONN:{
        luat_ble_disconn_ind_t *disconn = &(param->disconn_ind);
        lua_newtable(L);
        lua_pushinteger(L, disconn->reason);
        lua_setfield(L, -2, "reason");
        ble_call_lua(L, 3);
        break;
    }
    default:
        ble_call_lua(L, 2);
        break;
    }
exit:
    ble_free_event(evt, param);
    return 0;
}

void luat_ble_cb(luat_ble_t *args, luat_ble_event_t ble_event, luat_ble_param_t *ble_param){
    /* Runs on the transport task: copy borrowed data, never call Lua or RPC. */
    uint32_t generation = luat_ble_lua_generation();
    if (!generation) return;
    luat_ble_param_t *luat_ble_param = NULL;
    if (!ble_param && (ble_event == LUAT_BLE_EVENT_WRITE ||
        ble_event == LUAT_BLE_EVENT_READ || ble_event == LUAT_BLE_EVENT_READ_VALUE ||
        ble_event == LUAT_BLE_EVENT_SCAN_REPORT || ble_event == LUAT_BLE_EVENT_GATT_ITEM ||
        ble_event == LUAT_BLE_EVENT_GATT_DONE || ble_event == LUAT_BLE_EVENT_CONN ||
        ble_event == LUAT_BLE_EVENT_DISCONN)) return;
    if (ble_param){
        luat_ble_param = luat_heap_malloc(sizeof(luat_ble_param_t));
        if (!luat_ble_param) return;
        memcpy(luat_ble_param, ble_param, sizeof(luat_ble_param_t));
        if (ble_event == LUAT_BLE_EVENT_WRITE){
            if (ble_copy_bytes(&luat_ble_param->write_req.value, ble_param->write_req.value,
                               ble_param->write_req.value_len)) goto fail;
        }else if (ble_event == LUAT_BLE_EVENT_READ || ble_event == LUAT_BLE_EVENT_READ_VALUE){
            if (ble_copy_bytes(&luat_ble_param->read_req.value, ble_param->read_req.value,
                               ble_param->read_req.value_len)) goto fail;
        }else if (ble_event == LUAT_BLE_EVENT_SCAN_REPORT){
            if (ble_copy_bytes(&luat_ble_param->adv_req.data, ble_param->adv_req.data,
                               ble_param->adv_req.data_len)) goto fail;
        }else if (ble_event == LUAT_BLE_EVENT_GATT_ITEM){
            luat_ble_param->gatt_item_ind.gatt_service = ble_copy_gatt(ble_param->gatt_item_ind.gatt_service);
            if (!luat_ble_param->gatt_item_ind.gatt_service) goto fail;
        }
    }

    rtos_msg_t msg = {
        .handler = l_ble_callback,
        .ptr = luat_ble_param,
        .arg1 = (int)ble_event,
        .arg2 = (int)generation,
    };
    if (luat_msgbus_put(&msg, 0) == 0) return;
fail:
    ble_free_event(ble_event, luat_ble_param);
}

/*
创建一个BLE GATT服务
@api ble.gatt_create(opts)
@table GATT服务的描述信息
@return boolean 是否创建成功
@usage
local att_db = { -- Service
    string.fromHex("FA00"), -- Service UUID, 服务的UUID, 可以是16位、32位或128位
    -- Characteristic
    { -- Characteristic 1
        string.fromHex("EA01"), -- Characteristic UUID Value, 特征的UUID值, 可以是16位、32位或128位
        ble.NOTIFY | ble.READ | ble.WRITE -- Properties, 对应蓝牙特征的属性, 参考权限常量
        string.fromHex("1234"), -- 默认value
    }
}
ble_device:gatt_create(att_db)
*/
static int l_ble_gatt_create(lua_State *L){
    int top = lua_gettop(L);
    luat_ble_gatt_service_t *gatt = NULL;
    luat_ble_uuid_t uuid;
    if (!lua_isuserdata(L, 1) || !lua_istable(L, 2)) goto error_exit;
#ifndef LUAT_USE_DRV_BLUETOOTH
    /* A retained tree must have a live Lua BLE owner that can tear it down. */
    if (g_bt_ble_ref <= 0 || !luat_ble_lua_generation()) goto error_exit;
    lua_rawgeti(L, LUA_REGISTRYINDEX, g_bt_ble_ref);
    int current = lua_rawequal(L, 1, -1);
    lua_pop(L, 1);
    if (!current) goto error_exit;
#endif
    size_t count = lua_rawlen(L, 2);
    if (count < 2 || count > UINT8_MAX + 1U) goto error_exit;
    lua_rawgeti(L, 2, 1);
    if (ble_parse_uuid(L, -1, &uuid)) goto error_exit;
    lua_pop(L, 1);
    gatt = luat_heap_calloc(1, sizeof(*gatt));
    if (!gatt) goto error_exit;
    gatt->uuid_type = uuid.uuid_type;
    memcpy(gatt->uuid, uuid.uuid, sizeof(gatt->uuid));
    gatt->characteristics = luat_heap_calloc(count - 1, sizeof(*gatt->characteristics));
    if (!gatt->characteristics) goto error_exit;
    for (size_t i = 2; i <= count; i++) {
        if (lua_rawgeti(L, 2, i) != LUA_TTABLE) goto error_exit;
        int entry = lua_gettop(L);
        lua_rawgeti(L, entry, 1);
        if (ble_parse_uuid(L, -1, &uuid)) goto error_exit;
        lua_pop(L, 1);
        uint16_t *perm, *max_size, *value_len;
        uint8_t **value;
        uint16_t short_uuid = ((uint16_t)uuid.uuid[0] << 8) | uuid.uuid[1];
        if (uuid.uuid_type == LUAT_BLE_UUID_TYPE_16 &&
            short_uuid >= LUAT_BLE_GATT_DESC_MIN && short_uuid <= LUAT_BLE_GATT_DESC_MAX) {
            if (!gatt->characteristics_num) goto error_exit;
            luat_ble_gatt_chara_t *ch = &gatt->characteristics[gatt->characteristics_num - 1];
            if (ch->descriptors_num == UINT8_MAX) goto error_exit;
            luat_ble_gatt_descriptor_t *descs = luat_heap_realloc(ch->descriptor,
                (ch->descriptors_num + 1) * sizeof(*descs));
            if (!descs) goto error_exit;
            ch->descriptor = descs;
            luat_ble_gatt_descriptor_t *desc = &descs[ch->descriptors_num++];
            memset(desc, 0, sizeof(*desc));
            desc->uuid_type = uuid.uuid_type;
            memcpy(desc->uuid, uuid.uuid, sizeof(desc->uuid));
            perm = &desc->perm; max_size = &desc->max_size;
            value = &desc->value; value_len = &desc->value_len;
        } else {
            luat_ble_gatt_chara_t *ch = &gatt->characteristics[gatt->characteristics_num++];
            ch->uuid_type = uuid.uuid_type;
            memcpy(ch->uuid, uuid.uuid, sizeof(ch->uuid));
            perm = &ch->perm; max_size = &ch->max_size;
            value = &ch->value; value_len = &ch->value_len;
        }
        lua_rawgeti(L, entry, 2);
        if (!lua_isinteger(L, -1) || lua_tointeger(L, -1) < 0 ||
            lua_tointeger(L, -1) > UINT16_MAX) goto error_exit;
        *perm = (uint16_t)lua_tointeger(L, -1);
        lua_pop(L, 1);
        lua_rawgeti(L, entry, 3);
        if (!lua_isnil(L, -1)) {
            size_t len;
            if (lua_type(L, -1) != LUA_TSTRING) goto error_exit;
            const char *data = lua_tolstring(L, -1, &len);
            if (len > UINT16_MAX || ble_copy_bytes(value, (const uint8_t *)data, len)) goto error_exit;
            *value_len = (uint16_t)len;
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "max_size");
        lua_rawget(L, entry);
        *max_size = *value_len > 255 ? *value_len : 255;
        if (!lua_isnil(L, -1)) {
            if (!lua_isinteger(L, -1) || lua_tointeger(L, -1) < *value_len ||
                lua_tointeger(L, -1) > UINT16_MAX) goto error_exit;
            *max_size = (uint16_t)lua_tointeger(L, -1);
        }
        lua_pop(L, 2);
    }
    /* Add one CCCD for notify or indicate unless explicitly supplied. */
    for (size_t i = 0; i < gatt->characteristics_num; i++) {
        luat_ble_gatt_chara_t *ch = &gatt->characteristics[i];
        if (!(ch->perm & (LUAT_BLE_GATT_PERM_NOTIFY | LUAT_BLE_GATT_PERM_IND))) continue;
        size_t j;
        for (j = 0; j < ch->descriptors_num; j++) {
            if (ch->descriptor[j].uuid_type == LUAT_BLE_UUID_TYPE_16 &&
                ch->descriptor[j].uuid[0] == 0x29 && ch->descriptor[j].uuid[1] == 0x02) break;
        }
        if (j < ch->descriptors_num) continue;
        if (ch->descriptors_num == UINT8_MAX) goto error_exit;
        luat_ble_gatt_descriptor_t *descs = luat_heap_realloc(ch->descriptor,
            (ch->descriptors_num + 1) * sizeof(*descs));
        if (!descs) goto error_exit;
        ch->descriptor = descs;
        luat_ble_gatt_descriptor_t *desc = &descs[ch->descriptors_num++];
        memset(desc, 0, sizeof(*desc));
        desc->uuid_type = LUAT_BLE_UUID_TYPE_16;
        desc->uuid[0] = 0x29; desc->uuid[1] = 0x02;
        desc->perm = LUAT_BLE_GATT_PERM_READ | LUAT_BLE_GATT_PERM_WRITE;
        desc->max_size = 2;
    }
#ifndef LUAT_USE_DRV_BLUETOOTH
    /* Allocate tracking before calling the backend: even a failed call can
     * retain the tree until teardown, so there must be no allocation afterward. */
    ble_lua_gatt_t *entry = luat_heap_malloc(sizeof(*entry));
    if (!entry) goto error_exit;
    entry->service = gatt;
    entry->next = s_lua_gatts;
    s_lua_gatts = entry;
#else
    /* Both RPC and legacy driver ports consume the tree, including failures. */
#endif
    lua_pushboolean(L, luat_ble_create_gatt(NULL, gatt) == 0);
    return 1;
error_exit:
    ble_free_gatt(gatt);
    lua_settop(L, top);
    lua_pushboolean(L, 0);
    return 1;
}

/*
创建一个BLE广播
@api ble.adv_create(opts)
@table 广播的描述信息
@return boolean 是否创建成功
@usage
-- 创建广播信息
ble_device:adv_create({
    addr_mode = ble.PUBLIC, -- 广播地址模式, 可选值: ble.PUBLIC, ble.RANDOM, ble.RPA, ble.NRPA
    channel_map = ble.CHNLS_ALL, -- 广播的通道, 可选值: ble.CHNLS_37, ble.CHNLS_38, ble.CHNLS_39, ble.CHNLS_ALL
    intv_min = 120, -- 广播间隔最小值, 单位为0.625ms, 最小值为20, 最大值为10240
    intv_max = 120, -- 广播间隔最大值, 单位为0.625ms, 最小值为20, 最大值为10240
    adv_data = { -- 支持表格形式, 也支持字符串形式(255字节以内)
        {ble.FLAGS, string.char(0x06)},
        {ble.COMPLETE_LOCAL_NAME, "LuatOS123"}, -- 广播的设备名
        {ble.SERVICE_DATA, string.fromHex("FE01")}, -- 广播的服务数据
        {ble.MANUFACTURER_SPECIFIC_DATA, string.fromHex("05F0")}
    }
})
*/
static int l_ble_advertising_create(lua_State *L){
    if (!lua_isuserdata(L, 1)){
        return 0;
    }
    if (lua_type(L, 2) != LUA_TTABLE){
        LLOGE("error param");
        return 0;
    }
    size_t len = 0;
    uint8_t local_name_set_flag = 0;
    char complete_local_name[32] = {0};

    luat_ble_adv_cfg_t luat_ble_adv_cfg = {
        .addr_mode = LUAT_BLE_ADDR_MODE_PUBLIC,
        .channel_map = LUAT_BLE_ADV_CHNLS_ALL,
        .intv_min = 120,
        .intv_max = 160,
        .adv_type = LUAT_BLE_ADV_TYPE_LEGACY,
        .adv_prop = LUAT_BLE_ADV_PROP_CONNECTABLE|LUAT_BLE_ADV_PROP_SCANNABLE,
    };

    lua_pushstring(L, "addr_mode");
    if (LUA_TNUMBER == lua_gettable(L, 2)){
        luat_ble_adv_cfg.addr_mode = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    lua_pushstring(L, "channel_map");
    if (LUA_TNUMBER == lua_gettable(L, 2)){
        luat_ble_adv_cfg.channel_map = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    lua_pushstring(L, "intv_min");
    if (LUA_TNUMBER == lua_gettable(L, 2)){
        luat_ble_adv_cfg.intv_min = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    lua_pushstring(L, "intv_max");
    if (LUA_TNUMBER == lua_gettable(L, 2)){
        luat_ble_adv_cfg.intv_max = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    lua_pushstring(L, "adv_type");
    if (LUA_TNUMBER == lua_gettable(L, 2)){
        luat_ble_adv_cfg.adv_type = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    lua_pushstring(L, "adv_prop");
    if (LUA_TNUMBER == lua_gettable(L, 2)){
        luat_ble_adv_cfg.adv_prop = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    if (luat_ble_create_advertising(NULL, &luat_ble_adv_cfg)) {
        lua_pushboolean(L, 0);
        return 1;
    }

    // 广播内容 (adv data)
    uint8_t adv_data[255] = {0};
    size_t adv_index = 0;

    lua_pushstring(L, "adv_data");
    if (LUA_TTABLE == lua_gettable(L, 2)){
        int adv_data_count = luaL_len(L, -1);
        for (int i = 1; i <= adv_data_count; i++){
            lua_rawgeti(L, -1, i);
            if (LUA_TTABLE == lua_type(L, -1)){
                lua_rawgeti(L, -1, 2);
                if (lua_type(L, -1) == LUA_TSTRING){
                    const char *data = luaL_checklstring(L, -1, &len);
                    if (len > 253 || adv_index + len + 2 > sizeof(adv_data)) goto end;
                    adv_data[adv_index++] = (uint8_t)(len + 1);
                    lua_rawgeti(L, -2, 1);
                    if (lua_type(L, -1) == LUA_TNUMBER){
                        uint8_t adv_type = (uint8_t)luaL_checknumber(L, -1);
                        adv_data[adv_index++] = adv_type;
                        if (adv_type == LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME){
                            if (luat_ble_set_name(NULL, (char *)data, len)) goto end;
                            local_name_set_flag = 1;
                        }
                    }else{
                        LLOGE("error adv_data type");
                        goto end;
                    }
                    memcpy(adv_data + adv_index, data, len);
                    adv_index += len;
                    lua_pop(L, 2);
                }else{
                    LLOGE("error adv_data type");
                    goto end;
                }
            }else{
                LLOGE("error adv_data type");
                goto end;
            }
            lua_pop(L, 1);
        }
    }
    else if (lua_isstring(L, -1)){
        // 字符串形式
        const char *data = luaL_checklstring(L, -1, &len);
        if (len > 255) {
            LLOGE("adv_data too long, max length is 255");
            goto end;
        }
        memcpy(adv_data, data, len);
        adv_index = len;
    }
    else {
        LLOGE("error adv_data type");
        goto end;
    }
    lua_pop(L, 1);

    if (!local_name_set_flag){
        l_sprintf(complete_local_name, sizeof(complete_local_name), "LuatOS_%s", luat_os_bsp());
        if (luat_ble_set_name(NULL, complete_local_name, strlen(complete_local_name))) goto end;
    }

    /* set adv paramters */
    if (luat_ble_set_adv_data(NULL, adv_data, adv_index)) goto end;

    lua_pushstring(L, "rsp_data");
    if (LUA_TSTRING == lua_gettable(L, 2)){
        const char *rsp_data = luaL_checklstring(L, -1, &len);
        if (len > 255) goto end;
        if (len){
            if (luat_ble_set_scan_rsp_data(NULL, (uint8_t *)rsp_data, len)) goto end;
        }
    }
    lua_pop(L, 1);

    lua_pushboolean(L, 1);
    return 1;
end:
    luat_ble_delete_advertising(NULL);
    lua_pushboolean(L, 0);
    return 1;
}

/*
开始广播
@api ble.adv_start()
@return boolean 是否成功
@usage
-- 开始广播
ble_device:adv_start()

-- 提醒, 对于从机模式, 如果被断开了连接, 则需要重新开始广播, 才能被重新搜索到
*/
static int l_ble_advertising_start(lua_State *L){
    lua_pushboolean(L, luat_ble_start_advertising(NULL) ? 0 : 1);
    return 1;
}

/*
主动停止广播
@api ble.adv_stop()
@return boolean 是否成功
@usage
-- 停止广播
ble_device:adv_stop()
*/
static int l_ble_advertising_stop(lua_State *L){
    lua_pushboolean(L, luat_ble_stop_advertising(NULL) ? 0 : 1);
    return 1;
}

/*
写入带通知的特征值
@api ble.write_notify(opts, value)
@table 特征值的描述信息
@string value 要写入的值
@return boolean 是否成功
@usage
-- 写入带通知的特征值
ble_device:write_notify({
    uuid_service = "FA00", -- 服务的UUID, 可以是16位、32位或128位
    uuid_characteristic = "EA01", -- 特征的UUID值, 可以是16位、32位或128位
}, "Hello BLE") -- 要写入的值
*/
static int l_ble_write_notify(lua_State *L){
    if (!ble_validate_value_args(L, 1)) { lua_pushboolean(L, 0); return 1; }
    uint16_t ret = 0;
    const char *service_uuid = NULL;
    const char *characteristic_uuid = NULL;
    const char *descriptor_uuid = NULL;
    luat_ble_uuid_t service = {0};
    luat_ble_uuid_t characteristic = {0};
    luat_ble_uuid_t descriptor = {0};
    size_t tmp = 0;
    if (1){
        size_t len = 0;
        const char *value = luaL_checklstring(L, 3, &len);

        lua_pushstring(L, "uuid_service");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            service_uuid = luaL_checklstring(L, -1, &tmp);
            service.uuid_type = tmp;
            memcpy(service.uuid, service_uuid, service.uuid_type);
            // LLOGD("uuid_service: %02X %02X", service.uuid[0], service.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_service 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_characteristic");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            characteristic_uuid = luaL_checklstring(L, -1, &tmp);
            characteristic.uuid_type = tmp;
            memcpy(characteristic.uuid, characteristic_uuid, characteristic.uuid_type);
            // LLOGD("uuid_characteristic: %02X %02X", characteristic.uuid[0], characteristic.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_characteristic 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_descriptor");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            descriptor_uuid = luaL_checklstring(L, -1, &tmp);
            descriptor.uuid_type = tmp;
            memcpy(descriptor.uuid, descriptor_uuid, descriptor.uuid_type);
            // LLOGD("uuid_descriptor: %02X %02X", descriptor.uuid[0], descriptor.uuid[1]);
            ret = luat_ble_write_notify_value(&service, &characteristic, &descriptor, (uint8_t *)value, len);
        }else{
            ret = luat_ble_write_notify_value(&service, &characteristic, NULL, (uint8_t *)value, len);
        }
        lua_pop(L, 1);
        
        // LLOGD("luat_ble_write_notify_value ret %d", ret);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        return 1;
    }
end_error:
    LLOGE("error param");
    return 0;
}

/*
写入带指示的特征值
@api ble.write_indicate(opts, value)
@table 特征值的描述信息
@string value 要写入的值
@return boolean 是否成功
@usage
-- 写入带指示的特征值
ble_device:write_indicate({
    uuid_service = "FA00", -- 服务的UUID, 可以是16位、32位或128位
    uuid_characteristic = "EA01", -- 特征的UUID值, 可以是16位、32位或128位
}, "Hello BLE") -- 要写入的值
*/
static int l_ble_write_indicate(lua_State *L){
    if (!ble_validate_value_args(L, 1)) { lua_pushboolean(L, 0); return 1; }
    uint16_t ret = 0;
    const char *service_uuid = NULL;
    const char *characteristic_uuid = NULL;
    const char *descriptor_uuid = NULL;
    luat_ble_uuid_t service = {0};
    luat_ble_uuid_t characteristic = {0};
    luat_ble_uuid_t descriptor = {0};
    size_t tmp = 0;
    if (1){
        size_t len = 0;
        const char *value = luaL_checklstring(L, 3, &len);

        lua_pushstring(L, "uuid_service");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            service_uuid = luaL_checklstring(L, -1, &tmp);
            service.uuid_type = tmp;
            memcpy(service.uuid, service_uuid, service.uuid_type);
            // LLOGD("uuid_service: %02X %02X", service.uuid[0], service.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_service 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_characteristic");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            characteristic_uuid = luaL_checklstring(L, -1, &tmp);
            characteristic.uuid_type = tmp;
            memcpy(characteristic.uuid, characteristic_uuid, characteristic.uuid_type);
            // LLOGD("uuid_characteristic: %02X %02X", characteristic.uuid[0], characteristic.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_characteristic 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_descriptor");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            descriptor_uuid = luaL_checklstring(L, -1, &tmp);
            descriptor.uuid_type = tmp;
            memcpy(descriptor.uuid, descriptor_uuid, descriptor.uuid_type);
            // LLOGD("uuid_descriptor: %02X %02X", descriptor.uuid[0], descriptor.uuid[1]);
            ret = luat_ble_write_indicate_value(&service, &characteristic, &descriptor, (uint8_t *)value, len);
        }else{
            ret = luat_ble_write_indicate_value(&service, &characteristic, NULL, (uint8_t *)value, len);
        }
        lua_pop(L, 1);
        
        // LLOGD("luat_ble_write_indicate_value ret %d", ret);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        return 1;
    }
end_error:
    LLOGE("error param");
    return 0;
}

/*
写入特征值
@api ble.write_value(opts, value)
@table 特征值的描述信息
@string value 要写入的值
@return boolean 是否成功
@usage
-- 写入特征值,填充预设值,被动读取
ble_device:write_value({
    uuid_service = "FA00", -- 服务的UUID, 可以是16位、32位或128位
    uuid_characteristic = "EA01", -- 特征的UUID值, 可以是16位、32位或128位
}, "Hello BLE") -- 要写入的值
*/
static int l_ble_write_value(lua_State *L){
    if (!ble_validate_value_args(L, 1)) { lua_pushboolean(L, 0); return 1; }
    uint16_t ret = 0;
    const char *service_uuid = NULL;
    const char *characteristic_uuid = NULL;
    const char *descriptor_uuid = NULL;
    luat_ble_uuid_t service = {0};
    luat_ble_uuid_t characteristic = {0};
    luat_ble_uuid_t descriptor = {0};
    size_t tmp = 0;
    if (1){
        size_t len = 0;
        const char *value = luaL_checklstring(L, 3, &len);

        lua_pushstring(L, "uuid_service");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            service_uuid = luaL_checklstring(L, -1, &tmp);
            service.uuid_type = tmp;
            memcpy(service.uuid, service_uuid, service.uuid_type);
            // LLOGD("uuid_service: %02X %02X", service.uuid[0], service.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_service 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_characteristic");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            characteristic_uuid = luaL_checklstring(L, -1, &tmp);
            characteristic.uuid_type = tmp;
            memcpy(characteristic.uuid, characteristic_uuid, characteristic.uuid_type);
            // LLOGD("uuid_characteristic: %02X %02X", characteristic.uuid[0], characteristic.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_characteristic 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_descriptor");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            descriptor_uuid = luaL_checklstring(L, -1, &tmp);
            descriptor.uuid_type = tmp;
            memcpy(descriptor.uuid, descriptor_uuid, descriptor.uuid_type);
            // LLOGD("uuid_descriptor: %02X %02X", descriptor.uuid[0], descriptor.uuid[1]);
            ret = luat_ble_write_value(&service, &characteristic, &descriptor, (uint8_t *)value, len);

        }else{
            ret = luat_ble_write_value(&service, &characteristic, NULL, (uint8_t *)value, len);
        }
        lua_pop(L, 1);
        
        // LLOGD("luat_ble_write_value ret %d", ret);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        return 1;
    }
end_error:
    LLOGE("error param");
    return 0;
}

/*
读取特征值
@api ble.read_value(opts)
@table 特征值的描述信息
@return boolean 是否成功
@usage
-- 读取特征值,通过回调中的 EVENT_READ_VALUE 事件返回读取的value值
ble_device:read_value({
    uuid_service = "FA00", -- 服务的UUID, 可以是16位、32位或128位
    uuid_characteristic = "EA01", -- 特征的UUID值, 可以是16位、32位或128位
})
*/
static int l_ble_read_value(lua_State *L){
    if (!ble_validate_value_args(L, 0)) { lua_pushboolean(L, 0); return 1; }
    uint16_t ret = 0;
    const char *service_uuid = NULL;
    const char *characteristic_uuid = NULL;
    const char *descriptor_uuid = NULL;
    luat_ble_uuid_t service = {0};
    luat_ble_uuid_t characteristic = {0};
    luat_ble_uuid_t descriptor = {0};
    size_t tmp = 0;
    if (1){
        uint16_t len = 0;
        uint8_t* value = NULL;

        lua_pushstring(L, "uuid_service");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            service_uuid = luaL_checklstring(L, -1, &tmp);
            service.uuid_type = tmp;
            memcpy(service.uuid, service_uuid, service.uuid_type);
            // LLOGD("uuid_service: %02X %02X", service.uuid[0], service.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_service 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_characteristic");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            characteristic_uuid = luaL_checklstring(L, -1, &tmp);
            characteristic.uuid_type = tmp;
            memcpy(characteristic.uuid, characteristic_uuid, characteristic.uuid_type);
            // LLOGD("uuid_characteristic: %02X %02X", characteristic.uuid[0], characteristic.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_characteristic 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_descriptor");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            descriptor_uuid = luaL_checklstring(L, -1, &tmp);
            descriptor.uuid_type = tmp;
            memcpy(descriptor.uuid, descriptor_uuid, descriptor.uuid_type);
            // LLOGD("uuid_descriptor: %02X %02X", descriptor.uuid[0], descriptor.uuid[1]);
            ret = luat_ble_read_value(&service, &characteristic, &descriptor, &value, &len);

        }else{
            ret = luat_ble_read_value(&service, &characteristic, NULL, &value, &len);
        }
        lua_pop(L, 1);
        if (ret == 0){
#if defined(LUAT_USE_DRV_BLUETOOTH) && defined(LUAT_USE_AIRLINK_RPC)
            /* RPC returns the value later via EVENT_READ_VALUE. */
            lua_pushboolean(L, 1);
#else
            lua_pushlstring(L, (const char *)value, len);
#endif
            return 1;
        }else{
            LLOGE("ble read value error");
            lua_pushboolean(L, 0);
            return 1;
        }
    }
end_error:
    LLOGE("error param");
    return 0;
}

/*
开关通知监听
@api ble.notify_enable(opts, enable)
@table 特征值的描述信息
@boolean enable 开/关 可选,默认开
@return boolean 是否成功
@usage
-- 写入特征值,填充预设值,被动读取
ble_device:notify_enable({
    uuid_service = "FA00", -- 服务的UUID, 可以是16位、32位或128位
    uuid_characteristic = "EA01", -- 特征的UUID值, 可以是16位、32位或128位
}, true) -- 开/关
*/
static int l_ble_notify_enable(lua_State *L){
    if (!ble_validate_value_args(L, 0)) { lua_pushboolean(L, 0); return 1; }
    uint16_t ret = 0;
    const char *service_uuid = NULL;
    const char *characteristic_uuid = NULL;
    luat_ble_uuid_t service = {0};
    luat_ble_uuid_t characteristic = {0};
    size_t tmp = 0;
    if (1){
        uint8_t enable = 1;
        if (lua_isboolean(L, 3)) {
            enable = lua_toboolean(L, 3);
        }
        
        lua_pushstring(L, "uuid_service");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            service_uuid = luaL_checklstring(L, -1, &tmp);
            service.uuid_type = tmp;
            memcpy(service.uuid, service_uuid, service.uuid_type);
            // LLOGD("uuid_service: %02X %02X", service.uuid[0], service.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_service 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_characteristic");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            characteristic_uuid = luaL_checklstring(L, -1, &tmp);
            characteristic.uuid_type = tmp;
            memcpy(characteristic.uuid, characteristic_uuid, characteristic.uuid_type);
            // LLOGD("uuid_characteristic: %02X %02X", characteristic.uuid[0], characteristic.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_characteristic 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        ret = luat_ble_notify_enable(&service, &characteristic, enable);
        
        // LLOGD("luat_ble_write_value ret %d", ret);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        return 1;
    }
end_error:
    LLOGE("error param");
    return 0;
}

/*
开关指示监听
@api ble.indicate_enable(opts, enable)
@table 特征值的描述信息
@boolean enable 开/关 可选,默认开
@return boolean 是否成功
@usage
-- 写入特征值,填充预设值,被动读取
ble_device:indicate_enable({
    uuid_service = "FA00", -- 服务的UUID, 可以是16位、32位或128位
    uuid_characteristic = "EA01", -- 特征的UUID值, 可以是16位、32位或128位
}, true) -- 开/关
*/
static int l_ble_indicate_enable(lua_State *L){
    if (!ble_validate_value_args(L, 0)) { lua_pushboolean(L, 0); return 1; }
    uint16_t ret = 0;
    const char *service_uuid = NULL;
    const char *characteristic_uuid = NULL;
    luat_ble_uuid_t service = {0};
    luat_ble_uuid_t characteristic = {0};
    size_t tmp = 0;
    if (1){
        uint8_t enable = 1;
        if (lua_isboolean(L, 3)) {
            enable = lua_toboolean(L, 3);
        }
        
        lua_pushstring(L, "uuid_service");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            service_uuid = luaL_checklstring(L, -1, &tmp);
            service.uuid_type = tmp;
            memcpy(service.uuid, service_uuid, service.uuid_type);
            // LLOGD("uuid_service: %02X %02X", service.uuid[0], service.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_service 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        lua_pushstring(L, "uuid_characteristic");
        if (LUA_TSTRING == lua_gettable(L, 2)){
            characteristic_uuid = luaL_checklstring(L, -1, &tmp);
            characteristic.uuid_type = tmp;
            memcpy(characteristic.uuid, characteristic_uuid, characteristic.uuid_type);
            // LLOGD("uuid_characteristic: %02X %02X", characteristic.uuid[0], characteristic.uuid[1]);
        }
        else{
            LLOGW("缺失 uuid_characteristic 参数");
            goto end_error;
        }
        lua_pop(L, 1);

        ret = luat_ble_indicate_enable(&service, &characteristic, enable);
        
        // LLOGD("luat_ble_write_value ret %d", ret);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        return 1;
    }
end_error:
    LLOGE("error param");
    return 0;
}


/*
创建一个BLE扫描
@api ble.scan_create(addr_mode, scan_interval, scan_window)
@int addr_mode 广播地址模式, 可选值: ble.PUBLIC, ble.RANDOM, ble.RPA, ble.NRPA
@int scan_interval 扫描间隔, 单位为0.625ms, 最小值为20, 最大值为10240
@int scan_window 扫描窗口, 单位为0.625ms, 最小值为20, 最大值为10240
@int scan_type 扫描类型, 可选值: ble.SCAN_ACTIVE, ble.SCAN_PASSIVE, 默认 ble.SCAN_PASSIVE
@return boolean 是否创建成功
@usage
-- 创建BLE扫描
ble_device:scan_create(ble.PUBLIC, 100, 100)
-- 注意, 创建扫描后需要调用 ble.scan_start() 才能开始扫描
-- 2025.12.26新增参数 scan_type, 可选值: ble.SCAN_ACTIVE, ble.SCAN_PASSIVE
*/
static int l_ble_scanning_create(lua_State *L){
    if (!lua_isuserdata(L, 1)){
        return 0;
    }
    if (1){
        luat_ble_scan_cfg_t cfg = {
            .addr_mode = LUAT_BLE_ADDR_MODE_PUBLIC,
            .scan_interval = 100,
            .scan_window = 100,
        };
        if (lua_isinteger(L, 2))
        {
            cfg.addr_mode = luaL_checkinteger(L, 2);
        }
        if (lua_isinteger(L, 3))
        {
            cfg.scan_interval = luaL_checkinteger(L, 3);
        }
        if (lua_isinteger(L, 4))
        {
            cfg.scan_window = luaL_checkinteger(L, 4);
        }
        if (lua_isinteger(L, 5))
        {
            cfg.scan_type = luaL_checkinteger(L, 5);
        }
        lua_pushboolean(L, luat_ble_create_scanning(NULL, &cfg) ? 0 : 1);
        return 1;
    }
    return 0;
}

/*
开始BLE扫描
@api ble.scan_start()
@return boolean 是否成功
@usage
-- 开始BLE扫描
ble_device:scan_start()
-- 提醒, 扫描会一直进行, 直到调用ble.scan_stop()停止扫描
-- 扫描结果会立即执行回调, 同一个设备不会去重, 扫描到数据就会执行回调
*/
static int l_ble_scanning_start(lua_State *L){
    lua_pushboolean(L, luat_ble_start_scanning(NULL) ? 0 : 1);
    return 1;
}

/*
停止BLE扫描
@api ble.scan_stop()
@return boolean 是否成功
@usage
-- 停止BLE扫描
ble_device:scan_stop()
-- 提醒, 扫描会一直进行, 直到调用ble.scan_stop()停止扫描
*/
static int l_ble_scanning_stop(lua_State *L){
    lua_pushboolean(L, luat_ble_stop_scanning(NULL) ? 0 : 1);
    return 1;
}

/*
BLE连接
@api ble.connect(mac, addr_type)
@string mac 地址
@int 地址类型 ble.PUBLIC ble.RANDOM
@return boolean 启动蓝牙连接是否成功(不代表连接成功, 连接成功会在回调中通过事件通知)
@usage
-- BLE连接
ble_device:connect(string.fromHex("C8478C4E027D"),0)
*/
static int l_ble_connect(lua_State *L){
    size_t len = 0;
    luat_ble_connect_req_t conn = {0};
    const char *adv_addr = luaL_checklstring(L, 2, &len);
    uint8_t adv_addr_type = luaL_checknumber(L, 3);
    if (len != 6){
        LLOGE("error adv_addr len %d", len);
        return 0;
    }
    memcpy(conn.adv_addr, adv_addr, len);
    conn.adv_addr_type = adv_addr_type;
    // LLOGD(" adv_addr_type:%d, adv_addr:%02x:%02x:%02x:%02x:%02x:%02x",
    //       adv_addr_type, adv_addr[0], adv_addr[1], adv_addr[2],
    //       adv_addr[3], adv_addr[4], adv_addr[5]);
    lua_pushboolean(L, luat_ble_connect(NULL, &conn) ? 0 : 1);
    return 1;
}

/*
BLE断开连接
@api ble.disconnect()
@return boolean 是否成功
@usage
-- BLE断开连接
ble_device:disconnect()
*/
static int l_ble_disconnect(lua_State *L){
    lua_pushboolean(L, luat_ble_disconnect(NULL) ? 0 : 1);
    return 1;
}

/*
解码广播数据
@api ble.adv_decode(data)
@string data 广播数据
@return table 广播数据的解码结果
@usage
-- 解码广播数据
local data = string.fromHex("1EFF060001092002BE0F0AAD8A6D2E251ED6DFBB3D15249929E10BE138DF7B")
-- 解析广播数据
local adv_data = ble_device:adv_decode(data)
if adv_data then
    for k, v in pairs(adv_data) do
        log.info("ble", "adv data", v.len, v.tp, v.data:toHex())
    end
end
*/
static int l_ble_adv_decode(lua_State *L) {
    size_t len = 0;
    const char *data = luaL_checklstring(L, 2, &len);
    if (len == 0) {
        lua_pushnil(L);
        return 1;
    }
    lua_newtable(L);
    uint8_t *p = (uint8_t *)data;
    size_t offset = 0;
    int index = 1;
    while (offset < len) {
        uint8_t length = p[offset++];
        if (length == 0 || offset + length > len) {
            LLOGE("Invalid BLE advertisement data");
            lua_pushnil(L);
            return 1;
        }
        uint8_t type = p[offset++];
        lua_newtable(L);
        lua_pushinteger(L, length - 1); // Length does not include the length byte itself
        lua_setfield(L, -2, "len");
        lua_pushinteger(L, type);
        lua_setfield(L, -2, "tp");
        lua_pushlstring(L, (const char *)&p[offset], length - 1); // Data does not include the length byte
        lua_setfield(L, -2, "data");

        lua_seti(L, -2, index);
        offset += length - 1;
        index ++;
    }
    return 1;
}


/*
获取蓝牙MAC
@api ble.mac()
@return string 当前的MAC
@usage
-- 本函数于2025.8.29新增
local mac = ble.mac()
log.info("ble mac", mac and mac:toHex())
*/
static int l_ble_get_mac(lua_State *L){
	uint8_t mac[6] = {0};
    if (luat_bluetooth_get_mac(NULL, mac)) return 0;
    luat_bluetooth_mac_swap(mac);
	lua_pushlstring(L, (const char*)mac, 6);
	return 1;
}


static int _ble_struct_newindex(lua_State *L);

/*
反初始化BLE对象。成功后旧对象失效, 丢弃尚未派发的事件。
可通过bluetooth_device:ble(callback)重新创建BLE对象, 切换主从角色。
@api ble.deinit()
@return boolean 是否成功
@usage
assert(ble_device:deinit())
ble_device = bluetooth_device:ble(callback)
*/
extern int l_bluetooth_ble_deinit(lua_State *L);

void luat_ble_struct_init(lua_State *L){
    luaL_newmetatable(L, LUAT_BLE_TYPE);
    lua_pushcfunction(L, _ble_struct_newindex);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_ble[] = {
    {"deinit",          ROREG_FUNC(l_bluetooth_ble_deinit)},
    // advertise
    {"adv_create",      ROREG_FUNC(l_ble_advertising_create)},
    {"adv_start",       ROREG_FUNC(l_ble_advertising_start)},
    {"adv_stop",        ROREG_FUNC(l_ble_advertising_stop)},
    {"adv_decode",      ROREG_FUNC(l_ble_adv_decode)},

    // gatt
    // slaver
    {"gatt_create",      ROREG_FUNC(l_ble_gatt_create)},
    {"write_notify",     ROREG_FUNC(l_ble_write_notify)},
    {"write_indicate",   ROREG_FUNC(l_ble_write_indicate)},
    {"write_value",      ROREG_FUNC(l_ble_write_value)},
    {"read_value",       ROREG_FUNC(l_ble_read_value)},

    {"notify_enable",    ROREG_FUNC(l_ble_notify_enable)},
    {"indicate_enable",  ROREG_FUNC(l_ble_indicate_enable)},
    
    // scanning
    {"scan_create",      ROREG_FUNC(l_ble_scanning_create)},
    {"scan_start",       ROREG_FUNC(l_ble_scanning_start)},
    {"scan_stop",        ROREG_FUNC(l_ble_scanning_stop)},

    {"connect",          ROREG_FUNC(l_ble_connect)},
    {"disconnect",       ROREG_FUNC(l_ble_disconnect)},

    // 获取蓝牙MAC
    {"mac",             ROREG_FUNC(l_ble_get_mac)},

    // BLE_EVENT
    {"EVENT_NONE", ROREG_INT(LUAT_BLE_EVENT_NONE)},
    {"EVENT_INIT", ROREG_INT(LUAT_BLE_EVENT_INIT)},
    {"EVENT_DEINIT", ROREG_INT(LUAT_BLE_EVENT_DEINIT)},
    {"EVENT_ADV_INIT", ROREG_INT(LUAT_BLE_EVENT_ADV_INIT)},
    {"EVENT_ADV_START", ROREG_INT(LUAT_BLE_EVENT_ADV_START)},
    {"EVENT_ADV_STOP", ROREG_INT(LUAT_BLE_EVENT_ADV_STOP)},
    {"EVENT_ADV_DEINIT", ROREG_INT(LUAT_BLE_EVENT_ADV_DEINIT)},
    {"EVENT_SCAN_INIT", ROREG_INT(LUAT_BLE_EVENT_SCAN_INIT)},
    {"EVENT_SCAN_START", ROREG_INT(LUAT_BLE_EVENT_SCAN_START)},
    {"EVENT_SCAN_STOP", ROREG_INT(LUAT_BLE_EVENT_SCAN_STOP)},
    {"EVENT_SCAN_DEINIT", ROREG_INT(LUAT_BLE_EVENT_SCAN_DEINIT)},
    {"EVENT_SCAN_REPORT", ROREG_INT(LUAT_BLE_EVENT_SCAN_REPORT)},
    {"EVENT_CONN", ROREG_INT(LUAT_BLE_EVENT_CONN)},
    {"EVENT_DISCONN", ROREG_INT(LUAT_BLE_EVENT_DISCONN)},
    {"EVENT_WRITE", ROREG_INT(LUAT_BLE_EVENT_WRITE)},
    {"EVENT_READ", ROREG_INT(LUAT_BLE_EVENT_READ)},
    {"EVENT_READ_VALUE", ROREG_INT(LUAT_BLE_EVENT_READ_VALUE)},
    {"EVENT_GATT_DONE", ROREG_INT(LUAT_BLE_EVENT_GATT_DONE)},
    {"EVENT_GATT_ITEM", ROREG_INT(LUAT_BLE_EVENT_GATT_ITEM)},
    

    // ADV_ADDR_MODE
    //@const PUBLIC 控制器的公共地址
    {"PUBLIC", ROREG_INT(LUAT_BLE_ADDR_MODE_PUBLIC)},
    //@const RANDOM 生成的静态地址
    {"RANDOM", ROREG_INT(LUAT_BLE_ADDR_MODE_RANDOM)},
    {"RPA", ROREG_INT(LUAT_BLE_ADDR_MODE_RPA)},
    {"NRPA", ROREG_INT(LUAT_BLE_ADDR_MODE_NRPA)},

    // ADV_CHNL
    //@const CHNL_37 37通道
    {"CHNL_37", ROREG_INT(LUAT_BLE_ADV_CHNL_37)},
    //@const CHNL_38 38通道
    {"CHNL_38", ROREG_INT(LUAT_BLE_ADV_CHNL_38)},
    //@const CHNL_39 39通道
    {"CHNL_39", ROREG_INT(LUAT_BLE_ADV_CHNL_39)},
    //@const CHNLS_ALL 所有通道(37 38 39)
    {"CHNLS_ALL", ROREG_INT(LUAT_BLE_ADV_CHNLS_ALL)},

    // Permission
    //@const READ 读权限
    {"READ", ROREG_INT(LUAT_BLE_GATT_PERM_READ)},
    //@const WRITE 写权限
    {"WRITE", ROREG_INT(LUAT_BLE_GATT_PERM_WRITE)},
    //@const IND 指示权限
    {"IND", ROREG_INT(LUAT_BLE_GATT_PERM_IND)},
    //@const NOTIFY 通知权限
    {"NOTIFY", ROREG_INT(LUAT_BLE_GATT_PERM_NOTIFY)},
    //@const WRITE_CMD 写权限(无需确认)
    {"WRITE_CMD", ROREG_INT(LUAT_BLE_GATT_PERM_WRITE_CMD)},

    // FLAGS
    {"FLAGS", ROREG_INT(LUAT_ADV_TYPE_FLAGS)},
    {"COMPLETE_LOCAL_NAME", ROREG_INT(LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME)},
    {"SERVICE_DATA", ROREG_INT(LUAT_ADV_TYPE_SERVICE_DATA_16BIT)},
    {"MANUFACTURER_SPECIFIC_DATA", ROREG_INT(LUAT_ADV_TYPE_MANUFACTURER_SPECIFIC_DATA)},

    // adv type
    {"ADV_TYPE_LEGACY", ROREG_INT(LUAT_BLE_ADV_TYPE_LEGACY)},
    {"ADV_TYPE_EXTENDED", ROREG_INT(LUAT_BLE_ADV_TYPE_EXTENDED)},
    {"ADV_TYPE_SCAN_RESPONSE", ROREG_INT(LUAT_BLE_ADV_PERIODIC)},

    // adv prop
    {"ADV_PROP_CONNECTABLE", ROREG_INT(LUAT_BLE_ADV_PROP_CONNECTABLE)},
    {"ADV_PROP_SCANNABLE", ROREG_INT(LUAT_BLE_ADV_PROP_SCANNABLE)},
    {"ADV_PROP_DIRECTED", ROREG_INT(LUAT_BLE_ADV_PROP_DIRECTED)},
    {"ADV_PROP_HDC", ROREG_INT(LUAT_BLE_ADV_PROP_HDC)},
    {"ADV_PROP_ANONYMOUS", ROREG_INT(LUAT_BLE_ADV_PROP_ANONYMOUS)},
    {"ADV_PROP_LEGACY", ROREG_INT(LUAT_BLE_ADV_PROP_LEGACY)},
    {"ADV_PROP_TX_PWR", ROREG_INT(LUAT_BLE_ADV_PROP_TX_PWR)},

    {"SCAN_PASSIVE", ROREG_INT(LUAT_BLE_PASSIVE_SCANNING)},
    {"SCAN_ACTIVE", ROREG_INT(LUAT_BLE_ACTIVE_SCANNING)},
    {NULL, ROREG_INT(0)}};

static int _ble_struct_newindex(lua_State *L){
    const rotable_Reg_t *reg = reg_ble;
    const char *key = luaL_checkstring(L, 2);
    while (1){
        if (reg->name == NULL)
            return 0;
        if (!strcmp(reg->name, key)){
            lua_pushcfunction(L, reg->value.value.func);
            return 1;
        }
        reg++;
    }
}

LUAMOD_API int luaopen_ble(lua_State *L){
    rotable2_newlib(L, reg_ble);
    luat_ble_struct_init(L);
    return 1;
}
