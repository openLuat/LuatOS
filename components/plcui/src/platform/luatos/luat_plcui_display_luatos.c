/** @file luat_plcui_display_luatos.c RGB565 PARTIAL rendering to display FBs. */
#include "luat_conf_bsp.h"
#if defined(LUAT_USE_PLCUI_LUATOS)

#include "luat_plcui_luatos.h"
#include "luat_plcui_conf.h"
#include "luat_display.h"
#include <string.h>

#define LUAT_LOG_TAG "plcui.display"
#include "luat_log.h"

static struct {
    struct luat_display *device;
    lv_display_t *display;
    uint32_t front;
    uint8_t frame_open;
    uint8_t failed;
    uint8_t redraw;
} state;

static void fail_frame(void)
{
    state.failed = 1;
    state.redraw = 1;
    state.device->fb_info->fb_index = state.front;
}

static int copy_rect(struct luat_display_rect *rect, const void *pixels, uint32_t stride)
{
    struct luat_display_fb_info *info = state.device->fb_info;
    uint32_t saved_stride = info->stride;
    info->stride = stride;
    int result = state.device->display_funcs->fb_flush(state.device, rect, pixels, LUAT_DISPLAY_ROTATE_0);
    info->stride = saved_stride;
    return result;
}

static void display_flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    struct luat_display_fb_info *info = state.device->fb_info;
    struct luat_display_rect rect = {area->x1, area->y1,
                                     area->x2 - area->x1 + 1, area->y2 - area->y1 + 1};
    int last = lv_display_flush_is_last(display);
    lv_draw_buf_t *buffer = lv_display_get_buf_active(display);

    if (!state.frame_open) {
        state.frame_open = 1;
        state.failed = 0;
        info->fb_index = (state.front + 1U) % info->fb_count;
        int whole = rect.x == 0 && rect.y == 0 &&
                    rect.w == (int32_t)info->width && rect.h == (int32_t)info->height;
        if (!whole) {
            struct luat_display_rect all = {0, 0, (int32_t)info->width, (int32_t)info->height};
            const uint8_t *front = (const uint8_t *)info->fb_start + (size_t)state.front * info->fb_size;
            if (copy_rect(&all, front, info->width * 2U) != 0) fail_frame();
        }
    }

    if (!state.failed) {
        if (!pixels || !buffer || rect.x < 0 || rect.y < 0 || rect.w <= 0 || rect.h <= 0 ||
            (uint64_t)rect.x + (uint32_t)rect.w > info->width ||
            (uint64_t)rect.y + (uint32_t)rect.h > info->height ||
            buffer->header.stride < (uint32_t)rect.w * 2U ||
            (uint64_t)buffer->header.stride * (uint32_t)rect.h > buffer->data_size ||
            copy_rect(&rect, pixels, buffer->header.stride) != 0) {
            fail_frame();
        }
    }

    if (last) {
        if (!state.failed) {
            if (state.device->display_funcs->pan_display(state.device, (int)info->fb_index) != 0) {
                fail_frame();
            } else {
                state.front = info->fb_index;
            }
        }
        if (state.failed) LLOGE("display copy/pan failed; retaining front buffer %u", state.front);
        state.frame_open = 0;
    }
    /* The SDK fb_flush contract is synchronous: DMA has stopped using pixels. */
    lv_display_flush_ready(display);
}

int plcui_luatos_display_init(int width, int height)
{
    if (state.display || width < 1 || height < 1 || width > 1024 || height > 600) return -1;
    struct luat_display *device = luat_display_get_by_id(0);
    if (!device || !device->panel || device->panel->connector_type != LUAT_DISPLAY_CONNECTOR_RGB ||
        !device->panel->screen_win || device->panel->screen_win->w != width ||
        device->panel->screen_win->h != height || device->rotation != LUAT_DISPLAY_ROTATE_0 ||
        !device->fb_info || !device->display_funcs || !device->display_funcs->fb_flush ||
        !device->display_funcs->pan_display) {
        LLOGE("initialize a matching RGB display before plcui.init");
        return -1;
    }
    struct luat_display_fb_info *info = device->fb_info;
    struct luat_display_buf *draw = &info->draw_buf;
    uint64_t frame_bytes = (uint64_t)(uint32_t)width * (uint32_t)height * 2U;
    uint32_t lv_stride = lv_draw_buf_width_to_stride((uint32_t)width, LV_COLOR_FORMAT_RGB565);
    if (info->width != (uint32_t)width || info->height != (uint32_t)height ||
        info->format != LUAT_DISPLAY_FORMAT_RGB565 || info->bits_per_pixel != 16U ||
        !info->fb_start || ((uintptr_t)info->fb_start & 7U) ||
        info->fb_size < frame_bytes || (info->fb_size & 7U) || info->fb_count < 2U ||
        info->fb_index >= info->fb_count || info->stride != (uint32_t)width * 2U ||
        !draw->buffer || ((uintptr_t)draw->buffer & 7U) || draw->count < 1U ||
        draw->format != LUAT_DISPLAY_FORMAT_RGB565 || draw->width != (uint32_t)width ||
        draw->height < (uint32_t)height || draw->stride != lv_stride ||
        (uint64_t)lv_stride * (uint32_t)height > draw->size) {
        LLOGE("invalid RGB565 scan/draw buffers");
        return -1;
    }

    lv_display_t *display = lv_display_create(width, height);
    if (!display) return -1;
    memset(&state, 0, sizeof(state));
    state.device = device;
    state.display = display;
    state.front = info->fb_index;
    lv_display_set_default(display);
    lv_display_set_color_format(display, LV_COLOR_FORMAT_RGB565);
    lv_display_set_buffers(display, draw->buffer, NULL, draw->size, LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(display, display_flush);
    lv_timer_set_period(lv_display_get_refr_timer(display), PLCUI_REFRESH_PERIOD_MS);
    LLOGI("RGB565 %dx%d draw=%u scan=%u cache=%u", width, height,
          draw->size, info->fb_count, (unsigned)LV_CACHE_DEF_SIZE);
    return 0;
}

void plcui_luatos_display_poll(void)
{
    if (state.display && state.redraw && !state.frame_open) {
        state.redraw = 0;
        lv_obj_invalidate(lv_display_get_screen_active(state.display));
    }
}

lv_display_t *plcui_luatos_display(void)
{
    return state.display;
}

void plcui_luatos_display_deinit(void)
{
    if (state.device && state.frame_open) state.device->fb_info->fb_index = state.front;
    if (state.display) lv_display_delete(state.display);
    /* All scan and draw allocations remain owned by the display library. */
    memset(&state, 0, sizeof(state));
}

#endif
