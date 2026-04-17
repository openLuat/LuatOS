/**
 * @file luat_airui_tabview.c
 * @summary TabView 组件实现
 * @responsible TabView 构建、页管理、激活控制
 */

#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/indev/lv_indev.h"
#include "lvgl9/src/widgets/tabview/lv_tabview.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/core/lv_obj_scroll.h"
#include "lvgl9/src/core/lv_obj_style.h"
#include "lvgl9/src/misc/lv_color.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

typedef enum {
    AIRUI_TABVIEW_SWITCH_MODE_SWIPE = 0,
    AIRUI_TABVIEW_SWITCH_MODE_JUMP
} airui_tabview_switch_mode_t;

typedef struct {
    airui_tabview_pad_method_t pad_method;
    bool has_pad;
    lv_coord_t pad_value;
    lv_coord_t tabbar_size;
    bool has_tabbar_size;
    lv_opa_t bg_opa;
    bool has_bg_opa;
    lv_color_t bg_color;
    bool has_bg_color;
} airui_tabview_page_style_t;

typedef struct {
    uint8_t switch_mode;
    bool gesture_hooked;
    airui_ctx_t *ctx;
    bool pointer_tracking;
    lv_point_t press_point;
    int tab_font_size;
    airui_tabview_page_style_t page_style;
    bool page_style_used;
} airui_tabview_data_t;

/**
 * 释放 TabView 页面缓存数据
 */
static void airui_tabview_data_free(airui_tabview_data_t *data)
{
    if (data == NULL) {
        return;
    }
    luat_heap_free(data);
}

static uint32_t airui_tabview_get_page_count_internal(lv_obj_t *tabview)
{
    if (tabview == NULL) {
        return 0;
    }

    return lv_tabview_get_tab_count(tabview);
}

static lv_obj_t *airui_tabview_get_page_by_index(lv_obj_t *tabview, int idx)
{
    lv_obj_t *cont = lv_tabview_get_content(tabview);
    if (cont == NULL || idx < 0) {
        return NULL;
    }

    return lv_obj_get_child(cont, idx);
}

static void airui_tabview_apply_jump_page_flags(lv_obj_t *page)
{
    if (page == NULL) {
        return;
    }

    lv_obj_remove_flag(page, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scroll_dir(page, LV_DIR_NONE);
    lv_obj_stop_scroll_anim(page);
}

static airui_tabview_switch_mode_t airui_tabview_parse_switch_mode(const char *mode)
{
    if (mode == NULL) {
        return AIRUI_TABVIEW_SWITCH_MODE_SWIPE;
    }
    if (strcmp(mode, "jump") == 0) {
        return AIRUI_TABVIEW_SWITCH_MODE_JUMP;
    }
    return AIRUI_TABVIEW_SWITCH_MODE_SWIPE;
}

static bool airui_tabview_contains_obj(lv_obj_t *tabview, lv_obj_t *obj)
{
    while (obj != NULL) {
        if (obj == tabview) {
            return true;
        }
        obj = lv_obj_get_parent(obj);
    }
    return false;
}

static void airui_tabview_jump_indev_cb(lv_event_t *e)
{
    if (e == NULL) {
        return;
    }

    lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_PRESSED && code != LV_EVENT_RELEASED) {
        return;
    }

    lv_indev_t *indev = lv_event_get_current_target(e);
    lv_obj_t *tabview = (lv_obj_t *)lv_event_get_user_data(e);
    lv_obj_t *event_obj = (lv_obj_t *)lv_event_get_param(e);
    if (indev == NULL || tabview == NULL || event_obj == NULL || !lv_obj_is_valid(tabview)) {
        return;
    }

    airui_component_meta_t *meta = airui_component_meta_get(tabview);
    if (meta == NULL || meta->user_data == NULL) {
        return;
    }

    airui_tabview_data_t *data = (airui_tabview_data_t *)meta->user_data;
    if (data->switch_mode != AIRUI_TABVIEW_SWITCH_MODE_JUMP) {
        return;
    }

    if (code == LV_EVENT_PRESSED) {
        data->pointer_tracking = airui_tabview_contains_obj(tabview, event_obj);
        if (data->pointer_tracking) {
            lv_indev_get_point(indev, &data->press_point);
        }
        return;
    }

    if (!data->pointer_tracking) {
        return;
    }
    data->pointer_tracking = false;

    if (!airui_tabview_contains_obj(tabview, event_obj)) {
        return;
    }

    lv_point_t release_point;
    lv_indev_get_point(indev, &release_point);
    lv_coord_t dx = release_point.x - data->press_point.x;
    lv_coord_t dy = release_point.y - data->press_point.y;
    if (LV_ABS(dx) <= 50 || LV_ABS(dx) <= LV_ABS(dy)) {
        return;
    }

    int32_t current = (int32_t)lv_tabview_get_tab_active(tabview);
    int32_t next = current;
    if (dx < 0) {
        next++;
    }
    else {
        next--;
    }

    if (next < 0) {
        next = 0;
    }
    uint32_t page_count = airui_tabview_get_page_count_internal(tabview);
    if (page_count == 0) {
        return;
    }
    if (next >= (int32_t)page_count) {
        next = (int32_t)page_count - 1;
    }
    if (next == current) {
        return;
    }

    lv_tabview_set_active(tabview, (uint32_t)next, LV_ANIM_OFF);
    lv_indev_stop_processing(indev);
    lv_obj_send_event(tabview, LV_EVENT_VALUE_CHANGED, NULL);
}

/**
 * 从 Lua 表中收集 page_style 配置
 */
static void airui_tabview_collect_page_style(lua_State *L, int table_idx, airui_tabview_page_style_t *style)
{
    if (!lua_istable(L, table_idx) || style == NULL) {
        return;
    }

    int abs_idx = lua_absindex(L, table_idx);

    // pad 设置
    lua_getfield(L, abs_idx, "pad");
    if (lua_istable(L, -1)) {
        lua_getfield(L, -1, "method");
        if (lua_type(L, -1) == LUA_TNUMBER) {
            int method = lua_tointeger(L, -1);
            if (method >= 0 && method < AIRUI_TABVIEW_PAD_MAX) {
                style->pad_method = (airui_tabview_pad_method_t)method;
                style->has_pad = true;
            }
        }
        lua_pop(L, 1);

        lua_getfield(L, -1, "value");
        if (lua_type(L, -1) == LUA_TNUMBER) {
            style->pad_value = (lv_coord_t)lua_tointeger(L, -1);
            style->has_pad = true;
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    // tab bar 尺寸，设为 0 可隐藏顶部/侧边 tab bar
    lua_getfield(L, abs_idx, "tabbar_size");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        style->tabbar_size = (lv_coord_t)lua_tointeger(L, -1);
        style->has_tabbar_size = true;
    }
    lua_pop(L, 1);

    // 背景透明度
    lua_getfield(L, abs_idx, "bg_opa");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        style->bg_opa = (lv_opa_t)lua_tointeger(L, -1);
        style->has_bg_opa = true;
    }
    lua_pop(L, 1);

    // 背景颜色
    lua_getfield(L, abs_idx, "bg_color");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        style->bg_color = lv_color_hex((uint32_t)lua_tointeger(L, -1));
        style->has_bg_color = true;
    }
    lua_pop(L, 1);
}

/**
 * 将 pad 配置应用到 page
 */
static void airui_tabview_apply_pad(lv_obj_t *page, const airui_tabview_page_style_t *style)
{
    if (page == NULL || style == NULL || !style->has_pad) {
        return;
    }

    lv_style_selector_t selector = (lv_style_selector_t)((uint32_t)LV_PART_MAIN | (uint32_t)LV_STATE_DEFAULT);
    switch (style->pad_method) {
        case AIRUI_TABVIEW_PAD_ALL:
            lv_obj_set_style_pad_all(page, style->pad_value, selector);
            break;
        case AIRUI_TABVIEW_PAD_HOR:
            lv_obj_set_style_pad_hor(page, style->pad_value, selector);
            break;
        case AIRUI_TABVIEW_PAD_VER:
            lv_obj_set_style_pad_ver(page, style->pad_value, selector);
            break;
        case AIRUI_TABVIEW_PAD_TOP:
            lv_obj_set_style_pad_top(page, style->pad_value, selector);
            break;
        case AIRUI_TABVIEW_PAD_BOTTOM:
            lv_obj_set_style_pad_bottom(page, style->pad_value, selector);
            break;
        case AIRUI_TABVIEW_PAD_LEFT:
            lv_obj_set_style_pad_left(page, style->pad_value, selector);
            break;
        case AIRUI_TABVIEW_PAD_RIGHT:
            lv_obj_set_style_pad_right(page, style->pad_value, selector);
            break;
        default:
            break;
    }
}

/**
 * 将 page_style 应用到页面（padding + 背景）
 */
static void airui_tabview_apply_page_style(lv_obj_t *page, const airui_tabview_page_style_t *style)
{
    if (page == NULL || style == NULL) {
        return;
    }

    airui_tabview_apply_pad(page, style);
    lv_style_selector_t selector = (lv_style_selector_t)((uint32_t)LV_PART_MAIN | (uint32_t)LV_STATE_DEFAULT);
    if (style->has_bg_opa) {
        lv_obj_set_style_bg_opa(page, style->bg_opa, selector);
    }
    if (style->has_bg_color) {
        lv_obj_set_style_bg_color(page, style->bg_color, selector);
    }
}

static void airui_tabview_apply_style(lv_obj_t *tabview, const airui_tabview_page_style_t *style)
{
    if (tabview == NULL || style == NULL) {
        return;
    }

    if (style->has_tabbar_size) {
        lv_tabview_set_tab_bar_size(tabview, style->tabbar_size);
    }
}

static void airui_tabview_apply_switch_mode(lv_obj_t *tabview, airui_tabview_data_t *data)
{
    if (tabview == NULL || data == NULL) {
        return;
    }

    if (data->switch_mode != AIRUI_TABVIEW_SWITCH_MODE_JUMP) {
        return;
    }

    lv_obj_t *cont = lv_tabview_get_content(tabview);
    if (cont == NULL) {
        return;
    }

    lv_obj_remove_flag(cont, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scroll_dir(cont, LV_DIR_NONE);
    lv_obj_stop_scroll_anim(cont);
    uint32_t page_count = airui_tabview_get_page_count_internal(tabview);
    for (uint32_t i = 0; i < page_count; i++) {
        airui_tabview_apply_jump_page_flags(airui_tabview_get_page_by_index(tabview, (int)i));
    }
    if (data->ctx != NULL && data->ctx->indev != NULL && !data->gesture_hooked) {
        lv_indev_add_event_cb(data->ctx->indev, airui_tabview_jump_indev_cb, LV_EVENT_PRESSED, tabview);
        lv_indev_add_event_cb(data->ctx->indev, airui_tabview_jump_indev_cb, LV_EVENT_RELEASED, tabview);
        data->gesture_hooked = true;
    }
}

/**
 * 判断 page_style 是否包含有效设置
 */
static bool airui_tabview_page_style_used(const airui_tabview_page_style_t *style)
{
    if (style == NULL) {
        return false;
    }
    return style->has_pad || style->has_tabbar_size || style->has_bg_opa || style->has_bg_color;
}

/**
 * 从 Lua config 创建 TabView
 * @param L Lua 状态
 * @param idx Config 表索引
 * @return TabView 对象指针，失败返回 NULL
 */
lv_obj_t *airui_tabview_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);

    if (ctx == NULL) {
        return NULL;
    }

    // 读取基础配置项
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_floor_integer(L, idx, "x", 0);
    int y = airui_marshal_floor_integer(L, idx, "y", 0);
    int w = airui_marshal_floor_integer(L, idx, "w", 320);
    int h = airui_marshal_floor_integer(L, idx, "h", 200);
    int tabbar_pos = airui_marshal_integer(L, idx, "tabbar_pos", LV_DIR_TOP);
    int active = airui_marshal_integer(L, idx, "active", 0);
    int tab_font_size = airui_marshal_integer(L, idx, "tab_font_size", 0);
    const char *switch_mode = airui_marshal_string(L, idx, "switch_mode", "swipe");

    // 创建 TabView 对象并设置样式
    lv_obj_t *tabview = lv_tabview_create(parent);
    if (tabview == NULL) {
        return NULL;
    }

    // 设置位置与大小
    lv_obj_set_pos(tabview, x, y);
    lv_obj_set_size(tabview, w, h);
    lv_tabview_set_tab_bar_position(tabview, (lv_dir_t)tabbar_pos);

    int tab_count = airui_marshal_table_length(L, idx, "tabs");
    if (tab_count <= 0) {
        tab_count = 1;
    }

    // 解析页面样式
    airui_tabview_page_style_t page_style = {0};
    lua_getfield(L_state, idx, "page_style");
    if (lua_istable(L_state, -1)) {
        airui_tabview_collect_page_style(L_state, -1, &page_style);
    }
    lua_pop(L_state, 1);

    airui_tabview_apply_style(tabview, &page_style);

    airui_tabview_data_t *data = (airui_tabview_data_t *)luat_heap_malloc(sizeof(airui_tabview_data_t));
    if (data == NULL) {
        lv_obj_delete(tabview);
        return NULL;
    }

    memset(data, 0, sizeof(airui_tabview_data_t));
    data->ctx = ctx;
    data->switch_mode = (uint8_t)airui_tabview_parse_switch_mode(switch_mode);
    data->tab_font_size = tab_font_size;
    data->page_style = page_style;
    data->page_style_used = airui_tabview_page_style_used(&page_style);

    // 创建每个 Tab 页并应用样式
    for (int i = 0; i < tab_count; i++) {
        const char *name = airui_marshal_table_string_at(L, idx, "tabs", i + 1);
        char default_name[16];
        if (name == NULL) {
            snprintf(default_name, sizeof(default_name), "Tab %d", i + 1);
            name = default_name;
        }
        lv_obj_t *page = lv_tabview_add_tab(tabview, name);
        if (page != NULL && airui_component_meta_get(page) == NULL) {
            (void)airui_component_meta_alloc(ctx, page, AIRUI_COMPONENT_CONTAINER);
        }
        if (data->page_style_used) {
            airui_tabview_apply_page_style(page, &page_style);
        }
    }

    if (active < 0) {
        active = 0;
    }
    if (active >= tab_count) {
        active = tab_count - 1;
    }
    lv_tabview_set_active(tabview, active, LV_ANIM_OFF);
    if (tab_font_size > 0) {
        lv_obj_t *tab_bar = lv_tabview_get_tab_bar(tabview);
        if (tab_bar != NULL) {
            (void)airui_text_font_apply_hzfont(tab_bar, tab_font_size,
                (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT));
            for (uint32_t i = 0; i < airui_tabview_get_page_count_internal(tabview); i++) {
                lv_obj_t *tab_btn = lv_tabview_get_tab_button(tabview, (int32_t)i);
                if (tab_btn != NULL) {
                    (void)airui_text_font_apply_hzfont(tab_btn, tab_font_size,
                        (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT));
                }
            }
        }
    }

    // 绑定 meta 与 page 数据
    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, tabview, AIRUI_COMPONENT_TABVIEW);
    if (meta == NULL) {
        airui_tabview_data_free(data);
        lv_obj_delete(tabview);
        return NULL;
    }
    meta->user_data = data;
    airui_tabview_apply_switch_mode(tabview, data);

    return tabview;
}

int airui_tabview_set_active(lv_obj_t *tabview, uint32_t idx)
{
    if (tabview == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    if (idx >= airui_tabview_get_page_count_internal(tabview)) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_tabview_set_active(tabview, idx, LV_ANIM_OFF);
    return AIRUI_OK;
}

lv_obj_t *airui_tabview_add_tab(lv_obj_t *tabview, const char *title)
{
    if (tabview == NULL || title == NULL) {
        return NULL;
    }

    lv_obj_t *page = lv_tabview_add_tab(tabview, title);
    if (page == NULL) {
        return NULL;
    }

    airui_component_meta_t *meta = airui_component_meta_get(tabview);
    airui_component_meta_t *page_meta = airui_component_meta_get(page);
    if (page_meta == NULL) {
        page_meta = airui_component_meta_alloc(meta != NULL ? meta->ctx : NULL, page, AIRUI_COMPONENT_CONTAINER);
        if (page_meta == NULL) {
            lv_obj_delete(page);
            return NULL;
        }
    }

    if (meta != NULL && meta->user_data != NULL) {
        airui_tabview_data_t *data = (airui_tabview_data_t *)meta->user_data;
        if (data->page_style_used) {
            airui_tabview_apply_page_style(page, &data->page_style);
        }
        if (data->tab_font_size > 0) {
            lv_obj_t *tab_btn = lv_tabview_get_tab_button(tabview, -1);
            if (tab_btn != NULL) {
                (void)airui_text_font_apply_hzfont(tab_btn, data->tab_font_size,
                    (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT));
            }
        }
        if (data->switch_mode == AIRUI_TABVIEW_SWITCH_MODE_JUMP) {
            airui_tabview_apply_jump_page_flags(page);
        }
    }

    return page;
}

int airui_tabview_remove_tab(lv_obj_t *tabview, uint32_t idx)
{
    if (tabview == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    uint32_t tab_count = airui_tabview_get_page_count_internal(tabview);
    if (tab_count <= 1 || idx >= tab_count) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_t *page = airui_tabview_get_page_by_index(tabview, (int)idx);
    lv_obj_t *button = lv_tabview_get_tab_button(tabview, (int32_t)idx);
    if (page == NULL || button == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    uint32_t active = lv_tabview_get_tab_active(tabview);
    uint32_t new_active = active;
    if (idx < active) {
        new_active = active - 1;
    }
    else if (idx == active) {
        new_active = idx;
        if (new_active >= tab_count - 1) {
            new_active = tab_count - 2;
        }
    }

    lv_obj_delete(page);
    lv_obj_delete(button);

    lv_tabview_set_active(tabview, new_active, LV_ANIM_OFF);

    if (idx <= active) {
        lv_obj_send_event(tabview, LV_EVENT_VALUE_CHANGED, NULL);
    }

    return AIRUI_OK;
}

uint32_t airui_tabview_get_tab_count(lv_obj_t *tabview)
{
    return airui_tabview_get_page_count_internal(tabview);
}

lv_obj_t *airui_tabview_get_content(lv_obj_t *tabview, int idx)
{
    if (tabview == NULL) {
        return NULL;
    }

    if (idx < 0 || idx >= (int)airui_tabview_get_page_count_internal(tabview)) {
        return NULL;
    }

    return airui_tabview_get_page_by_index(tabview, idx);
}

/**
 * 释放 TabView 关联的元数据
 */
void airui_tabview_release_data(airui_component_meta_t *meta)
{
    if (meta == NULL || meta->user_data == NULL) {
        return;
    }

    airui_tabview_data_t *data = (airui_tabview_data_t *)meta->user_data;
    if (data->gesture_hooked && data->ctx != NULL && data->ctx->indev != NULL) {
        lv_indev_remove_event_cb_with_user_data(data->ctx->indev, airui_tabview_jump_indev_cb, meta->obj);
        data->gesture_hooked = false;
    }
    airui_tabview_data_free(data);
    meta->user_data = NULL;
}

