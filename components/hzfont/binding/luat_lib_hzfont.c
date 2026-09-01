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
@api hzfont.init([ttf_path][, cache_size][, load_to_psram])
@string ttf_path TTF字体文件路径，可选；留空则回退到内置字库（若启用）
@int cache_size 可选，位图与码点缓存容量（支持常量 HZFONT_CACHE_128/256/512/1024/2048），默认 HZFONT_CACHE_256
@bool load_to_psram 可选，true 时将字库整包拷贝到 PSRAM 后再解析，减少后续 IO
@return boolean 成功返回true，失败返回false
@usage
-- 从文件加载，使用默认缓存 256
hzfont.init("/sd/font.ttf")
-- 从文件加载，指定缓存 1024
hzfont.init("/sd/font.ttf", hzfont.HZFONT_CACHE_1024)
-- 从luadb文件系统加载
hzfont.init("/luadb/font.ttf")
-- 回退内置字库（启用 固件配置项 LUAT_CONF_USE_HZFONT_BUILTIN_TTF 时生效）
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
    uint32_t cache_size = 0;
    if (!lua_isnoneornil(L, 2)) {
        cache_size = (uint32_t)luaL_checkinteger(L, 2);
    }
    int load_to_psram = 0;
    if (!lua_isnoneornil(L, 3)) {
        load_to_psram = lua_toboolean(L, 3);
    }
    int result = luat_hzfont_init(ttf_path, cache_size, load_to_psram);
    lua_pushboolean(L, result);
    return 1;
}

/* drawUtf8 已移至 lcd 模块的 lcd.drawHzfontUtf8 */

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

/**
获取字符灰度位图
@api hzfont.getBitmap(char[, font_size])
@string char 单个 UTF-8 字符（中文/英文均可）
@int font_size 字号（像素高度），默认 12
@return int 宽度
@return int 高度
@return string 灰度像素数据（width×height 字节，每字节 0-255）
@usage
local w, h, data = hzfont.getBitmap("中", 16)
-- data 是灰度字符串，每字节一个像素，0=透明 255=不透明
*/
static int l_hzfont_getBitmap(lua_State* L) {
    size_t len = 0;
    const char* utf8 = luaL_checklstring(L, 1, &len);
    if (utf8 == NULL || len == 0) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushstring(L, "");
        return 3;
    }

    int font_size = 12;
    if (!lua_isnoneornil(L, 2)) {
        font_size = (int)luaL_checkinteger(L, 2);
    }

    // UTF-8 解码，获取 Unicode 码点
    uint32_t codepoint = 0;
    unsigned char c = (unsigned char)utf8[0];
    if (c < 0x80) {
        codepoint = c;
    } else if ((c & 0xE0) == 0xC0) {
        codepoint = (c & 0x1F) << 6;
        if (len > 1) codepoint |= ((unsigned char)utf8[1] & 0x3F);
    } else if ((c & 0xF0) == 0xE0) {
        codepoint = (c & 0x0F) << 12;
        if (len > 1) codepoint |= ((unsigned char)utf8[1] & 0x3F) << 6;
        if (len > 2) codepoint |= ((unsigned char)utf8[2] & 0x3F);
    } else if ((c & 0xF8) == 0xF0) {
        codepoint = (c & 0x07) << 18;
        if (len > 1) codepoint |= ((unsigned char)utf8[1] & 0x3F) << 12;
        if (len > 2) codepoint |= ((unsigned char)utf8[2] & 0x3F) << 6;
        if (len > 3) codepoint |= ((unsigned char)utf8[3] & 0x3F);
    }

    // 查找 glyph 索引
    uint16_t glyph_index = 0;
    int ret = luat_hzfont_lookup_glyph_index(codepoint, &glyph_index);
    if (ret != 0 || glyph_index == 0) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushstring(L, "");
        return 3;
    }

    // 获取灰度位图
    const TtfBitmap* bitmap = luat_hzfont_get_bitmap(glyph_index, font_size, 0);
    if (bitmap == NULL || bitmap->width == 0 || bitmap->height == 0) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushstring(L, "");
        return 3;
    }

    uint32_t w = bitmap->width;
    uint32_t h = bitmap->height;

    // 返回宽高和灰度数据（每字节一个像素，0-255）
    lua_pushinteger(L, w);
    lua_pushinteger(L, h);
    lua_pushlstring(L, (const char*)bitmap->pixels, w * h);
    return 3;
}

static const rotable_Reg_t reg_hzfont[] = {
    { "init",        ROREG_FUNC(l_hzfont_init)},
    { "debug",       ROREG_FUNC(l_hzfont_debug)},
    { "getBitmap",   ROREG_FUNC(l_hzfont_getBitmap)},
    { "HZFONT_CACHE_128", ROREG_INT(128)},
    { "HZFONT_CACHE_256", ROREG_INT(256)},
    { "HZFONT_CACHE_512", ROREG_INT(512)},
    { "HZFONT_CACHE_1024", ROREG_INT(1024)},
    { "HZFONT_CACHE_2048", ROREG_INT(2048)},
    { NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_hzfont(lua_State *L) {
    luat_newlib2(L, reg_hzfont);
    return 1;
}