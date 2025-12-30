/**
 * @file luat_easylvgl_tabview.c
 * @summary TabView 组件实现
 * @responsible TabView 构建、页管理、激活控制
 */

#include "luat_easylvgl_component.h"
#include "luat_malloc.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/tabview/lv_tabview.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/core/lv_obj_style.h"
#include "lvgl9/src/misc/lv_color.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

typedef struct {
    lv_obj_t **pages;
    uint32_t page_count;
} easylvgl_tabview_data_t;

typedef struct {
    easylvgl_tabview_pad_method_t pad_method;
    bool has_pad;
    lv_coord_t pad_value;
    lv_opa_t bg_opa;
    bool has_bg_opa;
    lv_color_t bg_color;
    bool has_bg_color;
} easylvgl_tabview_page_style_t;

/**
 * 释放 TabView 页面缓存数据
 */
static void easylvgl_tabview_data_free(easylvgl_tabview_data_t *data)
{
    if (data == NULL) {
        return;
    }
    if (data->pages != NULL) {
        luat_heap_free(data->pages);
    }
    luat_heap_free(data);
}

/**
 * 从 Lua 表中收集 page_style 配置
 */
static void easylvgl_tabview_collect_page_style(lua_State *L, int table_idx, easylvgl_tabview_page_style_t *style)
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
            if (method >= 0 && method < EASYLVGL_TABVIEW_PAD_MAX) {
                style->pad_method = (easylvgl_tabview_pad_method_t)method;
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
static void easylvgl_tabview_apply_pad(lv_obj_t *page, const easylvgl_tabview_page_style_t *style)
{
    if (page == NULL || style == NULL || !style->has_pad) {
        return;
    }

    lv_style_selector_t selector = (lv_style_selector_t)((uint32_t)LV_PART_MAIN | (uint32_t)LV_STATE_DEFAULT);
    switch (style->pad_method) {
        case EASYLVGL_TABVIEW_PAD_ALL:
            lv_obj_set_style_pad_all(page, style->pad_value, selector);
            break;
        case EASYLVGL_TABVIEW_PAD_HOR:
            lv_obj_set_style_pad_hor(page, style->pad_value, selector);
            break;
        case EASYLVGL_TABVIEW_PAD_VER:
            lv_obj_set_style_pad_ver(page, style->pad_value, selector);
            break;
        case EASYLVGL_TABVIEW_PAD_TOP:
            lv_obj_set_style_pad_top(page, style->pad_value, selector);
            break;
        case EASYLVGL_TABVIEW_PAD_BOTTOM:
            lv_obj_set_style_pad_bottom(page, style->pad_value, selector);
            break;
        case EASYLVGL_TABVIEW_PAD_LEFT:
            lv_obj_set_style_pad_left(page, style->pad_value, selector);
            break;
        case EASYLVGL_TABVIEW_PAD_RIGHT:
            lv_obj_set_style_pad_right(page, style->pad_value, selector);
            break;
        default:
            break;
    }
}

/**
 * 将 page_style 应用到页面（padding + 背景）
 */
static void easylvgl_tabview_apply_page_style(lv_obj_t *page, const easylvgl_tabview_page_style_t *style)
{
    if (page == NULL || style == NULL) {
        return;
    }

    easylvgl_tabview_apply_pad(page, style);
    lv_style_selector_t selector = (lv_style_selector_t)((uint32_t)LV_PART_MAIN | (uint32_t)LV_STATE_DEFAULT);
    if (style->has_bg_opa) {
        lv_obj_set_style_bg_opa(page, style->bg_opa, selector);
    }
    if (style->has_bg_color) {
        lv_obj_set_style_bg_color(page, style->bg_color, selector);
    }
}

/**
 * 判断 page_style 是否包含有效设置
 */
static bool easylvgl_tabview_page_style_used(const easylvgl_tabview_page_style_t *style)
{
    if (style == NULL) {
        return false;
    }
    return style->has_pad || style->has_bg_opa || style->has_bg_color;
}

/**
 * 从 Lua config 创建 TabView
 * @param L Lua 状态
 * @param idx Config 表索引
 * @return TabView 对象指针，失败返回 NULL
 */
lv_obj_t *easylvgl_tabview_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);

    if (ctx == NULL) {
        return NULL;
    }

    // 读取基础配置项
    lv_obj_t *parent = easylvgl_marshal_parent(L, idx);
    int x = easylvgl_marshal_integer(L, idx, "x", 0);
    int y = easylvgl_marshal_integer(L, idx, "y", 0);
    int w = easylvgl_marshal_integer(L, idx, "w", 320);
    int h = easylvgl_marshal_integer(L, idx, "h", 200);
    int tabbar_pos = easylvgl_marshal_integer(L, idx, "tabbar_pos", LV_DIR_TOP);
    int active = easylvgl_marshal_integer(L, idx, "active", 0);

    // 创建 TabView 对象并设置样式
    lv_obj_t *tabview = lv_tabview_create(parent);
    if (tabview == NULL) {
        return NULL;
    }

    // 设置位置与大小
    lv_obj_set_pos(tabview, x, y);
    lv_obj_set_size(tabview, w, h);
    lv_tabview_set_tab_bar_position(tabview, (lv_dir_t)tabbar_pos);

    int tab_count = easylvgl_marshal_table_length(L, idx, "tabs");
    if (tab_count <= 0) {
        tab_count = 1;
    }

    // 解析页面样式
    easylvgl_tabview_page_style_t page_style = {0};
    lua_getfield(L_state, idx, "page_style");
    if (lua_istable(L_state, -1)) {
        easylvgl_tabview_collect_page_style(L_state, -1, &page_style);
    }
    lua_pop(L_state, 1);

    easylvgl_tabview_data_t *data = (easylvgl_tabview_data_t *)luat_heap_malloc(sizeof(easylvgl_tabview_data_t));
    if (data == NULL) {
        lv_obj_delete(tabview);
        return NULL;
    }

    data->pages = (lv_obj_t **)luat_heap_malloc(sizeof(lv_obj_t *) * tab_count);
    if (data->pages == NULL) {
        easylvgl_tabview_data_free(data);
        lv_obj_delete(tabview);
        return NULL;
    }
    data->page_count = tab_count;

    // 创建每个 Tab 页并应用样式
    for (int i = 0; i < tab_count; i++) {
        const char *name = easylvgl_marshal_table_string_at(L, idx, "tabs", i + 1);
        char default_name[16];
        if (name == NULL) {
            snprintf(default_name, sizeof(default_name), "Tab %d", i + 1);
            name = default_name;
        }
        lv_obj_t *page = lv_tabview_add_tab(tabview, name);
        data->pages[i] = page;
        if (easylvgl_tabview_page_style_used(&page_style)) {
            easylvgl_tabview_apply_page_style(page, &page_style);
        }
    }

    if (active < 0) {
        active = 0;
    }
    if (active >= (int)data->page_count) {
        active = data->page_count - 1;
    }
    lv_tabview_set_active(tabview, active, LV_ANIM_OFF);

    // 绑定 meta 与 page 数据
    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, tabview, EASYLVGL_COMPONENT_TABVIEW);
    if (meta == NULL) {
        easylvgl_tabview_data_free(data);
        lv_obj_delete(tabview);
        return NULL;
    }
    meta->user_data = data;

    return tabview;
}

int easylvgl_tabview_set_active(lv_obj_t *tabview, uint32_t idx)
{
    if (tabview == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    lv_tabview_set_active(tabview, idx, LV_ANIM_OFF);
    return EASYLVGL_OK;
}

lv_obj_t *easylvgl_tabview_get_content(lv_obj_t *tabview, int idx)
{
    if (tabview == NULL) {
        return NULL;
    }

    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(tabview);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }

    easylvgl_tabview_data_t *data = (easylvgl_tabview_data_t *)meta->user_data;
    if (idx < 0 || idx >= (int)data->page_count) {
        return NULL;
    }

    return data->pages[idx];
}

/**
 * 释放 TabView 关联的元数据
 */
void easylvgl_tabview_release_data(easylvgl_component_meta_t *meta)
{
    if (meta == NULL || meta->user_data == NULL) {
        return;
    }

    easylvgl_tabview_data_t *data = (easylvgl_tabview_data_t *)meta->user_data;
    easylvgl_tabview_data_free(data);
    meta->user_data = NULL;
}

