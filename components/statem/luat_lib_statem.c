
/*
@module  statem
@summary SM状态机
@version 1.0
@date    2021.09.26
@demo statem
@tag LUAT_USE_STATEM
*/

#include "luat_base.h"
#include "luat_statem.h"


/*
创建一个新的状态机.
@api statem.create(count, repeat)
@int 指令条数,默认32条
@int 重复执行的次数, 0 代表不重复, 正整数代表具体重复执行的次数. 暂不支持永续执行
@return some 若成功,返回状态机指针,否则返回nil
@usage
gpio.setup(7, 0, gpio.PULLUP)
gpio.setup(12, 0, gpio.PULLUP)
gpio.setup(13, 0, gpio.PULLUP)
gpio.setup(14, 0, gpio.PULLUP)
local sm =  statem.create()
            :gpio_set(7, 0) -- gpio设置为低电平
            :usleep(10)     -- 休眠10us
            :gpio_set(7, 1) -- gpio设置为高电平
            :usleep(40)     -- 休眠40us
            :gpio_set(12, 1) -- gpio设置为高电平
            :gpio_set(13, 1) -- gpio设置为高电平
            :gpio_set(14, 1) -- gpio设置为高电平
            :usleep(40)      -- 休眠40us
            :gpio_set(7, 0) -- gpio设置为低电平
            :finish()

-- 执行之,后续会支持后台执行
sm:exec()
*/
static int l_statem_create(lua_State *L) {
    int count = luaL_optinteger(L, 1, 32);
    if (count < 1)
        return 0;
    int repeat = luaL_optinteger(L, 2, 0);
    if (repeat < 0)
        return 0;
    luat_statem_t* sm = (luat_statem_t*)lua_newuserdata(L, sizeof(luat_statem_t) + sizeof(luat_statm_op_t)*count);
    if (sm == NULL) {
        return 0;
    }
    memset(sm, 0, sizeof(luat_statem_t) + sizeof(luat_statm_op_t) * count);
    sm->op_count = count;
    luaL_setmetatable(L, "SM*");
    return 1;
}

static int _statem_gpio_set(lua_State *L) {
    luat_statem_t* sm = luaL_checkudata(L, 1, "SM*");
    int gpio_pin = luaL_checkinteger(L, 2);
    int gpio_val = luaL_checkinteger(L, 3);
    luat_statem_addop(sm, LUAT_SM_OP_GPIO_SET, (uint8_t)gpio_pin, (uint8_t)gpio_val, (uint8_t)0);
    lua_settop(L, 1);
    return 1;
}

static int _statem_gpio_get(lua_State *L) {
    luat_statem_t* sm = luaL_checkudata(L, 1, "SM*");
    int gpio_pin = luaL_checkinteger(L, 2);
    luat_statem_addop(sm, LUAT_SM_OP_GPIO_GET, (uint8_t)gpio_pin, (uint8_t)0, (uint8_t)0);
    lua_settop(L, 1);
    return 1;
}

static int _statem_usleep(lua_State *L) {
    luat_statem_t* sm = luaL_checkudata(L, 1, "SM*");
    int usleep = luaL_checkinteger(L, 2);
    luat_statem_addop(sm, LUAT_SM_OP_USLEEP, (uint8_t)usleep, (uint8_t)0, (uint8_t)0);
    lua_settop(L, 1);
    return 1;
}

static int _finish_end(lua_State *L) {
    luat_statem_t* sm = luaL_checkudata(L, 1, "SM*");
    luat_statem_addop(sm, LUAT_SM_OP_END, (uint8_t)0, (uint8_t)0, (uint8_t)0);
    lua_settop(L, 1);
    return 1;
}
static int _statem_exec(lua_State *L) {
    luat_statem_t* sm = luaL_checkudata(L, 1, "SM*");
    int backgroud = luaL_optinteger(L, 2, 0);
    if (backgroud) {
        return 0;
    }
    else {
        luat_statem_exec(sm);
    }
    return 1;
}

static int _statem_clear(lua_State *L) {
    luat_statem_t* sm = luaL_checkudata(L, 1, "SM*");
    memset(sm, 0, sizeof(luat_statem_t) + sm->op_count*4);
    lua_settop(L, 1);
    return 1;
}

static int _statem_result(lua_State *L) {
    luat_statem_t* sm = luaL_checkudata(L, 1, "SM*");
    lua_createtable(L, 8, 0);
    for (size_t i = 0; i < 8; i++)
    {
        lua_pushinteger(L, sm->gpio_inputs[i]);
        lua_seti(L, -2, i+1);
    }
    return 1;
}

static int _statem_struct_newindex(lua_State *L) {
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("gpio_set", key)) {
        lua_pushcfunction(L, _statem_gpio_set);
        return 1;
    }
    else if (!strcmp("gpio_get", key)) {
        lua_pushcfunction(L, _statem_gpio_get);
        return 1;
    }
    else if (!strcmp("finish", key)) {
        lua_pushcfunction(L, _finish_end);
        return 1;
    }
    else if (!strcmp("usleep", key)) {
        lua_pushcfunction(L, _statem_usleep);
        return 1;
    }
    else if (!strcmp("exec", key)) {
        lua_pushcfunction(L, _statem_exec);
        return 1;
    }
    else if (!strcmp("clear", key)) {
        lua_pushcfunction(L, _statem_clear);
        return 1;
    }
    else if (!strcmp("result", key)) {
        lua_pushcfunction(L, _statem_result);
        return 1;
    }
    return 0;
}


#include "rotable2.h"
static const rotable_Reg_t reg_statem[] =
{
    { "create",      ROREG_FUNC(l_statem_create)},
	{ NULL,          ROREG_INT(0)}
};

static void luat_statem_struct_init(lua_State *L) {
    luaL_newmetatable(L, "SM*");
    lua_pushcfunction(L, _statem_struct_newindex);
    lua_setfield( L, -2, "__index" );
    lua_pop(L, 1);
}

LUAMOD_API int luaopen_statem( lua_State *L ) {
    luat_newlib2(L, reg_statem);
    luat_statem_struct_init(L);
    return 1;
}
