/*
@module  disp
@summary disp库已合并到u8g2库,API等价
@version 1.0
@date    2020.03.30
@demo u8g2
@tag LUAT_USE_DISP
*/
#include "luat_base.h"
#include "luat_malloc.h"

/*
显示屏初始化,请使用u8g2库
@api disp.init(conf)
@table conf 配置信息
@return int 正常初始化1,已经初始化过2,内存不够3,初始化失败返回4
@usage
-- disp库的所有API均已合并到u8g2库
-- disp库已经映射为u8g2库,所有API均代理到u8g2,请查阅u8g2库的API
*/
static int l_disp_init(lua_State *L) {
    return 0;
}

LUAMOD_API int luaopen_disp( lua_State *L ) {
    lua_getglobal(L, "u8g2");
    if (lua_isuserdata(L, -1))
        return 1;
    luaopen_u8g2(L);
    return 1;
}
