#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_ble.h"

#include "luat_log.h"
#define LUAT_LOG_TAG "ble"

#define LUAT_BLE_TYPE "BLE*"

static int luatos_ble_callback(lua_State *L, void* ptr){
	(void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_ble_t* luat_ble =(luat_ble_t *)msg->ptr;
    luat_ble_event_t ble_event = (luat_ble_event_t)msg->arg1;
    luat_ble_param_t* luat_ble_param = (luat_ble_param_t*)msg->arg2;

    lua_geti(L, LUA_REGISTRYINDEX, luat_ble->lua_cb);
    if (lua_isfunction(L, -1)) {
        lua_geti(L, LUA_REGISTRYINDEX, luat_ble->ble_ref);
        lua_pushinteger(L, ble_event);
    }

    switch(ble_event){
        case LUAT_BLE_EVENT_WRITE:{
            luat_ble_write_req_t* write_req = &(luat_ble_param->write_req);

            lua_createtable(L, 0, 3);
            lua_pushliteral(L, "conn_idx"); 
            lua_pushinteger(L, write_req->conn_idx);
            lua_settable(L, -3);
            lua_pushliteral(L, "service_id"); 
            lua_pushinteger(L, write_req->service_id);
            lua_settable(L, -3);
            lua_pushliteral(L, "handle"); 
            lua_pushinteger(L, write_req->handle);
            lua_settable(L, -3);
            lua_pushliteral(L, "data"); 
            lua_pushlstring(L, (const char *)write_req->value, write_req->len);
            lua_settable(L, -3);
            lua_call(L, 3, 0);
            if (write_req->value){
                luat_heap_free(write_req->value);
            }
            break;
        }
        case LUAT_BLE_EVENT_READ: {
            luat_ble_read_req_t* read_req = &(luat_ble_param->read_req);
            lua_createtable(L, 0, 3);

            lua_pushliteral(L, "conn_idx"); 
            lua_pushinteger(L, read_req->conn_idx);
            lua_settable(L, -3);
            lua_pushliteral(L, "service_id"); 
            lua_pushinteger(L, read_req->service_id);
            lua_settable(L, -3);
            lua_pushliteral(L, "handle"); 
            lua_pushinteger(L, read_req->handle);
            lua_settable(L, -3);

            lua_call(L, 3, 0);

            break;
        }
        default:
            lua_call(L, 2, 0);
            break;
    }
    if (luat_ble_param){
        luat_heap_free(luat_ble_param);
    }
    return 0;
}

void luat_ble_cb(luat_ble_t* luat_ble, luat_ble_event_t ble_event, luat_ble_param_t* ble_param){
    LLOGD("ble event: %d", ble_event);
    luat_ble_param_t* luat_ble_param = NULL;
    if (ble_param){
        LLOGD("ble param: %p", ble_param);
        luat_ble_param = luat_heap_malloc(sizeof(luat_ble_param_t));
        memcpy(luat_ble_param, ble_param, sizeof(luat_ble_param_t));
        if (ble_event == LUAT_BLE_EVENT_WRITE && ble_param->write_req.len){
            luat_ble_param->write_req.value = luat_heap_malloc(ble_param->write_req.len);
            memcpy(luat_ble_param->write_req.value, ble_param->write_req.value, ble_param->write_req.len);
        }else if(ble_event == LUAT_BLE_EVENT_READ && ble_param->read_req.len){
            LLOGD("ble read read_req value: %p", ble_param->read_req.value);
        }
    }
    
    rtos_msg_t msg = {
        .handler = luatos_ble_callback,
        .ptr = (void*)luat_ble,
        .arg1 = (int)ble_event,
        .arg2 = (int)luat_ble_param,
    };
    luat_msgbus_put(&msg, 0);
}

static int l_ble_gatt_create(lua_State* L) {
    if (!lua_isuserdata(L, 1)){
        return 0;
    }

    luat_ble_t* luat_ble = (luat_ble_t *)luaL_checkudata(L, 1, LUAT_BLE_TYPE);
    luat_ble_gatt_service_t luat_ble_gatt_service = {0};
    size_t len = 0;

    if (lua_type(L, 2) != LUA_TTABLE){
        LLOGE("error param");
        return 0;
    }
    
    luat_ble_gatt_service.characteristics_num = luaL_len(L, 2)-1;

    if (lua_rawgeti(L, -1, 1) == LUA_TSTRING){
        const char* service_uuid = luaL_checklstring(L, -1, &len);
        if (len == 2){
            luat_ble_gatt_service.uuid_type = LUAT_BLE_UUID_TYPE_16;
        }else if (len == 4){
            luat_ble_gatt_service.uuid_type = LUAT_BLE_UUID_TYPE_32;
        }else if (len == 16){
            luat_ble_gatt_service.uuid_type = LUAT_BLE_UUID_TYPE_128;
        }
        luat_ble_uuid_swap(service_uuid, luat_ble_gatt_service.uuid_type);
        memcpy(luat_ble_gatt_service.uuid, service_uuid, len);
    }else if (lua_rawgeti(L, -1, 1) == LUA_TNUMBER){
        uint16_t service_uuid = (uint16_t)luaL_checknumber(L, -1);
        luat_ble_gatt_service.uuid_type = LUAT_BLE_UUID_TYPE_16;
        luat_ble_gatt_service.uuid[0] = service_uuid & 0xff;
        luat_ble_gatt_service.uuid[1] = service_uuid >> 8;
    }else{
        LLOGE("error uuid type");
        return 0;
    }
    lua_pop(L, 1);

    // Characteristics
    luat_ble_gatt_service.characteristics = (luat_ble_gatt_chara_t*)luat_heap_malloc(sizeof(luat_ble_gatt_chara_t) * luat_ble_gatt_service.characteristics_num);

    for (size_t j = 2; j <= luat_ble_gatt_service.characteristics_num+1; j++){
        if (lua_rawgeti(L, -1, j) == LUA_TTABLE){
            lua_rawgeti(L, -1, 1);
            // Characteristics uuid
            if (LUA_TSTRING == lua_type(L, -1)){
                const char* characteristics_uuid = luaL_checklstring(L, -1, &len);
                if (len == 2){
                    luat_ble_gatt_service.characteristics[j-2].uuid_type = LUAT_BLE_UUID_TYPE_16;
                }else if (len == 4){
                    luat_ble_gatt_service.characteristics[j-2].uuid_type = LUAT_BLE_UUID_TYPE_32;
                }else if (len == 16){
                    luat_ble_gatt_service.characteristics[j-2].uuid_type = LUAT_BLE_UUID_TYPE_128;
                }
                luat_ble_uuid_swap(characteristics_uuid, luat_ble_gatt_service.characteristics[j-2].uuid_type);
                memcpy(luat_ble_gatt_service.characteristics[j-2].uuid, characteristics_uuid, len);
            }else if (LUA_TNUMBER == lua_type(L, -1)){
                uint16_t characteristics_uuid = (uint16_t)luaL_checknumber(L, -1);
                luat_ble_gatt_service.characteristics[j-2].uuid_type = LUAT_BLE_UUID_TYPE_16;
                luat_ble_gatt_service.characteristics[j-2].uuid[0] = characteristics_uuid & 0xff;
                luat_ble_gatt_service.characteristics[j-2].uuid[1] = characteristics_uuid >> 8;
            }else{
                LLOGE("error characteristics uuid type");
                goto error_exit;
            }
            lua_pop(L, 1);
            // Characteristics properties
            lua_rawgeti(L, -1, 2);
            if (LUA_TNUMBER == lua_type(L, -1)){
                luat_ble_gatt_service.characteristics[j-2].perm = (uint16_t)luaL_optnumber(L, -1, 0);
            }
            lua_pop(L, 1);
            // Characteristics descriptors
            lua_rawgeti(L, -1, 3);
            if (LUA_TSTRING == lua_type(L, -1)){
                luat_ble_gatt_service.characteristics[j-2].descriptors = (luat_ble_gatt_chara_t*)luat_heap_malloc(sizeof(luat_ble_gatt_chara_t));
                memset(luat_ble_gatt_service.characteristics[j-2].descriptors, 0, sizeof(luat_ble_gatt_chara_t));
                const char* descriptors_uuid = luaL_checklstring(L, -1, &len);
                if (len == 2){
                    luat_ble_gatt_service.characteristics[j-2].descriptors->uuid_type = LUAT_BLE_UUID_TYPE_16;
                }else if (len == 4){
                    luat_ble_gatt_service.characteristics[j-2].descriptors->uuid_type = LUAT_BLE_UUID_TYPE_32;
                }else if (len == 16){
                    luat_ble_gatt_service.characteristics[j-2].descriptors->uuid_type = LUAT_BLE_UUID_TYPE_128;
                }
                luat_ble_uuid_swap(descriptors_uuid, luat_ble_gatt_service.characteristics[j-2].descriptors->uuid_type);
                memcpy(luat_ble_gatt_service.characteristics[j-2].descriptors->uuid, descriptors_uuid, len);
            }
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
    luat_ble_create_gatt(luat_ble, &luat_ble_gatt_service);
    for (size_t i = 0; i < luat_ble_gatt_service.characteristics_num; i++){
        lua_pushinteger(L, luat_ble_gatt_service.characteristics[i].handle);
    }
    // lua_pushboolean(L, 1);
    return luat_ble_gatt_service.characteristics_num;
error_exit:
    return 0;
}

static int l_ble_advertising_create(lua_State* L) {
    if (!lua_isuserdata(L, 1)){
        return 0;
    }
    if (lua_type(L, 2) != LUA_TTABLE){
        LLOGE("error param");
        return 0;
    }
    luat_ble_t* luat_ble = (luat_ble_t *)luaL_checkudata(L, 1, LUAT_BLE_TYPE);
    size_t len = 0;
    uint8_t local_name_set_flag = 0;
    const char complete_local_name[32] = {0};

    luat_ble_adv_cfg_t luat_ble_adv_cfg = {
        .addr_mode = LUAT_BLE_ADV_ADDR_MODE_PUBLIC,
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
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_ble_adv_cfg.channel_map = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    lua_pushstring(L, "intv_min");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_ble_adv_cfg.intv_min = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    lua_pushstring(L, "intv_max");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_ble_adv_cfg.intv_max = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);

    luat_ble_create_advertising(luat_ble, &luat_ble_adv_cfg);

    // 广播内容 (adv data)
    uint8_t adv_data[255] = {0};
    uint8_t adv_index = 0;

    lua_pushstring(L, "adv_data");
    if (LUA_TTABLE == lua_gettable(L, -2)){
        int adv_data_count = luaL_len(L, -1);
        for (int i = 1; i <= adv_data_count; i++) {
            lua_rawgeti(L, -1, i);
            if (LUA_TTABLE == lua_type(L, -1)){
                lua_rawgeti(L, -1, 2);
                if (lua_type(L, -1) == LUA_TSTRING){
                    const char* data = luaL_checklstring(L, -1, &len);
                    adv_data[adv_index++] = (uint8_t)(len+1);
                    lua_rawgeti(L, -2, 1);
                    if (lua_type(L, -1) == LUA_TNUMBER){
                        uint8_t adv_type = (uint8_t)luaL_checknumber(L, -1);
                        adv_data[adv_index++] = adv_type;
                        if (adv_type == LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME){
                            luat_ble_set_name(luat_ble, data, len);
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
        luat_ble_set_name(luat_ble, complete_local_name, strlen(complete_local_name));
    }

    /* set adv paramters */
    luat_ble_set_adv_data(luat_ble, adv_data, adv_index);

    lua_pushboolean(L, 1);
    return 1;
end:
    return 0;
}

static int l_ble_advertising_start(lua_State* L) {
    luat_ble_t* luat_ble = (luat_ble_t *)luaL_checkudata(L, 1, LUAT_BLE_TYPE);
    lua_pushboolean(L, luat_ble_start_advertising(luat_ble)?0:1);
    return 1;
}

static int l_ble_advertising_stop(lua_State* L) {
    luat_ble_t* luat_ble = (luat_ble_t *)luaL_checkudata(L, 1, LUAT_BLE_TYPE);
    lua_pushboolean(L, luat_ble_stop_advertising(luat_ble)?0:1);
    return 1;
}

static int l_ble_read_response(lua_State* L) {
    luat_ble_t* luat_ble = (luat_ble_t *)luaL_checkudata(L, 1, LUAT_BLE_TYPE);
    uint8_t conn_idx = 0;
    uint16_t service_id, handle = 0;
    if (luat_ble) {
        lua_pushstring(L, "conn_idx");
        if (LUA_TNUMBER == lua_gettable(L, 2)) {
            conn_idx = luaL_checknumber(L, -1);
        }else{
            goto end_error;
        }
        lua_pop(L, 1);
        lua_pushstring(L, "service_id");
        if (LUA_TNUMBER == lua_gettable(L, 2)) {
            service_id = luaL_checknumber(L, -1);
        }else{
            goto end_error;
        }
        lua_pop(L, 1);
        lua_pushstring(L, "handle");
        if (LUA_TNUMBER == lua_gettable(L, 2)) {
            handle = luaL_checknumber(L, -1);
        }else{
            goto end_error;
        }
        lua_pop(L, 1);

        size_t len = 0;
        const char* response_data = luaL_checklstring(L, -1, &len);
        // LLOGD("read response conn_idx:%d service_id:%d handle:%d", conn_idx, service_id, handle);
        luat_ble_read_response(luat_ble, conn_idx, service_id, handle, len, (uint8_t *)response_data);

        return 1;
    }
end_error:
    LLOGE("error param");
    return 0;
}

static int _ble_struct_newindex(lua_State *L);

void luat_ble_struct_init(lua_State *L) {
    luaL_newmetatable(L, LUAT_BLE_TYPE);
    lua_pushcfunction(L, _ble_struct_newindex);
    lua_setfield( L, -2, "__index" );
    lua_pop(L, 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_ble[] = {
    {"gatt_create",                 ROREG_FUNC(l_ble_gatt_create)},
    {"adv_create",                  ROREG_FUNC(l_ble_advertising_create)},
    {"adv_start",                   ROREG_FUNC(l_ble_advertising_start)},
    {"adv_stop",                    ROREG_FUNC(l_ble_advertising_stop)},

    {"read_response",               ROREG_FUNC(l_ble_read_response)},

    // BLE_EVENT
    {"EVENT_NONE",                  ROREG_INT(LUAT_BLE_EVENT_NONE)},
    {"EVENT_INIT",                  ROREG_INT(LUAT_BLE_EVENT_INIT)},
    {"EVENT_DEINIT",                ROREG_INT(LUAT_BLE_EVENT_DEINIT)},
    {"EVENT_ADV_INIT",              ROREG_INT(LUAT_BLE_EVENT_ADV_INIT)},
    {"EVENT_ADV_START",             ROREG_INT(LUAT_BLE_EVENT_ADV_START)},
    {"EVENT_ADV_STOP",              ROREG_INT(LUAT_BLE_EVENT_ADV_STOP)},
    {"EVENT_ADV_DEINIT",            ROREG_INT(LUAT_BLE_EVENT_ADV_DEINIT)},
    {"EVENT_SCAN_INIT",             ROREG_INT(LUAT_BLE_EVENT_SCAN_INIT)},
    {"EVENT_SCAN_START",            ROREG_INT(LUAT_BLE_EVENT_SCAN_START)},
    {"EVENT_SCAN_STOP",             ROREG_INT(LUAT_BLE_EVENT_SCAN_STOP)},
    {"EVENT_SCAN_DEINIT",           ROREG_INT(LUAT_BLE_EVENT_SCAN_DEINIT)},
    {"EVENT_CONN",                  ROREG_INT(LUAT_BLE_EVENT_CONN)},
    {"EVENT_DISCONN",               ROREG_INT(LUAT_BLE_EVENT_DISCONN)},
    {"EVENT_WRITE",                 ROREG_INT(LUAT_BLE_EVENT_WRITE)},
    {"EVENT_READ",                  ROREG_INT(LUAT_BLE_EVENT_READ)},

    // ADV_ADDR_MODE
    {"PUBLIC",                      ROREG_INT(LUAT_BLE_ADV_ADDR_MODE_PUBLIC)},
    {"RANDOM",                      ROREG_INT(LUAT_BLE_ADV_ADDR_MODE_RANDOM)},
    {"RPA",                         ROREG_INT(LUAT_BLE_ADV_ADDR_MODE_RPA)},
    {"NRPA",                        ROREG_INT(LUAT_BLE_ADV_ADDR_MODE_NRPA)},
    // ADV_CHNL
    {"CHNL_37",                     ROREG_INT(LUAT_BLE_ADV_CHNL_37)},
    {"CHNL_38",                     ROREG_INT(LUAT_BLE_ADV_CHNL_38)},
    {"CHNL_39",                     ROREG_INT(LUAT_BLE_ADV_CHNL_39)},
    {"CHNLS_ALL",                   ROREG_INT(LUAT_BLE_ADV_CHNLS_ALL)},
    // Permission
    {"READ",                        ROREG_INT(LUAT_BLE_GATT_PERM_READ)},
    {"WRITE",                       ROREG_INT(LUAT_BLE_GATT_PERM_WRITE)},
    {"IND",                         ROREG_INT(LUAT_BLE_GATT_PERM_IND)},
    {"NOTIFY",                      ROREG_INT(LUAT_BLE_GATT_PERM_NOTIFY)},
    {"WRITE_CMD",                   ROREG_INT(LUAT_BLE_GATT_PERM_WRITE_CMD)},
    // FLAGS
    {"FLAGS",                       ROREG_INT(LUAT_ADV_TYPE_FLAGS)},
    {"COMPLETE_LOCAL_NAME",         ROREG_INT(LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME)},
    {"SERVICE_DATA",                ROREG_INT(LUAT_ADV_TYPE_SERVICE_DATA_16BIT)},
    {"MANUFACTURER_SPECIFIC_DATA",  ROREG_INT(LUAT_ADV_TYPE_MANUFACTURER_SPECIFIC_DATA)},
	{ NULL,                         ROREG_INT(0)}
};

static int _ble_struct_newindex(lua_State *L) {
	const rotable_Reg_t* reg = reg_ble;
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

LUAMOD_API int luaopen_ble( lua_State *L ) {
    rotable2_newlib(L, reg_ble);
    luat_ble_struct_init(L);
    return 1;
}
