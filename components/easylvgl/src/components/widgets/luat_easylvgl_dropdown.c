/**
 * @file luat_easylvgl_dropdown.c
 * @summary Dropdown 组件实现
 * @responsible 解析配置表、创建 lv_dropdown、绑定事件
 */

#include "luat_easylvgl_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/dropdown/lv_dropdown.h"
#include "lvgl9/src/core/lv_obj.h"
#include <string.h>

static easylvgl_ctx_t *easylvgl_binding_get_ctx(lua_State *L) {
    if (L == NULL) {
        return NULL;
    }

    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

static char *easylvgl_dropdown_build_options(lua_State *L, int idx) {
    int count = easylvgl_marshal_table_length(L, idx, "options");
    if (count <= 0) {
        return NULL;
    }

    size_t total = 0;
    for (int i = 1; i <= count; i++) {
        const char *entry = easylvgl_marshal_table_string_at(L, idx, "options", i);
        if (entry != NULL) {
            total += strlen(entry);
            total += 1;  // newline
        }
    }

    if (total == 0) {
        return NULL;
    }

    char *buffer = (char *)luat_heap_malloc(total + 1);
    if (buffer == NULL) {
        return NULL;
    }

    size_t offset = 0;
    for (int i = 1; i <= count; i++) {
        const char *entry = easylvgl_marshal_table_string_at(L, idx, "options", i);
        if (entry != NULL) {
            size_t len = strlen(entry);
            memcpy(buffer + offset, entry, len);
            offset += len;
            buffer[offset++] = '\n';
        }
    }

    if (offset > 0) {
        buffer[offset - 1] = '\0';
    } else {
        buffer[0] = '\0';
    }

    return buffer;
}

lv_obj_t *easylvgl_dropdown_create_from_config(void *L, int idx) {
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    easylvgl_ctx_t *ctx = easylvgl_binding_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    lv_obj_t *parent = easylvgl_marshal_parent(L, idx);
    int x = easylvgl_marshal_integer(L, idx, "x", 0);
    int y = easylvgl_marshal_integer(L, idx, "y", 0);
    int w = easylvgl_marshal_integer(L, idx, "w", 140);
    int h = easylvgl_marshal_integer(L, idx, "h", 40);
    int default_index = easylvgl_marshal_integer(L, idx, "default_index", -1);

    lv_obj_t *dropdown = lv_dropdown_create(parent);
    if (dropdown == NULL) {
        return NULL;
    }

    lv_obj_set_pos(dropdown, x, y);
    lv_obj_set_size(dropdown, w, h);

    char *options = easylvgl_dropdown_build_options(L_state, idx);
    if (options != NULL) {
        lv_dropdown_set_options(dropdown, options);
    }

    if (default_index >= 0) {
        lv_dropdown_set_selected(dropdown, default_index);
    }

    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, dropdown, EASYLVGL_COMPONENT_DROPDOWN);
    if (meta == NULL) {
        if (options != NULL) {
            luat_heap_free(options);
        }
        lv_obj_delete(dropdown);
        return NULL;
    }

    meta->user_data = options;

    int callback_ref = easylvgl_component_capture_callback(L, idx, "on_change");
    if (callback_ref != LUA_NOREF) {
        easylvgl_dropdown_set_on_change(dropdown, callback_ref);
    }

    return dropdown;
}

int easylvgl_dropdown_set_selected(lv_obj_t *dropdown, int index) {
    if (dropdown == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    lv_dropdown_set_selected(dropdown, index);
    return EASYLVGL_OK;
}

int easylvgl_dropdown_get_selected(lv_obj_t *dropdown) {
    if (dropdown == NULL) {
        return -1;
    }

    return lv_dropdown_get_selected(dropdown);
}

int easylvgl_dropdown_set_on_change(lv_obj_t *dropdown, int callback_ref) {
    if (dropdown == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(dropdown);
    if (meta == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    return easylvgl_component_bind_event(
        meta, EASYLVGL_EVENT_VALUE_CHANGED, callback_ref);
}

