#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_bluetooth.h"

#include "luat_log.h"
#define LUAT_LOG_TAG "bluetooth"

#define LUAT_BLUETOOTH_TYPE "BLUETOOTH*"
#define LUAT_BLE_TYPE "BLE*"

static int luatos_ble_callback(lua_State *L, void* ptr){
	(void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_bluetooth_t* luat_bluetooth =(luat_bluetooth_t *)msg->ptr;
    luat_ble_event_t ble_event = (luat_ble_event_t)msg->arg1;
    luat_ble_param_t* luat_ble_param = (luat_ble_param_t*)msg->arg2;

    // if (luat_bluetooth->luat_ble->lua_cb) {
        lua_geti(L, LUA_REGISTRYINDEX, luat_bluetooth->luat_ble->lua_cb);
        if (lua_isfunction(L, -1)) {
            lua_geti(L, LUA_REGISTRYINDEX, luat_bluetooth->bluetooth_ref);
            lua_pushinteger(L, ble_event);
            // lua_call(L, 2, 0);
        }
    // }

    switch(ble_event){
        case LUAT_BLE_EVENT_WRITE:{
            luat_ble_write_req_t* write_req = &(luat_ble_param->write_req);

            lua_createtable(L, 0, 3);
            lua_pushliteral(L, "conn_idx"); 
            lua_pushinteger(L, write_req->conn_idx);
            lua_settable(L, -3);
            lua_pushliteral(L, "prf_id"); 
            lua_pushinteger(L, write_req->prf_id);
            lua_settable(L, -3);
            lua_pushliteral(L, "att_idx"); 
            lua_pushinteger(L, write_req->att_idx + 1);
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
            lua_pushliteral(L, "prf_id"); 
            lua_pushinteger(L, read_req->prf_id);
            lua_settable(L, -3);
            lua_pushliteral(L, "att_idx"); 
            lua_pushinteger(L, read_req->att_idx + 1);
            lua_settable(L, -3);
            lua_pushliteral(L, "data"); 
            lua_pushlstring(L, (const char *)read_req->value, read_req->len);
            lua_settable(L, -3);

            lua_call(L, 3, 0);
            if (read_req->value){
                luat_heap_free(read_req->value);
            }
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

static void luat_ble_cb(luat_bluetooth_t* luat_bluetooth, luat_ble_event_t ble_event, luat_ble_param_t* ble_param){
    LLOGD("ble event: %d", ble_event);
    // luat_ble_param_t* luat_ble_param = NULL;
    // if (ble_param){
    //     luat_ble_param = luat_heap_malloc(sizeof(luat_ble_param_t));
    //     memcpy(luat_ble_param, ble_param, sizeof(luat_ble_param_t));
    //     if ((ble_event == LUAT_BLE_EVENT_WRITE || ble_event == LUAT_BLE_EVENT_READ) && ble_param->write_req.len){
    //         luat_ble_param->write_req.value = luat_heap_malloc(ble_param->write_req.len);
    //         memcpy(luat_ble_param->write_req.value, ble_param->write_req.value, ble_param->write_req.len);
    //     }
    // }
    
    // rtos_msg_t msg = {
    //     .handler = luatos_ble_callback,
    //     .ptr = (void*)luat_bluetooth,
    //     .arg1 = (int)ble_event,
    //     .arg2 = (int)luat_ble_param,
    // };
    // luat_msgbus_put(&msg, 0);
}

static int l_bluetooth_create_ble(lua_State* L) {
    if (!lua_isuserdata(L, 1)){
        return 0;
    }
    luat_bluetooth_t* luat_bluetooth = (luat_bluetooth_t *)luaL_checkudata(L, 1, LUAT_BLUETOOTH_TYPE);
    luat_ble_init(luat_bluetooth, luat_ble_cb);

    if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		luat_bluetooth->luat_ble->lua_cb = luaL_ref(L, LUA_REGISTRYINDEX);
	}

    lua_pushboolean(L, 1);
    return 1;
}

static int l_ble_gatt_create(lua_State* L) {
    if (!lua_isuserdata(L, 1)){
        return 0;
    }

    luat_bluetooth_t* luat_bluetooth = (luat_bluetooth_t *)luaL_checkudata(L, 1, LUAT_BLUETOOTH_TYPE);
    luat_ble_gatt_cfg_t luat_ble_gatt_cfg = {0};

    int argc = lua_gettop(L);
    for (size_t m = 2; m <= argc; m++){
        if (lua_type(L, m) != LUA_TTABLE){
            LLOGE("error param");
            return 0;
        }
        size_t len = 0;
        
        memset(luat_ble_gatt_cfg.uuid, 0x00, sizeof(luat_ble_gatt_cfg.uuid));
        lua_pushstring(L, "uuid");
        if (LUA_TSTRING == lua_gettable(L, m)){
            const char* uuid_data = luaL_checklstring(L, -1, &len);
            if (len == 2){
                luat_ble_gatt_cfg.uuid_type = LUAT_BLE_UUID_TYPE_16;
            }else if (len == 4){
                luat_ble_gatt_cfg.uuid_type = LUAT_BLE_UUID_TYPE_32;
            }else if (len == 16){
                luat_ble_gatt_cfg.uuid_type = LUAT_BLE_UUID_TYPE_128;
            }
            luat_ble_uuid_swap(uuid_data, luat_ble_gatt_cfg.uuid_type);
            memcpy(luat_ble_gatt_cfg.uuid, uuid_data, len);
        }
        lua_pop(L, 1);
        
        lua_pushstring(L, "att_db");
        if (LUA_TTABLE == lua_gettable(L, m)){
            luat_ble_gatt_cfg.att_db_num = luaL_len(L, -1);
            luat_ble_gatt_cfg.att_db = (luat_ble_att_db_t*)luat_heap_malloc(sizeof(luat_ble_att_db_t) * luat_ble_gatt_cfg.att_db_num);
            memset(luat_ble_gatt_cfg.att_db, 0x00, sizeof(luat_ble_att_db_t));
            for (int i = 1; i <= luat_ble_gatt_cfg.att_db_num; i++) {
                lua_rawgeti(L, -1, i);
                int table_len = luaL_len(L, -1);
                for (int j = 1; j <= table_len; j++){
                    lua_rawgeti(L, -1, j);
                    if (j == 1 && lua_type(L, -1) == LUA_TSTRING){
                        const char* uuid_data = luaL_checklstring(L, -1, &len);
                        if (len == 2){
                            luat_ble_gatt_cfg.att_db[i-1].uuid_type = LUAT_BLE_UUID_TYPE_16;
                        }else if (len == 4){
                            luat_ble_gatt_cfg.att_db[i-1].uuid_type = LUAT_BLE_UUID_TYPE_32;
                        }else if (len == 16){
                            luat_ble_gatt_cfg.att_db[i-1].uuid_type = LUAT_BLE_UUID_TYPE_128;
                        }
                        luat_ble_uuid_swap(uuid_data, luat_ble_gatt_cfg.att_db[i-1].uuid_type);
                        memcpy(luat_ble_gatt_cfg.att_db[i-1].uuid, uuid_data, len);
                    }else if(j == 2 && lua_type(L, -1) == LUA_TNUMBER){
                        luat_ble_gatt_cfg.att_db[i-1].perm = (uint16_t)luaL_optnumber(L, -1, 0);
                    }else if(j == 3 && lua_type(L, -1) == LUA_TNUMBER){
                        luat_ble_gatt_cfg.att_db[i-1].max_size = (uint16_t)luaL_optnumber(L, -1, 256);
                    }else{
                        LLOGE("error att_db type");
                        goto end; 
                    }
                    lua_pop(L, 1);
                }
                lua_pop(L, 1);
            }
        }else{
            LLOGE("error att_db");
            goto end;
        }
        lua_pop(L, 1);
        luat_ble_create_gatt(luat_bluetooth, &luat_ble_gatt_cfg);
        luat_heap_free(luat_ble_gatt_cfg.att_db);
        luat_ble_gatt_cfg.prf_id++;
    }
    lua_pushboolean(L, 1);
    return 1;
end:
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
    luat_bluetooth_t* luat_bluetooth = (luat_bluetooth_t *)luaL_checkudata(L, 1, LUAT_BLUETOOTH_TYPE);
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

    luat_ble_create_advertising(luat_bluetooth, &luat_ble_adv_cfg);

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
                            luat_ble_set_name(luat_bluetooth, data, len);
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
        luat_ble_set_name(luat_bluetooth, complete_local_name, strlen(complete_local_name));
    }

    /* set adv paramters */
    luat_ble_set_adv_data(luat_bluetooth, adv_data, adv_index);

    lua_pushboolean(L, 1);
    return 1;
end:
    return 0;
}

static int l_ble_advertising_start(lua_State* L) {
    luat_bluetooth_t* luat_bluetooth = (luat_bluetooth_t*)lua_newuserdata(L, sizeof(luat_bluetooth_t));
    lua_pushboolean(L, luat_ble_start_advertising(luat_bluetooth)?0:1);
    return 1;
}

static int l_ble_advertising_stop(lua_State* L) {
    luat_bluetooth_t* luat_bluetooth = (luat_bluetooth_t*)lua_newuserdata(L, sizeof(luat_bluetooth_t));
    lua_pushboolean(L, luat_ble_stop_advertising(luat_bluetooth)?0:1);
    return 1;
}

static int l_bluetooth_init(lua_State* L) {
    luat_bluetooth_t* luat_bluetooth = (luat_bluetooth_t*)lua_newuserdata(L, sizeof(luat_bluetooth_t));
    if (luat_bluetooth) {
        luat_bluetooth_init(luat_bluetooth);
        luaL_setmetatable(L, LUAT_BLUETOOTH_TYPE);
        lua_pushvalue(L, -1);
        luat_bluetooth->bluetooth_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        return 1;
    }
    return 0;
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
    {"gatt_create",                 ROREG_FUNC(l_ble_gatt_create)},
    {"adv_create",                  ROREG_FUNC(l_ble_advertising_create)},
    {"adv_start",                   ROREG_FUNC(l_ble_advertising_start)},
    {"adv_stop",                    ROREG_FUNC(l_ble_advertising_stop)},

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
    // FLAGS
    {"FLAGS",                       ROREG_INT(LUAT_ADV_TYPE_FLAGS)},
    {"COMPLETE_LOCAL_NAME",         ROREG_INT(LUAT_ADV_TYPE_COMPLETE_LOCAL_NAME)},
    {"SERVICE_DATA",                ROREG_INT(LUAT_ADV_TYPE_SERVICE_DATA_16BIT)},
    {"MANUFACTURER_SPECIFIC_DATA",  ROREG_INT(LUAT_ADV_TYPE_MANUFACTURER_SPECIFIC_DATA)},
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
    lua_pushvalue(L, -1);
    lua_setglobal(L, "ble");
    return 1;
}
