/*
@module  display
@summary 显示核心库
@version 0.1.0
@date    2026.06.01
@tag     LUAT_USE_DISPLAY
@usage
-- PC 模拟器
display.init("st7789", {w = 240, h = 320, interface = "sdl"})

-- 真机 RGB
display.init("st7789", {w = 480, h = 800, interface = "rgb",
    hbp = 20, hfp = 20, hspw = 5, vbp = 20, vfp = 20, vspw = 5,
    pclk_hz = 25000000, pin_rst = 18, pin_bl = 19})

display.on()
display.flush()
*/

#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_panel_comm.h"        // 包含面板列表和查找函数
#include "luat_display_if_comm.h"           // 包含接口函数列表

#include "luat_mem.h"

#define LUAT_LOG_TAG "display"
#include "luat_log.h"


typedef struct {
    const char *name;
    struct luat_display_funcs *funcs;
} display_if_reg_t;

static const display_if_reg_t if_regs[] = 
{
    {"rgb", &rgb_funcs},
    {"dsi", &dsi_funcs},
    {"spi", &spi_funcs},
    {"sdl", &sdl_funcs},
    {"",    NULL}
};

static struct luat_display_funcs *get_interface_funcs(const char *name) 
{
    for (size_t i = 0; i < sizeof(if_regs) / sizeof(if_regs[0]); i++) 
    {
        if (if_regs[i].name[0] == '\0') break;
        if (strcmp(if_regs[i].name, name) == 0) {
            return if_regs[i].funcs;
        }
    }
    return NULL;
}

typedef struct {
    const char *name;
    const char *interface;
    const luat_display_panel *panel;
} display_panel_reg_t;

/*显示面板列表*/
static const display_panel_reg_t panel_regs[] = 
{
    {"custom", "rgb",  &rgb_panel_custom},
    {"custom", "lvds", &rgb_panel_custom},
    {"custom", "dsi",  &rgb_panel_custom},
    {"custom", "spi",  &rgb_panel_custom},

    {"st7789", "spi",  &spi_panel_st7789},
    {"ili9341", "spi", &spi_panel_ili9341},
    {"st7701s", "spi", &rgb_panel_st7701s},
    {"st7701s", "dsi", &dsi_panel_st7701s},
    {"",        NULL}
};

/*查找显示面板*/
static const luat_display_panel* get_panel(const char *name, const char *interface) 
{
    for (size_t i = 0; i < sizeof(panel_regs) / sizeof(panel_regs[0]); i++) 
    {
        if (panel_regs[i].name[0] == '\0' || panel_regs[i].interface[0] == '\0') {
            break;
        }
        if (strcmp(panel_regs[i].name, name) == 0 && 
            strcmp(panel_regs[i].interface, interface) == 0) 
        {
            return panel_regs[i].panel;
        }
    }
    return NULL;
}

/**
 * @api display.init(panel_name, config)
 * @string panel_name 面板型号，如 "st7789"
 * @table config 配置表
 * @int config.w 屏幕宽度，默认 240
 * @int config.h 屏幕高度，默认 320
 * @int config.bpp 每像素位数，默认 16 (RGB565)
 * @string config.interface 接口类型，"rgb"(默认) 或 "sdl"(PC模拟)
 * @int config.pin_rst 复位引脚，默认 0xFF(无)
 * @int config.pin_bl 背光引脚，默认 0xFF(无)
 * @int config.pin_pwr 电源引脚，默认 0xFF(无)
 * @int config.auto_flush 自动刷新，默认 1
 * @int config.hbp 水平后廊 (RGB接口)
 * @int config.hfp 水平前廊 (RGB接口)
 * @int config.hspw 水平同步脉宽 (RGB接口)
 * @int config.vbp 垂直后廊 (RGB接口)
 * @int config.vfp 垂直前廊 (RGB接口)
 * @int config.vspw 垂直同步脉宽 (RGB接口)
 * @int config.pclk_hz 像素时钟频率 (RGB接口)
 * @int config.hs_polarity HSYNC 极性，默认 1(高有效)
 * @int config.vs_polarity VSYNC 极性，默认 1(高有效)
 * @int config.de_polarity DE 极性，默认 1(高有效)
 * @int config.pclk_polarity PCLK 极性，默认 0(下降沿)
 * @return bool 成功返回 true，失败返回 false 和错误信息
 */
static int l_display_init(lua_State *L) 
{
    /*获取面板名称*/
    const char *panel_name = luaL_checkstring(L, 1);

    /*检查配置表是否为表类型*/
    luaL_checktype(L, 2, LUA_TTABLE);

    /*获取接口类型（必填）*/
    char iface_buf[16] = {0};
    lua_getfield(L, 2, "interface");
    if (!lua_isstring(L, -1)) {
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "config.interface is required (e.g. 'spi', 'rgb', 'dsi', 'dbi')");
        return 2;
    }
    strncpy(iface_buf, lua_tostring(L, -1), sizeof(iface_buf) - 1);
    lua_pop(L, 1);

    luat_display_t *L_disp = luat_heap_zalloc(sizeof(luat_display_t));

    if (L_disp == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "alloc display fail");
        return 2;
    }

    /*查找显示面板*/
    L_disp->panel = get_panel(panel_name, iface_buf);
    
    if (L_disp->panel == NULL) {
        luat_heap_free(L_disp);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "unknown panel or interface");
        return 2;
    }

    /*根据接口类型获取显示函数*/
    struct luat_display_funcs *funcs = get_interface_funcs(iface_buf);
    if (funcs == NULL) {
        luat_heap_free(L_disp);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "unknown interface");
        return 2;
    }

    L_disp->funcs = funcs;



#ifdef LUAT_USE_LCD_SDL2
        
#endif

    lua_getfield(L, 2, "w");
    disp->width = luaL_optinteger(L, -1, 240);
    lua_pop(L, 1);

    lua_getfield(L, 2, "h");
    disp->height = luaL_optinteger(L, -1, 320);
    lua_pop(L, 1);

    lua_getfield(L, 2, "bpp");
    disp->bpp = luaL_optinteger(L, -1, 16);
    if (disp->bpp == 0) disp->bpp = 16;
    lua_pop(L, 1);

    lua_getfield(L, 2, "pin_rst");
    disp->pin_rst = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pin_bl");
    disp->pin_bl = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pin_pwr");
    disp->pin_pwr = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    lua_getfield(L, 2, "auto_flush");
    disp->auto_flush = luaL_optinteger(L, -1, 1);
    lua_pop(L, 1);

    lua_getfield(L, 2, "hbp");
    disp->rgb_timing.hbp = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "hfp");
    disp->rgb_timing.hfp = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "hspw");
    disp->rgb_timing.hspw = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "vbp");
    disp->rgb_timing.vbp = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "vfp");
    disp->rgb_timing.vfp = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "vspw");
    disp->rgb_timing.vspw = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pclk_hz");
    disp->rgb_timing.pclk_hz = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "hs_polarity");
    disp->rgb_timing.hs_polarity = luaL_optinteger(L, -1, 1);
    lua_pop(L, 1);

    lua_getfield(L, 2, "vs_polarity");
    disp->rgb_timing.vs_polarity = luaL_optinteger(L, -1, 1);
    lua_pop(L, 1);

    lua_getfield(L, 2, "de_polarity");
    disp->rgb_timing.de_polarity = luaL_optinteger(L, -1, 1);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pclk_polarity");
    disp->rgb_timing.pclk_polarity = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    int ret = luat_display_init(disp);
    if (ret != 0) {
        luat_heap_free(disp);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "init fail");
        return 2;
    }

    luat_display_register(disp);

    luat_display_on(disp);

    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.on()
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_on(lua_State *L) {
    luat_display_t *disp = luat_display_get_default();
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_on(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.off()
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_off(lua_State *L) {
    luat_display_t *disp = luat_display_get_default();
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_off(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.sleep()
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_sleep(lua_State *L) {
    luat_display_t *disp = luat_display_get_default();
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_sleep(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.wakeup()
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_wakeup(lua_State *L) {
    luat_display_t *disp = luat_display_get_default();
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_wakeup(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.flush()
 * @return bool 成功返回 true，未初始化或无帧缓冲返回 false
 */
static int l_display_flush(lua_State *L) {
    luat_display_t *disp = luat_display_get_default();
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_flush(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.setRotation(rotation)
 * @int rotation 旋转角度，0/90/180/270，可用 display.ROTATE_0/90/180/270
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_set_rotation(lua_State *L) {
    luat_display_t *disp = luat_display_get_default();
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    uint8_t rot = luaL_checkinteger(L, 1);
    luat_display_set_rotation(disp, rot);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.getSize()
 * @return int width 屏幕宽度
 * @return int height 屏幕高度
 */
static int l_display_get_size(lua_State *L) {
    luat_display_t *disp = luat_display_get_default();
    if (disp == NULL) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        return 2;
    }
    lua_pushinteger(L, disp->width);
    lua_pushinteger(L, disp->height);
    return 2;
}

/**
 * @api display.getFbInfo()
 * @return userdata fb_addr FrameBuffer 地址
 * @return int fb_size FrameBuffer 大小 (bytes)
 * @return int fb_count FrameBuffer 数量 (1=单缓冲, 2=双缓冲)
 */
static int l_display_get_fb(lua_State *L) {
    luat_display_t *disp = luat_display_get_default();
    if (disp == NULL || disp->fb_info.addr == NULL) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushlightuserdata(L, disp->fb_info.addr);
    lua_pushinteger(L, disp->fb_info.size);
    lua_pushinteger(L, disp->fb_info.count);
    return 3;
}

#include "rotable2.h"
static const rotable_Reg_t reg_display[] = {
    {"init",        ROREG_FUNC(l_display_init)},
    {"on",          ROREG_FUNC(l_display_on)},
    {"off",         ROREG_FUNC(l_display_off)},
    {"sleep",       ROREG_FUNC(l_display_sleep)},
    {"wakeup",      ROREG_FUNC(l_display_wakeup)},
    {"flush",       ROREG_FUNC(l_display_flush)},
    {"setRotation", ROREG_FUNC(l_display_set_rotation)},
    {"getSize",     ROREG_FUNC(l_display_get_size)},
    {"getFbInfo",   ROREG_FUNC(l_display_get_fb)},
    {"ROTATE_0",    ROREG_INT(LUAT_DISPLAY_ROTATE_0)},
    {"ROTATE_90",   ROREG_INT(LUAT_DISPLAY_ROTATE_90)},
    {"ROTATE_180",  ROREG_INT(LUAT_DISPLAY_ROTATE_180)},
    {"ROTATE_270",  ROREG_INT(LUAT_DISPLAY_ROTATE_270)},
    {NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_display(lua_State *L) {
    luat_newlib2(L, reg_display);
    return 1;
}
