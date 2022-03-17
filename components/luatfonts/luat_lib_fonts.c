#include "luat_base.h"

#include "luat_fonts.h"

static int l_fonts_get_data(lua_State *L) {
    int font_id = luaL_checkinteger(L, 1);
    uint32_t chr = luaL_checkinteger(L, 2);
    uint8_t buff[512] = {0};
    luat_font_data_t data = {
        .buff = buff,
        .len = 512,
        .w = 0
    };
    int ret = luat_font_get(font_id, chr, &data);
    if (ret == 0) {
        lua_pushlstring(L, buff, data.len);
        lua_pushinteger(L, data.w);
        return 2;
    }
    return 0;
}

static int l_fonts_load_font(lua_State *L) {
    // TODO 从文件加载, 还得做个加载器
    return 0;
}

// static int l_fonts_close_font(lua_State *L) {
    
// }

#include "rotable2.h"
static const rotable_Reg_t reg_fonts[] =
{
    { "get_data" ,       ROREG_FUNC(l_fonts_get_data)},
    { "load_font" ,      ROREG_FUNC(l_fonts_load_font)},
    //{ "close_font" ,   ROREG_FUNC(l_fonts_close_font)},
	{ NULL,              {}}
};

LUAMOD_API int luaopen_fonts( lua_State *L ) {
    luat_newlib2(L, reg_fonts);
    return 1;
}
