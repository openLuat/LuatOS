#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "luat_camera.h"
#include "luat_common_api.h"
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

/*
 * fit 在 ingest 路径用软件完成，输出视口大小 RGB565；
 * LVGL 固定 CENTER 做 1:1 显示，避免 contain/stretch 触发 LVGL 全帧软件缩放堵死系统。
 */
typedef enum {
    AIRUI_CAMERA_FIT_CENTER = 0,
    AIRUI_CAMERA_FIT_CONTAIN,
    AIRUI_CAMERA_FIT_COVER,
    AIRUI_CAMERA_FIT_STRETCH,
} airui_camera_fit_t;

typedef struct {
    lv_obj_t *obj;
    lv_timer_t *timer;
    lv_image_dsc_t img_dsc;
    uint8_t *framebuffers[2];
    size_t framebuffer_size;
    uint8_t framebuffer_index;
    volatile bool framebuffer_dirty;
    volatile bool src_pending;
    lv_coord_t requested_width;
    lv_coord_t requested_height;
    uint16_t frame_width;
    uint16_t frame_height;
    int camera_id;
    airui_camera_fit_t fit;

    bool running;
    bool size_checked;
} airui_camera_data_t;

static lv_obj_t *g_airui_camera_target = NULL;

static airui_camera_fit_t airui_camera_parse_fit(const char *fit)
{
    if (fit == NULL || fit[0] == '\0') {
        return AIRUI_CAMERA_FIT_CENTER;
    }
    if (strcmp(fit, "center") == 0) {
        return AIRUI_CAMERA_FIT_CENTER;
    }
    if (strcmp(fit, "contain") == 0) {
        return AIRUI_CAMERA_FIT_CONTAIN;
    }
    if (strcmp(fit, "cover") == 0) {
        return AIRUI_CAMERA_FIT_COVER;
    }
    if (strcmp(fit, "stretch") == 0) {
        return AIRUI_CAMERA_FIT_STRETCH;
    }
    LLOGW("unknown camera fit: %s, fallback to center", fit);
    return AIRUI_CAMERA_FIT_CENTER;
}

static airui_camera_data_t *airui_camera_get_data(lv_obj_t *obj)
{
    airui_component_meta_t *meta = airui_component_meta_get(obj);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }
    return (airui_camera_data_t *)meta->user_data;
}

static void airui_camera_clear_preview_callback(airui_camera_data_t *data)
{
    int camera_id = LUAT_CAMERA_TYPE_USB;

    if (data != NULL) {
        camera_id = data->camera_id;
    }
    luat_camera_set_preview_data_callback(camera_id, NULL, NULL);
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
        airui_camera_clear_preview_callback(data);
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

/*
 * push 路径专用：仅分配缓冲与更新元数据，禁止任何 LVGL API。
 * img_dsc 的最终绑定与 lv_image_set_src 留给 timer。
 */
static int airui_camera_ensure_framebuffer(airui_camera_data_t *data, uint16_t width, uint16_t height)
{
    size_t fb_size;
    uint8_t *new_buf0;
    uint8_t *new_buf1;
    int need_alloc;
    int need_set_src;

    if (data == NULL || width == 0 || height == 0) {
        return -1;
    }

    fb_size = (size_t)width * (size_t)height * 2u;
    if ((fb_size / 2u) != ((size_t)width * (size_t)height)) {
        return -1;
    }

    need_alloc = (data->framebuffers[0] == NULL || data->framebuffers[1] == NULL || data->framebuffer_size != fb_size);
    if (need_alloc) {
        new_buf0 = (uint8_t *)luat_heap_malloc(fb_size);
        if (new_buf0 == NULL) {
            LLOGE("fb0 alloc fail size=%u", (unsigned)fb_size);
            return -1;
        }
        new_buf1 = (uint8_t *)luat_heap_malloc(fb_size);
        if (new_buf1 == NULL) {
            luat_heap_free(new_buf0);
            LLOGE("fb1 alloc fail size=%u", (unsigned)fb_size);
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

    need_set_src = need_alloc ||
                   data->frame_width != width ||
                   data->frame_height != height ||
                   data->img_dsc.data == NULL;

    data->frame_width = width;
    data->frame_height = height;

    /* 预填 dsc 头；data 指针在 timer swap 时再绑定到当前显示缓冲 */
    data->img_dsc.header.magic = LV_IMAGE_HEADER_MAGIC;
    data->img_dsc.header.cf = LV_COLOR_FORMAT_RGB565;
    data->img_dsc.header.w = width;
    data->img_dsc.header.h = height;
    data->img_dsc.header.stride = (uint32_t)width * 2u;
    data->img_dsc.header.flags = 0;
    data->img_dsc.data_size = fb_size;
    data->img_dsc.reserved = NULL;
    data->img_dsc.reserved_2 = NULL;

    if (need_set_src) {
        data->src_pending = true;
    }
    return 0;
}

static void airui_camera_timer_apply_img_dsc(lv_obj_t *camera, airui_camera_data_t *data)
{
    data->img_dsc.data = data->framebuffers[data->framebuffer_index];
    lv_image_set_src(camera, &data->img_dsc);
    data->src_pending = false;
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
        airui_camera_timer_apply_img_dsc(camera, data);
        lv_obj_invalidate(camera);
        data->framebuffer_dirty = false;
    } else if (data->src_pending) {
        /* 首帧分配后尚未 dirty 已处理时，仍需绑定 dsc */
        if (data->framebuffers[data->framebuffer_index] != NULL) {
            airui_camera_timer_apply_img_dsc(camera, data);
            lv_obj_invalidate(camera);
        }
    }
}

/* 最近邻：src(sw×sh) → dst 矩形 out_w×out_h，dst 行跨距为 dst_stride 像素 */
static void airui_camera_rgb565_nn_scale(const uint16_t *src, uint32_t sw, uint32_t sh,
                                        uint16_t *dst, uint32_t dst_stride,
                                        uint32_t out_w, uint32_t out_h)
{
    uint32_t y;
    uint32_t x;

    if (src == NULL || dst == NULL || sw == 0 || sh == 0 || out_w == 0 || out_h == 0) {
        return;
    }

    for (y = 0; y < out_h; y++) {
        uint32_t sy = (y * sh) / out_h;
        const uint16_t *src_row = src + sy * sw;
        uint16_t *dst_row = dst + y * dst_stride;
        for (x = 0; x < out_w; x++) {
            dst_row[x] = src_row[(x * sw) / out_w];
        }
    }
}

/* 从源图裁剪区域最近邻缩放到整个视口 */
static void airui_camera_rgb565_nn_scale_crop(const uint16_t *src, uint32_t sw, uint32_t sh,
                                             uint32_t crop_x, uint32_t crop_y,
                                             uint32_t crop_w, uint32_t crop_h,
                                             uint16_t *dst, uint32_t dw, uint32_t dh)
{
    uint32_t y;
    uint32_t x;

    if (src == NULL || dst == NULL || crop_w == 0 || crop_h == 0 || dw == 0 || dh == 0) {
        return;
    }
    if (crop_x + crop_w > sw || crop_y + crop_h > sh) {
        return;
    }

    for (y = 0; y < dh; y++) {
        uint32_t sy = crop_y + (y * crop_h) / dh;
        const uint16_t *src_row = src + sy * sw + crop_x;
        uint16_t *dst_row = dst + y * dw;
        for (x = 0; x < dw; x++) {
            dst_row[x] = src_row[(x * crop_w) / dw];
        }
    }
}

static int airui_camera_apply_fit(airui_camera_data_t *data,
                                  const uint8_t *rgb565, uint16_t src_w, uint16_t src_h,
                                  uint8_t *dst, uint16_t dst_w, uint16_t dst_h)
{
    const uint16_t *src = (const uint16_t *)rgb565;
    uint16_t *out = (uint16_t *)dst;
    uint32_t crop_w;
    uint32_t crop_h;
    uint32_t cut_x;
    uint32_t cut_y;
    uint32_t out_w;
    uint32_t out_h;
    uint32_t ox;
    uint32_t oy;

    if (data == NULL || src == NULL || out == NULL || src_w == 0 || src_h == 0 || dst_w == 0 || dst_h == 0) {
        return -1;
    }

    switch (data->fit) {
    case AIRUI_CAMERA_FIT_STRETCH:
        airui_camera_rgb565_nn_scale(src, src_w, src_h, out, dst_w, dst_w, dst_h);
        return 0;

    case AIRUI_CAMERA_FIT_CONTAIN:
        if ((uint32_t)src_w * (uint32_t)dst_h > (uint32_t)src_h * (uint32_t)dst_w) {
            out_w = dst_w;
            out_h = ((uint32_t)src_h * (uint32_t)dst_w) / (uint32_t)src_w;
            if (out_h == 0) {
                out_h = 1;
            }
        } else {
            out_h = dst_h;
            out_w = ((uint32_t)src_w * (uint32_t)dst_h) / (uint32_t)src_h;
            if (out_w == 0) {
                out_w = 1;
            }
        }
        if (out_w > dst_w) {
            out_w = dst_w;
        }
        if (out_h > dst_h) {
            out_h = dst_h;
        }
        ox = ((uint32_t)dst_w - out_w) / 2u;
        oy = ((uint32_t)dst_h - out_h) / 2u;
        memset(out, 0, (size_t)dst_w * (size_t)dst_h * 2u);
        airui_camera_rgb565_nn_scale(src, src_w, src_h, out + oy * dst_w + ox, dst_w, out_w, out_h);
        return 0;

    case AIRUI_CAMERA_FIT_COVER:
        /* 取与视口同宽高比的源中心区域，再拉满视口 */
        if ((uint32_t)src_w * (uint32_t)dst_h > (uint32_t)src_h * (uint32_t)dst_w) {
            crop_h = src_h;
            crop_w = ((uint32_t)src_h * (uint32_t)dst_w) / (uint32_t)dst_h;
            if (crop_w == 0) {
                crop_w = 1;
            }
            if (crop_w > src_w) {
                crop_w = src_w;
            }
            cut_x = ((uint32_t)src_w - crop_w) / 2u;
            cut_y = 0;
        } else {
            crop_w = src_w;
            crop_h = ((uint32_t)src_w * (uint32_t)dst_h) / (uint32_t)dst_w;
            if (crop_h == 0) {
                crop_h = 1;
            }
            if (crop_h > src_h) {
                crop_h = src_h;
            }
            cut_x = 0;
            cut_y = ((uint32_t)src_h - crop_h) / 2u;
        }
        if (crop_w == dst_w && crop_h == dst_h) {
            return luat_image_crop(rgb565, 2u, src_w, src_h, dst, dst_w, dst_h, cut_x, cut_y) == LUAT_ERROR_NONE
                       ? 0 : -1;
        }
        airui_camera_rgb565_nn_scale_crop(src, src_w, src_h, cut_x, cut_y, crop_w, crop_h, out, dst_w, dst_h);
        return 0;

    case AIRUI_CAMERA_FIT_CENTER:
    default:
        crop_w = src_w < dst_w ? src_w : dst_w;
        crop_h = src_h < dst_h ? src_h : dst_h;
        cut_x = ((uint32_t)src_w - crop_w) / 2u;
        cut_y = ((uint32_t)src_h - crop_h) / 2u;
        if (crop_w == dst_w && crop_h == dst_h) {
            return luat_image_crop(rgb565, 2u, src_w, src_h, dst, dst_w, dst_h, cut_x, cut_y) == LUAT_ERROR_NONE
                       ? 0 : -1;
        }
        /* 源小于视口：居中贴图，周围填黑 */
        memset(out, 0, (size_t)dst_w * (size_t)dst_h * 2u);
        ox = ((uint32_t)dst_w - crop_w) / 2u;
        oy = ((uint32_t)dst_h - crop_h) / 2u;
        {
            uint32_t row;
            for (row = 0; row < crop_h; row++) {
                memcpy(out + (oy + row) * dst_w + ox,
                       src + (cut_y + row) * src_w + cut_x,
                       (size_t)crop_w * 2u);
            }
        }
        return 0;
    }
}

/*
 * 按 fit 软件生成视口大小 RGB565 写入 next framebuffer。
 * 仅允许在 camera 任务等非 LVGL 线程调用：禁止任何 LVGL API。
 */
static int airui_camera_ingest_rgb565(lv_obj_t *camera, const uint8_t *rgb565, uint16_t src_w, uint16_t src_h)
{
    airui_camera_data_t *data;
    uint8_t *target_buf;
    uint16_t dst_w;
    uint16_t dst_h;

    if (camera == NULL || rgb565 == NULL || src_w == 0 || src_h == 0) {
        return -1;
    }

    data = airui_camera_get_data(camera);
    if (data == NULL || !data->running) {
        return -1;
    }

    /* dirty 未消费：丢帧，避免覆盖等待显示的 next buffer */
    if (data->framebuffer_dirty) {
        return 0;
    }

    dst_w = (data->requested_width > 0) ? (uint16_t)data->requested_width : src_w;
    dst_h = (data->requested_height > 0) ? (uint16_t)data->requested_height : src_h;
    if (dst_w == 0 || dst_h == 0) {
        return -1;
    }

    if (!data->size_checked) {
        data->size_checked = true;
        if (dst_w != src_w || dst_h != src_h) {
            LLOGW("camera: viewport %dx%d, frame %dx%d, fit=%d (software)",
                  (int)dst_w, (int)dst_h, (int)src_w, (int)src_h, (int)data->fit);
        }
    }

    if (airui_camera_ensure_framebuffer(data, dst_w, dst_h) != 0) {
        return -1;
    }

    target_buf = airui_camera_get_next_framebuffer(data);
    if (target_buf == NULL) {
        return -1;
    }

    if (airui_camera_apply_fit(data, rgb565, src_w, src_h, target_buf, dst_w, dst_h) != 0) {
        LLOGE("camera apply fit fail fit=%d src=%ux%u dst=%ux%u",
              (int)data->fit, (unsigned)src_w, (unsigned)src_h,
              (unsigned)dst_w, (unsigned)dst_h);
        return -1;
    }

    /* 先写像素，再置 dirty；LVGL API 仅由 timer 执行 */
    data->framebuffer_dirty = true;
    return 0;
}

int airui_camera_push_frame(lv_obj_t *camera, const uint8_t *rgb565, uint16_t w, uint16_t h)
{
    return airui_camera_ingest_rgb565(camera, rgb565, w, h);
}

static void airui_camera_preview_cb(luat_camera_preview_data_t *preview_data, void *user_data)
{
    lv_obj_t *camera = (lv_obj_t *)user_data;

    if (preview_data == NULL || preview_data->data == NULL) {
        return;
    }
    if (preview_data->data_type != LUAT_CAMERA_PREVIEW_DATA_TYPE_RAW) {
        return;
    }
    if (preview_data->color_bytes != 2u) {
        return;
    }
    if (preview_data->w == 0 || preview_data->h == 0) {
        return;
    }

    if (camera == NULL) {
        camera = g_airui_camera_target;
    }
    if (camera == NULL) {
        return;
    }

    /* 禁止释放 preview_data->data：缓冲归底层 jpeg out buffer 所有 */
    (void)airui_camera_ingest_rgb565(camera,
                                     (const uint8_t *)preview_data->data,
                                     (uint16_t)preview_data->w,
                                     (uint16_t)preview_data->h);
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
    const char *fit;

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
    fit = airui_marshal_string(L, idx, "fit", NULL);

    camera = lv_image_create(parent);
    if (camera == NULL) {
        return NULL;
    }

    lv_obj_set_pos(camera,
        airui_marshal_floor_integer(L, idx, "x", 0),
        airui_marshal_floor_integer(L, idx, "y", 0));
    lv_obj_set_size(camera, requested_width, requested_height);
    /* fit 已在 ingest 烘焙进像素，LVGL 只做 1:1 */
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
    data->camera_id = (int)airui_marshal_floor_integer(L, idx, "camera_id", LUAT_CAMERA_TYPE_USB);
    data->fit = airui_camera_parse_fit(fit);

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
        airui_camera_register_target(camera);
    }

    return camera;
}

int airui_camera_set_fit(lv_obj_t *camera, const char *fit)
{
    airui_camera_data_t *data;

    if (camera == NULL) {
        return -1;
    }

    data = airui_camera_get_data(camera);
    if (data == NULL) {
        return -1;
    }

    data->fit = airui_camera_parse_fit(fit);
    lv_image_set_inner_align(camera, LV_IMAGE_ALIGN_CENTER);
    return 0;
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
    airui_camera_data_t *data;

    if (camera == NULL) {
        return;
    }

    data = airui_camera_get_data(camera);
    if (data == NULL) {
        return;
    }

    /* 切换目标时先卸掉旧回调，避免指向已销毁对象 */
    if (g_airui_camera_target != NULL && g_airui_camera_target != camera) {
        airui_camera_data_t *old_data = airui_camera_get_data(g_airui_camera_target);
        airui_camera_clear_preview_callback(old_data);
    }

    g_airui_camera_target = camera;
    luat_camera_set_preview_data_callback(data->camera_id, airui_camera_preview_cb, camera);
}

void airui_camera_unregister_target(void)
{
    airui_camera_data_t *data = NULL;

    if (g_airui_camera_target != NULL) {
        data = airui_camera_get_data(g_airui_camera_target);
    }
    g_airui_camera_target = NULL;
    airui_camera_clear_preview_callback(data);
}

lv_obj_t *airui_camera_get_target(void)
{
    return g_airui_camera_target;
}

#endif /* AIRUI_USE_CAMERA */
