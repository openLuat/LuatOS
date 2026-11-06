#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_sdl2.h"
#include "luat_display_if_comm.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include <string.h>

#define LUAT_LOG_TAG "display_sdl"
#include "luat_log.h"

/*本地用户数据，用于登记信息用的*/
struct sdl_disp_userdata {
    luat_display_sdl2_ctx_t *ctx;
    void *draw_buf;
    /*SDL后端虚拟图层*/
    struct luat_display_layer_data v_layer[2];
};

/* 视频层。layer_id 0 是 UI 层，不叠到画面上。 */
static struct luat_display_layer_data s_video_layer;

/* 模拟真实屏幕的持续扫描, 定时器在 sdl_set_layer 里按视频层开关启停 */
static luat_rtos_timer_t s_video_scan_timer = NULL;
static uint8_t s_video_scan_posted = 0;
static uint8_t s_video_scan_running = 0;

/* 有的生产者(mplayer)整段播放复用同一块缓冲, 有的(videoplayer)每帧换缓冲并在下一帧释放旧的。
 * 检测到缓冲指针变化后切换到拷贝模式, 把每帧拷进后端自有的稳定缓冲, 异步扫描就不会读到已释放内存。*/
static uint8_t *s_video_own_buf = NULL;
static size_t s_video_own_size = 0;
static uint8_t s_video_copy_mode = 0;
static luat_rtos_mutex_t s_video_lock = NULL;

static void sdl_video_scan_stop(void);
static int sdl_video_lock(void);
static void sdl_video_unlock(void);

static int sdl_deinit(struct luat_display *disp)
{
    if (disp == NULL || disp->userdata == NULL) {
        return 0;
    }

    struct sdl_disp_userdata *ud = (struct sdl_disp_userdata *)disp->userdata;

    sdl_video_scan_stop();
    if (s_video_scan_timer != NULL) {
        luat_rtos_timer_delete(s_video_scan_timer);
        s_video_scan_timer = NULL;
    }
    sdl_video_lock();
    memset(&s_video_layer, 0, sizeof(s_video_layer));
    if (s_video_own_buf != NULL) {
        luat_heap_free(s_video_own_buf);
        s_video_own_buf = NULL;
    }
    s_video_own_size = 0;
    s_video_copy_mode = 0;
    sdl_video_unlock();
    if (s_video_lock != NULL) {
        luat_rtos_mutex_delete(s_video_lock);
        s_video_lock = NULL;
    }

    if (ud->ctx != NULL) {
        luat_display_sdl2_destroy(ud->ctx);
        ud->ctx = NULL;
    }
    if (ud->draw_buf != NULL) {
        luat_heap_free(ud->draw_buf);
        ud->draw_buf = NULL;
    }

    luat_heap_free(ud);
    disp->userdata = NULL;

    return 0;
}

/*探测显示缓冲区*/
static int sdl_fb_probe(struct luat_display_panel *panel, struct luat_display_fb_info *info)
{
    if (panel == NULL || panel->screen_win == NULL || info == NULL) {
        return -1;
    }

    info->width = panel->screen_win->w;
    info->height = panel->screen_win->h;

    /*SDL2 纹理使用 RGB565 格式，与 PC 模拟器常用配置保持一致*/
    info->format = LUAT_DISPLAY_FORMAT_RGB565;
    info->bits_per_pixel = 16;
    info->stride = info->width * 2;

    /*SDL2 framebuffer 由 SDL 纹理托管，不对外暴露 CPU 可写地址*/
    info->fb_start = NULL;
    info->fb_size = 0;
    info->fb_count = 1;

    return 0;
}

/*初始化接口，在这里创建 SDL2 窗口*/
static int sdl_inf_init(struct luat_display *disp)
{
    if (disp == NULL || disp->panel == NULL || disp->panel->screen_win == NULL) {
        return -1;
    }

    struct luat_display_panel *panel = disp->panel;
    struct luat_display_fb_info *info = disp->fb_info;

    if (info == NULL) {
        LLOGE("sdl2 fb_info not ready");
        return -1;
    }

    /*分配 userdata，用于管理该 display 实例的 SDL 上下文和 draw buffer*/
    struct sdl_disp_userdata *ud = luat_heap_zalloc(sizeof(struct sdl_disp_userdata));
    if (ud == NULL) {
        LLOGE("sdl2 userdata alloc failed");
        return -1;
    }

    if (s_video_lock == NULL) {
        if (luat_rtos_mutex_create(&s_video_lock) != 0) {
            s_video_lock = NULL;
            LLOGE("sdl2 video lock create failed");
            luat_heap_free(ud);
            return -1;
        }
    }

    /*分配 CPU 可写 draw buffer*/
    uint32_t draw_buf_size = info->width * info->height * 2;
    ud->draw_buf = luat_heap_zalloc(draw_buf_size);
    if (ud->draw_buf == NULL) {
        LLOGE("sdl2 draw buffer alloc failed");
        luat_heap_free(ud);
        return -1;
    }

    /*创建 SDL2 窗口*/
    ud->ctx = luat_display_sdl2_create(panel->name,
                                       panel->screen_win->w,
                                       panel->screen_win->h);
    if (ud->ctx == NULL) {
        LLOGE("sdl2 display create failed");
        luat_heap_free(ud->draw_buf);
        luat_heap_free(ud);
        return -1;
    }

    /*填充 draw_buf 信息*/
    info->draw_buf.buffer = ud->draw_buf;
    info->draw_buf.size = draw_buf_size;
    info->draw_buf.stride = info->stride;
    info->draw_buf.count = 1;
    info->draw_buf.format = info->format;
    info->draw_buf.width = info->width;
    info->draw_buf.height = info->height;

    disp->userdata = ud;

    return 0;
}

static struct sdl_disp_userdata *sdl_ud(struct luat_display *disp)
{
    if (disp == NULL || disp->userdata == NULL) {
        return NULL;
    }
    return (struct sdl_disp_userdata *)disp->userdata;
}

static void shadow_copy(struct luat_display *disp, struct sdl_disp_userdata *ud,
                        int x, int y, int w, int h, const void *data, uint32_t pitch)
{
    uint8_t *dst;
    const uint8_t *src;
    uint32_t dst_pitch;
    int row;

    if (ud == NULL || ud->draw_buf == NULL || disp->fb_info == NULL || data == NULL || w <= 0 || h <= 0) {
        return;
    }
    if (x < 0 || y < 0) {
        return;
    }
    dst_pitch = disp->fb_info->width * 2U;
    if ((uint32_t)(x + w) > disp->fb_info->width || (uint32_t)(y + h) > disp->fb_info->height) {
        return;
    }
    if (pitch == 0U) {
        pitch = (uint32_t)w * 2U;
    }
    dst = (uint8_t *)ud->draw_buf;
    src = (const uint8_t *)data;
    for (row = 0; row < h; row++) {
        memcpy(dst + (size_t)(y + row) * dst_pitch + (size_t)x * 2U,
               src + (size_t)row * pitch,
               (size_t)w * 2U);
    }
}

static void blit_video(struct luat_display *disp, struct sdl_disp_userdata *ud)
{
    int x;
    int y;
    int w;
    int h;

    if (!s_video_layer.enable || s_video_layer.buffer == NULL || ud == NULL || ud->ctx == NULL) {
        return;
    }
    if (s_video_layer.format != LUAT_DISPLAY_FORMAT_RGB565) {
        return;
    }
    x = (int)s_video_layer.area.x1;
    y = (int)s_video_layer.area.y1;
    w = (int)(s_video_layer.area.x2 - s_video_layer.area.x1);
    h = (int)(s_video_layer.area.y2 - s_video_layer.area.y1);
    if (w <= 0 || h <= 0 || disp->fb_info == NULL) {
        return;
    }
    if (x < 0 || y < 0 ||
        (uint32_t)(x + w) > disp->fb_info->width ||
        (uint32_t)(y + h) > disp->fb_info->height) {
        return;
    }
    luat_display_sdl2_draw(ud->ctx, (int16_t)x, (int16_t)y, (uint16_t)w, (uint16_t)h,
                           s_video_layer.buffer, (uint32_t)w * 2U);
}

static void restore_video_rect(struct luat_display *disp, struct sdl_disp_userdata *ud)
{
    int x;
    int y;
    int w;
    int h;
    uint32_t pitch;
    uint8_t *src;

    if (!s_video_layer.enable || ud == NULL || ud->ctx == NULL || ud->draw_buf == NULL || disp->fb_info == NULL) {
        return;
    }
    x = (int)s_video_layer.area.x1;
    y = (int)s_video_layer.area.y1;
    w = (int)(s_video_layer.area.x2 - s_video_layer.area.x1);
    h = (int)(s_video_layer.area.y2 - s_video_layer.area.y1);
    if (w <= 0 || h <= 0) {
        return;
    }
    pitch = disp->fb_info->width * 2U;
    src = (uint8_t *)ud->draw_buf + (size_t)y * pitch + (size_t)x * 2U;
    luat_display_sdl2_draw(ud->ctx, (int16_t)x, (int16_t)y, (uint16_t)w, (uint16_t)h, src, pitch);
}

/* 模拟真实屏幕的持续扫描: 视频层启用后按刷新周期把图层贴回窗口。
 * 定时器回调在 timer 线程, 通过 msgbus 投递到主线程执行, 避免跨线程操作 SDL。*/
#define SDL_VIDEO_SCAN_PERIOD_MS 16

static int sdl_video_lock(void)
{
    if (s_video_lock == NULL) {
        return -1;
    }
    return luat_rtos_mutex_lock(s_video_lock, LUAT_WAIT_FOREVER);
}

static void sdl_video_unlock(void)
{
    if (s_video_lock != NULL) {
        luat_rtos_mutex_unlock(s_video_lock);
    }
}

/*把生产者的一帧拷进后端自有缓冲。调用方需持有 s_video_lock。*/
static int sdl_video_copy_frame(struct luat_display_layer_data *layer)
{
    int w;
    int h;
    int row;
    uint32_t src_pitch;
    uint8_t *dst;
    size_t need;

    if (layer == NULL || layer->buffer == NULL) {
        return -1;
    }
    w = (int)(layer->area.x2 - layer->area.x1);
    h = (int)(layer->area.y2 - layer->area.y1);
    if (w <= 0 || h <= 0) {
        return -1;
    }
    need = (size_t)w * (size_t)h * 2U;
    if (s_video_own_size < need) {
        uint8_t *buf = luat_heap_malloc(need);
        if (buf == NULL) {
            LLOGW("video layer copy buffer alloc failed, %u bytes", (unsigned int)need);
            return -1;
        }
        if (s_video_own_buf != NULL) {
            luat_heap_free(s_video_own_buf);
        }
        s_video_own_buf = buf;
        s_video_own_size = need;
    }
    src_pitch = layer->stride ? layer->stride : (uint32_t)w * 2U;
    dst = s_video_own_buf;
    for (row = 0; row < h; row++) {
        memcpy(dst + (size_t)row * (size_t)w * 2U,
               (uint8_t *)layer->buffer + (size_t)row * src_pitch,
               (size_t)w * 2U);
    }
    return 0;
}

/*需持有 s_video_lock: 视频层开着就先叠到纹理上, 再送显。
 * 所有送显路径都必须走这里, 否则只呈现 UI 纹理会把视频区域盖掉。*/
static void sdl_present_locked(struct luat_display *disp, struct sdl_disp_userdata *ud)
{
    if (disp == NULL || ud == NULL || ud->ctx == NULL) {
        return;
    }
    if (s_video_layer.enable) {
        blit_video(disp, ud);
    }
    luat_display_sdl2_flush(ud->ctx);
}

/*主线程执行: 把视频层叠到 SDL 纹理并送显*/
static void sdl_video_present(void)
{
    struct luat_display *disp;
    struct sdl_disp_userdata *ud;

    if (sdl_video_lock() != 0) {
        return;
    }
    if (s_video_layer.enable) {
        disp = luat_display_get_default();
        ud = sdl_ud(disp);
        sdl_present_locked(disp, ud);
    }
    sdl_video_unlock();
}

static int sdl_video_scan_msg_handler(lua_State *L, void *ptr)
{
    (void)L;
    (void)ptr;
    s_video_scan_posted = 0;
    sdl_video_present();
    return 0;
}

static void sdl_video_scan_timer_cb(LUAT_RT_CB_PARAM)
{
    (void)param;
    rtos_msg_t msg;

    if (s_video_scan_posted) {
        return;
    }
    msg.handler = sdl_video_scan_msg_handler;
    msg.ptr = NULL;
    msg.arg1 = 0;
    msg.arg2 = 0;
    if (luat_msgbus_put(&msg, 0) == 0) {
        s_video_scan_posted = 1;
    }
}

static void sdl_video_scan_start(void)
{
    if (s_video_scan_running) {
        return;
    }
    if (s_video_scan_timer == NULL) {
        if (luat_rtos_timer_create(&s_video_scan_timer) != 0) {
            s_video_scan_timer = NULL;
            LLOGW("create video scan timer failed");
            return;
        }
    }
    s_video_scan_posted = 0;
    if (luat_rtos_timer_start(s_video_scan_timer, SDL_VIDEO_SCAN_PERIOD_MS, 1, sdl_video_scan_timer_cb, NULL) == 0) {
        s_video_scan_running = 1;
    }
}

static void sdl_video_scan_stop(void)
{
    if (s_video_scan_timer != NULL) {
        luat_rtos_timer_stop(s_video_scan_timer);
    }
    s_video_scan_posted = 0;
    s_video_scan_running = 0;
}

/*设置显示层。UI 层只记录，视频层叠到 SDL 纹理上。*/
static int sdl_set_layer(struct luat_display_layer_data *layer_data)
{
    struct luat_display *disp;
    struct sdl_disp_userdata *ud;

    if (layer_data == NULL) {
        return -1;
    }
    if (layer_data->layer_id == LUAT_DISPLAY_LAYER_UI) {
        return 0;
    }

    disp = luat_display_get_default();
    ud = sdl_ud(disp);

    if (sdl_video_lock() != 0) {
        return -1;
    }

    if (!layer_data->enable) {
        sdl_video_scan_stop();
        if (ud != NULL && ud->ctx != NULL) {
            restore_video_rect(disp, ud);
            luat_display_sdl2_flush(ud->ctx);
        }
        memset(&s_video_layer, 0, sizeof(s_video_layer));
        s_video_copy_mode = 0;
        sdl_video_unlock();
        return 0;
    }

    /*生产者换了缓冲, 说明它不会复用同一块内存, 之后每帧都拷贝到自有缓冲*/
    if (s_video_layer.buffer != NULL && layer_data->buffer != s_video_layer.buffer) {
        s_video_copy_mode = 1;
    }

    if (s_video_copy_mode && sdl_video_copy_frame(layer_data) == 0) {
        s_video_layer = *layer_data;
        s_video_layer.buffer = s_video_own_buf;
        s_video_layer.stride = (uint32_t)(layer_data->area.x2 - layer_data->area.x1) * 2U;
    }
    else {
        s_video_layer = *layer_data;
    }

    sdl_present_locked(disp, ud);
    sdl_video_scan_start();
    sdl_video_unlock();
    return 0;
}

static void *sdl_native(struct luat_display *disp, int which)
{
    struct sdl_disp_userdata *ud = sdl_ud(disp);
    if (ud == NULL || ud->ctx == NULL) {
        return NULL;
    }
    if (which == 0) {
        return ud->ctx->window;
    }
    if (which == 1) {
        return ud->ctx->renderer;
    }
    return ud->ctx->texture;
}

void *luat_display_sdl_get_window(struct luat_display *disp)
{
    return sdl_native(disp, 0);
}

void *luat_display_sdl_get_renderer(struct luat_display *disp)
{
    return sdl_native(disp, 1);
}

void *luat_display_sdl_get_texture(struct luat_display *disp)
{
    return sdl_native(disp, 2);
}

int luat_display_sdl_blit(struct luat_display *disp, int32_t x, int32_t y, int32_t w, int32_t h,
                          const void *data, uint32_t pitch, int present)
{
    struct sdl_disp_userdata *ud;

    if (disp == NULL || data == NULL || w <= 0 || h <= 0) {
        return -1;
    }
    ud = sdl_ud(disp);
    if (ud == NULL || ud->ctx == NULL) {
        return -1;
    }
    if (pitch == 0U) {
        pitch = (uint32_t)w * 2U;
    }
    if (sdl_video_lock() != 0) {
        return -1;
    }
    shadow_copy(disp, ud, (int)x, (int)y, (int)w, (int)h, data, pitch);
    luat_display_sdl2_draw(ud->ctx, (int16_t)x, (int16_t)y, (uint16_t)w, (uint16_t)h, data, pitch);
    if (present) {
        sdl_present_locked(disp, ud);
    }
    sdl_video_unlock();
    return 0;
}

/*刷新显示缓冲区*/
static int sdl_fb_flush(struct luat_display *disp, struct luat_display_rect *rect, const void *data, enum disp_rotate rotation)
{
    (void)rotation;
    if (rect == NULL) {
        return 0;
    }
    return luat_display_sdl_blit(disp, rect->x, rect->y, rect->w, rect->h, data, (uint32_t)rect->w * 2U, 1);
}

static int sdl_wait_vsync(struct luat_display *disp)
{
    if (disp == NULL || disp->userdata == NULL) {
        return 0;
    }

    struct sdl_disp_userdata *ud = (struct sdl_disp_userdata *)disp->userdata;
    if (ud->ctx != NULL) {
        luat_display_sdl2_pump_events(ud->ctx);
    }
    return 0;
}

static int sdl_pan_display(struct luat_display *disp, int index)
{
    if (disp == NULL || disp->userdata == NULL) {
        return 0;
    }

    struct sdl_disp_userdata *ud = (struct sdl_disp_userdata *)disp->userdata;
    if (ud->ctx != NULL) {
        if (sdl_video_lock() == 0) {
            sdl_present_locked(disp, ud);
            sdl_video_unlock();
        }
        luat_display_sdl2_pump_events(ud->ctx);
    }
    return 0;
}

struct luat_display_funcs sdl_funcs = {
    .name = "sdl",
    .fb_probe = sdl_fb_probe,
    .inf_init = sdl_inf_init,
    .fb_flush = sdl_fb_flush,
    .set_layer = sdl_set_layer,
    .wait_vsync = sdl_wait_vsync,
    .pan_display = sdl_pan_display,
    .deinit = sdl_deinit,
};
