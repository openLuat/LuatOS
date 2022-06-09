#include "luat_base.h"

#include "u8g2.h"
#include "u8g2_luat_fonts.h"

typedef struct u8g2_font
{
    const char* name;
    const uint8_t* font;
}u8g2_font_t;


static u8g2_font_t u8g2_fonts[] = {
#ifdef USE_U8G2_OPPOSANSM_ENGLISH
    {.name="unifont_t_symbols", .font=u8g2_font_unifont_t_symbols},
    {.name="open_iconic_weather_6x_t", .font=u8g2_font_open_iconic_weather_6x_t},
    {.name="opposansm8", .font=u8g2_font_opposansm8},
    {.name="opposansm10", .font=u8g2_font_opposansm10},
    {.name="opposansm12", .font=u8g2_font_opposansm12},
    {.name="opposansm16", .font=u8g2_font_opposansm16},
    {.name="opposansm20", .font=u8g2_font_opposansm20},
    {.name="opposansm24", .font=u8g2_font_opposansm24},
    {.name="opposansm32", .font=u8g2_font_opposansm32},
#endif
#ifdef USE_U8G2_OPPOSANSM8_CHINESE
    {.name="opposansm8_chinese", .font=u8g2_font_opposansm8_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM10_CHINESE
    {.name="opposansm10_chinese", .font=u8g2_font_opposansm10_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM12_CHINESE
    {.name="opposansm12_chinese", .font=u8g2_font_opposansm12_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM16_CHINESE
    {.name="opposansm16_chinese", .font=u8g2_font_opposansm16_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM18_CHINESE
    {.name="opposansm18_chinese", .font=u8g2_font_opposansm18_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM20_CHINESE
    {.name="opposansm20_chinese", .font=u8g2_font_opposansm20_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM22_CHINESE
    {.name="opposansm22_chinese", .font=u8g2_font_opposansm22_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM24_CHINESE
    {.name="opposansm24_chinese", .font=u8g2_font_opposansm24_chinese},
#endif
#ifdef USE_U8G2_OPPOSANSM32_CHINESE
    {.name="opposansm32_chinese", .font=u8g2_font_opposansm32_chinese},
#endif
    {.name="", .font=NULL},
};


static int l_fonts_u8g2_get(lua_State *L) {
    const char* name = luaL_checkstring(L,  1);
    u8g2_font_t *font = u8g2_fonts;
    while (font->font != NULL) {
        if (!strcmp(name, font->name)) {
            lua_pushlightuserdata(L, font->font);
            return 1;
        }
        font ++;
    }
    return 0;
}

static int l_fonts_u8g2_load(lua_State *L) {
    // TODO 从文件加载
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_fonts[] =
{
    { "u8g2_get" ,       ROREG_FUNC(l_fonts_u8g2_get)},
    //{ "u8g2_load" ,      ROREG_FUNC(l_fonts_u8g2_load)},
	{ NULL,              ROREG_INT(0)},
};

LUAMOD_API int luaopen_fonts( lua_State *L ) {
    luat_newlib2(L, reg_fonts);
    return 1;
}
