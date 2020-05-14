/*
 * 针对ec616/air302的一些特殊操作
 * 
 */

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"

static int l_nbiot_ready(lua_State *L) {
    lua_pushboolean(L, 0);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_nbiot[] =
{
    { "ready" ,         l_nbiot_ready , 0},
	{ NULL,             NULL ,        0}
};

LUAMOD_API int luaopen_nbiot( lua_State *L ) {
    rotable_newlib(L, reg_nbiot);
    return 1;
}
