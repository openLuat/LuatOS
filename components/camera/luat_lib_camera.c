
/*
@module  camera
@summary 摄像头
@version 1.0
@date    2022.01.11
*/
#include "luat_base.h"
#include "luat_camera.h"

#define LUAT_LOG_TAG "camera"

static int l_camera_init(lua_State *L){
    luat_camera_conf_t conf = {0};
    if (lua_istable(L, 1)) {
        lua_pushliteral(L, "zbar_scan");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.zbar_scan = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "i2c_addr");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.i2c_addr = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "sensor_width");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.sensor_width = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "sensor_height");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.sensor_height = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "id_reg");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.id_reg = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "id_value");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.id_value = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "init_cmd");
        lua_gettable(L, 1);
        if (lua_istable(L, -1)) {
            size_t init_cmd_size = lua_rawlen(L, -1);
            conf.init_cmd = luat_heap_malloc(init_cmd_size * sizeof(uint8_t));
            for (size_t i = 1; i <= init_cmd_size; i++){
                lua_geti(L, -1, i);
                conf.init_cmd[i-1] = luaL_checkinteger(L, -1);
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
    }
    luat_camera_init(&conf);
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_camera[] =
{
    { "init" ,       l_camera_init , 0},
    // { "open" ,       l_camera_open , 0},
    // { "close" ,      l_camera_close, 0},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_camera( lua_State *L ) {
    luat_newlib(L, reg_camera);
    return 1;
}

