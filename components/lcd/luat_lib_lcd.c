
/*
lcd驱动模块
@module lcd
@since 2021.06.16

*/
#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "lib_lcd"
#include "luat_log.h"

extern uint32_t BACK_COLOR , FORE_COLOR ;

extern const luat_lcd_opts_t lcd_opts_st7735;
extern const luat_lcd_opts_t lcd_opts_st7789;
extern const luat_lcd_opts_t lcd_opts_gc9a01;
extern const luat_lcd_opts_t lcd_opts_gc9106l;
extern const luat_lcd_opts_t lcd_opts_gc9306;
extern const luat_lcd_opts_t lcd_opts_ili9341;
extern const luat_lcd_opts_t lcd_opts_custom;

static luat_lcd_conf_t *default_conf = NULL;

/*
初始化lcd
@api lcd.init(tp, args)
@string lcd类型, 当前支持st7789/st7735/gc9a01/gc9106l/gc9306/ili9341/custom
@table 附加参数,与具体设备有关
*/
static int l_lcd_init(lua_State* L) {
    size_t len = 0;
    const char* tp = luaL_checklstring(L, 1, &len);
    if (!strcmp("st7735", tp) || !strcmp("st7789", tp)
            || !strcmp("gc9a01", tp)  || !strcmp("gc9106l", tp)
            || !strcmp("gc9306", tp)  || !strcmp("ili9341", tp)
            || !strcmp("custom", tp)) {
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

            lua_pushstring(L, "direction");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->direction = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);

            lua_pushstring(L, "w");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->w = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);

            lua_pushstring(L, "h");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                conf->h = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
        }
        if (!strcmp("st7735", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_st7735;
        else if (!strcmp("st7789", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_st7789;
        else if (!strcmp("gc9a01", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_gc9a01;
        else if (!strcmp("gc9106l", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_gc9106l;
        else if (!strcmp("gc9306", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_gc9306;
        else if (!strcmp("ili9341", tp))
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_ili9341;
        else if (!strcmp("custom", tp)) {
            conf->opts = (luat_lcd_opts_t*)&lcd_opts_custom;
            luat_lcd_custom_t *cst = luat_heap_malloc(sizeof(luat_lcd_custom_t));

            // 获取initcmd/sleepcmd/wakecmd
            lua_pushstring(L, "sleepcmd");
            lua_gettable(L, 2);
            cst->sleepcmd = luaL_checkinteger(L, -1);
            lua_pop(L, 1);

            lua_pushstring(L, "wakecmd");
            lua_gettable(L, 2);
            cst->wakecmd = luaL_checkinteger(L, -1);
            lua_pop(L, 1);

            lua_pushstring(L, "initcmd");
            lua_gettable(L, 2);
            cst->init_cmd_count = lua_rawlen(L, -1);
            luat_heap_realloc(cst, sizeof(luat_lcd_custom_t) + cst->init_cmd_count * 4);
            for (size_t i = 1; i <= cst->init_cmd_count; i++)
            {
                lua_geti(L, -1, i);
                cst->initcmd[i-1] = luaL_checkinteger(L, -1);
                lua_pop(L, 1);
            }
            lua_pop(L, 1);
        }
        int ret = luat_lcd_init(conf);
        lua_pushboolean(L, ret == 0 ? 1 : 0);
        if (ret == 0)
            default_conf = conf;
        lua_pushlightuserdata(L, conf);
        return 2;
    }
    return 0;
}

static int l_lcd_close(lua_State* L) {
    int ret = luat_lcd_close(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_display_on(lua_State* L) {
    int ret = luat_lcd_display_on(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_display_off(lua_State* L) {
    int ret = luat_lcd_display_off(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_sleep(lua_State* L) {
    int ret = luat_lcd_sleep(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_wakeup(lua_State* L) {
    int ret = luat_lcd_wakeup(default_conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_set_color(lua_State* L) {
    uint32_t back,fore;
    back = luaL_checkinteger(L, 1);
    fore = luaL_checkinteger(L, 2);
    int ret = luat_lcd_set_color(back, fore);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_draw(lua_State* L) {
    uint16_t x1, y1, x2, y2;
    uint32_t *color = FORE_COLOR;
    x1 = luaL_checkinteger(L, 1);
    y1 = luaL_checkinteger(L, 2);
    x2 = luaL_checkinteger(L, 3);
    y2 = luaL_checkinteger(L, 4);
    if (lua_gettop(L) > 4)
        color = (uint32_t *)luaL_checkinteger(L, 5);
    int ret = luat_lcd_draw(default_conf, x1, y1, x2, y2, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_clear(lua_State* L) {
    size_t len = 0;
    uint32_t color = FORE_COLOR;
    if (lua_gettop(L) > 0)
        color = luaL_checkinteger(L, 1);
    int ret = luat_lcd_clear(default_conf, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_draw_point(lua_State* L) {
    uint16_t x, y;
    uint32_t color = FORE_COLOR;
    x = luaL_checkinteger(L, 1);
    y = luaL_checkinteger(L, 2);
    if (lua_gettop(L) > 2)
        color = luaL_checkinteger(L, 3);
    int ret = luat_lcd_draw_point(default_conf, x, y, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_draw_line(lua_State* L) {
    uint16_t x1, y1, x2, y2;
    uint32_t color = FORE_COLOR;
    x1 = luaL_checkinteger(L, 1);
    y1 = luaL_checkinteger(L, 2);
    x2 = luaL_checkinteger(L, 3);
    y2 = luaL_checkinteger(L, 4);
    if (lua_gettop(L) > 4)
        color = luaL_checkinteger(L, 5);
    int ret = luat_lcd_draw_line(default_conf, x1,  y1,  x2,  y2, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_draw_rectangle(lua_State* L) {
    uint16_t x1, y1, x2, y2;
    uint32_t color = FORE_COLOR;
    x1 = luaL_checkinteger(L, 1);
    y1 = luaL_checkinteger(L, 2);
    x2 = luaL_checkinteger(L, 3);
    y2 = luaL_checkinteger(L, 4);
    if (lua_gettop(L) > 4)
        color = luaL_checkinteger(L, 5);
    int ret = luat_lcd_draw_rectangle(default_conf, x1,  y1,  x2,  y2, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_draw_circle(lua_State* L) {
    uint16_t x0, y0, r;
    uint32_t color = FORE_COLOR;
    x0 = luaL_checkinteger(L, 1);
    y0 = luaL_checkinteger(L, 2);
    r = luaL_checkinteger(L, 3);
    if (lua_gettop(L) > 3)
        color = luaL_checkinteger(L, 4);
    int ret = luat_lcd_draw_circle(default_conf, x0,  y0,  r, color);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

static int l_lcd_set_default(lua_State *L) {
    if (lua_gettop(L) == 1) {
        default_conf = lua_touserdata(L, 1);
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_lcd[] =
{
    { "init",      l_lcd_init,   0},
    { "close",      l_lcd_close,       0},
    { "on",      l_lcd_display_on,       0},
    { "off",      l_lcd_display_off,       0},
    { "sleep",      l_lcd_sleep,       0},
    { "wakeup",      l_lcd_wakeup,       0},
    { "setColor",      l_lcd_set_color,       0},
    { "draw",      l_lcd_draw,       0},
    { "clear",      l_lcd_clear,       0},
    { "drawPoint",      l_lcd_draw_point,       0},
    { "drawLine",      l_lcd_draw_line,       0},
    { "drawRectangle",      l_lcd_draw_rectangle,       0},
    { "drawCircle",      l_lcd_draw_circle,       0},
    { "setDefault", l_lcd_set_default, 0},
	{ NULL,        NULL,   0}
};

LUAMOD_API int luaopen_lcd( lua_State *L ) {
    luat_newlib(L, reg_lcd);
    return 1;
}
