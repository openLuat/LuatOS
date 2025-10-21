/*
@module  freetypefont
@summary FreeType字体库
@version 1.0
@date    2025.10.16
@tag LUAT_USE_FREETYPEFONT
@usage
-- 使用FreeType渲染TTF字体
-- 需要准备TTF字体文件

-- 初始化字体
freetypefont.init("/sd/font.ttf")

-- 获取字符串宽度
local width = freetypefont.getStrWidth("Hello世界", 24)
print("字符串宽度:", width)

-- 绘制文本
lcd.drawfreefontUtf8(10, 50, "Hello世界", 24, 0xFFFFFF)
*/

#include "luat_base.h"
#include "luat_freetypefont.h"
#include "ttf_parser.h"
#include "luat_lcd.h"

#define LUAT_LOG_TAG "freetypefont"
#include "luat_log.h"
#include "rotable2.h"

#include "luat_conf_bsp.h"

/**
初始化FreeType字体库
@api freetypefont.init(ttf_path)
@string ttf_path TTF字体文件路径
@return boolean 成功返回true，失败返回false
@usage
freetypefont.init("/sd/font.ttf")
*/
static int l_freetypefont_init(lua_State* L) {
    size_t len = 0;
    const char* ttf_path = luaL_checklstring(L, 1, &len);
    
    if (!ttf_path || len == 0) {
        LLOGE("TTF path is empty");
        lua_pushboolean(L, 0);
        return 1;
    }
    
    int result = luat_freetypefont_init(ttf_path);
    lua_pushboolean(L, result);
    return 1;
}

/**
反初始化FreeType字体库
@api freetypefont.deinit()
@usage
freetypefont.deinit()
*/
static int l_freetypefont_deinit(lua_State* L) {
    (void)L;
    luat_freetypefont_deinit();
    return 0;
}

/**
获取当前初始化状态
@api freetypefont.state()
@return int 状态值：0-未初始化，1-已初始化，2-错误
@usage
local state = freetypefont.state()
if state == 1 then
    print("FreeType已初始化")
end
*/
static int l_freetypefont_state(lua_State* L) {
    luat_freetypefont_state_t state = luat_freetypefont_get_state();
    lua_pushinteger(L, (int)state);
    return 1;
}

/**
获取UTF-8字符串宽度
@api freetypefont.getStrWidth(str, fontSize)
@string str UTF-8字符串
@int fontSize 字体大小（像素）
@return int 字符串宽度（像素）
@usage
local width = freetypefont.getStrWidth("Hello世界", 24)
print("字符串宽度:", width)
*/
static int l_freetypefont_get_str_width(lua_State* L) {
    size_t len = 0;
    const char* str = luaL_checklstring(L, 1, &len);
    int fontSize = luaL_checkinteger(L, 2);
    
    if (fontSize <= 0 || fontSize > 255) {
        LLOGE("Invalid font size: %d", fontSize);
        lua_pushinteger(L, 0);
        return 1;
    }
    
    unsigned int width = luat_freetypefont_get_str_width(str, (unsigned char)fontSize);
    lua_pushinteger(L, width);
    return 1;
}

/**
绘制UTF-8字符串到LCD
@api freetypefont.drawUtf8(x, y, str, fontSize, color)
@int x X坐标
@int y Y坐标（左下角为基准）
@string str UTF-8字符串
@int fontSize 字体大小（像素）
@int color 颜色值（RGB565格式）
@return boolean 成功返回true，失败返回false
@usage
-- 绘制白色文本
freetypefont.drawUtf8(10, 50, "Hello世界", 24, 0xFFFF)
-- 绘制红色文本
freetypefont.drawUtf8(10, 80, "红色文本", 24, 0xF800)
*/
static int l_freetypefont_draw_utf8(lua_State* L) {
    int x = luaL_checkinteger(L, 1);
    int y = luaL_checkinteger(L, 2);
    size_t len = 0;
    const char* str = luaL_checklstring(L, 3, &len);
    int fontSize = luaL_checkinteger(L, 4);
    uint32_t color = luaL_checkinteger(L, 5);
    
    if (fontSize <= 0 || fontSize > 255) {
        LLOGE("Invalid font size: %d", fontSize);
        lua_pushboolean(L, 0);
        return 1;
    }
    
    int result = luat_freetypefont_draw_utf8(x, y, str, (unsigned char)fontSize, color);
    lua_pushboolean(L, result == 0 ? 1 : 0);
    return 1;
}

/**
调试开关
@api freetypefont.debug(enable)
@boolean enable true 开启，false 关闭
@return boolean 总是返回true
*/
static int l_freetypefont_debug(lua_State* L) {
    int enable = lua_toboolean(L, 1);
    (void)ttf_set_debug(enable);
    lua_pushboolean(L, 1);
    return 1;
}

static const rotable_Reg_t reg_freetypefont[] = {
    { "init",        ROREG_FUNC(l_freetypefont_init)},
    { "deinit",      ROREG_FUNC(l_freetypefont_deinit)},
    { "state",       ROREG_FUNC(l_freetypefont_state)},
    { "getStrWidth", ROREG_FUNC(l_freetypefont_get_str_width)},
    { "drawUtf8",    ROREG_FUNC(l_freetypefont_draw_utf8)},
    { "debug",       ROREG_FUNC(l_freetypefont_debug)},
    { NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_freetypefont(lua_State *L) {
    luat_newlib2(L, reg_freetypefont);
    return 1;
}