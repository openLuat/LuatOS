
/*
lcd驱动模块
@module lcd
@since 2021.06.16

*/
#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_malloc.h"

#include "luat_malloc.h"

extern const luat_lcd_opts_t lcd_opts_st7789;
extern const luat_lcd_opts_t lcd_opts_st7735;

/*
初始化lcd
@api lcd.init(tp, buff, args)
@string lcd类型, 当前支持st7789
@table 附加参数,与具体设备有关
*/
static int l_lcd_init(lua_State* L) {
    size_t len = 0;
    const char* tp = luaL_checklstring(L, 1, &len);
    if (!strcmp("st7789", tp) || !strcmp("st7735", tp)) {
        luat_lcd_conf_t *conf = luat_heap_malloc(sizeof(luat_lcd_conf_t));
        memset(conf, 0, sizeof(luat_lcd_conf_t)); // 填充0,保证无脏数据
        
        if (lua_gettop(L) > 1) {
            lua_settop(L, 2); // 丢弃多余的参数
            
            lua_pushstring(L, "port");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->port = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);

            lua_pushstring(L, "pin_cs");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->pin_cs = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);

            lua_pushstring(L, "pin_dc");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->pin_dc = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);

            lua_pushstring(L, "pin_pwr");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->pin_pwr = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);

            lua_pushstring(L, "pin_rst");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->pin_rst = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
        }
        if (!strcmp("st7789", tp))
            conf->opts = &lcd_opts_st7789;
        else if (!strcmp("st7735", tp))
            conf->opts = &lcd_opts_st7735;
        int ret = luat_lcd_init(conf);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        return 1;
    }
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_lcd[] =
{
    { "init",      l_lcd_init,   0},
	{ NULL,        NULL,   0}
};

LUAMOD_API int luaopen_lcd( lua_State *L ) {
    luat_newlib(L, reg_lcd);
    return 1;
}
