#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_timer.h"
#include "lvgl9/src/widgets/image/lv_image.h"
#include <stdint.h>
#include <string.h>

#define LUAT_LOG_TAG "airui.camera"
#include "luat_log.h"

#if AIRUI_USE_CAMERA

typedef struct {
    lv_obj_t *obj;
    lv_timer_t *timer;
    lv_image_dsc_t img_dsc;
    uint8_t *framebuffers[2];
    size_t framebuffer_size;
    uint8_t framebuffer_index;
    bool framebuffer_dirty;
    lv_coord_t requested_width;
    lv_coord_t requested_height;
    uint16_t frame_width;
    uint16_t frame_height;

    bool running;
    bool size_checked;
} airui_camera_data_t;

static lv_obj_t *g_airui_camera_target = NULL;

static airui_camera_data_t *airui_camera_get_data(lv_obj_t *obj)
{
    airui_component_meta_t *meta = airui_component_meta_get(obj);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }
    return (airui_camera_data_t *)meta->user_data;
}

static void airui_camera_release_data(void *user_data)
{
    airui_camera_data_t *data = (airui_camera_data_t *)user_data;
    if (data == NULL) {
        return;
    }

    data->running = false;

    if (g_airui_camera_target == data->obj) {
        g_airui_camera_target = NULL;
    }

    if (data->timer != NULL) {
        lv_timer_delete(data->timer);
        data->timer = NULL;
    }

    if (data->framebuffers[0] != NULL) {
        luat_heap_free(data->framebuffers[0]);
        data->framebuffers[0] = NULL;
    }
    if (data->framebuffers[1] != NULL) {
        luat_heap_free(data->framebuffers[1]);
        data->framebuffers[1] = NULL;
    }

    luat_heap_free(data);
}

static uint8_t *airui_camera_get_next_framebuffer(airui_camera_data_t *data)
{
    if (data == NULL) {
        return NULL;
    }
    return data->framebuffers[(data->framebuffer_index + 1u) & 0x1u];
}

static int airui_camera_ensure_framebuffer(lv_obj_t *camera, airui_camera_data_t *data, uint16_t width, uint16_t height)
{
    size_t fb_size;
    uint8_t *new_buf0;
    uint8_t *new_buf1;

    if (camera == NULL || data == NULL || width == 0 || height == 0) {
        return -1;
    }

    fb_size = (size_t)width * (size_t)height * 2u;
    if ((fb_size / 2u) != ((size_t)width * (size_t)height)) {
        return -1;
    }

    if (data->framebuffers[0] == NULL || data->framebuffers[1] == NULL || data->framebuffer_size != fb_size) {
        new_buf0 = (uint8_t *)luat_heap_malloc(fb_size);
        if (new_buf0 == NULL) {
            return -1;
        }
        new_buf1 = (uint8_t *)luat_heap_malloc(fb_size);
        if (new_buf1 == NULL) {
            luat_heap_free(new_buf0);
            return -1;
        }
        if (data->framebuffers[0] != NULL) {
            luat_heap_free(data->framebuffers[0]);
        }
        if (data->framebuffers[1] != NULL) {
            luat_heap_free(data->framebuffers[1]);
        }
        data->framebuffers[0] = new_buf0;
        data->framebuffers[1] = new_buf1;
        data->framebuffer_size = fb_size;
        data->framebuffer_index = 0;
    }

    data->frame_width = width;
    data->frame_height = height;
    data->img_dsc.header.magic = LV_IMAGE_HEADER_MAGIC;
    data->img_dsc.header.cf = LV_COLOR_FORMAT_RGB565;
    data->img_dsc.header.w = width;
    data->img_dsc.header.h = height;
    data->img_dsc.header.stride = (uint32_t)width * 2u;
    data->img_dsc.header.flags = 0;
    data->img_dsc.data_size = fb_size;
    data->img_dsc.data = data->framebuffers[data->framebuffer_index];
    data->img_dsc.reserved = NULL;
    data->img_dsc.reserved_2 = NULL;

    lv_image_set_src(camera, &data->img_dsc);
    return 0;
}

static void airui_camera_timer_cb(lv_timer_t *timer)
{
    lv_obj_t *camera;
    airui_camera_data_t *data;

    if (timer == NULL) {
        return;
    }

    camera = (lv_obj_t *)lv_timer_get_user_data(timer);
    if (camera == NULL) {
        lv_timer_delete(timer);
        return;
    }

    data = airui_camera_get_data(camera);
    if (data == NULL || data->timer != timer || !data->running) {
        return;
    }

    if (data->framebuffer_dirty) {
        data->framebuffer_index = (uint8_t)((data->framebuffer_index + 1u) & 0x1u);
        data->img_dsc.data = data->framebuffers[data->framebuffer_index];
        lv_image_set_src(camera, &data->img_dsc);
        lv_obj_invalidate(camera);
        data->framebuffer_dirty = false;
    }
}

int airui_camera_push_frame(lv_obj_t *camera, const uint8_t *rgb565, uint16_t w, uint16_t h)
{
    airui_camera_data_t *data;
    uint8_t *target_buf;

    if (camera == NULL || rgb565 == NULL || w == 0 || h == 0) {
        return -1;
    }

    data = airui_camera_get_data(camera);
    if (data == NULL || !data->running) {
        return -1;
    }

    if (!data->size_checked) {
        data->size_checked = true;
        if (data->requested_width != (lv_coord_t)w || data->requested_height != (lv_coord_t)h) {
            LLOGW("camera: size mismatch, requested=%dx%d actual=%dx%d",
                  (int)data->requested_width, (int)data->requested_height, (int)w, (int)h);
            lv_obj_set_size(camera, (lv_coord_t)w, (lv_coord_t)h);
        }
    }

    if (airui_camera_ensure_framebuffer(camera, data, w, h) != 0) {
        return -1;
    }

    target_buf = airui_camera_get_next_framebuffer(data);
    if (target_buf == NULL) {
        return -1;
    }

    if (rgb565 != target_buf) {
        memcpy(target_buf, rgb565, data->framebuffer_size);
    }

    data->framebuffer_dirty = true;
    return 0;
}

static airui_ctx_t *airui_camera_get_ctx(lua_State *L_state)
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

lv_obj_t *airui_camera_create_from_config(void *L, int idx)
{
    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx;
    lv_obj_t *parent;
    lv_obj_t *camera;
    airui_component_meta_t *meta;
    airui_camera_data_t *data;
    lv_coord_t requested_width;
    lv_coord_t requested_height;

    if (L_state == NULL) {
        return NULL;
    }

    ctx = airui_camera_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    parent = airui_marshal_parent(L, idx);
    requested_width = (lv_coord_t)airui_marshal_floor_integer(L, idx, "w", 320);
    requested_height = (lv_coord_t)airui_marshal_floor_integer(L, idx, "h", 240);

    camera = lv_image_create(parent);
    if (camera == NULL) {
        return NULL;
    }

    lv_obj_set_pos(camera,
        airui_marshal_floor_integer(L, idx, "x", 0),
        airui_marshal_floor_integer(L, idx, "y", 0));
    lv_obj_set_size(camera, requested_width, requested_height);
    lv_image_set_inner_align(camera, LV_IMAGE_ALIGN_CENTER);

    meta = airui_component_meta_alloc(ctx, camera, AIRUI_COMPONENT_CAMERA);
    if (meta == NULL) {
        lv_obj_delete(camera);
        return NULL;
    }

    data = (airui_camera_data_t *)luat_heap_malloc(sizeof(airui_camera_data_t));
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(camera);
        return NULL;
    }
    memset(data, 0, sizeof(airui_camera_data_t));

    data->obj = camera;
    data->requested_width = requested_width;
    data->requested_height = requested_height;

    airui_component_meta_set_user_data(meta, data, airui_camera_release_data);

    data->timer = lv_timer_create(airui_camera_timer_cb, LV_DEF_REFR_PERIOD, camera);
    if (data->timer == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(camera);
        return NULL;
    }
    lv_timer_pause(data->timer);

    if (airui_marshal_bool(L, idx, "auto_start", false)) {
        data->running = true;
        lv_timer_resume(data->timer);
    }

    if (airui_marshal_bool(L, idx, "register_target", true)) {
        g_airui_camera_target = camera;
    }

    return camera;
}

int airui_camera_start(lv_obj_t *camera)
{
    airui_camera_data_t *data;

    if (camera == NULL) {
        return -1;
    }

    data = airui_camera_get_data(camera);
    if (data == NULL || data->timer == NULL) {
        return -1;
    }

    data->running = true;
    lv_timer_resume(data->timer);
    return 0;
}

int airui_camera_stop(lv_obj_t *camera)
{
    airui_camera_data_t *data;

    if (camera == NULL) {
        return -1;
    }

    data = airui_camera_get_data(camera);
    if (data == NULL || data->timer == NULL) {
        return -1;
    }

    data->running = false;
    lv_timer_pause(data->timer);
    return 0;
}

int airui_camera_destroy(lv_obj_t *camera)
{
    if (camera == NULL) {
        return -1;
    }

    if (!lv_obj_is_valid(camera)) {
        return -1;
    }

    lv_obj_delete(camera);
    return 0;
}

void airui_camera_register_target(lv_obj_t *camera)
{
    g_airui_camera_target = camera;
}

void airui_camera_unregister_target(void)
{
    g_airui_camera_target = NULL;
}

lv_obj_t *airui_camera_get_target(void)
{
    return g_airui_camera_target;
}

#endif /* AIRUI_USE_CAMERA */
