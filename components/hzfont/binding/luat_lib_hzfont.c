/*
@module  hzfont
@summary HzFont字体库
@version 1.0
@date    2025.10.16
@tag LUAT_USE_HZFONT
@usage
-- 使用HzFont渲染TTF字体
-- 需要准备TTF字体文件

-- 初始化字体
hzfont.init("/sd/font.ttf")

-- 获取字符串宽度
local width = hzfont.getStrWidth("Hello世界", 24)
print("字符串宽度:", width)

lcd.drawfreefontUtf8(10, 50, "Hello世界", 24, 0xFFFFFF)
*/

#include "luat_base.h"
#include "luat_hzfont.h"
#include "ttf_parser.h"
#include "luat_lcd.h"

#define LUAT_LOG_TAG "hzfont"
#include "luat_log.h"
#include "rotable2.h"

#include "luat_conf_bsp.h"

/**
初始化HzFont字体库
@api hzfont.init([ttf_path])
@string ttf_path TTF字体文件路径，可选；留空则回退到内置字库（若启用）
@return boolean 成功返回true，失败返回false
@usage
-- 从文件加载
hzfont.init("/sd/font.ttf")
-- 回退内置字库（启用 USE_HZFONT_BUILTIN_TTF 时生效）
hzfont.init()
*/
static int l_hzfont_init(lua_State* L) {
    const char* ttf_path = NULL;
    size_t len = 0;
    if (!lua_isnoneornil(L, 1)) {
        ttf_path = luaL_checklstring(L, 1, &len);
        if (len == 0) {
            ttf_path = NULL;
        }
    }
    int result = luat_hzfont_init(ttf_path);
    lua_pushboolean(L, result);
    return 1;
}

/**
获取UTF-8字符串宽度
@api hzfont.getStrWidth(str, fontSize)
@string str UTF-8字符串
@int fontSize 字体大小（像素）
@return int 字符串宽度（像素）
@usage
local width = hzfont.getStrWidth("Hello世界", 24)
print("字符串宽度:", width)
*/
static int l_hzfont_get_str_width(lua_State* L) {
    size_t len = 0;
    const char* str = luaL_checklstring(L, 1, &len);
    int fontSize = luaL_checkinteger(L, 2);
    
    if (fontSize <= 0 || fontSize > 255) {
        LLOGE("Invalid font size: %d", fontSize);
        lua_pushinteger(L, 0);
        return 1;
    }
    
    unsigned int width = luat_hzfont_get_str_width(str, (unsigned char)fontSize);
    lua_pushinteger(L, width);
    return 1;
}

/**
绘制UTF-8字符串到LCD
@api hzfont.drawUtf8(x, y, str, fontSize, [color], [antialias])
@int x X坐标
@int y Y坐标（左下角为基准）
@string str UTF-8字符串
@int fontSize 字体大小（像素）
@int color 颜色值（RGB565，缺省为黑色0x000000）
@int antialias 可选，抗锯齿级别（整数）：
-- -1：自动（≤12号字 无抗锯齿，>12号字 2x2超采样来抗锯齿）
-- 1：无抗锯齿
-- 2：2x2 超采样抗锯齿（首次加载较慢）
-- 4：4x4 超采样抗锯齿（首次加载更慢）
@return boolean 成功返回true，失败返回false
@usage
-- 省略颜色，默认黑色（自动抗锯齿）
hzfont.drawUtf8(10, 50, "Hello世界", 24)
-- 指定颜色与2x2 超采样抗锯齿
hzfont.drawUtf8(10, 80, "红色文本", 24, 0xF800, 2)
-- 省略颜色但指定抗锯齿（颜色位用 nil 占位）
hzfont.drawUtf8(10, 110, "锐利输出", 14, nil, 1)
*/
static int l_hzfont_draw_utf8(lua_State* L) {
    int x = luaL_checkinteger(L, 1);
    int y = luaL_checkinteger(L, 2);
    size_t len = 0;
    const char* str = luaL_checklstring(L, 3, &len);
    int fontSize = luaL_checkinteger(L, 4);
    uint32_t color = 0x000000; /* 默认黑色 */
    if (!lua_isnoneornil(L, 5)) {
        color = (uint32_t)luaL_checkinteger(L, 5);
    }
    int antialias = -1; /* -1 表示自动 */
    if (!lua_isnoneornil(L, 6)) {
        if (lua_isinteger(L, 6) || lua_isnumber(L, 6)) {
            int v = (int)luaL_checkinteger(L, 6);
            if (v == -1) antialias = -1;
            else if (v <= 1) antialias = 1;
            else if (v <= 2) antialias = 2;
            else antialias = 4;
        } else {
            /* 非数字类型一律按自动处理 */
            antialias = -1;
        }
    }

    if (fontSize <= 0 || fontSize > 255) {
        LLOGE("Invalid font size: %d", fontSize);
        lua_pushboolean(L, 0);
        return 1;
    }
    int result = luat_hzfont_draw_utf8(x, y, str, (unsigned char)fontSize, color, antialias);
    lua_pushboolean(L, result == 0 ? 1 : 0);
    return 1;
}

/**
调试开关
@api hzfont.debug(enable)
@boolean enable true 开启，false 关闭
@return boolean 总是返回true
*/
static int l_hzfont_debug(lua_State* L) {
    int enable = lua_toboolean(L, 1);
    (void)ttf_set_debug(enable);
    lua_pushboolean(L, 1);
    return 1;
}

static const rotable_Reg_t reg_hzfont[] = {
    { "init",        ROREG_FUNC(l_hzfont_init)},
    { "getStrWidth", ROREG_FUNC(l_hzfont_get_str_width)},
    { "drawUtf8",    ROREG_FUNC(l_hzfont_draw_utf8)},
    { "debug",       ROREG_FUNC(l_hzfont_debug)},
    { NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_hzfont(lua_State *L) {
    luat_newlib2(L, reg_hzfont);
    return 1;
}