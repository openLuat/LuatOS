#ifndef LUAT_LIB_AIRLINK_INTERNAL_H
#define LUAT_LIB_AIRLINK_INTERNAL_H

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_INSTANCE
int l_airlink_setup(lua_State *L);
int l_airlink_close(lua_State *L);
int l_airlink_status(lua_State *L);
int l_airlink_instance_statistics(lua_State *L);
#endif

// fota (luat_lib_airlink_fota.c)
int l_airlink_sfota_init(lua_State *L);
int l_airlink_sfota_done(lua_State *L);
int l_airlink_sfota_end(lua_State *L);
int l_airlink_sfota_write(lua_State *L);
int l_airlink_sfota(lua_State *L);

// ping (luat_lib_airlink_ping.c)
int l_airlink_ping(lua_State *L);

// loopback test (luat_lib_airlink_loopback_test.c)
#ifdef LUAT_USE_AIRLINK_LOOPBACK
int l_airlink_test_nanopb_gpio(lua_State *L);
int l_airlink_test_nanopb_uart(lua_State *L);
int l_airlink_test_nanopb_wlan(lua_State *L);
int l_airlink_test_nanopb_pm(lua_State *L);
#endif

#endif
