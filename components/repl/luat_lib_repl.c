
/*
@module  repl
@summary "读取-求值-输出" 循环
@date    2023.06.16
@tag LUAT_USE_REPL
*/
#include "luat_base.h"
#include "luat_repl.h"
#define LUAT_LOG_TAG "repl"
#include "luat_log.h"

/*
代理打印, 暂未实现
*/
static int l_repl_print(lua_State* L) {
    return 0;
}

/*
启用或禁用REPL功能
@api repl.enable(re)
@bool 启用与否,默认是启用
@return 之前的设置状态
@usage
-- 若固件支持REPL,即编译时启用了REPL,是默认启用REPL功能的
-- 本函数是提供关闭REPL的途径
repl.enable(false)
*/
static int l_repl_enable(lua_State* L) {
    int ret = 0;
    if (lua_isboolean(L, 1))
        ret = luat_repl_enable(lua_toboolean(L, 1));
    else
        ret = luat_repl_enable(-1);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_repl[] =
{
    { "print" ,         ROREG_FUNC(l_repl_print)},
    { "enable" ,        ROREG_FUNC(l_repl_enable)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_repl( lua_State *L ) {
    luat_newlib2(L, reg_repl);
    return 1;
}
