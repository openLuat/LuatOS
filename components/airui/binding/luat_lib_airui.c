/*
@module  airui
@summary AIRUI图像库 (LVGL 9.4) - 重构版本
@version 0.1.0
@date    2025.12.02
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "rotable2.h"
#include "luat_malloc.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"
#include "../inc/luat_airui_symbol.h"
#include "lvgl9/src/themes/default/lv_theme_default.h"
#include "luat_conf_bsp.h"
#if defined(LUAT_USE_AIRUI_LUATOS)
#include "../src/platform/luatos/luat_airui_platform_luatos.h"
#include "luat_gpio.h"
#endif
#if defined(LUAT_USE_AIRUI_SDL2)
#include <SDL2/SDL.h>
#endif
#include <string.h>

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

// 全局上下文（单例模式）
static airui_ctx_t *g_ctx = NULL;

// 函数声明
static int l_airui_init(lua_State *L);
static int l_airui_deinit(lua_State *L);
static int l_airui_refresh(lua_State *L);
static int l_airui_indev_bind_touch(lua_State *L);
static int l_airui_device_bind_keypad(lua_State *L);
static int l_airui_keyboard_enable_system(lua_State *L);
static int l_airui_font_load(lua_State *L);
static int l_airui_version(lua_State *L);

// XML 模块声明
extern int l_airui_xml_init(lua_State *L);
extern int l_airui_xml_deinit(lua_State *L);
extern int l_airui_xml_register_from_file(lua_State *L);
extern int l_airui_xml_register_from_data(lua_State *L);
extern int l_airui_xml_create_screen(lua_State *L);
extern int l_airui_xml_bind_event(lua_State *L);
extern int l_airui_xml_register_image(lua_State *L);
extern int l_airui_xml_register_font(lua_State *L);
extern int l_airui_xml_keyboard_bind(lua_State *L);

// Button 模块声明
extern void airui_register_button_meta(lua_State *L);
extern int airui_button_create(lua_State *L);

// Label 模块声明
extern void airui_register_label_meta(lua_State *L);
extern int airui_label_create(lua_State *L);

// Image 模块声明
extern void airui_register_image_meta(lua_State *L);
extern int airui_image_create(lua_State *L);

// Container 模块声明
extern void airui_register_container_meta(lua_State *L);
extern int airui_container_create(lua_State *L);

// Bar 模块声明
extern void airui_register_bar_meta(lua_State *L);
extern int airui_bar_create(lua_State *L);

// Table 模块声明
extern void airui_register_table_meta(lua_State *L);
extern int airui_table_create(lua_State *L);

// TabView 模块声明
extern void airui_register_tabview_meta(lua_State *L);
extern int airui_tabview_create(lua_State *L);

// Win 模块声明
extern void airui_register_win_meta(lua_State *L);
extern int airui_win_create(lua_State *L);

// Dropdown 模块声明
extern void airui_register_dropdown_meta(lua_State *L);
extern int airui_dropdown_create(lua_State *L);

// Switch 模块声明
extern void airui_register_switch_meta(lua_State *L);
extern int airui_switch_create(lua_State *L);

// Msgbox 模块声明
extern void airui_register_msgbox_meta(lua_State *L);
extern int airui_msgbox_create(lua_State *L);

// Textarea 模块声明
extern void airui_register_textarea_meta(lua_State *L);
extern int airui_textarea_create(lua_State *L);

// Keyboard 模块声明
extern void airui_register_keyboard_meta(lua_State *L);
extern int airui_keyboard_create(lua_State *L);

// Lottie 模块声明
extern void airui_register_lottie_meta(lua_State *L);
extern int airui_lottie_create(lua_State *L);

// 模块注册表
static const rotable_Reg_t reg_airui[] = {
    // 基础设置
    {"init", ROREG_FUNC(l_airui_init)},
    {"deinit", ROREG_FUNC(l_airui_deinit)},
    {"refresh", ROREG_FUNC(l_airui_refresh)},
    {"device_bind_touch", ROREG_FUNC(l_airui_indev_bind_touch)},
    {"device_bind_keypad", ROREG_FUNC(l_airui_device_bind_keypad)},
    {"keyboard_enable_system", ROREG_FUNC(l_airui_keyboard_enable_system)},
    {"font_load", ROREG_FUNC(l_airui_font_load)},
    {"version", ROREG_FUNC(l_airui_version)},
    // 废弃api接口说明，当前保持兼容，todo：后续2.0版本将删除
    {"indev_bind_touch", ROREG_FUNC(l_airui_indev_bind_touch)}, // 废弃，使用 airui.device_bind_touch 替代
    // XML 模块
    {"xml_init", ROREG_FUNC(l_airui_xml_init)},
    {"xml_deinit", ROREG_FUNC(l_airui_xml_deinit)},
    {"xml_register_from_file", ROREG_FUNC(l_airui_xml_register_from_file)},
    {"xml_register_from_data", ROREG_FUNC(l_airui_xml_register_from_data)},
    {"xml_register_image", ROREG_FUNC(l_airui_xml_register_image)},
    {"xml_register_font", ROREG_FUNC(l_airui_xml_register_font)},
    {"xml_create_screen", ROREG_FUNC(l_airui_xml_create_screen)},
    {"xml_bind_event", ROREG_FUNC(l_airui_xml_bind_event)},
    {"xml_keyboard_bind", ROREG_FUNC(l_airui_xml_keyboard_bind)},
    // 组件注册
    {"button", ROREG_FUNC(airui_button_create)},
    {"label", ROREG_FUNC(airui_label_create)},
    {"image", ROREG_FUNC(airui_image_create)},
    {"container", ROREG_FUNC(airui_container_create)},
    {"bar", ROREG_FUNC(airui_bar_create)},
    {"table", ROREG_FUNC(airui_table_create)},
    {"tabview", ROREG_FUNC(airui_tabview_create)},
    {"win", ROREG_FUNC(airui_win_create)},
    {"dropdown", ROREG_FUNC(airui_dropdown_create)},
    {"switch", ROREG_FUNC(airui_switch_create)},
    {"msgbox", ROREG_FUNC(airui_msgbox_create)},
    {"textarea", ROREG_FUNC(airui_textarea_create)},
    {"keyboard", ROREG_FUNC(airui_keyboard_create)},
    {"lottie", ROREG_FUNC(airui_lottie_create)},
    // 颜色格式常量
    {"COLOR_FORMAT_RGB565", ROREG_INT(AIRUI_COLOR_FORMAT_RGB565)},
    {"COLOR_FORMAT_ARGB8888", ROREG_INT(AIRUI_COLOR_FORMAT_ARGB8888)},
    // 文本对齐常量 (和 lvgl 一致)
    {"TEXT_ALIGN_LEFT", ROREG_INT(LV_TEXT_ALIGN_LEFT)},
    {"TEXT_ALIGN_CENTER", ROREG_INT(LV_TEXT_ALIGN_CENTER)},
    {"TEXT_ALIGN_RIGHT", ROREG_INT(LV_TEXT_ALIGN_RIGHT)},
    // TabView 对齐常量 (自己定义的常量)
    {"TABVIEW_PAD_ALL", ROREG_INT(AIRUI_TABVIEW_PAD_ALL)},
    {"TABVIEW_PAD_HOR", ROREG_INT(AIRUI_TABVIEW_PAD_HOR)},
    {"TABVIEW_PAD_VER", ROREG_INT(AIRUI_TABVIEW_PAD_VER)},
    {"TABVIEW_PAD_TOP", ROREG_INT(AIRUI_TABVIEW_PAD_TOP)},
    {"TABVIEW_PAD_BOTTOM", ROREG_INT(AIRUI_TABVIEW_PAD_BOTTOM)},
    {"TABVIEW_PAD_LEFT", ROREG_INT(AIRUI_TABVIEW_PAD_LEFT)},
    {"TABVIEW_PAD_RIGHT", ROREG_INT(AIRUI_TABVIEW_PAD_RIGHT)},
    // 事件常量 (和 lvgl 一致)
    {"EVENT_CLICKED", ROREG_INT(LV_EVENT_CLICKED)},
    {"EVENT_PRESSED", ROREG_INT(LV_EVENT_PRESSED)},
    {"EVENT_RELEASED", ROREG_INT(LV_EVENT_RELEASED)},
    {"EVENT_VALUE_CHANGED", ROREG_INT(LV_EVENT_VALUE_CHANGED)},
    // 图标常量
    AIRUI_SYMBOL_REG,
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_airui(lua_State *L) {
    // 注册各组件元表
    airui_register_button_meta(L);
    airui_register_label_meta(L);
    airui_register_image_meta(L);
    airui_register_container_meta(L);
    airui_register_bar_meta(L);
    airui_register_table_meta(L);
    airui_register_tabview_meta(L);
    airui_register_win_meta(L);
    airui_register_dropdown_meta(L);
    airui_register_switch_meta(L);
    airui_register_msgbox_meta(L);
    airui_register_textarea_meta(L);
    airui_register_keyboard_meta(L);
    airui_register_lottie_meta(L);
    
    // 注册模块函数
    luat_newlib2(L, reg_airui);
    return 1;
}

/**
 * 初始化 AIRUI
 * @api airui.init(width, height, color_format)
 * @int width 屏幕宽度，默认 480
 * @int height 屏幕高度，默认 320
 * @int color_format 颜色格式，可选，默认 RGB565
 *                   可用值：airui.COLOR_FORMAT_RGB565（嵌入式，节省内存）
 *                          airui.COLOR_FORMAT_ARGB8888（默认，高质量）
 * @return bool 成功返回 true，失败返回 false
 */
static int l_airui_init(lua_State *L) {
    if (g_ctx != NULL) {
        LLOGE("airui already initialized");
        lua_pushboolean(L, 0);
        return 1;
    }
    
    int w = luaL_optinteger(L, 1, 480);
    int h = luaL_optinteger(L, 2, 320);
    
    // 获取颜色格式参数，默认为RGB565
    lv_color_format_t color_format = (lv_color_format_t)luaL_optinteger(L, 3, AIRUI_COLOR_FORMAT_RGB565);
    
    // 验证颜色格式是否有效，需要和lvgl的颜色格式对应（只支持 RGB565 和 ARGB8888）
    if (color_format != AIRUI_COLOR_FORMAT_RGB565 && 
        color_format != AIRUI_COLOR_FORMAT_ARGB8888) {
        LLOGE("airui.init: invalid color format %d, using RGB565", color_format);
        color_format = AIRUI_COLOR_FORMAT_RGB565;
    }
    
    // 分配上下文
    g_ctx = luat_heap_malloc(sizeof(airui_ctx_t));
    if (g_ctx == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    // 创建上下文（自动选择平台驱动）
    int ret = airui_ctx_create(g_ctx, NULL);
    if (ret != 0) {
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    
    // 存储 Lua 主线程状态，避免协程结束导致悬空指针
    lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD);
    g_ctx->L = lua_tothread(L, -1);
    lua_pop(L, 1);
    
    // 将上下文存储到注册表
    lua_pushlightuserdata(L, g_ctx);
    lua_setfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    
    // 初始化 AIRUI（使用指定的颜色格式）
    ret = airui_init(g_ctx, w, h, color_format);
    if (ret != 0) {
        airui_ctx_create(g_ctx, NULL);  // 清理
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * 反初始化 AIRUI
 * @api airui.deinit()
 * @return nil
 */
static int l_airui_deinit(lua_State *L) {
    (void)L;
    
    if (g_ctx != NULL) {
        airui_deinit(g_ctx);
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        
        // 清除注册表中的上下文
        lua_pushnil(L);
        lua_setfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    }
    
    return 0;
}

/**
 * 刷新 LVGL 显示（执行定时器处理）
 * @api airui.refresh()
 * @return nil
 */
static int l_airui_refresh(lua_State *L) {
    (void)L;
    
    if (g_ctx == NULL) {
        luaL_error(L, "airui not initialized, call airui.init() first");
        return 0;
    }
    
    // 执行 LVGL 定时器处理（处理重绘、动画、事件等）
    // lv_timer_handler();
    int version = AIRUI_VERSION;
    LLOGW("airui refresh 接口在版本 %s 已废弃，改为自动刷新", version);

    return 0;
}

/**
 * 绑定触摸输入配置到 LuatOS 平台
 * @api airui.device_bind_touch(tp_cfg)
 * @userdata tp_cfg luat_tp_config_t*（lightuserdata）
 * @return bool 绑定是否成功
 */
static int l_airui_indev_bind_touch(lua_State *L) {
#if defined(LUAT_USE_AIRUI_LUATOS)
    luat_tp_config_t *tp_cfg = (luat_tp_config_t *)lua_touserdata(L, 1);
    if (tp_cfg == NULL) {
        LLOGE("device_bind_touch tp_cfg is NULL");
        lua_pushboolean(L, 0);
        return 1;
    }

    /* 保存到平台绑定，供初始化时同步 */
    airui_platform_luatos_bind_tp(tp_cfg);

    /* 如果上下文已存在且平台数据已分配，运行时也同步一份 */
    if (g_ctx && g_ctx->platform_data) {
        luatos_platform_data_t *data = (luatos_platform_data_t *)g_ctx->platform_data;
        data->tp_config = tp_cfg;
    }

    LLOGD("device_bind_touch bind %p", tp_cfg);
    lua_pushboolean(L, 1);
    return 1;
// SDL2 路径：SDL 输入已经通过事件轮询获取，无需绑定 TP
#elif defined(LUAT_USE_AIRUI_SDL2)
    (void)L;
    LLOGI("device_bind_touch ignored on SDL2 (mouse/SDL events used)");
    lua_pushboolean(L, 1);
    return 1;
#else
    (void)L;
    LLOGE("device_bind_touch unsupported on this platform");
    lua_pushboolean(L, 0);
    return 1;
#endif
}

#if defined(LUAT_USE_AIRUI_LUATOS)
static int airui_read_keypad_pin_field(lua_State *L, int idx, const char *key)
{
    int pin = -1;

    lua_getfield(L, idx, key);
    if (lua_isinteger(L, -1)) {
        pin = (int)lua_tointeger(L, -1);
    }
    lua_pop(L, 1);

    if (pin >= 0) {
        return pin;
    }

    lua_getfield(L, idx, "pins");
    if (lua_istable(L, -1)) {
        lua_getfield(L, -1, key);
        if (lua_isinteger(L, -1)) {
            pin = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    return pin;
}

static uint8_t airui_read_keypad_pull_mode(lua_State *L, int idx)
{
    uint8_t pull = LUAT_GPIO_PULLUP;
    lua_getfield(L, idx, "pull");
    if (lua_isinteger(L, -1)) {
        pull = (uint8_t)lua_tointeger(L, -1);
    } else if (lua_isstring(L, -1)) {
        const char *mode = lua_tostring(L, -1);
        if (mode != NULL) {
            if (strcmp(mode, "default") == 0) {
                pull = LUAT_GPIO_DEFAULT;
            } else if (strcmp(mode, "pulldown") == 0) {
                pull = LUAT_GPIO_PULLDOWN;
            } else {
                pull = LUAT_GPIO_PULLUP;
            }
        }
    }
    lua_pop(L, 1);
    return pull;
}
#endif

#if defined(LUAT_USE_AIRUI_SDL2)
/**
 * 将字符串转换为SDL_Keycode（辅助函数）
 */
static int sdl_string_to_keycode(const char *key_name)
{
    if (key_name == NULL) {
        return 0;
    }
    
    // 方向键
    if (strcmp(key_name, "up") == 0) return SDLK_UP;
    if (strcmp(key_name, "down") == 0) return SDLK_DOWN;
    if (strcmp(key_name, "left") == 0) return SDLK_LEFT;
    if (strcmp(key_name, "right") == 0) return SDLK_RIGHT;
    
    // 字母键
    if (strlen(key_name) == 1 && key_name[0] >= 'a' && key_name[0] <= 'z') {
        return SDLK_a + (key_name[0] - 'a');
    }
    if (strlen(key_name) == 1 && key_name[0] >= 'A' && key_name[0] <= 'Z') {
        return SDLK_a + (key_name[0] - 'A');
    }
    
    // 数字键
    if (strlen(key_name) == 1 && key_name[0] >= '0' && key_name[0] <= '9') {
        return SDLK_0 + (key_name[0] - '0');
    }
    
    // 特殊键
    if (strcmp(key_name, "return") == 0 || strcmp(key_name, "enter") == 0) return SDLK_RETURN;
    if (strcmp(key_name, "space") == 0) return SDLK_SPACE;
    if (strcmp(key_name, "escape") == 0 || strcmp(key_name, "esc") == 0) return SDLK_ESCAPE;
    if (strcmp(key_name, "backspace") == 0) return SDLK_BACKSPACE;
    if (strcmp(key_name, "tab") == 0) return SDLK_TAB;
    
    return 0;
}

/**
 * 从Lua表读取按键配置（辅助函数）
 */
static int sdl_read_keypad_field(lua_State *L, int idx, const char *key, int default_val)
{
    int val = default_val;
    lua_getfield(L, idx, key);
    if (!lua_isnil(L, -1)) {
        if (lua_isstring(L, -1)) {
            const char *key_name = lua_tostring(L, -1);
            val = sdl_string_to_keycode(key_name);
        } else if (lua_isinteger(L, -1)) {
            val = (int)lua_tointeger(L, -1);
        }
    }
    lua_pop(L, 1);
    return val;
}
#endif

/**
 * 绑定按键输入配置
 * @api airui.device_bind_keypad(cfg)
 * @table cfg 配置表
 * @int|table cfg.up 或 cfg.pins.up
 * @int|table cfg.down 或 cfg.pins.down
 * @int|table cfg.left 或 cfg.pins.left
 * @int|table cfg.right 或 cfg.pins.right
 * @int|table cfg.ok 或 cfg.pins.ok
 * @int|table cfg.back 或 cfg.pins.back
 * @bool cfg.active_low 可选，默认 true
 * @string|int cfg.pull 可选，默认 "pullup"
 * @return bool 绑定是否成功
 */
static int l_airui_device_bind_keypad(lua_State *L) {
#if defined(LUAT_USE_AIRUI_LUATOS)
    luaL_checktype(L, 1, LUA_TTABLE);

    airui_luatos_keypad_cfg_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.up = airui_read_keypad_pin_field(L, 1, "up");
    cfg.down = airui_read_keypad_pin_field(L, 1, "down");
    cfg.left = airui_read_keypad_pin_field(L, 1, "left");
    cfg.right = airui_read_keypad_pin_field(L, 1, "right");
    cfg.ok = airui_read_keypad_pin_field(L, 1, "ok");
    cfg.back = airui_read_keypad_pin_field(L, 1, "back");
    cfg.active_low = airui_marshal_bool(L, 1, "active_low", true) ? 1 : 0;
    cfg.pull_mode = airui_read_keypad_pull_mode(L, 1);
    cfg.enabled = 1;

    airui_platform_luatos_bind_keypad(&cfg);

    if (g_ctx && g_ctx->platform_data) {
        luatos_platform_data_t *data = (luatos_platform_data_t *)g_ctx->platform_data;
        data->keypad_cfg = cfg;
    }

    LLOGD("device_bind_keypad bind luatos up=%d down=%d left=%d right=%d ok=%d back=%d active_low=%d pull=%d",
          cfg.up, cfg.down, cfg.left, cfg.right, cfg.ok, cfg.back, cfg.active_low, cfg.pull_mode);
    lua_pushboolean(L, 1);
    return 1;
#elif defined(LUAT_USE_AIRUI_SDL2)
    // SDL2按键配置结构
    typedef struct {
        int up;
        int down;
        int left;
        int right;
        int ok;
        int back;
    } sdl_keypad_cfg_t;
    
    extern void airui_platform_sdl2_bind_keypad(bool enable);
    extern void airui_platform_sdl2_bind_keypad_cfg(const void *cfg);
    
    sdl_keypad_cfg_t cfg = {0};
    bool has_cfg = false;
    
    // 读取配置（如果提供）
    if (lua_istable(L, 1)) {
        // 读取各个按键配置，如果存在则使用，否则使用默认值
        int up_val = sdl_read_keypad_field(L, 1, "up", 0);
        int down_val = sdl_read_keypad_field(L, 1, "down", 0);
        int left_val = sdl_read_keypad_field(L, 1, "left", 0);
        int right_val = sdl_read_keypad_field(L, 1, "right", 0);
        int ok_val = sdl_read_keypad_field(L, 1, "ok", 0);
        int back_val = sdl_read_keypad_field(L, 1, "back", 0);
        
        // 如果至少有一个配置项被设置，则应用配置
        if (up_val != 0 || down_val != 0 || left_val != 0 || right_val != 0 || ok_val != 0 || back_val != 0) {
            cfg.up = (up_val != 0) ? up_val : SDLK_UP;
            cfg.down = (down_val != 0) ? down_val : SDLK_DOWN;
            cfg.left = (left_val != 0) ? left_val : SDLK_LEFT;
            cfg.right = (right_val != 0) ? right_val : SDLK_RIGHT;
            cfg.ok = (ok_val != 0) ? ok_val : SDLK_RETURN;
            cfg.back = (back_val != 0) ? back_val : SDLK_ESCAPE;
            has_cfg = true;
        }
    }
    
    // 应用配置
    if (has_cfg) {
        airui_platform_sdl2_bind_keypad_cfg(&cfg);
        LLOGD("device_bind_keypad SDL2 config: up=%d down=%d left=%d right=%d ok=%d back=%d",
              cfg.up, cfg.down, cfg.left, cfg.right, cfg.ok, cfg.back);
    } else {
        airui_platform_sdl2_bind_keypad(true);
        LLOGD("device_bind_keypad enabled on SDL2 (default: WASD/Arrow/Enter/Space/Esc)");
    }
    lua_pushboolean(L, 1);
    return 1;
#else
    (void)L;
    LLOGE("device_bind_keypad unsupported on this platform");
    lua_pushboolean(L, 0);
    return 1;
#endif
}

static int l_airui_keyboard_enable_system(lua_State *L) {
    bool enable = lua_toboolean(L, 1);
    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "airui not initialized");
        return 0;
    }

    int ret = airui_system_keyboard_enable(ctx, enable);
    lua_pushboolean(L, ret == AIRUI_OK);
    return 1;
}

/**
 * 推送组件 userdata（通用辅助函数）
 */
void airui_push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt) {
    airui_component_ud_t *ud = (airui_component_ud_t *)lua_newuserdata(L, sizeof(airui_component_ud_t));
    ud->obj = obj;
    luaL_getmetatable(L, mt);
    lua_setmetatable(L, -2);
}

/**
 * 检查组件 userdata（通用辅助函数）
 */
lv_obj_t *airui_check_component(lua_State *L, int index, const char *mt) {
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, index, mt);
    if (ud == NULL || ud->obj == NULL) {
        luaL_error(L, "invalid %s object", mt);
    }
    return ud->obj;
}

/**
 * 加载字体
 * @api airui.font_load(config)
 * @table config 配置表
 * @string config.type 字体类型，"hzfont" 或 "bin"
 * @string config.path 字体路径，对于 "hzfont"，传 nil 则使用内置字库
 * @int config.size 可选，TTF 字体大小，默认 16
 * @int config.cache_size 可选，TTF 缓存数量，默认 256
 * @int config.antialias 可选，TTF 抗锯齿等级，默认 -1（自动）
 * @bool config.load_to_psram 可选，是否将字体及缓存加载到 PSRAM（默认 false）
 * @return userdata 字体指针
 */
static int l_airui_font_load(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    const char *type = airui_marshal_string(L, 1, "type", NULL);
    if (type == NULL) {
        luaL_error(L, "font_load: config.type is required");
        return 0;
    }
    lv_font_t *font = NULL;

    if (strcmp(type, "hzfont") == 0) {
        const char *path = airui_marshal_string(L, 1, "path", NULL);
        uint16_t size = airui_marshal_integer(L, 1, "size", 16);
        uint32_t cache_size = airui_marshal_integer(L, 1, "cache_size", 256);
        int antialias = airui_marshal_integer(L, 1, "antialias", -1);
        bool load_to_psram = airui_marshal_bool(L, 1, "load_to_psram", false);
        font = airui_font_hzfont_create(path, size, cache_size, antialias, load_to_psram);
        if (font == NULL) {
            LLOGE("font_load: failed to create hzfont");
            return 0;
        }
    } else if (strcmp(type, "bin") == 0) {
        const char *path = luaL_checkstring(L, 2);
        font = lv_binfont_create(path);
        if (font == NULL) {
            LLOGE("font_load: failed to create bin font");
            return 0;
        }
    } else {
        LLOGE("font_load: unsupported type %s", type);
        return 0;
    }

    if (font) {
        // 设置为全局默认字体
        lv_obj_set_style_text_font(lv_screen_active(), font, 0);
        /* 更新主题字体 */
        if (lv_theme_default_is_inited()) {lv_theme_default_deinit();}
        lv_theme_default_init(g_ctx->display,lv_palette_main(LV_PALETTE_BLUE),lv_palette_darken(LV_PALETTE_BLUE, 2),false,font);
        
        lua_pushlightuserdata(L, font);
        return 1;
    }else{
        LLOGE("font_load: failed to create font");
        return 0;
    }
    
    return 0;
}

/**
 * 获取 AIRUI 库的版本号
 * @api airui.version()
 * @return string 当前版本（由 AIRUI_VERSION 提供）
 */
static int l_airui_version(lua_State *L) {
    lua_pushstring(L, AIRUI_VERSION);
    return 1;
}
