/**
 * @file luat_airui_lottie.c
 * @summary Lottie 动画组件
 * @responsible Lottie 创建、缓冲管理、动画控制、事件驱动
 */

#include "luat_airui_component.h"
#include "luat_airui.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_mem.h"

#include "luat_airui_conf.h"
#if LV_USE_LOTTIE == 1

#include "lvgl9/src/widgets/lottie/lv_lottie.h"
#include "lvgl9/src/draw/lv_draw_buf.h"
#include "lvgl9/src/misc/lv_anim.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.lottie"
#include "luat_log.h"

typedef struct {
    lv_draw_buf_t draw_buf;
    void *draw_buf_data;
    size_t draw_buf_size;
    lv_anim_t *anim;
    bool loop;
    bool auto_play;
    float speed;
    uint32_t base_duration;
} airui_lottie_data_t;

static airui_lottie_data_t *lottie_get_data(airui_component_meta_t *meta);
static void lottie_anim_completed_cb(lv_anim_t *anim);
static void lottie_update_speed(airui_lottie_data_t *data);
static void lottie_update_loop(airui_lottie_data_t *data);
static void lottie_cleanup_on_error(airui_ctx_t *ctx, airui_lottie_data_t *data, airui_component_meta_t *meta, lv_obj_t *lottie);
static bool lottie_alloc_buffer(airui_ctx_t *ctx, airui_lottie_data_t *data, int w, int h);
static bool lottie_setup_anim(airui_component_meta_t *meta, lv_obj_t *obj);
static bool lottie_apply_src_data(airui_component_meta_t *meta, lv_obj_t *obj, const void *src, size_t size);
static bool lottie_load_from_file(airui_component_meta_t *meta, lv_obj_t *obj, const char *path);

/**
 * 从 Lua 配置创建 Lottie 组件，并准备缓冲 + 事件回调
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL Lottie 对象或 NULL
 */
lv_obj_t *airui_lottie_create_from_config(void *L, int idx)
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

    // 计算控件正确的父对象和位置尺寸
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int w = airui_marshal_integer(L, idx, "w", 100);
    int h = airui_marshal_integer(L, idx, "h", 100);

    // 创建 LVGL 对象并设置几何参数
    lv_obj_t *lottie = lv_lottie_create(parent);
    if (lottie == NULL) {
        return NULL;
    }

    lv_obj_set_pos(lottie, x, y);
    lv_obj_set_size(lottie, w, h);

    // 安全分配元数据和状态
    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, lottie, AIRUI_COMPONENT_LOTTIE);
    if (meta == NULL) {
        lottie_cleanup_on_error(ctx, NULL, NULL, lottie);
        return NULL;
    }

    airui_lottie_data_t *data = (airui_lottie_data_t *)luat_heap_malloc(sizeof(airui_lottie_data_t));
    if (data == NULL) {
        lottie_cleanup_on_error(ctx, NULL, meta, lottie);
        return NULL;
    }

    memset(data, 0, sizeof(airui_lottie_data_t));
    data->speed = 1.0f;
    data->loop = true;
    data->auto_play = true;
    meta->user_data = data;

    data->loop = airui_marshal_bool(L, idx, "loop", data->loop);
    data->auto_play = airui_marshal_bool(L, idx, "auto_play", data->auto_play);

    lua_getfield(L_state, idx, "speed");
    if (lua_type(L_state, -1) == LUA_TNUMBER) {
        data->speed = (float)lua_tonumber(L_state, -1);
        if (data->speed <= 0.0f) {
            data->speed = 1.0f;
        }
    }
    lua_pop(L_state, 1);

    // 初始化画布缓冲区
    if (!lottie_alloc_buffer(ctx, data, w, h)) {
        lottie_cleanup_on_error(ctx, data, meta, lottie);
        return NULL;
    }

    lv_lottie_set_draw_buf(lottie, &data->draw_buf);

    const char *src = airui_marshal_string(L, idx, "src", NULL);
    size_t inline_len = 0;
    lua_getfield(L_state, idx, "data");
    if (lua_type(L_state, -1) == LUA_TSTRING) {
        lua_tolstring(L_state, -1, &inline_len);
    }
    const char *inline_data = lua_type(L_state, -1) == LUA_TSTRING ? lua_tostring(L_state, -1) : NULL;
    lua_pop(L_state, 1);

    bool ready = false;
    if (src != NULL && src[0] != '\0') {
        ready = lottie_load_from_file(meta, lottie, src);
    } else if (inline_data != NULL && inline_len > 0) {
        ready = lottie_apply_src_data(meta, lottie, inline_data, inline_len);
    }

    // 根据 src/data 配置加载动画源
    if (!ready) {
        LLOGE("lottie: no source configured");
        lottie_cleanup_on_error(ctx, data, meta, lottie);
        return NULL;
    }

    // 绑定 Lua 回调
    int ready_ref = airui_component_capture_callback(L, idx, "on_ready");
    if (ready_ref != LUA_NOREF) {
        airui_component_bind_event(meta, AIRUI_EVENT_READY, ready_ref);
    }

    int complete_ref = airui_component_capture_callback(L, idx, "on_complete");
    if (complete_ref != LUA_NOREF) {
        airui_component_bind_event(meta, AIRUI_EVENT_COMPLETE, complete_ref);
    }

    return lottie;
}

/**
 * 从元数据中获取 Lottie 缓存数据
 * @param meta 组件元数据
 * @return 绑定的 airui_lottie_data_t，或 NULL
 */
static airui_lottie_data_t *lottie_get_data(airui_component_meta_t *meta)
{
    if (meta == NULL) {
        return NULL;
    }
    return (airui_lottie_data_t *)meta->user_data;
}

/**
 * 动画完成回调：触发 Lua 注册的 on_complete 事件
 * @param anim 动画实例（由 lv_lottie 决定）
 */
static void lottie_anim_completed_cb(lv_anim_t *anim)
{
    if (anim == NULL) {
        return;
    }

    airui_component_meta_t *meta = (airui_component_meta_t *)lv_anim_get_user_data(anim);
    if (meta == NULL || meta->ctx == NULL) {
        return;
    }

    airui_component_call_callback(meta, AIRUI_EVENT_COMPLETE, meta->ctx->L);
}

/**
 * 根据速率调整动画周期
 * @param data Lottie 状态数据
 */
static void lottie_update_speed(airui_lottie_data_t *data)
{
    if (data == NULL || data->anim == NULL) {
        return;
    }

    if (data->speed <= 0.0f) {
        data->speed = 1.0f;
    }

    uint32_t duration = (uint32_t)((float)data->base_duration / data->speed);
    if (duration == 0) {
        duration = 1;
    }

    lv_anim_set_duration(data->anim, duration);
}

/**
 * 根据 loop 属性调整动画重复策略
 * @param data Lottie 状态数据
 */
static void lottie_update_loop(airui_lottie_data_t *data)
{
    if (data == NULL || data->anim == NULL) {
        return;
    }

    lv_anim_set_repeat_count(data->anim, data->loop ? LV_ANIM_REPEAT_INFINITE : 1);
}

/**
 * 为 Lottie 分配绘制缓冲区并初始化 lv_draw_buf
 * @param ctx AIRUI 上下文
 * @param data Lottie 状态数据
 * @param w 宽度
 * @param h 高度
 * @return 是否成功
 */
static bool lottie_alloc_buffer(airui_ctx_t *ctx, airui_lottie_data_t *data, int w, int h)
{
    if (data == NULL || ctx == NULL) {
        return false;
    }

    // 申请画布所需的像素缓冲区
    size_t buf_size = LV_DRAW_BUF_SIZE(w, h, LV_COLOR_FORMAT_ARGB8888_PREMULTIPLIED);
    void *buf = airui_buffer_alloc(ctx, buf_size, AIRUI_BUFFER_OWNER_SYSTEM);
    if (buf == NULL) {
        LLOGE("lottie: draw buffer alloc failed (%zux%zu)", w, h);
        return false;
    }

    data->draw_buf_data = buf;
    data->draw_buf_size = buf_size;

    // 初始化 lv_draw_buf 并设置缓冲对齐
    uint32_t stride = lv_draw_buf_width_to_stride(w, LV_COLOR_FORMAT_ARGB8888_PREMULTIPLIED);
    lv_result_t res = lv_draw_buf_init(
        &data->draw_buf,
        w,
        h,
        LV_COLOR_FORMAT_ARGB8888_PREMULTIPLIED,
        stride,
        lv_draw_buf_align(buf, LV_COLOR_FORMAT_ARGB8888_PREMULTIPLIED),
        (uint32_t)buf_size);
    if (res != LV_RES_OK) {
        LLOGE("lottie: draw buf init failed");
        airui_buffer_free(ctx, buf);
        data->draw_buf_data = NULL;
        data->draw_buf_size = 0;
        return false;
    }

    lv_draw_buf_set_flag(&data->draw_buf, LV_IMAGE_FLAGS_PREMULTIPLIED);

    return true;
}

/**
 * 配置动画参数并注册完成回调
 * @param meta 组件元数据
 * @param obj Lottie 对象
 * @return 是否成功
 */
static bool lottie_setup_anim(airui_component_meta_t *meta, lv_obj_t *obj)
{
    if (meta == NULL || obj == NULL) {
        return false;
    }

    airui_lottie_data_t *data = lottie_get_data(meta);
    if (data == NULL) {
        return false;
    }

    // 获取 LVGL 的动画实例，并绑定回调
    data->anim = lv_lottie_get_anim(obj);
    if (data->anim == NULL) {
        return false;
    }

    lv_anim_set_user_data(data->anim, meta);
    lv_anim_set_completed_cb(data->anim, lottie_anim_completed_cb);

    // 记录基础时长，避免除零
    data->base_duration = lv_anim_get_time(data->anim);
    if (data->base_duration == 0) {
        data->base_duration = 1;
    }

    lottie_update_speed(data);
    lottie_update_loop(data);

    // 根据 auto_play 控制播放/暂停
    if (data->auto_play) {
        lv_anim_resume(data->anim);
    } else {
        lv_anim_pause(data->anim);
    }

    return true;
}

/**
 * 使用缓冲数据更新 Lottie 源并初始化动画
 * @param meta 组件元数据
 * @param obj Lottie 对象
 * @param src 动画数据指针
 * @param size 数据长度
 * @return 是否成功
 */
static bool lottie_apply_src_data(airui_component_meta_t *meta, lv_obj_t *obj, const void *src, size_t size)
{
    if (meta == NULL || obj == NULL || src == NULL || size == 0) {
        return false;
    }

    lv_lottie_set_src_data(obj, src, size);
    if (!lottie_setup_anim(meta, obj)) {
        return false;
    }

    airui_component_call_callback(meta, AIRUI_EVENT_READY, meta->ctx ? meta->ctx->L : NULL);
    return true;
}

/**
 * 从文件加载 Lottie 数据并应用
 * @param meta 组件元数据
 * @param obj Lottie 对象
 * @param path 文件路径
 * @return 是否成功
 */
static bool lottie_load_from_file(airui_component_meta_t *meta, lv_obj_t *obj, const char *path)
{
    if (meta == NULL || obj == NULL || path == NULL) {
        return false;
    }

    // 通过 AIRUI 的文件系统接口读取数据
    void *buffer = NULL;
    size_t len = 0;
    if (!airui_fs_load_file(meta->ctx, path, &buffer, &len)) {
        LLOGE("lottie: failed to load %s", path);
        return false;
    }

    bool ok = lottie_apply_src_data(meta, obj, buffer, len);
    // 释放psram加载的json动画内存
    luat_heap_opt_free(LUAT_HEAP_PSRAM, buffer);
    return ok;
}

/**
 * 失败时清理资源（缓冲、meta、对象）
 * @param ctx 上下文，用于释放缓冲
 * @param data Lottie 状态，可能为 NULL
 * @param meta 组件元数据，可能为 NULL
 * @param lottie LVGL 对象，可能为 NULL
 */
static void lottie_cleanup_on_error(airui_ctx_t *ctx, airui_lottie_data_t *data,
                                    airui_component_meta_t *meta, lv_obj_t *lottie)
{
    if (data != NULL) {
        if (data->draw_buf_data != NULL && ctx != NULL) {
            airui_buffer_free(ctx, data->draw_buf_data);
            data->draw_buf_data = NULL;
        }
        luat_heap_free(data);
        if (meta != NULL) {
            meta->user_data = NULL;
        }
    }

    if (meta != NULL) {
        airui_component_meta_free(meta);
    }

    if (lottie != NULL) {
        lv_obj_delete(lottie);
    }
}

/**
 * 恢复 Lottie 动画播放
 * @param lottie Lottie 对象
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_play(lv_obj_t *lottie)
{
    if (lottie == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    airui_lottie_data_t *data = lottie_get_data(meta);
    if (data == NULL || data->anim == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    // 恢复底层动画
    lv_anim_resume(data->anim);
    return AIRUI_OK;
}

/**
 * 暂停 Lottie 动画
 * @param lottie Lottie 对象
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_pause(lv_obj_t *lottie)
{
    if (lottie == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    airui_lottie_data_t *data = lottie_get_data(meta);
    if (data == NULL || data->anim == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    // 暂停动画
    lv_anim_pause(data->anim);
    return AIRUI_OK;
}

/**
 * 停止动画并重置到起始帧
 * @param lottie Lottie 对象
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_stop(lv_obj_t *lottie)
{
    if (lottie == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    airui_lottie_data_t *data = lottie_get_data(meta);
    if (data == NULL || data->anim == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    // 暂停动画并复位到起始关键帧
    lv_anim_pause(data->anim);
    data->anim->act_time = 0;
    int32_t start_value = data->anim->start_value;
    data->anim->current_value = start_value;
    if (data->anim->exec_cb) {
        data->anim->exec_cb(data->anim->var, start_value);
    }
    if (data->anim->custom_exec_cb) {
        data->anim->custom_exec_cb(data->anim, start_value);
    }

    // 将动画时间恢复至开头
    return AIRUI_OK;
}

/**
 * 为 Lottie 绑定新的文件源
 * @param lottie Lottie 对象
 * @param path 文件路径
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_set_src_file(lv_obj_t *lottie, const char *path)
{
    if (lottie == NULL || path == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return lottie_load_from_file(meta, lottie, path) ? AIRUI_OK : AIRUI_ERR_INVALID_PARAM;
}

/**
 * 直接使用内存数据更新动画
 * @param lottie Lottie 对象
 * @param data 数据指针
 * @param size 数据长度
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_set_src_data(lv_obj_t *lottie, const void *data, size_t size)
{
    if (lottie == NULL || data == NULL || size == 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return lottie_apply_src_data(meta, lottie, data, size) ? AIRUI_OK : AIRUI_ERR_INVALID_PARAM;
}

/**
 * 设置是否循环播放
 * @param lottie Lottie 对象
 * @param loop true 表示无限循环
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_set_loop(lv_obj_t *lottie, bool loop)
{
    if (lottie == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    airui_lottie_data_t *data = lottie_get_data(meta);
    if (data == NULL || data->anim == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->loop = loop;
    lottie_update_loop(data);
    return AIRUI_OK;
}

/**
 * 调整播放速度
 * @param lottie Lottie 对象
 * @param speed 速率（<=0 默认为 1）
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_set_speed(lv_obj_t *lottie, float speed)
{
    if (lottie == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    airui_lottie_data_t *data = lottie_get_data(meta);
    if (data == NULL || data->anim == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (speed <= 0.0f) {
        speed = 1.0f;
    }

    data->speed = speed;
    lottie_update_speed(data);
    return AIRUI_OK;
}

/**
 * 跳转动画进度
 * @param lottie Lottie 对象
 * @param progress 进度 [0.0, 1.0]
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_set_progress(lv_obj_t *lottie, float progress)
{
    if (lottie == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    airui_lottie_data_t *data = lottie_get_data(meta);
    if (data == NULL || data->anim == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (progress < 0.0f) {
        progress = 0.0f;
    } else if (progress > 1.0f) {
        progress = 1.0f;
    }

    int32_t range = data->anim->end_value - data->anim->start_value;
    int32_t target = data->anim->start_value + (int32_t)(range * progress);
    data->anim->act_time = (int32_t)(data->anim->duration * progress);
    data->anim->current_value = target;

    if (data->anim->exec_cb) {
        data->anim->exec_cb(data->anim->var, target);
    }
    if (data->anim->custom_exec_cb) {
        data->anim->custom_exec_cb(data->anim, target);
    }

    return AIRUI_OK;
}

/**
 * 销毁 Lottie 组件并释放缓冲
 * @param lottie Lottie 对象
 * @return AIRUI_OK 或错误码
 */
int airui_lottie_destroy(lv_obj_t *lottie)
{
    if (lottie == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(lottie);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_lottie_data_t *data = lottie_get_data(meta);
    if (data != NULL) {
        if (data->draw_buf_data != NULL && meta->ctx != NULL) {
            // 释放缓冲区
            airui_buffer_free(meta->ctx, data->draw_buf_data);
            data->draw_buf_data = NULL;
        }
        luat_heap_free(data);
        meta->user_data = NULL;
    }

    airui_component_meta_free(meta);
    lv_obj_delete(lottie);
    return AIRUI_OK;
}

// LV_USE_LOTTIE 未启用时的占位实现
#else
// Lottie 组件未启用时的空实现
lv_obj_t *airui_lottie_create_from_config(void *L, int idx){ return NULL; }
int airui_lottie_play(lv_obj_t *lottie){ return AIRUI_ERR_NOT_SUPPORTED; }
int airui_lottie_pause(lv_obj_t *lottie){ return AIRUI_ERR_NOT_SUPPORTED; }
int airui_lottie_stop(lv_obj_t *lottie){ return AIRUI_ERR_NOT_SUPPORTED; }
int airui_lottie_set_src_file(lv_obj_t *lottie, const char *path){ return AIRUI_ERR_NOT_SUPPORTED; }
int airui_lottie_set_src_data(lv_obj_t *lottie, const void *data, size_t size){ return AIRUI_ERR_NOT_SUPPORTED; }
int airui_lottie_set_loop(lv_obj_t *lottie, bool loop){ return AIRUI_ERR_NOT_SUPPORTED; }
int airui_lottie_set_speed(lv_obj_t *lottie, float speed){ return AIRUI_ERR_NOT_SUPPORTED; }
int airui_lottie_set_progress(lv_obj_t *lottie, float progress){ return AIRUI_ERR_NOT_SUPPORTED; }
int airui_lottie_destroy(lv_obj_t *lottie){ return AIRUI_ERR_NOT_SUPPORTED; }
#endif