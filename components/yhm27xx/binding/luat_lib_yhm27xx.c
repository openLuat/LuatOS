
/*
@module  yhm27xx
@summary yhm27xx充电芯片
@version 1.0
@date    2025.04.2
@tag LUAT_USE_GPIO
@demo yhm27xxx
@usage
-- 请查阅demo/yhm27xx
*/

#include "luat_pm.h"

#define LUAT_LOG_TAG "yhm27xx"
#include "luat_log.h"

static int l_yhm27xx_cmd(lua_State *L)
{
    // 设置命令类型为读写寄存器
    lua_pushinteger(L, LUAT_PM_YHM27XX_CMD_READWRITE);
    lua_insert(L, 4); // 将命令类型插入到第四个参数位置
    
    return l_pm_chgcmd(L);
}

static int l_yhm27xx_reqinfo(lua_State *L)
{
    // 设置命令类型为请求所有寄存器信息
    lua_pushinteger(L, LUAT_PM_YHM27XX_CMD_REQINFO);
    lua_insert(L, 3); // 将命令类型插入到第三个参数位置
    
    return l_pm_chgcmd(L);
}

#include "rotable2.h"
static const rotable_Reg_t reg_yhm27xx[] = {
        {"cmd",     ROREG_FUNC(l_yhm27xx_cmd)},
        {"reqinfo", ROREG_FUNC(l_yhm27xx_reqinfo)},
        {NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_yhm27xx(lua_State *L)
{
  luat_newlib2(L, reg_yhm27xx);
  return 1;
}
