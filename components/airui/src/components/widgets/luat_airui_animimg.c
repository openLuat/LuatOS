#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/animimage/lv_animimage.h"
#include "lvgl9/src/widgets/image/lv_image.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/stdlib/lv_string.h"
#include <string.h>
#include <stdint.h>

#define LUAT_LOG_TAG "airui.animimg"
#include "luat_log.h"

typedef struct {
    const void **srcs;
    char **owned_paths;
    uint16_t frame_count;
    bool reverse;
} airui_animimg_data_t;

static airui_animimg_data_t *airui_animimg_get_data(lv_obj_t *animimg);
static void airui_animimg_release_data(void *user_data);
static bool airui_animimg_store_frames(lua_State *L, int index, airui_animimg_data_t *data);
static int airui_animimg_apply_frames(lv_obj_t *animimg, airui_animimg_data_t *data);
static void airui_animimg_completed_cb(lv_anim_t *anim);
static void airui_animimg_clear_frames(airui_animimg_data_t *data);
static void airui_animimg_reset_to_first_frame(lv_obj_t *animimg, airui_animimg_data_t *data);
static airui_ctx_t *airui_animimg_get_ctx(lua_State *L_state);
static lv_anim_t *airui_animimg_get_running_anim(lv_obj_t *animimg);

lv_obj_t *airui_animimg_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_animimg_get_ctx(L_state);

    if (ctx == NULL) {
        return NULL;
    }

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int w = airui_marshal_integer(L, idx, "w", 100);
    int h = airui_marshal_integer(L, idx, "h", 100);
    uint32_t duration = (uint32_t)airui_marshal_integer(L, idx, "duration", 300);
    bool loop = airui_marshal_bool(L, idx, "loop", true);
    bool auto_play = airui_marshal_bool(L, idx, "auto_play", true);
    bool reverse = airui_marshal_bool(L, idx, "reverse", false);

    lv_obj_t *animimg = lv_animimg_create(parent);
    if (animimg == NULL) {
        return NULL;
    }

    lv_obj_set_pos(animimg, x, y);
    lv_obj_set_size(animimg, w, h);

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, animimg, AIRUI_COMPONENT_ANIMIMG);
    if (meta == NULL) {
        lv_obj_delete(animimg);
        return NULL;
    }

    airui_animimg_data_t *data = (airui_animimg_data_t *)luat_heap_malloc(sizeof(airui_animimg_data_t));
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(animimg);
        return NULL;
    }
    memset(data, 0, sizeof(airui_animimg_data_t));
    data->reverse = reverse;
    airui_component_meta_set_user_data(meta, data, airui_animimg_release_data);

    lua_getfield(L_state, idx, "frames");
    bool frame_ok = lua_istable(L_state, -1) && airui_animimg_store_frames(L_state, lua_gettop(L_state), data);
    lua_pop(L_state, 1);

    if (!frame_ok || airui_animimg_apply_frames(animimg, data) != AIRUI_OK) {
        airui_component_meta_free(meta);
        lv_obj_delete(animimg);
        return NULL;
    }

    lv_animimg_set_duration(animimg, duration);
    lv_animimg_set_repeat_count(animimg, loop ? LV_ANIM_REPEAT_INFINITE : 1);

    int complete_ref = airui_component_capture_callback(L, idx, "on_complete");
    if (complete_ref != LUA_NOREF) {
        airui_component_bind_event(meta, AIRUI_EVENT_COMPLETE, complete_ref);
        lv_anim_t *anim = lv_animimg_get_anim(animimg);
        if (anim != NULL) {
            lv_anim_set_user_data(anim, meta);
            lv_anim_set_completed_cb(anim, airui_animimg_completed_cb);
        }
    }

    if (auto_play) {
        lv_animimg_start(animimg);
    } else if (data->frame_count > 0) {
        airui_animimg_reset_to_first_frame(animimg, data);
    }

    return animimg;
}

static airui_animimg_data_t *airui_animimg_get_data(lv_obj_t *animimg)
{
    airui_component_meta_t *meta = airui_component_meta_get(animimg);
    if (meta == NULL) {
        return NULL;
    }
    return (airui_animimg_data_t *)meta->user_data;
}

static airui_ctx_t *airui_animimg_get_ctx(lua_State *L_state)
{
    airui_ctx_t *ctx = NULL;
    if (L_state == NULL) {
        return NULL;
    }

    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    return ctx;
}

static lv_anim_t *airui_animimg_get_running_anim(lv_obj_t *animimg)
{
    if (animimg == NULL) {
        return NULL;
    }

    return lv_anim_get(animimg, NULL);
}

static void airui_animimg_release_data(void *user_data)
{
    airui_animimg_data_t *data = (airui_animimg_data_t *)user_data;
    if (data == NULL) {
        return;
    }

    airui_animimg_clear_frames(data);

    luat_heap_free(data);
}

static void airui_animimg_clear_frames(airui_animimg_data_t *data)
{
    if (data == NULL) {
        return;
    }

    if (data->owned_paths != NULL) {
        for (uint16_t i = 0; i < data->frame_count; i++) {
            if (data->owned_paths[i] != NULL) {
                lv_free(data->owned_paths[i]);
            }
        }
        luat_heap_free(data->owned_paths);
        data->owned_paths = NULL;
    }

    if (data->srcs != NULL) {
        luat_heap_free((void *)data->srcs);
        data->srcs = NULL;
    }

    data->frame_count = 0;
}

static bool airui_animimg_store_frames(lua_State *L, int index, airui_animimg_data_t *data)
{
    uint32_t count;
    if (data == NULL || !lua_istable(L, index)) {
        return false;
    }

    count = (uint32_t)lua_rawlen(L, index);
    if (count == 0 || count > UINT16_MAX) {
        return false;
    }

    if (data->owned_paths != NULL || data->srcs != NULL) {
        airui_animimg_clear_frames(data);
    }

    data->owned_paths = (char **)luat_heap_malloc(sizeof(char *) * count);
    data->srcs = (const void **)luat_heap_malloc(sizeof(void *) * count);
    if (data->owned_paths == NULL || data->srcs == NULL) {
        return false;
    }
    memset(data->owned_paths, 0, sizeof(char *) * count);
    memset((void *)data->srcs, 0, sizeof(void *) * count);

    for (uint32_t i = 0; i < count; i++) {
        lua_rawgeti(L, index, (lua_Integer)i + 1);
        if (lua_type(L, -1) != LUA_TSTRING) {
            lua_pop(L, 1);
            airui_animimg_clear_frames(data);
            return false;
        }

        const char *path = lua_tostring(L, -1);
        char *path_copy = lv_strdup(path);
        lua_pop(L, 1);
        if (path_copy == NULL) {
            airui_animimg_clear_frames(data);
            return false;
        }

        data->owned_paths[i] = path_copy;
        data->srcs[i] = path_copy;
    }

    data->frame_count = (uint16_t)count;
    return true;
}

static int airui_animimg_apply_frames(lv_obj_t *animimg, airui_animimg_data_t *data)
{
    if (animimg == NULL || data == NULL || data->srcs == NULL || data->frame_count == 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (data->reverse) {
        lv_animimg_set_src_reverse(animimg, data->srcs, data->frame_count);
    } else {
        lv_animimg_set_src(animimg, data->srcs, data->frame_count);
    }
    lv_image_set_src(animimg, data->srcs[0]);
    return AIRUI_OK;
}

static void airui_animimg_completed_cb(lv_anim_t *anim)
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

static void airui_animimg_reset_to_first_frame(lv_obj_t *animimg, airui_animimg_data_t *data)
{
    uint16_t frame_index;
    if (animimg == NULL || data == NULL || data->frame_count == 0 || data->srcs == NULL) {
        return;
    }

    frame_index = data->reverse ? (uint16_t)(data->frame_count - 1) : 0;
    if (data->srcs[frame_index] != NULL) {
        lv_image_set_src(animimg, data->srcs[frame_index]);
    }
}

int airui_animimg_play(lv_obj_t *animimg)
{
    airui_animimg_data_t *data;
    lv_anim_t *running_anim;

    if (animimg == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data = airui_animimg_get_data(animimg);
    if (data == NULL || data->frame_count == 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    running_anim = airui_animimg_get_running_anim(animimg);
    if (running_anim == NULL) {
        airui_animimg_reset_to_first_frame(animimg, data);
        lv_animimg_start(animimg);
    } else {
        lv_anim_resume(running_anim);
    }
    return AIRUI_OK;
}

int airui_animimg_pause(lv_obj_t *animimg)
{
    lv_anim_t *anim;
    if (animimg == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    anim = airui_animimg_get_running_anim(animimg);
    if (anim == NULL) {
        return AIRUI_OK;
    }
    lv_anim_pause(anim);
    return AIRUI_OK;
}

int airui_animimg_stop(lv_obj_t *animimg)
{
    lv_anim_t *anim;
    airui_animimg_data_t *data;

    if (animimg == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    anim = airui_animimg_get_running_anim(animimg);
    data = airui_animimg_get_data(animimg);
    if (data == NULL || data->frame_count == 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (anim != NULL) {
        lv_anim_delete(animimg, NULL);
    }

    airui_animimg_reset_to_first_frame(animimg, data);
    return AIRUI_OK;
}

int airui_animimg_set_src(lv_obj_t *animimg, void *L, int idx)
{
    lua_State *L_state = (lua_State *)L;
    airui_animimg_data_t *data;
    airui_component_meta_t *meta;
    airui_ctx_t *ctx;
    bool was_running = false;
    int32_t saved_duration = 0;
    uint32_t saved_repeat_count = 0;
    bool reverse = false;

    if (animimg == NULL || L_state == NULL || !lua_istable(L_state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    meta = airui_component_meta_get(animimg);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data = airui_animimg_get_data(animimg);
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    ctx = airui_animimg_get_ctx(L_state);
    if (ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    saved_duration = (int32_t)lv_animimg_get_duration(animimg);
    saved_repeat_count = lv_animimg_get_repeat_count(animimg);
    reverse = data->reverse;
    if (lua_getfield(L_state, idx, "reverse") != LUA_TNIL) {
        reverse = lua_toboolean(L_state, -1);
    }
    lua_pop(L_state, 1);
    was_running = lv_animimg_delete(animimg);

    airui_animimg_clear_frames(data);
    data->reverse = reverse;

    if (!airui_animimg_store_frames(L_state, idx, data)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    int ret = airui_animimg_apply_frames(animimg, data);
    if (ret == AIRUI_OK) {
        lv_animimg_set_duration(animimg, (uint32_t)saved_duration);
        lv_animimg_set_repeat_count(animimg, saved_repeat_count);

        int complete_ref = meta->callback_refs[AIRUI_EVENT_COMPLETE];
        if (complete_ref != LUA_NOREF) {
            lv_anim_t *anim = lv_animimg_get_anim(animimg);
            if (anim != NULL) {
                lv_anim_set_user_data(anim, meta);
                lv_anim_set_completed_cb(anim, airui_animimg_completed_cb);
            }
        }

        airui_animimg_reset_to_first_frame(animimg, data);
        if (was_running) {
            lv_animimg_start(animimg);
        }
    }
    return ret;
}

int airui_animimg_destroy(lv_obj_t *animimg)
{
    if (animimg == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (!lv_obj_is_valid(animimg)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_delete(animimg);
    return AIRUI_OK;
}
