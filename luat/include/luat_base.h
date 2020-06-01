
#ifndef LUAT_BASE
#define LUAT_BASE

#define LUAT_VERSION "1.0.6-SNAPSHOT"

#define LUAT_DEBUG 0

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "stdint.h"
#include "string.h"

//lua_State * luat_get_state();
int luat_main (int argc, char **argv, int _);

void luat_openlibs(lua_State *L);


LUAMOD_API int luaopen_sys( lua_State *L );
LUAMOD_API int luaopen_rtos( lua_State *L );
LUAMOD_API int luaopen_timer( lua_State *L );
LUAMOD_API int luaopen_msgbus( lua_State *L );
LUAMOD_API int luaopen_gpio( lua_State *L );
LUAMOD_API int luaopen_uart( lua_State *L );
LUAMOD_API int luaopen_pm( lua_State *L );
LUAMOD_API int luaopen_fs( lua_State *L );
LUAMOD_API int luaopen_wlan( lua_State *L );
LUAMOD_API int luaopen_socket( lua_State *L );
LUAMOD_API int luaopen_sensor( lua_State *L );
LUAMOD_API int luaopen_log( lua_State *L );
LUAMOD_API int luaopen_cjson( lua_State *L );
LUAMOD_API int luaopen_i2c( lua_State *L );
LUAMOD_API int luaopen_disp( lua_State *L );
LUAMOD_API int luaopen_utest( lua_State *L );
LUAMOD_API int luaopen_spi( lua_State *L );

LUAMOD_API int luaopen_mqtt( lua_State *L );
LUAMOD_API int luaopen_http( lua_State *L );
LUAMOD_API int luaopen_pack( lua_State *L );
LUAMOD_API int luaopen_mqttcore( lua_State *L );

int l_sprintf(char *buf, size_t size, const char *fmt, ...);

void luat_os_reboot(int code);
void luat_os_standy(int timeout);
const char* luat_os_bsp(void);

void stopboot(void);

#endif
