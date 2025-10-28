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

static const rotable_Reg_t reg_hzfont[] = {
    { "init",        ROREG_FUNC(l_hzfont_init)},
    { "debug",       ROREG_FUNC(l_hzfont_debug)},
    { NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_hzfont(lua_State *L) {
    luat_newlib2(L, reg_hzfont);
    return 1;
}