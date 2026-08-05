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

-- 多屏：指定 ID 初始化两个屏（ID 0~4）
display.init("custom", {id = 0, w = 240, h = 320, interface = "sdl"})
display.init("custom", {id = 1, w = 480, h = 320, interface = "sdl"})

display.on()
display.flush()      -- 刷新默认屏 (ID 最小的)
display.flush(1)     -- 刷新 ID 为 1 的屏
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
    {"rgb",  &rgb_funcs},
    {"dsi",  &dsi_funcs},
    {"spi",  &spi_funcs},
    {"lvds", &lvds_funcs},
#ifdef LUAT_USE_LCD_SDL2
    {"sdl",  &sdl_funcs},
#endif
    {"",     NULL}
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
    struct luat_display_panel *panel;
} display_panel_reg_t;

/*显示面板列表*/
static const display_panel_reg_t panel_regs[] = 
{
    {"custom", "rgb",  &rgb_panel_custom},
    {"custom", "lvds", &lvds_panel_custom},
    {"custom", "dsi",  &dsi_panel_custom},

    {"st7789",  "spi",  &spi_panel_st7789},
    {"ili9341", "spi", &spi_panel_ili9341},
    {"st7701s", "rgb", &rgb_panel_st7701s},
    {"st7701s", "dsi", &dsi_panel_st7701s},
    {"",        NULL}
};

/*查找显示面板*/
static struct luat_display_panel* get_panel(const char *name, const char *interface) 
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

/*根据 Lua 可选参数获取 display 实例：
  - 如果第 index 个参数是整数，则当作 display id
  - 否则返回默认 display
*/
static struct luat_display* l_get_display_opt(lua_State *L, int index)
{
    if (lua_gettop(L) >= index && lua_isinteger(L, index)) {
        return luat_display_get_by_id((uint8_t)lua_tointeger(L, index));
    }
    return luat_display_get_default();
}

/*设置显示窗口*/
static void panel_crop_win_setup(struct luat_display_panel *panel,lua_State *L)
{
    /*设置当前屏幕是否需要裁剪*/
    lua_getfield(L, 2, "crop_x");
    if (lua_isnil(L, -1)) {
        panel->screen_win->x = 0;
    } else if (lua_isinteger(L, -1)) {
        panel->screen_win->x = luaL_optinteger(L, -1, 0);
    }
    lua_pop(L, 1);
    
    lua_getfield(L, 2, "crop_y");
    if (lua_isnil(L, -1)) {
        panel->screen_win->y = 0;
    } else if (lua_isinteger(L, -1)) {
        panel->screen_win->y = luaL_optinteger(L, -1, 0);
    }
    lua_pop(L, 1);
    
    lua_getfield(L, 2, "crop_w");
    if (lua_isnil(L, -1)) {
        panel->screen_win->w = panel->timing->hactive;
    } else if (lua_isinteger(L, -1)) {
        panel->screen_win->w = luaL_optinteger(L, -1, panel->timing->hactive);
    }
    lua_pop(L, 1);
    
    lua_getfield(L, 2, "crop_h");
    if (lua_isnil(L, -1)) {
        panel->screen_win->h = panel->timing->vactive;
    } else if (lua_isinteger(L, -1)) {
        panel->screen_win->h = luaL_optinteger(L, -1, panel->timing->vactive);
    }
    lua_pop(L, 1);
}

/*自定义面板初始化*/
static int custom_panel_setup(struct luat_display_panel *panel,lua_State *L) 
{
    int polarity = 0;

    /*检查面板是否为自定义面板*/
    if (strcmp(panel->name, "custom") != 0) {
        return 2;
    }

    /*设置新的时序参数*/
    lua_getfield(L, 2, "w");
    panel->timing->hactive = luaL_optinteger(L, -1, 240);
    lua_pop(L, 1);

    lua_getfield(L, 2, "h");
    panel->timing->vactive = luaL_optinteger(L, -1, 320);
    lua_pop(L, 1);

    lua_getfield(L, 2, "hbp");
    panel->timing->hbp = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "hfp");
    panel->timing->hfp = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "hspw");
    panel->timing->hspw = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "vbp");
    panel->timing->vbp = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "vfp");
    panel->timing->vfp = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "vspw");
    panel->timing->vspw = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pclk_hz");
    panel->timing->pclk_hz = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    /*设置极性*/
    panel->timing->flags = 0;

    lua_getfield(L, 2, "hs_polarity");
    polarity = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);
    panel->timing->flags |= (polarity) ? DISPLAY_FLAGS_HSYNC_HIGH : DISPLAY_FLAGS_HSYNC_LOW;
    
    lua_getfield(L, 2, "vs_polarity");
    polarity = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);
    panel->timing->flags |= (polarity) ? DISPLAY_FLAGS_VSYNC_HIGH : DISPLAY_FLAGS_VSYNC_LOW;
    
    lua_getfield(L, 2, "de_polarity");
    polarity = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);
    panel->timing->flags |= (polarity) ? DISPLAY_FLAGS_DE_HIGH : DISPLAY_FLAGS_DE_LOW;
    
    lua_getfield(L, 2, "pclk_polarity");
    polarity = luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);
    panel->timing->flags |= (polarity) ? DISPLAY_FLAGS_PCLK_HIGH : DISPLAY_FLAGS_PCLK_LOW;
    
    return 0;
}

/*pin引脚配置*/
static int custom_pin_setup(struct panel_pin_device *pin, lua_State *L) 
{
    lua_getfield(L, 2, "pin_rst");
    pin->rst = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pin_bl");
    pin->bl = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pin_pwr");
    pin->pwr = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pin_cs");
    pin->cs = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pin_scl");
    pin->scl = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    lua_getfield(L, 2, "pin_sdi");
    pin->sdi = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);
    
    lua_getfield(L, 2, "pin_dc");
    pin->dc = luaL_optinteger(L, -1, LUAT_GPIO_NONE);
    lua_pop(L, 1);

    return 0;
}


/**
 * @api display.init(panel_name, config)
 * @string panel_name 面板型号，如 "st7789"
 * @table config 配置表
 * @int config.w 屏幕宽度，默认 240
 * @int config.h 屏幕高度，默认 320
 * @int config.crop_x 窗口X坐标，默认 0
 * @int config.crop_y 窗口Y坐标，默认 0
 * @int config.crop_w 窗口宽度，默认 240
 * @int config.crop_h 窗口高度，默认 320
 * @int config.bpp 每像素位数，默认 16 (RGB565)
 * @int config.id 显示组件 ID (0~4)，省略则自动分配
 * @string config.interface 接口类型，"rgb"(默认) 或 "sdl"(PC模拟)
 * @int config.pin_rst 复位引脚，默认 0xFF(无)
 * @int config.pin_bl 背光引脚，默认 0xFF(无)
 * @int config.pin_pwr 电源引脚，默认 0xFF(无)
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
    
    struct luat_display *L_disp = luat_heap_zalloc(sizeof(struct luat_display));

    if (L_disp == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "alloc display fail");
        return 2;
    }

    int screen_win_allocated = 0;

    lua_getfield(L, 2, "bpp");
    L_disp->bpp = luaL_optinteger(L, -1, 16);   //暂时没用到，占位用
    lua_pop(L, 1);

    /*根据接口类型查找显示面板*/
    L_disp->panel = get_panel(panel_name, iface_buf);
    
    if (L_disp->panel == NULL) {
        luat_heap_free(L_disp);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "unknown panel or interface");
        return 2;
    }

    /*先检查，如果没有屏幕有效区域就分配屏幕有效区域*/
    if(L_disp->panel->screen_win == NULL) {
        L_disp->panel->screen_win = luat_heap_zalloc(sizeof(struct luat_display_rect));
        if(L_disp->panel->screen_win == NULL) {
            luat_heap_free(L_disp);
            lua_pushboolean(L, 0);
            lua_pushstring(L, "alloc screen win fail");
            return 2;
        }
        screen_win_allocated = 1;
        /*设置裁剪窗口,默认全屏*/
        panel_crop_win_setup(L_disp->panel, L);
    }

    /*自定义面板*/
    if(strcmp(panel_name, "custom") == 0) {
        /*设置时序参数*/
        int ret = custom_panel_setup(L_disp->panel, L);
        if(ret) {
            lua_pushboolean(L, 0);
            lua_pushstring(L, "panel setup fail");
            goto init_fail;
        }
    }

#ifdef LUAT_USE_LCD_SDL2
    strncpy(iface_buf, "sdl", 3);   //对于PC平台强制使用SDL接口
#endif

    /*根据接口类型获取显示函数*/
    struct luat_display_funcs *funcs = get_interface_funcs(iface_buf);
    if (funcs == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "unknown interface");
        goto init_fail;
    }

    L_disp->display_funcs = funcs;

    /*获取引脚配置参数*/
    struct panel_pin_device *pin = luat_heap_zalloc(sizeof(struct panel_pin_device));
    if (pin == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "alloc pin fail");
        goto init_fail;
    }

    custom_pin_setup(pin, L);

    L_disp->panel->pin = pin;

    /*初始化显示*/
    int ret = luat_display_init(L_disp);

    if (ret != 0) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "init fail");
        goto init_fail;
    }

    /*注册显示器*/
    lua_getfield(L, 2, "id");
    if (lua_isinteger(L, -1)) {
        int req_id = (int)lua_tointeger(L, -1);
        L_disp->id = luat_display_register_with_id(L_disp, (uint8_t)req_id);
        if (L_disp->id < 0) {
            lua_pop(L, 1);
            lua_pushboolean(L, 0);
            lua_pushstring(L, "display id already used or out of range");
            goto init_fail;
        }
    } else {
        L_disp->id = luat_display_register(L_disp);
        if (L_disp->id < 0) {
            lua_pop(L, 1);
            lua_pushboolean(L, 0);
            lua_pushstring(L, "no available display slot");
            goto init_fail;
        }
    }
    lua_pop(L, 1);

    luat_display_on(L_disp);

    lua_pushboolean(L, 1);
    return 1;

init_fail:
    /*screen_win 是本函数分配的，且 panel 是全局模板，
      因此先释放 screen_win，再由 luat_display_destroy 释放其余资源*/
    if (screen_win_allocated && L_disp->panel != NULL && L_disp->panel->screen_win != NULL) {
        luat_heap_free(L_disp->panel->screen_win);
        L_disp->panel->screen_win = NULL;
    }
    luat_display_destroy(L_disp);
    return 2;
}



/**
 * @api display.on([id])
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_on(lua_State *L) {
    struct luat_display *disp = l_get_display_opt(L, 1);
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_on(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.off([id])
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_off(lua_State *L) {
    struct luat_display *disp = l_get_display_opt(L, 1);
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_off(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.sleep([id])
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_sleep(lua_State *L) {
    struct luat_display *disp = l_get_display_opt(L, 1);
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_sleep(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.wakeup([id])
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_wakeup(lua_State *L) {
    struct luat_display *disp = l_get_display_opt(L, 1);
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_wakeup(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.flush([id])
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @return bool 成功返回 true，未初始化或无帧缓冲返回 false
 */
static int l_display_flush(lua_State *L) {
    struct luat_display *disp = l_get_display_opt(L, 1);
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_display_flush(disp);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.setRotation([id], rotation)
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @int rotation 旋转角度，0/90/180/270，可用 display.ROTATE_0/90/180/270
 * @return bool 成功返回 true，未初始化返回 false
 */
static int l_display_set_rotation(lua_State *L) {
    int id_index = 1;
    int rot_index = 2;
    if (lua_gettop(L) == 1) {
        id_index = 0;
        rot_index = 1;
    }

    struct luat_display *disp = (id_index > 0) ? l_get_display_opt(L, id_index) : luat_display_get_default();
    if (disp == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    uint8_t rot = luaL_checkinteger(L, rot_index);
    luat_display_set_rotation(disp, rot);
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * @api display.getSize([id])
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @return int width 屏幕宽度
 * @return int height 屏幕高度
 */
static int l_display_get_size(lua_State *L) 
{
    struct luat_display *disp = l_get_display_opt(L, 1);
    if (disp == NULL) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        return 2;
    }

    lua_pushinteger(L, disp->fb_info->width);
    lua_pushinteger(L, disp->fb_info->height);

    return 2;
}

/**
 * @api display.getFbInfo([id])
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @return userdata fb_addr FrameBuffer 地址
 * @return int fb_size FrameBuffer 大小 (bytes)
 * @return int fb_count FrameBuffer 数量 (1=单缓冲, 2=双缓冲)
 */
static int l_display_get_fb(lua_State *L) 
{
    struct luat_display *disp = l_get_display_opt(L, 1);
    if (disp == NULL || disp->fb_info == NULL) {
        lua_pushnil(L);
        return 1;
    }

    /*优先返回 CPU 可写 draw buffer，SDL/软件渲染场景使用；
      不存在时再退回 fb_start（硬件直接写屏场景）。*/
    void *fb_addr = disp->fb_info->draw_buf.buffer ? disp->fb_info->draw_buf.buffer : disp->fb_info->fb_start;
    uint32_t fb_size = disp->fb_info->draw_buf.buffer ? disp->fb_info->draw_buf.size : disp->fb_info->fb_size;
    uint32_t fb_count = disp->fb_info->draw_buf.buffer ? disp->fb_info->draw_buf.count : disp->fb_info->fb_count;

    if (fb_addr == NULL) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushlightuserdata(L, fb_addr);
    lua_pushinteger(L, fb_size);
    lua_pushinteger(L, fb_count);

    return 3;
}

/**
 * @api display.fill([id], x1, y1, x2, y2, color)
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @int x1 左上角 x
 * @int y1 左上角 y
 * @int x2 右下角 x
 * @int y2 右下角 y
 * @int color 颜色值（与当前 format 对齐，RGB565 时 0xF800 为红色）
 * @return bool 成功返回 true
 */
static int l_display_fill(lua_State *L) {
    int id_index = 0;
    int x1_index, y1_index, x2_index, y2_index, color_index;

    if (lua_gettop(L) == 6) {
        id_index = 1;
        x1_index = 2; y1_index = 3; x2_index = 4; y2_index = 5; color_index = 6;
    } else {
        x1_index = 1; y1_index = 2; x2_index = 3; y2_index = 4; color_index = 5;
    }

    struct luat_display *disp = (id_index > 0) ? l_get_display_opt(L, id_index) : luat_display_get_default();
    if (disp == NULL || disp->fb_info == NULL || !disp->fb_info->inited) {
        lua_pushboolean(L, 0);
        return 1;
    }

    int x1 = luaL_checkinteger(L, x1_index);
    int y1 = luaL_checkinteger(L, y1_index);
    int x2 = luaL_checkinteger(L, x2_index);
    int y2 = luaL_checkinteger(L, y2_index);
    uint32_t color = (uint32_t)luaL_checkinteger(L, color_index);

    struct luat_display_fb_info *info = disp->fb_info;
    uint32_t width = info->width;
    uint32_t height = info->height;
    uint32_t stride = info->stride;
    void *buf = info->draw_buf.buffer ? info->draw_buf.buffer : info->fb_start;

    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x2 >= (int)width) x2 = width - 1;
    if (y2 >= (int)height) y2 = height - 1;
    if (x1 > x2 || y1 > y2 || buf == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }

    int rect_w = x2 - x1 + 1;
    int rect_h = y2 - y1 + 1;
    uint8_t *ptr = (uint8_t *)buf;

    switch (info->format) {
    case LUAT_DISPLAY_FORMAT_RGB565:
    case LUAT_DISPLAY_FORMAT_BGR565: {
        uint16_t c = (uint16_t)(color & 0xFFFF);
        for (int y = y1; y < y1 + rect_h; y++) {
            uint16_t *line = (uint16_t *)(ptr + y * stride + x1 * 2);
            for (int x = 0; x < rect_w; x++) {
                line[x] = c;
            }
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_RGB888: {
        uint8_t r = (color >> 16) & 0xFF;
        uint8_t g = (color >> 8) & 0xFF;
        uint8_t b = color & 0xFF;
        for (int y = y1; y < y1 + rect_h; y++) {
            uint8_t *line = ptr + y * stride + x1 * 3;
            for (int x = 0; x < rect_w; x++) {
                line[x * 3 + 0] = r;
                line[x * 3 + 1] = g;
                line[x * 3 + 2] = b;
            }
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_ARGB8888:
    case LUAT_DISPLAY_FORMAT_ABGR8888:
    case LUAT_DISPLAY_FORMAT_RGBA8888:
    case LUAT_DISPLAY_FORMAT_BGRA8888: {
        for (int y = y1; y < y1 + rect_h; y++) {
            uint32_t *line = (uint32_t *)(ptr + y * stride + x1 * 4);
            for (int x = 0; x < rect_w; x++) {
                line[x] = color;
            }
        }
        break;
    }
    default:
        lua_pushboolean(L, 0);
        return 1;
    }

    LLOGI("fill done fmt=%d bpp=%u buf=%p first=0x%04x",
          info->format, info->bits_per_pixel, buf,
          (info->bits_per_pixel == 16) ? ((uint16_t *)buf)[0] : (uint16_t)(((uint32_t *)buf)[0] & 0xFFFF));

    lua_pushboolean(L, 1);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_display[] = {
    {"init",        ROREG_FUNC(l_display_init)},
    {"on",          ROREG_FUNC(l_display_on)},
    {"off",         ROREG_FUNC(l_display_off)},
    {"sleep",       ROREG_FUNC(l_display_sleep)},
    {"wakeup",      ROREG_FUNC(l_display_wakeup)},
    {"flush",       ROREG_FUNC(l_display_flush)},
    {"fill",        ROREG_FUNC(l_display_fill)},
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
