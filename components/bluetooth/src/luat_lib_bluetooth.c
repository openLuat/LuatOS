#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_log.h"
#define LUAT_LOG_TAG "bluetooth"

extern void luat_ble_cb(luat_ble_t* luat_ble, luat_ble_event_t ble_event, luat_ble_param_t* ble_param);

static int l_bluetooth_create_ble(lua_State* L) {
    if (!lua_isuserdata(L, 1)){
        return 0;
    }
    luat_bluetooth_t* luat_bluetooth = (luat_bluetooth_t *)luaL_checkudata(L, 1, LUAT_BLUETOOTH_TYPE);

    luat_bluetooth->luat_ble = (luat_ble_t*)lua_newuserdata(L, sizeof(luat_ble_t));
    luat_ble_init(luat_bluetooth->luat_ble, luat_ble_cb);

    if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		luat_bluetooth->luat_ble->lua_cb = luaL_ref(L, LUA_REGISTRYINDEX);
	}else{
        LLOGE("error cb");
        return 0;
    }

    luaL_setmetatable(L, LUAT_BLE_TYPE);
    lua_pushvalue(L, -1);
    luat_bluetooth->luat_ble->ble_ref = luaL_ref(L, LUA_REGISTRYINDEX);
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
