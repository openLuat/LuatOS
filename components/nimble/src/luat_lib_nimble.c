#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_spi.h"

#include "luat_nimble.h"

#define LUAT_LOG_TAG "nimble"
#include "luat_log.h"

static uint32_t nimble_mode = 0;

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
    lua_pushinteger(L, ret);
    return 2;
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

