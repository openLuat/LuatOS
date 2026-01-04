/**
 * @file luat_easylvgl_image.c
 * @summary Image 组件实现
 * @responsible Image 组件创建、属性设置、事件绑定
 */

#include "luat_easylvgl_component.h"
#include "lvgl9/src/widgets/image/lv_image.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>
#include <stdint.h>

#define LUAT_LOG_TAG "easylvgl.image"
#include "luat_log.h"


/**
 * 从配置表创建 Image 组件
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL 对象指针，失败返回 NULL
 */
lv_obj_t *easylvgl_image_create_from_config(void *L, int idx)
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
    int w = easylvgl_marshal_integer(L, idx, "w", 100);
    int h = easylvgl_marshal_integer(L, idx, "h", 100);
    const char *src = easylvgl_marshal_string(L, idx, "src", NULL);
    
    // 创建 Image 对象
    lv_obj_t *img = lv_image_create(parent);
    if (img == NULL) {
        return NULL;
    }
    
    // 设置位置和大小
    lv_obj_set_pos(img, x, y);
    lv_obj_set_size(img, w, h);
    
    // 设置图片源
    if (src != NULL && strlen(src) > 0) {
        lv_image_set_src(img, src);
    }
    
    // 读取 pivot 点（旋转中心）
    lv_point_t pivot;
    if (easylvgl_marshal_point(L, idx, "pivot", &pivot)) {
        lv_image_set_pivot(img, pivot.x, pivot.y);
    }
    
    // 读取 zoom（缩放比例，256 = 100%）
    int zoom = easylvgl_marshal_integer(L, idx, "zoom", 256);
    if (zoom != 256) {
        lv_image_set_scale(img, zoom);
    }
    
    // 读取 opacity（透明度，0-255）
    int opacity = easylvgl_marshal_integer(L, idx, "opacity", 255);
    if (opacity != 255) {
        lv_obj_set_style_opa(img, opacity, 0);
    }
    
    // 分配元数据
    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, img, EASYLVGL_COMPONENT_IMAGE);
    if (meta == NULL) {
        lv_obj_delete(img);
        return NULL;
    }
    
    // 绑定点击事件（仅当用户提供回调）
    int callback_ref = easylvgl_component_capture_callback(L, idx, "on_click");
    if (callback_ref != LUA_NOREF) {  // LUA_NOREF
        // 使图片成为可点击对象（默认 LVGL Image 不响应点击事件）
        lv_obj_add_flag(img, LV_OBJ_FLAG_CLICKABLE);
        easylvgl_component_bind_event(meta, EASYLVGL_EVENT_CLICKED, callback_ref);
    }
    
    return img;
}

/**
 * 设置 Image 图片源
 * @param img Image 对象指针
 * @param src 图片路径或符号
 * @return 0 成功，<0 失败
 */
int easylvgl_image_set_src(lv_obj_t *img, const char *src)
{
    if (img == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    lv_image_set_src(img, src != NULL ? src : "");
    return EASYLVGL_OK;
}

/**
 * 设置 Image 缩放比例
 * @param img Image 对象指针
 * @param zoom 缩放比例，256 = 100%
 * @return 0 成功，<0 失败
 */
int easylvgl_image_set_zoom(lv_obj_t *img, int zoom)
{
    if (img == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    lv_image_set_scale(img, zoom);
    return EASYLVGL_OK;
}

/**
 * 设置 Image 透明度
 * @param img Image 对象指针
 * @param opacity 透明度，0-255
 * @return 0 成功，<0 失败
 */
int easylvgl_image_set_opacity(lv_obj_t *img, int opacity)
{
    if (img == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    if (opacity < 0) opacity = 0;
    if (opacity > 255) opacity = 255;
    
    lv_obj_set_style_opa(img, opacity, 0);
    return EASYLVGL_OK;
}

