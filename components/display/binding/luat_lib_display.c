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

/*释放面板的 Lua 自定义初始化命令序列（重复 init 或 init 失败时调用）*/
static void panel_init_cmds_free(struct luat_display_panel *panel)
{
    if (panel == NULL || panel->custom_cmds == NULL) {
        return;
    }
    if (panel->custom_cmd_count > 0 && panel->custom_cmds[0].data != NULL) {
        luat_heap_free((void *)panel->custom_cmds[0].data);
    }
    luat_heap_free(panel->custom_cmds);
    panel->custom_cmds = NULL;
    panel->custom_cmd_count = 0;
}

/*解析 Lua 的 custom_cmds 表并挂到面板上：
   每行 {cmd, data..., delay = ms}，首元素为命令。
   只支持在预置面板名上使用；未传或空表则保持 C 内置序列不变。*/
static int panel_custom_cmds_setup(struct luat_display_panel *panel, lua_State *L)
{
    struct luat_display_seq_cmd *cmds = NULL;
    unsigned char *data_buf = NULL;
    size_t total = 0;
    size_t count = 0;

    lua_getfield(L, 2, "custom_cmds");
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return 0;   // 未传 custom_cmds 表，保持默认序列
    }
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return -1;
    }
    int t = lua_gettop(L);
    luaL_checktype(L, t, LUA_TTABLE);

    /*重复 init 时先释放旧序列，避免泄漏*/
    panel_init_cmds_free(panel);

    size_t nrows = luaL_len(L, t);
    if (nrows == 0) {
        lua_pop(L, 1);
        return 0;
    }

    /*第一遍：统计命令条数与总数据字节数*/
    for (size_t r = 1; r <= nrows; r++) {
        lua_rawgeti(L, t, (lua_Integer)r);
        if (lua_istable(L, -1)) {
            int n = 0;
            lua_rawgeti(L, -1, 1);
            while (!lua_isnil(L, -1)) {
                lua_pop(L, 1);
                n++;
                lua_rawgeti(L, -1, n + 1);
            }
            lua_pop(L, 1); /* nil 结束符 */
            if (n > 0) {
                count++;
                total += (size_t)n;
            }
        }
        lua_pop(L, 1);
    }

    if (count == 0) {
        lua_pop(L, 1);
        return 0;
    }

    cmds = luat_heap_malloc(sizeof(struct luat_display_seq_cmd) * count);
    if (cmds == NULL) {
        LLOGE("alloc custom_cmds struct fail");
        lua_pop(L, 1);
        return -1;
    }
    memset(cmds, 0, sizeof(struct luat_display_seq_cmd) * count);

    if (total > 0) {
        data_buf = luat_heap_malloc(total);
        if (data_buf == NULL) {
            LLOGE("alloc custom_cmds data fail");
            luat_heap_free(cmds);
            lua_pop(L, 1);
            return -1;
        }
    }

    /*第二遍：填充每个命令的数据与延时*/
    {
        struct luat_display_seq_cmd *cmd = cmds;
        unsigned char *p = data_buf;

        for (size_t r = 1; r <= nrows; r++) {
            lua_rawgeti(L, t, (lua_Integer)r);
            if (lua_istable(L, -1)) {
                int n = 0;
                lua_rawgeti(L, -1, 1);
                while (!lua_isnil(L, -1)) {
                    lua_pop(L, 1);
                    n++;
                    lua_rawgeti(L, -1, n + 1);
                }
                lua_pop(L, 1); /* nil 结束符 */

                if (n > 0) {
                    cmd->data = p;
                    cmd->len = (uint32_t)n;
                    cmd->delay_ms = 0;

                    for (int j = 1; j <= n; j++) {
                        lua_rawgeti(L, -1, j);
                        p[j - 1] = (unsigned char)(lua_tointeger(L, -1) & 0xFF);
                        lua_pop(L, 1);
                    }
                    p += n;

                    lua_getfield(L, -1, "delay");
                    if (lua_isinteger(L, -1)) {
                        cmd->delay_ms = (uint32_t)lua_tointeger(L, -1);
                    }
                    lua_pop(L, 1);

                    cmd++;
                }
            }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1); /* init_cmds 表 */

    panel->custom_cmds = cmds;
    panel->custom_cmd_count = (uint32_t)count;
    return 0;
}

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
    {"nv3052c", "rgb", &rgb_panel_nv3052c},
    {"", NULL, NULL}
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
            LLOGI("Find panel: %s interface: %s", name, interface);
            return panel_regs[i].panel;
        }
    }
    LLOGI("Not find panel");
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

/*读取 config 里的整型字段；未提供（nil/非整数）时返回 dflt*/
static long panel_timing_get_field(lua_State *L, const char *key, long dflt)
{
    long v = dflt;
    lua_getfield(L, 2, key);
    if (lua_isinteger(L, -1)) {
        v = lua_tointeger(L, -1);
    }
    lua_pop(L, 1);
    return v;
}

/*覆盖面板 timing：
  - custom 面板：固定默认 w=240/h=320/时序 0，极性默认低有效（保持旧行为）
  - 内置面板：以模板当前 timing 为默认，dflt 用 -1 哨兵表示「未提供」，
    只有 Lua 显式传入的字段才会覆盖；极性用位掩码覆盖对应位，保留模板其它位
*/
static int panel_timing_setup(struct luat_display_panel *panel, lua_State *L, int is_custom)
{
    struct luat_display_timing *tg = panel->timing;
    long v;

    if (tg == NULL) {
        return -1;
    }

    /*常规整型时序字段：custom 固定默认，内置以当前值为默认（未传保持不变）*/
    tg->hactive = (uint32_t)panel_timing_get_field(L, "w",
                      is_custom ? 240 : (long)tg->hactive);
    tg->vactive = (uint32_t)panel_timing_get_field(L, "h",
                      is_custom ? 320 : (long)tg->vactive);
    tg->hbp     = (uint32_t)panel_timing_get_field(L, "hbp",
                      is_custom ? 0 : (long)tg->hbp);
    tg->hfp     = (uint32_t)panel_timing_get_field(L, "hfp",
                      is_custom ? 0 : (long)tg->hfp);
    tg->hspw    = (uint32_t)panel_timing_get_field(L, "hspw",
                      is_custom ? 0 : (long)tg->hspw);
    tg->vbp     = (uint32_t)panel_timing_get_field(L, "vbp",
                      is_custom ? 0 : (long)tg->vbp);
    tg->vfp     = (uint32_t)panel_timing_get_field(L, "vfp",
                      is_custom ? 0 : (long)tg->vfp);
    tg->vspw    = (uint32_t)panel_timing_get_field(L, "vspw",
                      is_custom ? 0 : (long)tg->vspw);
    tg->pclk_hz = (uint32_t)panel_timing_get_field(L, "pclk_hz",
                      is_custom ? 0 : (long)tg->pclk_hz);

    /*极性：custom 统一清零后重建；内置用位掩码覆盖，未提供时保留当前位*/
    if (is_custom) {
        tg->flags = 0;
    }
    v = panel_timing_get_field(L, "hs_polarity", -1);
    if (is_custom || v >= 0) {
        tg->flags = (tg->flags & ~((long)DISPLAY_FLAGS_HSYNC_LOW | (long)DISPLAY_FLAGS_HSYNC_HIGH)) |
                    ((v < 0 ? 0L : v) ? DISPLAY_FLAGS_HSYNC_HIGH : DISPLAY_FLAGS_HSYNC_LOW);
    }
    v = panel_timing_get_field(L, "vs_polarity", -1);
    if (is_custom || v >= 0) {
        tg->flags = (tg->flags & ~((long)DISPLAY_FLAGS_VSYNC_LOW | (long)DISPLAY_FLAGS_VSYNC_HIGH)) |
                    ((v < 0 ? 0L : v) ? DISPLAY_FLAGS_VSYNC_HIGH : DISPLAY_FLAGS_VSYNC_LOW);
    }
    v = panel_timing_get_field(L, "de_polarity", -1);
    if (is_custom || v >= 0) {
        tg->flags = (tg->flags & ~((long)DISPLAY_FLAGS_DE_LOW | (long)DISPLAY_FLAGS_DE_HIGH)) |
                    ((v < 0 ? 0L : v) ? DISPLAY_FLAGS_DE_HIGH : DISPLAY_FLAGS_DE_LOW);
    }
    v = panel_timing_get_field(L, "pclk_polarity", -1);
    if (is_custom || v >= 0) {
        tg->flags = (tg->flags & ~((long)DISPLAY_FLAGS_PCLK_LOW | (long)DISPLAY_FLAGS_PCLK_HIGH)) |
                    ((v < 0 ? 0L : v) ? DISPLAY_FLAGS_PCLK_HIGH : DISPLAY_FLAGS_PCLK_LOW);
    }

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
 * @string panel_name 面板型号：custom(自定义) / st7789 / ili9341 / st7701s / nv3052c
 * @table config 配置表
 * @string config.interface 接口类型（必填）："rgb" / "dsi" / "spi" / "lvds" / "sdl"(PC模拟)
 * @int config.id 显示组件 ID (0~4)，省略则自动分配
 * @int config.w 屏幕宽度：custom 面板默认 240；内置面板不传则保持模板
 * @int config.h 屏幕高度：custom 面板默认 320；内置面板不传则保持模板
 * @int config.bpp 每像素位数，默认 16 (RGB565)，当前为占位参数
 * @int config.crop_x 裁剪窗口X坐标，默认 0
 * @int config.crop_y 裁剪窗口Y坐标，默认 0
 * @int config.crop_w 裁剪窗口宽度，默认屏宽
 * @int config.crop_h 裁剪窗口高度，默认屏高
 * @int config.hbp 水平后廊：custom 默认 0；内置面板仅显式传入才覆盖模板
 * @int config.hfp 水平前廊：custom 默认 0；内置面板仅显式传入才覆盖模板
 * @int config.hspw 水平同步脉宽：custom 默认 0；内置面板仅显式传入才覆盖模板
 * @int config.vbp 垂直后廊：custom 默认 0；内置面板仅显式传入才覆盖模板
 * @int config.vfp 垂直前廊：custom 默认 0；内置面板仅显式传入才覆盖模板
 * @int config.vspw 垂直同步脉宽：custom 默认 0；内置面板仅显式传入才覆盖模板
 * @int config.pclk_hz 像素时钟频率：custom 默认 0；内置面板仅显式传入才覆盖模板
 * @int config.hs_polarity HSYNC 极性，默认 0(低有效)；内置面板仅显式传入才覆盖模板
 * @int config.vs_polarity VSYNC 极性，默认 0(低有效)；内置面板仅显式传入才覆盖模板
 * @int config.de_polarity DE 极性，默认 0(低有效)；内置面板仅显式传入才覆盖模板
 * @int config.pclk_polarity PCLK 极性，默认 0(低有效)；内置面板仅显式传入才覆盖模板
 * @int config.pin_rst 复位引脚，默认 0xFF(无)
 * @int config.pin_bl 背光引脚，默认 0xFF(无)
 * @int config.pin_pwr 电源引脚，默认 0xFF(无)
 * @int config.pin_cs 片选引脚，默认 0xFF(无，SPI 接口)
 * @int config.pin_scl 时钟引脚，默认 0xFF(无，SPI 接口)
 * @int config.pin_sdi 数据引脚，默认 0xFF(无，SPI 接口)
 * @int config.pin_dc 数据/命令引脚，默认 0xFF(无，SPI 接口)
 * @table config.custom_cmds 自定义初始化命令序列，每行 {cmd, data..., delay = ms}；
 *        面板初始化期间发送后可释放节省 RAM
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

    /*覆盖面板时序参数（custom 与内置面板通用）：
        - custom 面板：按 config.w/h/… 重建 timing（未传用固定默认）
        - 内置面板：仅当 config 显式给出对应字段时才覆盖模板 timing*/
    int tret = panel_timing_setup(L_disp->panel, L, strcmp(panel_name, "custom") == 0);
    if (tret) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "panel timing setup fail");
        goto init_fail;
    }

    /*Lua 自定义初始化命令序列（所有面板通用：RGB/DBI/DSI）*/
    int cmds_ret = panel_custom_cmds_setup(L_disp->panel, L);
    if (cmds_ret) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "custom_cmds setup fail");
        goto init_fail;
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

    /*重复 init 时先释放上一份 pin（panel 为全局模板，pin 由本函数分配维护；
       init 失败路径再由 luat_display_destroy 释放新分配的 pin）*/
    if (L_disp->panel->pin != NULL) {
        luat_heap_free(L_disp->panel->pin);
        L_disp->panel->pin = NULL;
    }

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

    /*初始化已完成，custom_cmds 仅面板初始化期间使用，释放以节省 RAM*/
    panel_init_cmds_free(L_disp->panel);

    /*注册显示器*/
    lua_getfield(L, 2, "id");
    if (lua_isinteger(L, -1)) {
        int req_id = (int)lua_tointeger(L, -1);
        int reg_id = luat_display_register_with_id(L_disp, (uint8_t)req_id);
        if (reg_id < 0) {
            lua_pop(L, 1);
            lua_pushboolean(L, 0);
            lua_pushstring(L, "display id already used or out of range");
            goto init_fail;
        }
        L_disp->id = (uint8_t)reg_id;
    } else {
        int reg_id = luat_display_register(L_disp);
        if (reg_id < 0) {
            lua_pop(L, 1);
            lua_pushboolean(L, 0);
            lua_pushstring(L, "no available display slot");
            goto init_fail;
        }
        L_disp->id = (uint8_t)reg_id;
    }
    lua_pop(L, 1);

    luat_display_on(L_disp);        //默认开启显示

    lua_pushboolean(L, 1);
    return 1;

init_fail:
    /*screen_win 是本函数分配的，且 panel 是全局模板，
      因此先释放 screen_win，再由 luat_display_destroy 释放其余资源*/
    panel_init_cmds_free(L_disp->panel);
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

    /*优先返回 LCDC 显存 fb_start（硬件直接写屏场景）；
      SDL/软件渲染无 fb_start 时才回退到 draw_buf。*/
    void *fb_addr = disp->fb_info->fb_start ? disp->fb_info->fb_start : disp->fb_info->draw_buf.buffer;
    uint32_t fb_size = disp->fb_info->fb_start ? disp->fb_info->fb_size : disp->fb_info->draw_buf.size;
    uint32_t fb_count = disp->fb_info->fb_start ? disp->fb_info->fb_count : disp->fb_info->draw_buf.count;

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
    struct luat_display_area area = {
        .x1 = luaL_checkinteger(L, x1_index),
        .y1 = luaL_checkinteger(L, y1_index),
        .x2 = luaL_checkinteger(L, x2_index),
        .y2 = luaL_checkinteger(L, y2_index),
    };
    uint32_t color = (uint32_t)luaL_checkinteger(L, color_index);

    int ret = luat_display_fill(disp, area, color);
    lua_pushboolean(L, ret);
    return 1;
}

/**
 * @api display.sendSeq([id], cmd_table)
 * @int [id] 显示组件 ID，省略则操作默认 display
 * @table cmd_table 命令序列表，首元素为命令，其余为数据，如 {0x36, 0x08}
 * @return bool 成功返回 true
 * @usage
 * display.sendSeq({0x36, 0x08})          -- 默认屏
 * display.sendSeq(1, {0x29, 0x11})       -- 指定 ID=1 的屏
 */
static int l_display_send_seq(lua_State *L)
{
    int id_index = 1;
    int seq_index = 2;
    if (lua_gettop(L) == 1) {
        id_index = 0;
        seq_index = 1;
    }

    struct luat_display *disp = (id_index > 0) ? l_get_display_opt(L, id_index) : luat_display_get_default();
    if (disp == NULL || disp->panel == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }

    luaL_checktype(L, seq_index, LUA_TTABLE);
    size_t n = luaL_len(L, seq_index);
    if (n == 0) {
        lua_pushboolean(L, 0);
        return 1;
    }

    unsigned char *buf = luat_heap_malloc(n);
    if (buf == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }

    for (size_t j = 0; j < n; j++) {
        lua_rawgeti(L, seq_index, (lua_Integer)(j + 1));
        buf[j] = (unsigned char)(lua_tointeger(L, -1) & 0xFF);
        lua_pop(L, 1);
    }

    /*通过面板控制接口发送命令序列（由面板实现按连接器类型下发）*/
    int ret = -1;
    if (disp->panel->panel_funcs != NULL &&
        disp->panel->panel_funcs->panel_ctrl != NULL) {
        struct luat_display_seq_cmd cmd = {
            .data = buf,
            .len = (uint32_t)n,
            .delay_ms = 0,
        };
        ret = disp->panel->panel_funcs->panel_ctrl(disp->panel, LUAT_DISPLAY_SEND_SEQ, &cmd);
    }
    luat_heap_free(buf);

    lua_pushboolean(L, ret == 0);
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
    {"sendSeq",     ROREG_FUNC(l_display_send_seq)},
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
