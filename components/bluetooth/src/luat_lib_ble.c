/*
@module ble
@summary 低功耗蓝牙
@version 1.0
@date    2025.6.21
@usage
-- 本库用于操作BLE对象, 需要搭配bluetooth.init()使用
-- 详细用法请查阅demo

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

int l_ble_callback(lua_State *L, void *ptr)
{
    (void)ptr;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    luat_ble_event_t evt = (luat_ble_event_t)msg->arg1;
    luat_ble_param_t *param = (luat_ble_param_t *)msg->arg2;
    uint8_t tmpbuff[16] = {0};

    lua_geti(L, LUA_REGISTRYINDEX, g_ble_lua_cb_ref);
    if (lua_isfunction(L, -1)){
        lua_geti(L, LUA_REGISTRYINDEX, g_bt_ble_ref);
        lua_pushinteger(L, evt);
    }else{
        LLOGE("用户回调函数不存在");
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
        lua_call(L, 3, 0);
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
        lua_call(L, 3, 0);
        if (read_req->value){
            luat_heap_free(read_req->value);
            read_req->value = NULL;
        }
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

        lua_call(L, 3, 0);
        break;
    }case LUAT_BLE_EVENT_GATT_DONE:{
        luat_ble_gatt_service_t **gatt_services = param->gatt_done_ind.gatt_service;
        uint8_t gatt_service_num = param->gatt_done_ind.gatt_service_num;
        lua_createtable(L, gatt_service_num, 0);
        for (size_t i = 0; i < gatt_service_num; i++){
            luat_ble_gatt_service_t *gatt_service = gatt_services[i];
            lua_newtable(L);
            // servise uuid
            lua_pushlstring(L, (const char *)gatt_service->uuid, gatt_service->uuid_type);
            lua_rawseti(L, -2, 1);
            // characteristics
            uint8_t characteristics_num = gatt_service->characteristics_num;
            for (size_t m = 0; m < characteristics_num; m++){
                luat_ble_gatt_chara_t *gatt_chara = &gatt_service->characteristics[m];
                lua_newtable(L);
                lua_pushlstring(L, (const char *)gatt_chara->uuid, gatt_service->uuid_type);
                lua_seti(L, -2, 1);
                // Properties
                lua_pushnumber(L, gatt_chara->perm);
                lua_seti(L, -2, 2);

                lua_seti(L, -2, m + 2);
            }
            lua_rawseti(L, -2, i + 1);
        }
        lua_call(L, 3, 0);
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
        lua_call(L, 3, 0);
        break;
    }case LUAT_BLE_EVENT_DISCONN:{
        luat_ble_disconn_ind_t *disconn = &(param->disconn_ind);
        lua_newtable(L);
        lua_pushinteger(L, disconn->reason);
        lua_setfield(L, -2, "reason");
        lua_call(L, 3, 0);
        break;
    }
    default:
        lua_call(L, 2, 0);
        break;
    }
exit:
    if (param)
    {
        if (param->write_req.value)
        {
            LLOGD("free write_req.value %p", param->write_req.value);
            luat_heap_free(param->write_req.value);
            param->write_req.value = NULL;
        }
        if (param->adv_req.data)
        {
            LLOGD("free adv_req.data %p", param->adv_req.data);
            luat_heap_free(param->adv_req.data);
            param->adv_req.data = NULL;
        }
        luat_heap_free(param);
        param = NULL;
    }
    return 0;
}

void luat_ble_cb(luat_ble_t *args, luat_ble_event_t ble_event, luat_ble_param_t *ble_param){
    // LLOGD("ble event: %d param: %p", ble_event, ble_param);
    luat_ble_param_t *luat_ble_param = NULL;
    if (ble_param){
        // LLOGD("ble param: %p", ble_param);
        luat_ble_param = luat_heap_malloc(sizeof(luat_ble_param_t));
        memcpy(luat_ble_param, ble_param, sizeof(luat_ble_param_t));
        if (ble_event == LUAT_BLE_EVENT_WRITE && ble_param->write_req.value_len){
            luat_ble_param->write_req.value = luat_heap_malloc(ble_param->write_req.value_len);
            memcpy(luat_ble_param->write_req.value, ble_param->write_req.value, ble_param->write_req.value_len);
        }else if (ble_event == LUAT_BLE_EVENT_READ_VALUE && ble_param->read_req.value_len){
            luat_ble_param->read_req.value = luat_heap_malloc(ble_param->read_req.value_len);
            memcpy(luat_ble_param->read_req.value, ble_param->read_req.value, ble_param->read_req.value_len);
        }else if (ble_event == LUAT_BLE_EVENT_SCAN_REPORT && ble_param->adv_req.data_len){
            luat_ble_param->adv_req.data = luat_heap_malloc(ble_param->adv_req.data_len);
            memcpy(luat_ble_param->adv_req.data, ble_param->adv_req.data, ble_param->adv_req.data_len);
        }
    }

    rtos_msg_t msg = {
        .handler = l_ble_callback,
        .ptr = (void *)NULL,
        .arg1 = (int)ble_event,
        .arg2 = (int)luat_ble_param,
    };
    luat_msgbus_put(&msg, 0);
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
        ble.NOTIFY | ble.READ | ble.WRITE -- Properties, 对应蓝牙特征的属性, 可以是以下值的组合:
        -- ble.READ: 可读
        -- ble.WRITE: 可写
        -- ble.NOTIFY: 可通知
        -- ble.INDICATE: 可指示
    }
}
ble_device:gatt_create(att_db)
*/
static int l_ble_gatt_create(lua_State *L){
    if (!lua_isuserdata(L, 1)){
        return 0;
    }
    uint8_t characteristics_num = 0;
    size_t len = 0;
    luat_ble_gatt_service_t *luat_ble_gatt_service = luat_heap_malloc(sizeof(luat_ble_gatt_service_t));
    memset(luat_ble_gatt_service, 0, sizeof(luat_ble_gatt_service_t));

    if (lua_type(L, 2) != LUA_TTABLE){
        LLOGE("error param");
        return 0;
    }

    int gatt_table_len = luaL_len(L, 2) - 1;

    if (lua_rawgeti(L, -1, 1) == LUA_TSTRING){
        const char *service_uuid = luaL_checklstring(L, -1, &len);
        if (len == 2){
            luat_ble_gatt_service->uuid_type = LUAT_BLE_UUID_TYPE_16;
        }else if (len == 4){
            luat_ble_gatt_service->uuid_type = LUAT_BLE_UUID_TYPE_32;
        }else if (len == 16){
            luat_ble_gatt_service->uuid_type = LUAT_BLE_UUID_TYPE_128;
        }
        memcpy(luat_ble_gatt_service->uuid, service_uuid, len);
    }else if (lua_rawgeti(L, -1, 1) == LUA_TNUMBER){
        uint16_t service_uuid = (uint16_t)luaL_checknumber(L, -1);
        luat_ble_gatt_service->uuid_type = LUAT_BLE_UUID_TYPE_16;
        luat_ble_gatt_service->uuid[0] = service_uuid & 0xff;
        luat_ble_gatt_service->uuid[1] = service_uuid >> 8;
    }else{
        LLOGE("error uuid type");
        return 0;
    }
    lua_pop(L, 1);

    // Characteristics
    luat_ble_gatt_service->characteristics = (luat_ble_gatt_chara_t *)luat_heap_malloc(sizeof(luat_ble_gatt_chara_t) * gatt_table_len);
    memset(luat_ble_gatt_service->characteristics, 0, sizeof(luat_ble_gatt_chara_t) * gatt_table_len);
    luat_ble_gatt_chara_t *characteristics = luat_ble_gatt_service->characteristics;
    for (size_t j = 2; j <= gatt_table_len + 1; j++){
        if (lua_rawgeti(L, -1, j) == LUA_TTABLE){
            lua_rawgeti(L, -1, 1);

            // lua_pushstring(L, "descriptor");
            // if (LUA_TSTRING == lua_gettable(L, -2)){
            //     const char* value = luaL_checklstring(L, -1, &len);
            //     characteristics[j-2].value = luat_heap_malloc(len);
            //     characteristics[j-2].value_len = len;
            // }
            // lua_pop(L, 1);

            // UUID
            uint16_t uuid_type = 0;
            uint8_t uuid[LUAT_BLE_UUID_LEN_MAX] = {0};
            if (LUA_TSTRING == lua_type(L, -1)){
                const char *characteristics_uuid = luaL_checklstring(L, -1, &len);
                uuid_type = len;
                memcpy(uuid, characteristics_uuid, len);
            }else if (LUA_TNUMBER == lua_type(L, -1)){
                uint16_t characteristics_uuid = (uint16_t)luaL_checknumber(L, -1);
                uuid_type = LUAT_BLE_UUID_TYPE_16;
                uuid[0] = characteristics_uuid >> 8;
                uuid[1] = characteristics_uuid & 0xFF;
            }else{
                LLOGE("error characteristics uuid type");
                goto error_exit;
            }
            lua_pop(L, 1);

            if (characteristics[characteristics_num].uuid_type == LUAT_BLE_UUID_TYPE_16 && 
                characteristics[characteristics_num].uuid[0] == (LUAT_BLE_GATT_DESC_MAX >> 8) && 
                characteristics[characteristics_num].uuid[1] <= (LUAT_BLE_GATT_DESC_MAX & 0xFF)){
                // Descriptors
                characteristics[characteristics_num].perm |= LUAT_BLE_GATT_PERM_READ;
                characteristics[characteristics_num].perm |= LUAT_BLE_GATT_PERM_WRITE;
                characteristics[characteristics_num].max_size = 0;

                luat_ble_gatt_descriptor_t *descriptor = characteristics[characteristics_num].descriptor;
                if (descriptor){
                    descriptor = luat_heap_realloc(descriptor,sizeof(luat_ble_gatt_descriptor_t)*(characteristics[characteristics_num].descriptors_num+1));
                    descriptor[characteristics[characteristics_num].descriptors_num].uuid_type = uuid_type;
                    memcpy(descriptor[characteristics[characteristics_num].descriptors_num].uuid, uuid, len);
                }else{
                    descriptor = luat_heap_malloc(sizeof(luat_ble_gatt_descriptor_t));
                    descriptor->uuid_type = uuid_type;
                    memcpy(descriptor->uuid, uuid, len);
                }
                characteristics[characteristics_num].descriptors_num++;
            }else{
                // Characteristics uuid
                characteristics[characteristics_num].uuid_type = uuid_type;
                memcpy(characteristics[characteristics_num].uuid, uuid, len);

                // Characteristics properties
                lua_rawgeti(L, -1, 2);
                if (LUA_TNUMBER == lua_type(L, -1)){
                    characteristics[characteristics_num].perm = (uint16_t)luaL_optnumber(L, -1, 0);
                }
                lua_pop(L, 1);

                // Descriptors
                if (characteristics[characteristics_num].perm & LUAT_BLE_GATT_PERM_NOTIFY){
                    luat_ble_gatt_chara_t *characteristic = &characteristics[characteristics_num];
                    if (characteristic->descriptor){
                        uint8_t descriptor_ind = characteristics[characteristics_num].descriptors_num;
                        characteristic->descriptor = luat_heap_realloc(characteristic->descriptor,sizeof(luat_ble_gatt_descriptor_t)*(descriptor_ind+1));
                        memset(&characteristic->descriptor[descriptor_ind],0,sizeof(luat_ble_gatt_descriptor_t));
                        characteristic->descriptor[descriptor_ind].uuid_type = LUAT_BLE_UUID_TYPE_16;
                        characteristic->descriptor[descriptor_ind].uuid[0] = 0x2902 >> 8;
                        characteristic->descriptor[descriptor_ind].uuid[1] = 0x2902 & 0xFF;
                    }else{
                        characteristic->descriptor = luat_heap_malloc(sizeof(luat_ble_gatt_descriptor_t));
                        memset(characteristic->descriptor,0,sizeof(luat_ble_gatt_descriptor_t));
                        characteristic->descriptor->uuid_type = LUAT_BLE_UUID_TYPE_16;
                        characteristic->descriptor->uuid[0] = 0x2902 >> 8;
                        characteristic->descriptor->uuid[1] = 0x2902 & 0xFF;
                    }
                    characteristics[characteristics_num].descriptors_num++;
                }

                // Characteristics value
                lua_rawgeti(L, -1, 3);
                if (LUA_TSTRING == lua_type(L, -1)){
                    const char *value = luaL_checklstring(L, -1, &len);
                    characteristics[characteristics_num].value = luat_heap_malloc(len);
                    memcpy(characteristics[characteristics_num].value, value, len);
                    characteristics[characteristics_num].value_len = len;
                }
                lua_pop(L, 1);

                // Characteristics max_size
                lua_pushstring(L, "max_size");
                if (LUA_TNUMBER == lua_gettable(L, -2)){
                    characteristics[characteristics_num].max_size = (uint16_t)luaL_optnumber(L, -1, 0);
                }else{
                    characteristics[characteristics_num].max_size = 256;
                }
                lua_pop(L, 1);
                characteristics_num++;
            }
        }
        lua_pop(L, 1);
    }
    luat_ble_gatt_service->characteristics_num = characteristics_num;
    lua_pushboolean(L, luat_ble_create_gatt(NULL, luat_ble_gatt_service) == 0 ? 1 : 0);
    return 1;
error_exit:
    return 0;
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
    adv_data = {
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
    const char complete_local_name[32] = {0};

    luat_ble_adv_cfg_t luat_ble_adv_cfg = {
        .addr_mode = LUAT_BLE_ADDR_MODE_PUBLIC,
        .channel_map = LUAT_BLE_ADV_CHNLS_ALL,
        .intv_min = 120,
        .intv_max = 160,
    };

    lua_pushstring(L, "addr_mode");
    if (LUA_TNUMBER == lua_gettable(L, -2)){
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

    luat_ble_create_advertising(NULL, &luat_ble_adv_cfg);

    // 广播内容 (adv data)
    uint8_t adv_data[255] = {0};
    uint8_t adv_index = 0;

    lua_pushstring(L, "adv_data");
    if (LUA_TTABLE == lua_gettable(L, -2)){
        int adv_data_count = luaL_len(L, -1);
        for (int i = 1; i <= adv_data_count; i++){
            lua_rawgeti(L, -1, i);
            if (LUA_TTABLE == lua_type(L, -1)){
                lua_rawgeti(L, -1, 2);
                if (lua_type(L, -1) == LUA_TSTRING){
                    const char *data = luaL_checklstring(L, -1, &len);
                    adv_data[adv_index++] = (uint8_t)(len + 1);
                    lua_rawgeti(L, -2, 1);
                    if (lua_type(L, -1) == LUA_TNUMBER){
                        uint8_t adv_type = (uint8_t)luaL_checknumber(L, -1);
                        adv_data[adv_index++] = adv_type;
                        if (adv_type == LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME){
                            luat_ble_set_name(NULL, data, len);
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
    lua_pop(L, 1);

    if (!local_name_set_flag){
        sprintf_(complete_local_name, "LuatOS_%s", luat_os_bsp());
        luat_ble_set_name(NULL, complete_local_name, strlen(complete_local_name));
    }

    /* set adv paramters */
    luat_ble_set_adv_data(NULL, adv_data, adv_index);

    lua_pushstring(L, "rsp_data");
    if (LUA_TSTRING == lua_gettable(L, 2)){
        uint8_t *rsp_data = luaL_checklstring(L, -1, &len);
        if (len){
            luat_ble_set_scan_rsp_data(NULL, rsp_data, len);
        }
    }
    lua_pop(L, 1);

    lua_pushboolean(L, 1);
    return 1;
end:
    return 0;
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
            LLOGD("uuid_service: %02X %02X", service.uuid[0], service.uuid[1]);
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
            LLOGD("uuid_characteristic: %02X %02X", characteristic.uuid[0], characteristic.uuid[1]);
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
            LLOGD("uuid_descriptor: %02X %02X", descriptor.uuid[0], descriptor.uuid[1]);
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
            lua_pushlstring(L, (const char *)value, len);
            return 1;
        }else{
            LLOGE("ble read value error");
            return 0;
        }
    }
end_error:
    LLOGE("error param");
    return 0;
}

/*创建一个BLE扫描
@api ble.scan_create(addr_mode, scan_interval, scan_window)
@number addr_mode 广播地址模式, 可选值: ble.PUBLIC, ble.RANDOM, ble.RPA, ble.NRPA
@number scan_interval 扫描间隔, 单位为0.625ms, 最小值为20, 最大值为10240
@number scan_window 扫描窗口, 单位为0.625ms, 最小值为20, 最大值为10240
@return boolean 是否创建成功
@usage
-- 创建BLE扫描
ble_device:scan_create(ble.PUBLIC, 100, 100)
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
@api ble.connect()
@string mac 地址
@int 地址类型 ble.PUBLIC ble.RANDOM
@return boolean 是否成功
@usage
-- BLE连接
ble_device:connect(string.fromHex("C8478C4E027D"),0)
*/
static int l_ble_connect(lua_State *L){
    size_t len;
    uint8_t *adv_addr = luaL_checklstring(L, 2, &len);
    uint8_t adv_addr_type = luaL_checknumber(L, 3);
    // LLOGD(" adv_addr_type:%d, adv_addr:%02x:%02x:%02x:%02x:%02x:%02x",
    //       adv_addr_type, adv_addr[0], adv_addr[1], adv_addr[2],
    //       adv_addr[3], adv_addr[4], adv_addr[5]);
    lua_pushboolean(L, luat_ble_connect(NULL, adv_addr, adv_addr_type) ? 0 : 1);
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

static int _ble_struct_newindex(lua_State *L);

void luat_ble_struct_init(lua_State *L){
    luaL_newmetatable(L, LUAT_BLE_TYPE);
    lua_pushcfunction(L, _ble_struct_newindex);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_ble[] = {
    // advertise
    {"adv_create", ROREG_FUNC(l_ble_advertising_create)},
    {"adv_start", ROREG_FUNC(l_ble_advertising_start)},
    {"adv_stop", ROREG_FUNC(l_ble_advertising_stop)},

    // gatt
    // slaver
    {"gatt_create", ROREG_FUNC(l_ble_gatt_create)},
    {"write_notify", ROREG_FUNC(l_ble_write_notify)},
    {"write_indicate", ROREG_FUNC(l_ble_write_indicate)},
    {"write_value", ROREG_FUNC(l_ble_write_value)},
    {"read_value", ROREG_FUNC(l_ble_read_value)},
    
    // scanning
    {"scan_create", ROREG_FUNC(l_ble_scanning_create)},
    {"scan_start", ROREG_FUNC(l_ble_scanning_start)},
    {"scan_stop", ROREG_FUNC(l_ble_scanning_stop)},

    {"connect", ROREG_FUNC(l_ble_connect)},
    {"disconnect", ROREG_FUNC(l_ble_disconnect)},

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

    // ADV_ADDR_MODE
    // @const PUBLIC 控制器的公共地址
    {"PUBLIC", ROREG_INT(LUAT_BLE_ADDR_MODE_PUBLIC)},
    // @const RANDOM 生成的静态地址
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
    //@const READ 写权限
    {"WRITE", ROREG_INT(LUAT_BLE_GATT_PERM_WRITE)},
    {"IND", ROREG_INT(LUAT_BLE_GATT_PERM_IND)},
    {"NOTIFY", ROREG_INT(LUAT_BLE_GATT_PERM_NOTIFY)},
    {"WRITE_CMD", ROREG_INT(LUAT_BLE_GATT_PERM_WRITE_CMD)},

    // FLAGS
    {"FLAGS", ROREG_INT(LUAT_ADV_TYPE_FLAGS)},
    {"COMPLETE_LOCAL_NAME", ROREG_INT(LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME)},
    {"SERVICE_DATA", ROREG_INT(LUAT_ADV_TYPE_SERVICE_DATA_16BIT)},
    {"MANUFACTURER_SPECIFIC_DATA", ROREG_INT(LUAT_ADV_TYPE_MANUFACTURER_SPECIFIC_DATA)},
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
