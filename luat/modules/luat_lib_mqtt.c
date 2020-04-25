/*
@module  mqtt
@summary mqtt操作库
@version 1.0
@data    2020.03.30
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "rotable.h"

#include "netclient.h"

#define LUAT_MQTT_HANDLE "mqtt"

static int l_mqtt_new(lua_State *L) {
    return 0;
};

static int mqtt_id(lua_State *L) {
    return 0;
};
static int mqtt_host(lua_State *L) {
    return 0;
};
static int mqtt_port(lua_State *L) {
    return 0;
};
static int mqtt_start(lua_State *L) {
    return 0;
};
static int mqtt_close(lua_State *L) {
    return 0;
};
static int mqtt_subscribe(lua_State *L) {
    return 0;
};
static int mqtt_unsubscribe(lua_State *L) {
    return 0;
};
static int mqtt_publish(lua_State *L) {
    return 0;
};
static int mqtt_clean(lua_State *L) {
    return 0;
};
static int mqtt_gc(lua_State *L) {
    return 0;
};
static int mqtt_tostring(lua_State *L) {
    return 0;
};

static const luaL_Reg lib_mqtt[] = {
    {"id",          mqtt_id},
    {"host",        mqtt_host},
    {"port",        mqtt_port},
    {"start",       mqtt_start},
    {"close",       mqtt_close},
    {"subscribe",   mqtt_subscribe},
    {"unsubscribe", mqtt_unsubscribe},
    {"publish",     mqtt_publish},
    {"clean",       mqtt_clean},
    {"__gc",        mqtt_gc},
    {"__tostring",  mqtt_tostring},
    {NULL, NULL}
};


static void createmeta (lua_State *L) {
  luaL_newmetatable(L, LUAT_MQTT_HANDLE);  /* create metatable for file handles */
  lua_pushvalue(L, -1);  /* push metatable */
  lua_setfield(L, -2, "__index");  /* metatable.__index = metatable */
  luaL_setfuncs(L, lib_mqtt, 0);  /* add file methods to new metatable */
  lua_pop(L, 1);  /* pop new metatable */
}

static const rotable_Reg reg_mqtt[] =
{
    { "new", l_mqtt_new, 0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_mqtt( lua_State *L ) {
    rotable_newlib(L, reg_mqtt);
    return 1;
}
