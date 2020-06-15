/*
@module  disp
@summary 显示屏控制
@version 1.0
@data    2020.03.30
*/
#include "luat_base.h"
#include "luat_malloc.h"

#include "luat_disp.h"
#include "u8g2.h"

static u8g2_t* u8g2;
static int u8g2_lua_ref;

/*
显示屏初始化
@function disp.init(id, type, port)
@int 显示器id, 默认值0, 当前只支持0,单个显示屏
@string 显示屏类型,当前仅支持ssd1306,默认值也是ssd1306
@string 接口类型,当前仅支持i2c1,默认值也是i2c1
@return int 正常初始化1,已经初始化过2,内存不够3
@usage
-- 初始化i2c1的ssd1306
if disp.init() == 1 then
    log.info("显示屏初始化成功")
end
--disp.init(0, "ssd1306", "i2c1")
*/
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
    // TODO: 暂时只支持SSD1306 12864, I2C接口-> i2c1soft, 软件模拟
    luat_disp_conf_t conf = {0};
    conf.ptr = u8g2;
    if (luat_disp_setup(&conf)) {
        return 0; // 初始化失败
    }
    
    u8g2_lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    
    lua_pushinteger(L, 1);
    return 1;
}

/*
关闭显示屏
@function disp.close(id) 
@int 显示器id, 默认值0, 当前只支持0,单个显示屏
@usage
disp.close()
*/
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
/*
@function disp.clear(id) 清屏
@int 显示器id, 默认值0, 当前只支持0,单个显示屏
@usage
disp.clear(0)
*/
static int l_disp_clear(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_ClearBuffer(u8g2);
    return 0;
}
/*
把显示数据更新到屏幕
@function disp.update(id)
@int 显示器id, 默认值0, 当前只支持0,单个显示屏
@usage
disp.update(0)
*/
static int l_disp_update(lua_State *L) {
    if (u8g2 == NULL) return 0;
    u8g2_SendBuffer(u8g2);
    return 0;
}

/*
在显示屏上画一段文字,要调用disp.update才会更新到屏幕
@function disp.drawStr(id, content, x, y) 
@int 显示器id, 默认值0, 当前只支持0,单个显示屏, 这参数暂时不要传.
@string 文件内容
@int 横坐标
@int 竖坐标
@usage
disp.drawStr("wifi is ready", 10, 20)
*/
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

LUAT_WEAK int luat_disp_setup(luat_disp_conf_t *conf) {
    luat_log_warn("luat.disp", "not support yet");
    return -1;
}
