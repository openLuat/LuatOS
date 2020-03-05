
#include "luat_base.h"
#include "rtconfig.h"
#include "luat_malloc.h"

#ifdef PKG_USING_U8G2
#include <rtdevice.h>
#include <u8g2_port.h>

static u8g2_t* u8g2;
static int u8g2_lua_ref;

static int l_disp_init(lua_State *L) {
    if (u8g2 != NULL) {
        lua_pushinteger(L, 2);
        return 1;
    }
    u8g2 = (u8g2_t*)lua_newuserdata(L, sizeof(u8g2_t));
    if (u8g2 == NULL) {
        lua_pushinteger(L, 3);
        return 1;
    }
    // if (lua_isstring(L, 1)) {
    //     size_t len;
    //     const char* tp = lua_tolstring(L, 1, len);
    //     if (rt_strncmp("ssd1306", tp, len)) {

    //     }
    // }
    // TODO: 暂时只支持SSD1306 12864, I2C接口-> i2c1soft, 软件模拟
    u8g2_Setup_ssd1306_i2c_128x64_noname_f( u8g2, U8G2_R0, u8x8_byte_rt_hw_i2c, u8x8_rt_gpio_and_delay);
    u8g2_InitDisplay(u8g2);
    u8g2_SetPowerSave(u8g2, 0);
    u8g2_lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    
    lua_pushinteger(L, 1);
    return 1;
}
static int l_disp_close(lua_State *L) {
    if (u8g2_lua_ref != 0) {
        lua_geti(L, LUA_REGISTRYINDEX, u8g2_lua_ref);
        if (lua_isuserdata(L, -1)) {
            luaL_unref(L, LUA_REGISTRYINDEX, u8g2_lua_ref);
        }
        u8g2_lua_ref = 0;
    }
    lua_gc(L, LUA_GCCOLLECT, 0);
    u8g2 = NULL;
    return 0;
}
static int l_disp_clear(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_ClearBuffer(u8g2);
    return 0;
}
static int l_disp_update(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_SendBuffer(u8g2);
    return 0;
}
static int l_disp_draw_text(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_SetFont(u8g2, u8g2_font_ncenB08_tr);
    size_t len;
    size_t x, y;
    const char* str = luaL_checklstring(L, 1, &len);
    x = luaL_checkinteger(L, 2);
    y = luaL_checkinteger(L, 3);
    
    u8g2_DrawStr(u8g2, x, y, str);
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_disp[] =
{
    { "init", l_disp_init, 0},
    { "close", l_disp_close, 0},
    { "clear", l_disp_clear, 0},
    { "update", l_disp_update, 0},
    { "drawStr", l_disp_draw_text, 0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_disp( lua_State *L ) {
    u8g2_lua_ref = 0;
    u8g2 = NULL;
    rotable_newlib(L, reg_disp);
    return 1;
}
#endif
