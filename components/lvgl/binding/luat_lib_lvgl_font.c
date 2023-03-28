/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_malloc.h"

#include "luat_lvgl_fonts.h"
#include "luat_spi.h"

#ifdef LUAT_USE_GTFONT
    extern luat_spi_device_t* gt_spi_dev;
#endif

/*
获取内置字体
@api lvgl.font_get(name)
@string 字体名称+字号, 例如 opposans_m_10
@return userdata 字体指针
@usage

local font = lvgl.font_get("opposans_m_12")
*/
int luat_lv_font_get(lua_State *L) {
    lv_font_t* font = NULL;
    const char* fontname = luaL_checkstring(L, 1);
    if (!strcmp("", fontname)) {
    }
#ifdef LV_FONT_MONTSERRAT_14
    else if (!strcmp("montserrat_14", fontname)) { font = &lv_font_montserrat_14;}
#endif
#ifdef LV_FONT_OPPOSANS_M_8
    else if (!strcmp("opposans_m_8", fontname)) { font = &lv_font_opposans_m_8;}
#endif
#ifdef LV_FONT_OPPOSANS_M_10
    else if (!strcmp("opposans_m_10", fontname)) { font = &lv_font_opposans_m_10;}
#endif
#ifdef LV_FONT_OPPOSANS_M_12
    else if (!strcmp("opposans_m_12", fontname)) { font = &lv_font_opposans_m_12;}
#endif
#ifdef LV_FONT_OPPOSANS_M_14
    else if (!strcmp("opposans_m_14", fontname)) { font = &lv_font_opposans_m_14;}
#endif
#ifdef LV_FONT_OPPOSANS_M_16
    else if (!strcmp("opposans_m_16", fontname)) { font = &lv_font_opposans_m_16;}
#endif
#ifdef LV_FONT_OPPOSANS_M_18
    else if (!strcmp("opposans_m_18", fontname)) { font = &lv_font_opposans_m_18;}
#endif
#ifdef LV_FONT_OPPOSANS_M_20
    else if (!strcmp("opposans_m_20", fontname)) { font = &lv_font_opposans_m_20;}
#endif
#ifdef LV_FONT_OPPOSANS_M_22
    else if (!strcmp("opposans_m_22", fontname)) { font = &lv_font_opposans_m_22;}
#endif

    if (font) {
        lua_pushlightuserdata(L, font);
        return 1;
    }
    return 0;
}

/*
从文件系统加载字体
@api lvgl.font_load(path/spi_device,size,bpp,thickness,cache_size,sty_zh,sty_en)
@string/userdata 字体路径/spi_device (spi_device为使用外置高通矢量字库芯片)
@number size 可选,字号 16-192 默认16(使用高通矢量字库)
@number bpp 可选 深度 默认4(使用高通矢量字库)
@number thickness 可选 粗细值 默认size * bpp(使用高通矢量字库)
@number cache_size 可选 默认0(使用高通矢量字库)
@number sty_zh 可选 选择字体 默认1(使用高通矢量字库)
@number sty_en 可选 选择字体 默认3(使用高通矢量字库)
@return userdata 字体指针
@usage
local font = lvgl.font_load("/font_32.bin")
--local font = lvgl.font_load(spi_device,16)(高通矢量字库)
*/
int luat_lv_font_load(lua_State *L) {
    lv_font_t *font = NULL;
    if (lua_isuserdata(L, 1)) {
        #ifdef LUAT_USE_GTFONT
            luat_spi_device_t *spi = lua_touserdata(L, 1);
            uint8_t size = luaL_optinteger(L, 2, 16);
            uint8_t bpp = luaL_optinteger(L, 3, 4);
            uint16_t thickness = luaL_optinteger(L, 4, size * bpp);
            uint8_t cache_size = luaL_optinteger(L, 5, 0);
            uint8_t sty_zh = luaL_optinteger(L, 6, 1);
            uint8_t sty_en = luaL_optinteger(L, 7, 3);

            if (!(bpp >= 1 && bpp <= 4 && bpp != 3)) {
                return 0;
            }
            if (gt_spi_dev == NULL) {
                gt_spi_dev = lua_touserdata(L, 1);
            }
            font = lv_font_new_gt(sty_zh, sty_en, size, bpp, thickness, cache_size);
        #endif
    } else {
        const char* fontname = luaL_checkstring(L, 1);
        font = lv_font_load(fontname);
    }
    if (font) {
        lua_pushlightuserdata(L, font);
        return 1;
    }
    return 0;
}

/*
释放字体,慎用!!!仅通过font_load加载的字体允许卸载,通过font_get获取的字体不允许卸载
@api lvgl.font_free(font)
@string 字体路径
@return userdata 字体指针
@usage
local font = lvgl.font_load("/font_32.bin")
-- N N N N 操作
-- 确定字体不被使用,不被引用,且内存紧张需要释放
lvgl.font_free(font)
*/
int luat_lv_font_free(lua_State *L) {
    lv_font_t* font = lua_touserdata(L, 1);
    if (font) {
        if (lv_font_is_gt(font)) lv_font_del_gt(font);
        else lv_font_free(font);
    }
    return 0;
}
