/**
 * @file luat_airui_dropdown.c
 * @summary Dropdown 组件实现
 * @responsible 解析配置表、创建 lv_dropdown、绑定事件
 */
// 负责：构建下拉框配置并将事件与 Lua 回调关联（参考 .cursor/rules/code/RULE.md）

#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/dropdown/lv_dropdown.h"
#include "lvgl9/src/core/lv_obj.h"
#include <string.h>

static airui_ctx_t *airui_binding_get_ctx(lua_State *L) {
    if (L == NULL) {
        return NULL;
    }

    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

/**
 * 从 Lua 配置表读取选项并拼接成 LVGL 所需字符串
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return 拼接后的选项字符串（需调用方释放），失败返回 NULL
 */
static char *airui_dropdown_build_options(lua_State *L, int idx) {
    int count = airui_marshal_table_length(L, idx, "options");
    if (count <= 0) {
        return NULL;
    }

    size_t total = 0;
    for (int i = 1; i <= count; i++) {
        const char *entry = airui_marshal_table_string_at(L, idx, "options", i);
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
        const char *entry = airui_marshal_table_string_at(L, idx, "options", i);
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

/**
 * 根据 Lua 配置表创建下拉框并完成基本属性设置
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return 构建成功的 LVGL 下拉框对象，失败返回 NULL
 */
lv_obj_t *airui_dropdown_create_from_config(void *L, int idx) {
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_binding_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    // 读取配置（父对象、位置尺寸、默认选中）
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int w = airui_marshal_integer(L, idx, "w", 140);
    int h = airui_marshal_integer(L, idx, "h", 40);
    int default_index = airui_marshal_integer(L, idx, "default_index", -1);

    lv_obj_t *dropdown = lv_dropdown_create(parent);
    if (dropdown == NULL) {
        return NULL;
    }

    lv_obj_set_pos(dropdown, x, y);
    lv_obj_set_size(dropdown, w, h);

    // 构建 options 字符串并同步到 LVGL 下拉框
    char *options = airui_dropdown_build_options(L_state, idx);
    if (options != NULL) {
        lv_dropdown_set_options(dropdown, options);
    }

    // 如果指定了默认选中，立即设置
    if (default_index >= 0) {
        lv_dropdown_set_selected(dropdown, default_index);
    }

    // 分配组件元数据并挂载到上下文
    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, dropdown, AIRUI_COMPONENT_DROPDOWN);
    if (meta == NULL) {
        if (options != NULL) {
            luat_heap_free(options);
        }
        lv_obj_delete(dropdown);
        return NULL;
    }

    // 将 options 字符串绑定到 user_data，方便后续回收
    meta->user_data = options;

    // 捕获 Lua 回调并绑定 LVGL 事件
    int callback_ref = airui_component_capture_callback(L, idx, "on_change");
    if (callback_ref != LUA_NOREF) {
        airui_dropdown_set_on_change(dropdown, callback_ref);
    }

    return dropdown;
}

/** 
 * 设置下拉框选中索引
 * @param dropdown LVGL 下拉框对象
 * @param index 要选中的索引
 * @return AIRUI_OK 成功，其他失败 
 */
int airui_dropdown_set_selected(lv_obj_t *dropdown, int index) {
    if (dropdown == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_dropdown_set_selected(dropdown, index);
    return AIRUI_OK;
}

/**
 * 获取当前选中的索引
 * @param dropdown LVGL 下拉框对象
 * @return 当前选中索引，失败返回 -1
 */
int airui_dropdown_get_selected(lv_obj_t *dropdown) {
    if (dropdown == NULL) {
        return -1;
    }

    return lv_dropdown_get_selected(dropdown);
}

/**
 * 设置下拉框选中项变化回调
 * @param dropdown LVGL 下拉框对象
 * @param callback_ref Lua 回调引用
 * @return AIRUI_OK 成功，其他失败
 */
int airui_dropdown_set_on_change(lv_obj_t *dropdown, int callback_ref) {
    if (dropdown == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(dropdown);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return airui_component_bind_event(
        meta, AIRUI_EVENT_VALUE_CHANGED, callback_ref);
}

