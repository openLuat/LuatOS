#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_timer.h"
#include "lvgl9/src/widgets/image/lv_image.h"
#include <stdint.h>
#include <string.h>

#if defined(LUAT_USE_VIDEOPLAYER)
#include "luat_videoplayer.h"
#endif

#define LUAT_LOG_TAG "airui.video"
#include "luat_log.h"

#define AIRUI_VIDEO_STATUS_OK 0
#define AIRUI_VIDEO_STATUS_EOF 1

/* 通用帧描述：组件层只关心一帧 RGB565 数据，不关心底层解码实现。 */
typedef struct {
    const uint8_t *data;
    size_t data_size;
    uint16_t width;
    uint16_t height;
    void *priv;
} airui_video_frame_t;

typedef struct {
    const char *src;
    airui_video_format_t format;
    airui_video_backend_t backend;
    airui_video_decode_mode_t decode_mode;
} airui_video_open_opts_t;

/*
 * backend 抽象层：
 * AirUI 组件统一走 open/read_frame/restart/close，
 * 后续可以接 videoplayer/ffmpeg/平台硬解而不改控件主逻辑。
 */
typedef struct airui_video_backend_ops {
    int (*open)(void **backend_ctx, const airui_video_open_opts_t *opts);
    void (*close)(void *backend_ctx);
    int (*read_frame)(void *backend_ctx, airui_video_frame_t *frame);
    void (*release_frame)(void *backend_ctx, airui_video_frame_t *frame);
    int (*restart)(void *backend_ctx);
} airui_video_backend_ops_t;

typedef struct {
    const airui_video_backend_ops_t *ops;
    void *backend_ctx;
    lv_timer_t *timer;
    lv_image_dsc_t img_dsc;
    uint8_t *framebuffer;
    size_t framebuffer_size;
    char *src;
    lv_coord_t requested_width;
    lv_coord_t requested_height;
    uint16_t frame_width;
    uint16_t frame_height;
    uint32_t interval;
    airui_video_format_t format;
    airui_video_backend_t backend;
    airui_video_decode_mode_t decode_mode;
    bool loop;
    bool playing;
    bool eof;
    bool size_checked;
} airui_video_data_t;

#if defined(LUAT_USE_VIDEOPLAYER)
/* videoplayer backend 的私有运行态。 */
typedef struct {
    luat_vp_ctx_t *player;
    char *src;
    airui_video_format_t format;
    airui_video_decode_mode_t decode_mode;
} airui_video_videoplayer_ctx_t;
#endif

static airui_ctx_t *airui_video_get_ctx(lua_State *L_state);
static airui_video_data_t *airui_video_get_data(lv_obj_t *video);
static void airui_video_release_data(void *user_data);
static char *airui_video_strdup(const char *src);
static airui_video_format_t airui_video_parse_format(lua_State *L, int idx, airui_video_format_t def);
static airui_video_backend_t airui_video_parse_backend(lua_State *L, int idx, airui_video_backend_t def);
static airui_video_decode_mode_t airui_video_parse_decode_mode(lua_State *L, int idx, airui_video_decode_mode_t def);
static airui_video_format_t airui_video_guess_format(const char *src);
static int airui_video_select_backend(airui_video_data_t *data);
static int airui_video_open_backend(airui_video_data_t *data);
static void airui_video_close_backend(airui_video_data_t *data);
static int airui_video_ensure_framebuffer(lv_obj_t *video, airui_video_data_t *data, uint16_t width, uint16_t height);
static int airui_video_present_frame(lv_obj_t *video, airui_video_data_t *data, const airui_video_frame_t *frame);
static int airui_video_read_and_present(lv_obj_t *video, airui_video_data_t *data, bool allow_loop);
static int airui_video_restart_and_prime(lv_obj_t *video, airui_video_data_t *data);
static void airui_video_timer_cb(lv_timer_t *timer);

#if defined(LUAT_USE_VIDEOPLAYER)
static int airui_video_vp_open(void **backend_ctx, const airui_video_open_opts_t *opts);
static void airui_video_vp_close(void *backend_ctx);
static int airui_video_vp_read_frame(void *backend_ctx, airui_video_frame_t *frame);
static void airui_video_vp_release_frame(void *backend_ctx, airui_video_frame_t *frame);
static int airui_video_vp_restart(void *backend_ctx);

static const airui_video_backend_ops_t g_airui_video_videoplayer_ops = {
    .open = airui_video_vp_open,
    .close = airui_video_vp_close,
    .read_frame = airui_video_vp_read_frame,
    .release_frame = airui_video_vp_release_frame,
    .restart = airui_video_vp_restart,
};
#endif

static airui_ctx_t *airui_video_get_ctx(lua_State *L_state)
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

static airui_video_data_t *airui_video_get_data(lv_obj_t *video)
{
    airui_component_meta_t *meta = airui_component_meta_get(video);
    if (meta == NULL) {
        return NULL;
    }
    return (airui_video_data_t *)meta->user_data;
}

static void airui_video_release_data(void *user_data)
{
    airui_video_data_t *data = (airui_video_data_t *)user_data;
    if (data == NULL) {
        return;
    }

    /* 先停 timer，再释放 backend/framebuffer，避免回调踩已释放内存。 */
    if (data->timer != NULL) {
        lv_timer_delete(data->timer);
        data->timer = NULL;
    }

    airui_video_close_backend(data);

    if (data->framebuffer != NULL) {
        luat_heap_free(data->framebuffer);
        data->framebuffer = NULL;
    }

    if (data->src != NULL) {
        luat_heap_free(data->src);
        data->src = NULL;
    }

    luat_heap_free(data);
}

static char *airui_video_strdup(const char *src)
{
    size_t len;
    char *copy;

    if (src == NULL) {
        return NULL;
    }

    len = strlen(src);
    copy = (char *)luat_heap_malloc(len + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, src, len + 1);
    return copy;
}

static airui_video_format_t airui_video_parse_format(lua_State *L, int idx, airui_video_format_t def)
{
    lua_getfield(L, idx, "format");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        int format = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
        if (format >= AIRUI_VIDEO_FORMAT_AUTO && format <= AIRUI_VIDEO_FORMAT_MP4_H264) {
            return (airui_video_format_t)format;
        }
        return def;
    }

    if (lua_type(L, -1) == LUA_TSTRING) {
        const char *format = lua_tostring(L, -1);
        lua_pop(L, 1);
        if (strcmp(format, "mjpg") == 0) {
            return AIRUI_VIDEO_FORMAT_MJPG;
        }
        if (strcmp(format, "avi_mjpg") == 0 || strcmp(format, "avi-mjpg") == 0) {
            return AIRUI_VIDEO_FORMAT_AVI_MJPG;
        }
        if (strcmp(format, "mp4") == 0 || strcmp(format, "mp4_h264") == 0 || strcmp(format, "h264") == 0) {
            return AIRUI_VIDEO_FORMAT_MP4_H264;
        }
        return AIRUI_VIDEO_FORMAT_AUTO;
    }

    lua_pop(L, 1);
    return def;
}

static airui_video_backend_t airui_video_parse_backend(lua_State *L, int idx, airui_video_backend_t def)
{
    lua_getfield(L, idx, "backend");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        int backend = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
        if (backend >= AIRUI_VIDEO_BACKEND_AUTO && backend <= AIRUI_VIDEO_BACKEND_PLATFORM) {
            return (airui_video_backend_t)backend;
        }
        return def;
    }

    if (lua_type(L, -1) == LUA_TSTRING) {
        const char *backend = lua_tostring(L, -1);
        lua_pop(L, 1);
        if (strcmp(backend, "videoplayer") == 0) {
            return AIRUI_VIDEO_BACKEND_VIDEOPLAYER;
        }
        if (strcmp(backend, "ffmpeg") == 0) {
            return AIRUI_VIDEO_BACKEND_FFMPEG;
        }
        if (strcmp(backend, "platform") == 0) {
            return AIRUI_VIDEO_BACKEND_PLATFORM;
        }
        return AIRUI_VIDEO_BACKEND_AUTO;
    }

    lua_pop(L, 1);
    return def;
}

static airui_video_decode_mode_t airui_video_parse_decode_mode(lua_State *L, int idx, airui_video_decode_mode_t def)
{
    lua_getfield(L, idx, "decode_mode");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        int mode = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
        if (mode == AIRUI_VIDEO_DECODE_HW) {
            return AIRUI_VIDEO_DECODE_HW;
        }
        return AIRUI_VIDEO_DECODE_SW;
    }

    if (lua_type(L, -1) == LUA_TSTRING) {
        const char *mode = lua_tostring(L, -1);
        lua_pop(L, 1);
        if (strcmp(mode, "hw") == 0 || strcmp(mode, "hardware") == 0) {
            return AIRUI_VIDEO_DECODE_HW;
        }
        return AIRUI_VIDEO_DECODE_SW;
    }

    lua_pop(L, 1);
    return def;
}

static airui_video_format_t airui_video_guess_format(const char *src)
{
    const char *dot;

    if (src == NULL) {
        return AIRUI_VIDEO_FORMAT_AUTO;
    }

    dot = strrchr(src, '.');
    if (dot == NULL) {
        return AIRUI_VIDEO_FORMAT_AUTO;
    }

    if (strcmp(dot, ".mjpg") == 0 || strcmp(dot, ".mjpeg") == 0) {
        return AIRUI_VIDEO_FORMAT_MJPG;
    }
    if (strcmp(dot, ".avi") == 0) {
        return AIRUI_VIDEO_FORMAT_AVI_MJPG;
    }
    if (strcmp(dot, ".mp4") == 0) {
        return AIRUI_VIDEO_FORMAT_MP4_H264;
    }
    return AIRUI_VIDEO_FORMAT_AUTO;
}

static int airui_video_select_backend(airui_video_data_t *data)
{
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    /* 首版先按扩展名做轻量探测，后续可替换为更可靠的文件头探测。 */
    if (data->format == AIRUI_VIDEO_FORMAT_AUTO) {
        data->format = airui_video_guess_format(data->src);
    }

    /* auto 模式下先把 MJPG 路由到 videoplayer backend。 */
    if (data->backend == AIRUI_VIDEO_BACKEND_AUTO) {
        if (data->format == AIRUI_VIDEO_FORMAT_AUTO || data->format == AIRUI_VIDEO_FORMAT_MJPG) {
            data->backend = AIRUI_VIDEO_BACKEND_VIDEOPLAYER;
        }
    }

#if defined(LUAT_USE_VIDEOPLAYER)
    if (data->backend == AIRUI_VIDEO_BACKEND_VIDEOPLAYER) {
        data->ops = &g_airui_video_videoplayer_ops;
        return AIRUI_OK;
    }
#endif

    return AIRUI_ERR_NOT_SUPPORTED;
}

static int airui_video_open_backend(airui_video_data_t *data)
{
    airui_video_open_opts_t opts;

    if (data == NULL || data->ops == NULL || data->src == NULL || data->ops->open == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    opts.src = data->src;
    opts.format = data->format;
    opts.backend = data->backend;
    opts.decode_mode = data->decode_mode;

    return data->ops->open(&data->backend_ctx, &opts);
}

static void airui_video_close_backend(airui_video_data_t *data)
{
    if (data == NULL || data->ops == NULL || data->ops->close == NULL || data->backend_ctx == NULL) {
        return;
    }

    data->ops->close(data->backend_ctx);
    data->backend_ctx = NULL;
}

static int airui_video_ensure_framebuffer(lv_obj_t *video, airui_video_data_t *data, uint16_t width, uint16_t height)
{
    size_t framebuffer_size;
    uint8_t *new_buf;

    if (video == NULL || data == NULL || width == 0 || height == 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    framebuffer_size = (size_t)width * (size_t)height * 2u;
    if ((framebuffer_size / 2u) != ((size_t)width * (size_t)height)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    /* 帧尺寸变化时重建持久 framebuffer，LVGL 始终持有这一份稳定内存。 */
    if (data->framebuffer == NULL || data->framebuffer_size != framebuffer_size) {
        new_buf = (uint8_t *)luat_heap_malloc(framebuffer_size);
        if (new_buf == NULL) {
            return AIRUI_ERR_NO_MEM;
        }
        if (data->framebuffer != NULL) {
            luat_heap_free(data->framebuffer);
        }
        data->framebuffer = new_buf;
        data->framebuffer_size = framebuffer_size;
    }

    data->frame_width = width;
    data->frame_height = height;
    data->img_dsc.header.magic = LV_IMAGE_HEADER_MAGIC;
    data->img_dsc.header.cf = LV_COLOR_FORMAT_RGB565;
    data->img_dsc.header.w = width;
    data->img_dsc.header.h = height;
    data->img_dsc.header.stride = (uint32_t)width * 2u;
    data->img_dsc.header.flags = 0;
    data->img_dsc.data_size = framebuffer_size;
    data->img_dsc.data = data->framebuffer;
    data->img_dsc.reserved = NULL;
    data->img_dsc.reserved_2 = NULL;

    lv_image_set_src(video, &data->img_dsc);
    return AIRUI_OK;
}

static int airui_video_present_frame(lv_obj_t *video, airui_video_data_t *data, const airui_video_frame_t *frame)
{
    int ret;

    if (video == NULL || data == NULL || frame == NULL || frame->data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (!data->size_checked) {
        data->size_checked = true;
        if (data->requested_width != (lv_coord_t)frame->width || data->requested_height != (lv_coord_t)frame->height) {
            LLOGW("video: scaling is not supported yet, requested size=%dx%d, video size=%dx%d, force reset widget size to %dx%d",
                  (int)data->requested_width,
                  (int)data->requested_height,
                  (int)frame->width,
                  (int)frame->height,
                  (int)frame->width,
                  (int)frame->height);
            lv_obj_set_size(video, (lv_coord_t)frame->width, (lv_coord_t)frame->height);
        }
    }

    ret = airui_video_ensure_framebuffer(video, data, frame->width, frame->height);
    if (ret != AIRUI_OK) {
        return ret;
    }

    /* 不能直接引用 backend 返回的临时帧内存，必须拷贝到组件自有缓冲区。 */
    memcpy(data->framebuffer, frame->data, data->framebuffer_size);
    lv_obj_invalidate(video);
    return AIRUI_OK;
}

static int airui_video_read_and_present(lv_obj_t *video, airui_video_data_t *data, bool allow_loop)
{
    airui_video_frame_t frame;
    int ret;

    if (video == NULL || data == NULL || data->ops == NULL || data->ops->read_frame == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    memset(&frame, 0, sizeof(frame));
    /* 主播放路径：读一帧 -> 可选 loop 重启 -> 渲染 -> 释放 backend 帧。 */
    ret = data->ops->read_frame(data->backend_ctx, &frame);
    if (ret == AIRUI_VIDEO_STATUS_EOF && allow_loop && data->loop && data->ops->restart != NULL) {
        ret = data->ops->restart(data->backend_ctx);
        if (ret == AIRUI_OK) {
            memset(&frame, 0, sizeof(frame));
            ret = data->ops->read_frame(data->backend_ctx, &frame);
        }
    }

    if (ret == AIRUI_VIDEO_STATUS_OK) {
        ret = airui_video_present_frame(video, data, &frame);
        if (data->ops->release_frame != NULL) {
            data->ops->release_frame(data->backend_ctx, &frame);
        }
        data->eof = false;
        return ret;
    }

    if (ret == AIRUI_VIDEO_STATUS_EOF) {
        data->eof = true;
        return AIRUI_VIDEO_STATUS_EOF;
    }

    return ret;
}

static int airui_video_restart_and_prime(lv_obj_t *video, airui_video_data_t *data)
{
    int ret;

    if (video == NULL || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (data->backend_ctx == NULL) {
        ret = airui_video_open_backend(data);
        if (ret != AIRUI_OK) {
            return ret;
        }
    } else if (data->ops != NULL && data->ops->restart != NULL) {
        ret = data->ops->restart(data->backend_ctx);
        if (ret != AIRUI_OK) {
            return ret;
        }
    }

    /* stop()/EOF 后恢复时，先重置 backend，再立即解出首帧做预览。 */
    ret = airui_video_read_and_present(video, data, false);
    if (ret == AIRUI_VIDEO_STATUS_EOF) {
        return AIRUI_OK;
    }
    return ret;
}

static void airui_video_timer_cb(lv_timer_t *timer)
{
    lv_obj_t *video;
    airui_video_data_t *data;
    int ret;

    if (timer == NULL) {
        return;
    }

    video = (lv_obj_t *)lv_timer_get_user_data(timer);
    if (video == NULL) {
        lv_timer_delete(timer);
        return;
    }

    data = airui_video_get_data(video);
    if (data == NULL || data->timer != timer || !data->playing) {
        return;
    }

    /* timer 只负责推进播放，暂停/停止语义由 playing 标志控制。 */
    ret = airui_video_read_and_present(video, data, true);
    if (ret != AIRUI_OK) {
        data->playing = false;
        lv_timer_pause(timer);
        if (ret != AIRUI_VIDEO_STATUS_EOF) {
            LLOGE("video: frame decode failed: %d", ret);
        }
    }
}

#if defined(LUAT_USE_VIDEOPLAYER)
static int airui_video_vp_open(void **backend_ctx, const airui_video_open_opts_t *opts)
{
    airui_video_videoplayer_ctx_t *ctx;
    int ret;

    if (backend_ctx == NULL || opts == NULL || opts->src == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    /* 当前 videoplayer backend 仅接 MJPG，其他格式先明确返回不支持。 */
    if (!(opts->format == AIRUI_VIDEO_FORMAT_AUTO || opts->format == AIRUI_VIDEO_FORMAT_MJPG)) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }

    ctx = (airui_video_videoplayer_ctx_t *)luat_heap_malloc(sizeof(airui_video_videoplayer_ctx_t));
    if (ctx == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    memset(ctx, 0, sizeof(airui_video_videoplayer_ctx_t));

    ctx->src = airui_video_strdup(opts->src);
    if (ctx->src == NULL) {
        luat_heap_free(ctx);
        return AIRUI_ERR_NO_MEM;
    }

    ctx->format = opts->format;
    ctx->decode_mode = opts->decode_mode;
    ctx->player = luat_videoplayer_open(ctx->src);
    if (ctx->player == NULL) {
        luat_heap_free(ctx->src);
        luat_heap_free(ctx);
        return AIRUI_ERR_INIT_FAILED;
    }

    ret = luat_videoplayer_set_decode_mode(ctx->player, (luat_vp_decode_mode_t)ctx->decode_mode);
    if (ret != LUAT_VP_OK) {
        luat_videoplayer_close(ctx->player);
        luat_heap_free(ctx->src);
        luat_heap_free(ctx);
        return AIRUI_ERR_INIT_FAILED;
    }

    *backend_ctx = ctx;
    return AIRUI_OK;
}

static void airui_video_vp_close(void *backend_ctx)
{
    airui_video_videoplayer_ctx_t *ctx = (airui_video_videoplayer_ctx_t *)backend_ctx;
    if (ctx == NULL) {
        return;
    }

    if (ctx->player != NULL) {
        luat_videoplayer_close(ctx->player);
        ctx->player = NULL;
    }
    if (ctx->src != NULL) {
        luat_heap_free(ctx->src);
        ctx->src = NULL;
    }
    luat_heap_free(ctx);
}

static int airui_video_vp_read_frame(void *backend_ctx, airui_video_frame_t *frame)
{
    airui_video_videoplayer_ctx_t *ctx = (airui_video_videoplayer_ctx_t *)backend_ctx;
    luat_vp_frame_t *vp_frame;
    int ret;

    if (ctx == NULL || ctx->player == NULL || frame == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    /* 用一层 priv 包装 luat_vp_frame_t，便于在 release_frame 中统一回收。 */
    vp_frame = (luat_vp_frame_t *)luat_heap_malloc(sizeof(luat_vp_frame_t));
    if (vp_frame == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    memset(vp_frame, 0, sizeof(luat_vp_frame_t));

    ret = luat_videoplayer_read_frame(ctx->player, vp_frame);
    if (ret == LUAT_VP_ERR_EOF) {
        luat_heap_free(vp_frame);
        return AIRUI_VIDEO_STATUS_EOF;
    }
    if (ret != LUAT_VP_OK) {
        luat_heap_free(vp_frame);
        return AIRUI_ERR_INIT_FAILED;
    }

    frame->data = vp_frame->data;
    frame->data_size = (size_t)vp_frame->width * (size_t)vp_frame->height * 2u;
    frame->width = vp_frame->width;
    frame->height = vp_frame->height;
    frame->priv = vp_frame;
    return AIRUI_VIDEO_STATUS_OK;
}

static void airui_video_vp_release_frame(void *backend_ctx, airui_video_frame_t *frame)
{
    luat_vp_frame_t *vp_frame;

    (void)backend_ctx;

    if (frame == NULL || frame->priv == NULL) {
        return;
    }

    /* 归还 videoplayer 分配的帧像素缓冲，并释放包装结构。 */
    vp_frame = (luat_vp_frame_t *)frame->priv;
    luat_videoplayer_frame_free(vp_frame);
    luat_heap_free(vp_frame);
    memset(frame, 0, sizeof(airui_video_frame_t));
}

static int airui_video_vp_restart(void *backend_ctx)
{
    airui_video_videoplayer_ctx_t *ctx = (airui_video_videoplayer_ctx_t *)backend_ctx;
    luat_vp_ctx_t *player;
    luat_vp_ctx_t *old_player;
    int ret;

    if (ctx == NULL || ctx->src == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    old_player = ctx->player;

    /*
     * BK72xx 硬解链路存在全局/单实例资源约束，不能在旧实例未释放前
     * 再创建一个新的硬解 player，否则 reopen 时可能出现 decode_start 失败。
     */
    if (ctx->decode_mode == AIRUI_VIDEO_DECODE_HW && old_player != NULL) {
        luat_videoplayer_close(old_player);
        old_player = NULL;
        ctx->player = NULL;
    }

    /* videoplayer 当前没有 seek，restart 通过 reopen 实现回到开头。 */
    player = luat_videoplayer_open(ctx->src);
    if (player == NULL) {
        return AIRUI_ERR_INIT_FAILED;
    }

    ret = luat_videoplayer_set_decode_mode(player, (luat_vp_decode_mode_t)ctx->decode_mode);
    if (ret != LUAT_VP_OK) {
        luat_videoplayer_close(player);
        return AIRUI_ERR_INIT_FAILED;
    }

    if (old_player != NULL) {
        luat_videoplayer_close(old_player);
    }
    ctx->player = player;
    return AIRUI_OK;
}
#endif

lv_obj_t *airui_video_create_from_config(void *L, int idx)
{
    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx;
    lv_obj_t *parent;
    lv_obj_t *video;
    airui_component_meta_t *meta;
    airui_video_data_t *data;
    const char *src;
    int ret;
    lv_coord_t requested_width;
    lv_coord_t requested_height;

    if (L_state == NULL) {
        return NULL;
    }

    ctx = airui_video_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    src = airui_marshal_string(L, idx, "src", NULL);
    if (src == NULL || src[0] == '\0') {
        LLOGE("video: src is required");
        return NULL;
    }

    parent = airui_marshal_parent(L, idx);
    requested_width = (lv_coord_t)airui_marshal_floor_integer(L, idx, "w", 160);
    requested_height = (lv_coord_t)airui_marshal_floor_integer(L, idx, "h", 120);

    /* 首版直接复用 lv_image 作为显示载体，减少自定义 widget 成本。 */
    video = lv_image_create(parent);
    if (video == NULL) {
        return NULL;
    }

    lv_obj_set_pos(video, airui_marshal_floor_integer(L, idx, "x", 0), airui_marshal_floor_integer(L, idx, "y", 0));
    lv_obj_set_size(video, requested_width, requested_height);
    /* 嵌入式场景暂不支持缩放，inner align 使用居中避免进入 contain 缩放路径。 */
    lv_image_set_inner_align(video, LV_IMAGE_ALIGN_CENTER);

    meta = airui_component_meta_alloc(ctx, video, AIRUI_COMPONENT_VIDEO);
    if (meta == NULL) {
        lv_obj_delete(video);
        return NULL;
    }

    data = (airui_video_data_t *)luat_heap_malloc(sizeof(airui_video_data_t));
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(video);
        return NULL;
    }
    memset(data, 0, sizeof(airui_video_data_t));

    data->requested_width = requested_width;
    data->requested_height = requested_height;

    data->src = airui_video_strdup(src);
    if (data->src == NULL) {
        luat_heap_free(data);
        airui_component_meta_free(meta);
        lv_obj_delete(video);
        return NULL;
    }

    data->interval = (uint32_t)airui_marshal_integer(L, idx, "interval", 33);
    if (data->interval == 0) {
        data->interval = 33;
    }
    data->loop = airui_marshal_bool(L, idx, "loop", false);
    data->playing = false;
    data->eof = false;
    data->format = airui_video_parse_format(L_state, idx, AIRUI_VIDEO_FORMAT_AUTO);
    data->backend = airui_video_parse_backend(L_state, idx, AIRUI_VIDEO_BACKEND_AUTO);
    data->decode_mode = airui_video_parse_decode_mode(L_state, idx, AIRUI_VIDEO_DECODE_SW);

    ret = airui_video_select_backend(data);
    if (ret != AIRUI_OK) {
        LLOGE("video: unsupported backend=%d format=%d", data->backend, data->format);
        luat_heap_free(data->src);
        luat_heap_free(data);
        airui_component_meta_free(meta);
        lv_obj_delete(video);
        return NULL;
    }

    airui_component_meta_set_user_data(meta, data, airui_video_release_data);

    ret = airui_video_open_backend(data);
    if (ret != AIRUI_OK) {
        airui_component_meta_free(meta);
        lv_obj_delete(video);
        return NULL;
    }

    /* timer 默认先暂停，auto_play 再决定是否启动。 */
    data->timer = lv_timer_create(airui_video_timer_cb, data->interval, video);
    if (data->timer == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(video);
        return NULL;
    }
    lv_timer_pause(data->timer);

    /* 创建阶段先解一帧，确保控件未播放时也能看到首帧预览。 */
    ret = airui_video_read_and_present(video, data, false);
    if (ret == AIRUI_VIDEO_STATUS_EOF) {
        ret = AIRUI_OK;
    }
    if (ret != AIRUI_OK) {
        airui_component_meta_free(meta);
        lv_obj_delete(video);
        return NULL;
    }

    if (airui_marshal_bool(L, idx, "auto_play", true)) {
        data->playing = true;
        lv_timer_resume(data->timer);
    }

    return video;
}

int airui_video_play(lv_obj_t *video)
{
    airui_video_data_t *data;
    int ret;

    if (video == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data = airui_video_get_data(video);
    if (data == NULL || data->timer == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    /* EOF 后再次 play，语义上等价于从头重新播放。 */
    if (data->eof) {
        ret = airui_video_restart_and_prime(video, data);
        if (ret != AIRUI_OK) {
            return ret;
        }
    }

    data->playing = true;
    lv_timer_resume(data->timer);
    return AIRUI_OK;
}

int airui_video_pause(lv_obj_t *video)
{
    airui_video_data_t *data;

    if (video == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data = airui_video_get_data(video);
    if (data == NULL || data->timer == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->playing = false;
    lv_timer_pause(data->timer);
    return AIRUI_OK;
}

int airui_video_stop(lv_obj_t *video)
{
    airui_video_data_t *data;
    int ret;

    if (video == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data = airui_video_get_data(video);
    if (data == NULL || data->timer == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->playing = false;
    lv_timer_pause(data->timer);
    /* stop 的语义是停止并回到首帧，而不是仅仅暂停当前帧。 */
    ret = airui_video_restart_and_prime(video, data);
    if (ret != AIRUI_OK) {
        return ret;
    }
    return AIRUI_OK;
}

int airui_video_destroy(lv_obj_t *video)
{
    if (video == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (!lv_obj_is_valid(video)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_delete(video);
    return AIRUI_OK;
}
