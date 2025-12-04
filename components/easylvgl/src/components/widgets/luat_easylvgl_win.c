/**
 * @file luat_easylvgl_win.c
 * @summary Win 组件实现
 * @responsible Win 组件创建、属性设置、事件绑定
 */

#include "luat_easylvgl_component.h"
#include "lvgl9/src/widgets/win/lv_win.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_event.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * Win 组件私有数据结构
 */
typedef struct {
    lv_obj_t *title_label;  /**< 标题标签指针 */
    lv_obj_t *content;      /**< 内容容器指针 */
} easylvgl_win_data_t;

/**
 * Win 关闭事件回调
 */
static void easylvgl_win_close_event_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    lv_obj_t *win = NULL;
    
    if (code == LV_EVENT_CLICKED) {
        // 从关闭按钮点击事件
        lv_obj_t *btn = lv_event_get_target(e);
        if (btn != NULL) {
            // 向上查找直到找到 win 对象（win 是按钮的祖先）
            win = lv_obj_get_parent(btn);
            while (win != NULL) {
                // 检查是否是 win 对象（通过检查是否有 win 的特征）
                lv_obj_t *content = lv_win_get_content(win);
                if (content != NULL) {
                    break;  // 找到了 win 对象
                }
                win = lv_obj_get_parent(win);
            }
        }
    } else if (code == LV_EVENT_DELETE) {
        // 从窗口删除事件
        win = lv_event_get_target(e);
    }
    
    if (win != NULL) {
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(win);
        if (meta != NULL && meta->ctx != NULL) {
            // 调用 on_close 回调
            easylvgl_component_call_callback(meta, EASYLVGL_EVENT_CLOSE, meta->ctx->L);
        }
        
        // 删除窗口（如果是从点击事件触发）
        if (code == LV_EVENT_CLICKED) {
            lv_obj_delete(win);
        }
    }
}

/**
 * 从配置表创建 Win 组件
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL 对象指针，失败返回 NULL
 */
lv_obj_t *easylvgl_win_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }
    
    lua_State *L_state = (lua_State *)L;
    
    // 获取上下文（从注册表中获取）
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    
    if (ctx == NULL) {
        return NULL;
    }
    
    // 读取配置
    lv_obj_t *parent = easylvgl_marshal_parent(L, idx);
    int x = easylvgl_marshal_integer(L, idx, "x", 0);
    int y = easylvgl_marshal_integer(L, idx, "y", 0);
    int w = easylvgl_marshal_integer(L, idx, "w", 400);
    int h = easylvgl_marshal_integer(L, idx, "h", 300);
    const char *title = easylvgl_marshal_string(L, idx, "title", NULL);
    bool close_btn = easylvgl_marshal_bool(L, idx, "close_btn", false);
    bool auto_center = easylvgl_marshal_bool(L, idx, "auto_center", false);
    
    // 创建 Win 对象
    lv_obj_t *win = lv_win_create(parent);
    if (win == NULL) {
        return NULL;
    }
    
    // 设置位置和大小
    lv_obj_set_pos(win, x, y);
    lv_obj_set_size(win, w, h);
    
    // 分配元数据
    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, win, EASYLVGL_COMPONENT_WIN);
    if (meta == NULL) {
        lv_obj_delete(win);
        return NULL;
    }
    
    // 分配 Win 私有数据
    easylvgl_win_data_t *win_data = malloc(sizeof(easylvgl_win_data_t));
    if (win_data == NULL) {
        easylvgl_component_meta_free(meta);
        lv_obj_delete(win);
        return NULL;
    }
    win_data->title_label = NULL;
    win_data->content = NULL;
    meta->user_data = win_data;
    
    // 设置标题
    lv_obj_t *title_label = NULL;
    if (title != NULL && strlen(title) > 0) {
        title_label = lv_win_add_title(win, title);
        win_data->title_label = title_label;
    }
    
    // 添加关闭按钮
    if (close_btn) {
        lv_obj_t *btn = lv_win_add_button(win, LV_SYMBOL_CLOSE, 40);
        lv_obj_add_event_cb(btn, easylvgl_win_close_event_cb, LV_EVENT_CLICKED, win);
    }
    
    // 自动居中
    if (auto_center) {
        lv_obj_center(win);
    }
    
    // 应用样式
    lua_getfield(L_state, idx, "style");
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        int style_idx = lua_gettop(L_state);
        int radius = easylvgl_marshal_integer(L, style_idx, "radius", 0);
        if (radius > 0) {
            lv_obj_set_style_radius(win, radius, 0);
        }
        int pad = easylvgl_marshal_integer(L, style_idx, "pad", 0);
        if (pad > 0) {
            lv_obj_set_style_pad_all(win, pad, 0);
        }
        int border = easylvgl_marshal_integer(L, style_idx, "border_width", 0);
        if (border > 0) {
            lv_obj_set_style_border_width(win, border, 0);
        }
    }
    lua_pop(L_state, 1);
    
    // 获取内容容器
    lv_obj_t *content = lv_win_get_content(win);
    win_data->content = content;
    
    // 绑定关闭事件
    int callback_ref = easylvgl_component_capture_callback(L, idx, "on_close");
    if (callback_ref != -1) {  // LUA_NOREF
        easylvgl_component_bind_event(meta, EASYLVGL_EVENT_CLOSE, callback_ref);
        
        // 如果没有关闭按钮，在窗口删除时触发回调
        if (!close_btn) {
            lv_obj_add_event_cb(win, easylvgl_win_close_event_cb, LV_EVENT_DELETE, win);
        }
    }
    
    return win;
}

/**
 * 设置 Win 标题
 * @param win Win 对象指针
 * @param title 标题文本
 * @return 0 成功，<0 失败
 */
int easylvgl_win_set_title(lv_obj_t *win, const char *title)
{
    if (win == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(win);
    if (meta == NULL || meta->user_data == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    easylvgl_win_data_t *win_data = (easylvgl_win_data_t *)meta->user_data;
    
    // 如果已有标题标签，更新文本
    if (win_data->title_label != NULL) {
        lv_label_set_text(win_data->title_label, title != NULL ? title : "");
    } else {
        // 创建新标题
        lv_obj_t *title_label = lv_win_add_title(win, title != NULL ? title : "");
        win_data->title_label = title_label;
    }
    
    return EASYLVGL_OK;
}

/**
 * 添加子组件到 Win 内容容器
 * @param win Win 对象指针
 * @param child 子对象指针
 * @return 0 成功，<0 失败
 */
int easylvgl_win_add_content(lv_obj_t *win, lv_obj_t *child)
{
    if (win == NULL || child == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(win);
    if (meta == NULL || meta->user_data == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    easylvgl_win_data_t *win_data = (easylvgl_win_data_t *)meta->user_data;
    
    // 获取内容容器
    lv_obj_t *content = win_data->content;
    if (content == NULL) {
        content = lv_win_get_content(win);
        if (content == NULL) {
            return EASYLVGL_ERR_INVALID_PARAM;
        }
        win_data->content = content;
    }
    
    // 将子对象添加到内容容器
    lv_obj_set_parent(child, content);
    
    return EASYLVGL_OK;
}

