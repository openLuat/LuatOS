/*
@module  misc
@summary 杂项驱动，各种非常规驱动，芯片独有驱动都放在这里
@version 1.0
@date    2025.7.24
@author  lisiqi
@tag     LUAT_USE_MISC
@demo    misc
@usage
*/

#include "luat_base.h"
#include "luat_gpio.h"
#define LUAT_LOG_TAG "misc"
#include "luat_log.h"

#include "rotable2.h"

/*
某个引脚的GPO功能使能
@api misc.gpo_setup(id)
@int id, GPO编号
@return nil
@usage
misc.gpo_setup(0)
*/
static int l_misc_gpo_setup(lua_State *L)
{
#ifdef LUAT_USE_MISC_GPO
	luat_gpo_open(luaL_optinteger(L, 1, 0));
#endif
	return 0;
}

/*
GPO输出高低电平
@api misc.gpo_output(id,level)
@int id, GPO编号
@int level, 1高电平，0低电平
@return nil
@usage
misc.gpo_output(0,1)
*/
static int l_misc_gpo_output(lua_State *L)
{
#ifdef LUAT_USE_MISC_GPO
	luat_gpo_output(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, 0));
#endif
	return 0;
}

/*
获取GPO输出的电平
@api misc.gpo_level(id)
@int id, GPO编号
@return int level, 1高电平，0低电平
@usage
misc.gpo_level(0)
*/
static int l_misc_gpo_get_output_level(lua_State *L)
{
#ifdef LUAT_USE_MISC_GPO
	lua_pushinteger(L, luat_gpo_get_output_level(luaL_optinteger(L, 1, 0)));
	return 1;
#else
	return 0;
#endif
}

static const rotable_Reg_t reg_misc[] =
{
	{"gpo_setup", ROREG_FUNC(l_misc_gpo_setup)},
	{"gpo_output", ROREG_FUNC(l_misc_gpo_output)},
	{"gpo_level", ROREG_FUNC(l_misc_gpo_get_output_level)},
	{NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_misc(lua_State *L)
{
    luat_newlib2(L, reg_misc);
    return 1;
}
