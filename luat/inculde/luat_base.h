
#ifndef LUAT_BASE
#define LUAT_BASE

#define LUAT_VERSION ("1.0.0")

#define LUAT_DEBUG 0

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "stdint.h"

lua_State * luat_get_state();
int luat_main (int argc, char **argv, int _);


LUAMOD_API int luaopen_sys( lua_State *L );
LUAMOD_API int luaopen_rtos( lua_State *L );
LUAMOD_API int luaopen_timer( lua_State *L );
LUAMOD_API int luaopen_msgbus( lua_State *L );
LUAMOD_API int luaopen_gpio( lua_State *L );
LUAMOD_API int luaopen_uart( lua_State *L );
LUAMOD_API int luaopen_pm( lua_State *L );

#endif
