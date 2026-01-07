/*
@module  easylvgl
@summary EasyLVGL图像库 (LVGL 9.4) - 重构版本
@version 0.1.0
@date    2025.12.02
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "rotable2.h"
#include "luat_malloc.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include "../inc/luat_easylvgl_symbol.h"
#include "lvgl9/src/themes/default/lv_theme_default.h"
#include "luat_conf_bsp.h"
#if defined(LUAT_USE_EASYLVGL_LUATOS)
#include "../src/platform/luatos/luat_easylvgl_platform_luatos.h"
#endif
#include <string.h>

#define LUAT_LOG_TAG "easylvgl"
#include "luat_log.h"

// 全局上下文（单例模式）
static easylvgl_ctx_t *g_ctx = NULL;

// 函数声明
static int l_easylvgl_init(lua_State *L);
static int l_easylvgl_deinit(lua_State *L);
static int l_easylvgl_refresh(lua_State *L);
static int l_easylvgl_indev_bind_touch(lua_State *L);
static int l_easylvgl_keyboard_enable_system(lua_State *L);
static int l_easylvgl_font_load(lua_State *L);

// XML 模块声明
extern int l_easylvgl_xml_init(lua_State *L);
extern int l_easylvgl_xml_deinit(lua_State *L);
extern int l_easylvgl_xml_register_from_file(lua_State *L);
extern int l_easylvgl_xml_register_from_data(lua_State *L);
extern int l_easylvgl_xml_create_screen(lua_State *L);
extern int l_easylvgl_xml_bind_event(lua_State *L);
extern int l_easylvgl_xml_register_image(lua_State *L);
extern int l_easylvgl_xml_register_font(lua_State *L);
extern int l_easylvgl_xml_keyboard_bind(lua_State *L);

// Button 模块声明
extern void easylvgl_register_button_meta(lua_State *L);
extern int easylvgl_button_create(lua_State *L);

// Label 模块声明
extern void easylvgl_register_label_meta(lua_State *L);
extern int easylvgl_label_create(lua_State *L);

// Image 模块声明
extern void easylvgl_register_image_meta(lua_State *L);
extern int easylvgl_image_create(lua_State *L);

// Container 模块声明
extern void easylvgl_register_container_meta(lua_State *L);
extern int easylvgl_container_create(lua_State *L);

// Table 模块声明
extern void easylvgl_register_table_meta(lua_State *L);
extern int easylvgl_table_create(lua_State *L);

// TabView 模块声明
extern void easylvgl_register_tabview_meta(lua_State *L);
extern int easylvgl_tabview_create(lua_State *L);

// Win 模块声明
extern void easylvgl_register_win_meta(lua_State *L);
extern int easylvgl_win_create(lua_State *L);

// Dropdown 模块声明
extern void easylvgl_register_dropdown_meta(lua_State *L);
extern int easylvgl_dropdown_create(lua_State *L);

// Switch 模块声明
extern void easylvgl_register_switch_meta(lua_State *L);
extern int easylvgl_switch_create(lua_State *L);

// Msgbox 模块声明
extern void easylvgl_register_msgbox_meta(lua_State *L);
extern int easylvgl_msgbox_create(lua_State *L);

// Textarea 模块声明
extern void easylvgl_register_textarea_meta(lua_State *L);
extern int easylvgl_textarea_create(lua_State *L);

// Keyboard 模块声明
extern void easylvgl_register_keyboard_meta(lua_State *L);
extern int easylvgl_keyboard_create(lua_State *L);

// 模块注册表
static const rotable_Reg_t reg_easylvgl[] = {
    // 基础设置
    {"init", ROREG_FUNC(l_easylvgl_init)},
    {"deinit", ROREG_FUNC(l_easylvgl_deinit)},
    {"refresh", ROREG_FUNC(l_easylvgl_refresh)},
    {"indev_bind_touch", ROREG_FUNC(l_easylvgl_indev_bind_touch)},
    {"keyboard_enable_system", ROREG_FUNC(l_easylvgl_keyboard_enable_system)},
    {"font_load", ROREG_FUNC(l_easylvgl_font_load)},
    // XML 模块
    {"xml_init", ROREG_FUNC(l_easylvgl_xml_init)},
    {"xml_deinit", ROREG_FUNC(l_easylvgl_xml_deinit)},
    {"xml_register_from_file", ROREG_FUNC(l_easylvgl_xml_register_from_file)},
    {"xml_register_from_data", ROREG_FUNC(l_easylvgl_xml_register_from_data)},
    {"xml_register_image", ROREG_FUNC(l_easylvgl_xml_register_image)},
    {"xml_register_font", ROREG_FUNC(l_easylvgl_xml_register_font)},
    {"xml_create_screen", ROREG_FUNC(l_easylvgl_xml_create_screen)},
    {"xml_bind_event", ROREG_FUNC(l_easylvgl_xml_bind_event)},
    {"xml_keyboard_bind", ROREG_FUNC(l_easylvgl_xml_keyboard_bind)},
    // 组件注册
    {"button", ROREG_FUNC(easylvgl_button_create)},
    {"label", ROREG_FUNC(easylvgl_label_create)},
    {"image", ROREG_FUNC(easylvgl_image_create)},
    {"container", ROREG_FUNC(easylvgl_container_create)},
    {"table", ROREG_FUNC(easylvgl_table_create)},
    {"tabview", ROREG_FUNC(easylvgl_tabview_create)},
    {"win", ROREG_FUNC(easylvgl_win_create)},
    {"dropdown", ROREG_FUNC(easylvgl_dropdown_create)},
    {"switch", ROREG_FUNC(easylvgl_switch_create)},
    {"msgbox", ROREG_FUNC(easylvgl_msgbox_create)},
    {"textarea", ROREG_FUNC(easylvgl_textarea_create)},
    {"keyboard", ROREG_FUNC(easylvgl_keyboard_create)},
    // 颜色格式常量
    {"COLOR_FORMAT_RGB565", ROREG_INT(EASYLVGL_COLOR_FORMAT_RGB565)},
    {"COLOR_FORMAT_ARGB8888", ROREG_INT(EASYLVGL_COLOR_FORMAT_ARGB8888)},
    // 文本对齐常量 (和 lvgl 一致)
    {"EASYLVGL_TEXT_ALIGN_LEFT", ROREG_INT(LV_TEXT_ALIGN_LEFT)},
    {"EASYLVGL_TEXT_ALIGN_CENTER", ROREG_INT(LV_TEXT_ALIGN_CENTER)},
    {"EASYLVGL_TEXT_ALIGN_RIGHT", ROREG_INT(LV_TEXT_ALIGN_RIGHT)},
    // TabView 对齐常量 (自己定义的常量)
    {"EASYLVGL_TABVIEW_PAD_ALL", ROREG_INT(EASYLVGL_TABVIEW_PAD_ALL)},
    {"EASYLVGL_TABVIEW_PAD_HOR", ROREG_INT(EASYLVGL_TABVIEW_PAD_HOR)},
    {"EASYLVGL_TABVIEW_PAD_VER", ROREG_INT(EASYLVGL_TABVIEW_PAD_VER)},
    {"EASYLVGL_TABVIEW_PAD_TOP", ROREG_INT(EASYLVGL_TABVIEW_PAD_TOP)},
    {"EASYLVGL_TABVIEW_PAD_BOTTOM", ROREG_INT(EASYLVGL_TABVIEW_PAD_BOTTOM)},
    {"EASYLVGL_TABVIEW_PAD_LEFT", ROREG_INT(EASYLVGL_TABVIEW_PAD_LEFT)},
    {"EASYLVGL_TABVIEW_PAD_RIGHT", ROREG_INT(EASYLVGL_TABVIEW_PAD_RIGHT)},
    // 事件常量 (和 lvgl 一致)
    {"EASYLVGL_EVENT_CLICKED", ROREG_INT(LV_EVENT_CLICKED)},
    {"EASYLVGL_EVENT_PRESSED", ROREG_INT(LV_EVENT_PRESSED)},
    {"EASYLVGL_EVENT_RELEASED", ROREG_INT(LV_EVENT_RELEASED)},
    {"EASYLVGL_EVENT_VALUE_CHANGED", ROREG_INT(LV_EVENT_VALUE_CHANGED)},
    // 图标常量
    EASYLVGL_SYMBOL_REG,
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_easylvgl(lua_State *L) {
    // 注册各组件元表
    easylvgl_register_button_meta(L);
    easylvgl_register_label_meta(L);
    easylvgl_register_image_meta(L);
    easylvgl_register_container_meta(L);
    easylvgl_register_table_meta(L);
    easylvgl_register_tabview_meta(L);
    easylvgl_register_win_meta(L);
    easylvgl_register_dropdown_meta(L);
    easylvgl_register_switch_meta(L);
    easylvgl_register_msgbox_meta(L);
    easylvgl_register_textarea_meta(L);
    easylvgl_register_keyboard_meta(L);
    
    // 注册模块函数
    luat_newlib2(L, reg_easylvgl);
    return 1;
}

/**
 * 初始化 EasyLVGL
 * @api easylvgl.init(width, height, color_format)
 * @int width 屏幕宽度，默认 480
 * @int height 屏幕高度，默认 320
 * @int color_format 颜色格式，可选，默认 RGB565
 *                   可用值：easylvgl.COLOR_FORMAT_RGB565（嵌入式，节省内存）
 *                          easylvgl.COLOR_FORMAT_ARGB8888（默认，高质量）
 * @return bool 成功返回 true，失败返回 false
 */
static int l_easylvgl_init(lua_State *L) {
    if (g_ctx != NULL) {
        LLOGE("easylvgl already initialized");
        lua_pushboolean(L, 0);
        return 1;
    }
    
    int w = luaL_optinteger(L, 1, 480);
    int h = luaL_optinteger(L, 2, 320);
    
    // 获取颜色格式参数，默认为RGB565
    lv_color_format_t color_format = (lv_color_format_t)luaL_optinteger(L, 3, EASYLVGL_COLOR_FORMAT_RGB565);
    
    // 验证颜色格式是否有效，需要和lvgl的颜色格式对应（只支持 RGB565 和 ARGB8888）
    if (color_format != EASYLVGL_COLOR_FORMAT_RGB565 && 
        color_format != EASYLVGL_COLOR_FORMAT_ARGB8888) {
        LLOGE("easylvgl.init: invalid color format %d, using RGB565", color_format);
        color_format = EASYLVGL_COLOR_FORMAT_RGB565;
    }
    
    // 分配上下文
    g_ctx = luat_heap_malloc(sizeof(easylvgl_ctx_t));
    if (g_ctx == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    // 创建上下文（自动选择平台驱动）
    int ret = easylvgl_ctx_create(g_ctx, NULL);
    if (ret != 0) {
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    
    // 存储 Lua 状态
    g_ctx->L = L;
    
    // 将上下文存储到注册表
    lua_pushlightuserdata(L, g_ctx);
    lua_setfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    
    // 初始化 EasyLVGL（使用指定的颜色格式）
    ret = easylvgl_init(g_ctx, w, h, color_format);
    if (ret != 0) {
        easylvgl_ctx_create(g_ctx, NULL);  // 清理
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * 反初始化 EasyLVGL
 * @api easylvgl.deinit()
 * @return nil
 */
static int l_easylvgl_deinit(lua_State *L) {
    (void)L;
    
    if (g_ctx != NULL) {
        easylvgl_deinit(g_ctx);
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        
        // 清除注册表中的上下文
        lua_pushnil(L);
        lua_setfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    }
    
    return 0;
}

/**
 * 刷新 LVGL 显示（执行定时器处理）
 * @api easylvgl.refresh()
 * @return nil
 */
static int l_easylvgl_refresh(lua_State *L) {
    (void)L;
    
    if (g_ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }
    
    // 执行 LVGL 定时器处理（处理重绘、动画、事件等）
    lv_timer_handler();
    
    return 0;
}

/**
 * 绑定触摸输入配置到 LuatOS 平台
 * @api easylvgl.indev_bind_touch(tp_cfg)
 * @userdata tp_cfg luat_tp_config_t*（lightuserdata）
 * @return bool 绑定是否成功
 */
static int l_easylvgl_indev_bind_touch(lua_State *L) {
#if defined(LUAT_USE_EASYLVGL_LUATOS)
    luat_tp_config_t *tp_cfg = (luat_tp_config_t *)lua_touserdata(L, 1);
    if (tp_cfg == NULL) {
        LLOGE("indev_bind_touch tp_cfg is NULL");
        lua_pushboolean(L, 0);
        return 1;
    }

    /* 保存到平台绑定，供初始化时同步 */
    easylvgl_platform_luatos_bind_tp(tp_cfg);

    /* 如果上下文已存在且平台数据已分配，运行时也同步一份 */
    if (g_ctx && g_ctx->platform_data) {
        luatos_platform_data_t *data = (luatos_platform_data_t *)g_ctx->platform_data;
        data->tp_config = tp_cfg;
    }

    LLOGD("indev_bind_touch bind %p", tp_cfg);
    lua_pushboolean(L, 1);
    return 1;
// SDL2 路径：SDL 输入已经通过事件轮询获取，无需绑定 TP
#elif defined(LUAT_USE_EASYLVGL_SDL2)
    (void)L;
    LLOGI("indev_bind_touch ignored on SDL2 (mouse/SDL events used)");
    lua_pushboolean(L, 1);
    return 1;
#else
    (void)L;
    LLOGE("indev_bind_touch unsupported on this platform");
    lua_pushboolean(L, 0);
    return 1;
#endif
}

static int l_easylvgl_keyboard_enable_system(lua_State *L) {
    bool enable = lua_toboolean(L, 1);
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "easylvgl not initialized");
        return 0;
    }

    int ret = easylvgl_system_keyboard_enable(ctx, enable);
    lua_pushboolean(L, ret == EASYLVGL_OK);
    return 1;
}

/**
 * 推送组件 userdata（通用辅助函数）
 */
void easylvgl_push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)lua_newuserdata(L, sizeof(easylvgl_component_ud_t));
    ud->obj = obj;
    luaL_getmetatable(L, mt);
    lua_setmetatable(L, -2);
}

/**
 * 检查组件 userdata（通用辅助函数）
 */
lv_obj_t *easylvgl_check_component(lua_State *L, int index, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, index, mt);
    if (ud == NULL || ud->obj == NULL) {
        luaL_error(L, "invalid %s object", mt);
    }
    return ud->obj;
}

/**
 * 加载字体
 * @api easylvgl.font_load(config)
 * @table config 配置表
 * @string config.type 字体类型，"hzfont" 或 "bin"
 * @string config.path 字体路径，对于 "hzfont"，传 nil 则使用内置字库
 * @int config.size 可选，TTF 字体大小，默认 16
 * @int config.cache_size 可选，TTF 缓存数量，默认 256
 * @int config.antialias 可选，TTF 抗锯齿等级，默认 -1（自动）
 * @return userdata 字体指针
 */
static int l_easylvgl_font_load(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    const char *type = easylvgl_marshal_string(L, 1, "type", NULL);
    if (type == NULL) {
        luaL_error(L, "font_load: config.type is required");
        return 0;
    }
    lv_font_t *font = NULL;

    if (strcmp(type, "hzfont") == 0) {
        const char *path = easylvgl_marshal_string(L, 1, "path", NULL);
        uint16_t size = easylvgl_marshal_integer(L, 1, "size", 16);
        uint32_t cache_size = easylvgl_marshal_integer(L, 1, "cache_size", 256);
        int antialias = easylvgl_marshal_integer(L, 1, "antialias", -1);
        font = easylvgl_font_hzfont_create(path, size, cache_size, antialias);
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

