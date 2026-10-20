/*
 * luat_mplayer.c - 媒体播放器 API 层
 * 负责: 按媒体类型选择解码器并分发所有控制操作。
 * 当前仅 MP4 解码器已接入; MP3/WAV/FLAC 解码器未编入固件, 分支为 TODO。
 */

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_mplayer.h"
#include "luat_display.h"

/** MP4 解码器*/
#include "mp4_decode.h"
/* YUV420P -> RGB565 转换接口(YUV_RGB_Param / YUV_RGB_565), 实现在 yuv_rgb_565.s */
#include "yuv_rgb_565.h"

/* 解码线程(基于 FreeRTOS; 信号量/挂起操作用到) */
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include <stdio.h>

#include <string.h>

#define LUAT_LOG_TAG "mplayer"
#include "luat_log.h"

/* 解码线程参数 */
#define MPLAYER_DS_STACK     24 * 1024
/* 解码线程优先级不能高于 luatos 主任务(80>>2=20)：H264 单帧解码 40~106ms 密集
 * 占用 CPU，若高于主任务会抢占 UI → 界面卡顿。保持 50(>>2=12) 低于主任务。
 * 代价：播放中可能被 UI/文件选择器临时抢占产生解码尖峰、偶发跳帧(轻微不同步)，
 * 但消除它不能靠提优先级，需另走同步策略/解码减负方向。 */
#define MPLAYER_DS_PRIO      50
#define MPLAYER_DS_STOP_TO   500   /* 停线程等待 ms */

/* 渲染线程参数 */
#define MPLAYER_RS_STACK     8 * 1024
#define MPLAYER_RS_PRIO      45   /* 略低于解码线程, 不抢占解码 */

/*视频渲染层*/
struct luat_display_layer_data g_video_layer = { 0 };

/* 视频层显示缓冲(RGB565, 由 g_video_layer.buffer 指向) */
#define MPLAYER_VIDEO_BUF_ALIGN 32
static void *s_video_buf = NULL;        /* 视频层缓冲基址 */
static size_t s_video_buf_size = 0;     /* 已分配字节数 */

/* 关闭视频层并归还缓冲 */
static void mplayer_video_buf_release(void)
{
    if (s_video_buf == NULL) {
        return;
    }

    /* 先把视频层关掉: 此时 buffer 仍指向旧块, 让 LCDC 停止扫描后再释放内存,
     * 否则关层前那块内存可能已被别人复用, LCDC 会扫到垃圾(-5 及花屏风险)。
     * 顺带把被视频层压制掉的 UI 层恢复(interface 侧在 enable=0 时会自行恢复)。 */
    if (g_video_layer.buffer == s_video_buf) {
        struct luat_display *display = luat_display_get_default();
        if (display != NULL && display->display_funcs != NULL &&
            display->display_funcs->set_layer != NULL) {
            g_video_layer.enable = 0;
            display->display_funcs->set_layer(&g_video_layer);
        }
    }

    luat_heap_free(s_video_buf);
    s_video_buf = NULL;
    s_video_buf_size = 0;
    g_video_layer.buffer = NULL;
}

/* 申请/复用视频层缓冲, 成功返回 0 */
static int mplayer_video_buf_prepare(int width, int height)
{
    /* RGB565: 每像素 2 字节 */
    size_t need = (size_t)width * (size_t)height * 2U;

    if (s_video_buf == NULL || s_video_buf_size < need) {
        mplayer_video_buf_release();

        void *buf = luat_heap_memalign(MPLAYER_VIDEO_BUF_ALIGN, need);
        if (buf == NULL) {
            LLOGE("video layer buffer %dx%d alloc failed", width, height);
            return -1;
        }
        /* 首帧到达前 LCDC 已经在扫这块内存, 清零避免显示随机内容 */
        memset(buf, 0, need);

        s_video_buf = buf;
        s_video_buf_size = need;
    }

    g_video_layer.buffer = s_video_buf;
    return 0;
}

/*显示器输出*/
static void disp_output(int width, int height, unsigned char **yuv, int *linesize)
{
    YUV_RGB_Param p;

    if (g_video_layer.buffer == NULL) {
        return;
    }

    p.y_src     = yuv[0];
    p.u_src     = yuv[1];
    p.v_src     = yuv[2];
    p.y_stride  = linesize[0];
    p.uv_stride = linesize[1];

    YUV_RGB_565(g_video_layer.buffer, width, height, &p);

}

/* MP4 解码线程入口*/
static void mplayer_mp4_task_entry(void *arg) 
{
    luat_mplayer_t *m = (luat_mplayer_t *)arg;
    movie_mp4 *mp4 = (movie_mp4 *)m->media;
    while (m->decode_running) {
        movie_mp4_task(mp4);
        movie_render_task(mp4);
        luat_rtos_task_sleep(2);
    }
    if (m->done_sem) {
        xSemaphoreGive((SemaphoreHandle_t)m->done_sem);
    }
    vTaskSuspend(NULL);
}
/* MP4 渲染线程入口*/
static void mplayer_mp4_render_task(void *arg) 
{
    luat_mplayer_t *m = (luat_mplayer_t *)arg;
    movie_mp4 *mp4 = (movie_mp4 *)m->media;
    while (m->decode_running) {
        movie_mp4_task(mp4);
        movie_render_task(mp4);
        luat_rtos_task_sleep(2);
    }
    if (m->done_sem) {
        xSemaphoreGive((SemaphoreHandle_t)m->done_sem);
    }
    vTaskSuspend(NULL);
}

/* 启动 mp4 解码线程 */
static int mplayer_start_mp4_thread(luat_mplayer_t *m) {
    SemaphoreHandle_t sem = xSemaphoreCreateBinary();
    if (!sem) {
        LLOGE("create done_sem failed");
        return -1;
    }
    m->done_sem = sem;

    m->decode_running = 1;
    m->decode_task = NULL;
    /*luat_rtos_task_create */
    int rc = luat_rtos_task_create((luat_rtos_task_handle *)&m->decode_task, MPLAYER_DS_STACK,
                              MPLAYER_DS_PRIO, "mplayer", mplayer_mp4_task_entry, m, 0);
    if (rc != 0) {
        LLOGE("task_create rc=%d", rc);
        m->decode_running = 0;
        xSemaphoreGive(sem);   /* 尚无线程会 give, 主动 give 避免 stop 阻塞 */
        return -1;
    }
    return 0;
}

/* 停止并回收解码线程 */
static void mplayer_stop_mp4_thread(luat_mplayer_t *m) {
    m->decode_running = 0;
    if (m->decode_task) {
        if (m->done_sem) {
            xSemaphoreTake((SemaphoreHandle_t)m->done_sem, pdMS_TO_TICKS(MPLAYER_DS_STOP_TO));
        }
        luat_rtos_task_delete((luat_rtos_task_handle)m->decode_task);
        m->decode_task = NULL;
    }
    if (m->done_sem) {
        vSemaphoreDelete((SemaphoreHandle_t)m->done_sem);
        m->done_sem = NULL;
    }
}

/* 按文件扩展名识别媒体类型 */
static MediaType luat_mplayer_detect_type(const char *path) {
    const char *ext = strrchr(path, '.');
    if (!ext) return MEDIA_TYPE_UNKNOWN;
    if (strcmp(ext, ".mp4") == 0 || strcmp(ext, ".m4v") == 0) {
        return MEDIA_TYPE_MP4;
    } else if (strcmp(ext, ".mp3") == 0) {
        return MEDIA_TYPE_MP3;
    } else if (strcmp(ext, ".wav") == 0) {
        return MEDIA_TYPE_WAV;
    } else if (strcmp(ext, ".flac") == 0) {
        return MEDIA_TYPE_FLAC;
    }
    return MEDIA_TYPE_UNKNOWN;
}

/* 按媒体类型加载解码器, 失败返回 NULL */
static void *luat_mplayer_load(MediaType type, const char *path) {
    if (type == MEDIA_TYPE_MP4) {
        /* mp4/m4v: 已接入 */
        return (void *)loadmovie_mp4(path);
    } else if (type == MEDIA_TYPE_MP3) {
        /* MP3 走 AUDIO_V2 框架(luat_audio_request_play_files), 不在此加载解码器 */
        return NULL;
    }
    /* TODO: 启用对应音频解码器后填入:
     *   MEDIA_TYPE_WAV  -> return load_wave((char*)path);
     *   MEDIA_TYPE_FLAC -> return load_flac((char*)path); */
    return NULL;
}

/* 按媒体类型停止并释放解码器 */
static void luat_mplayer_unload_media(void *media, MediaType type) {
    if (type == MEDIA_TYPE_MP4) {
        movie_mp4 *mp4 = (movie_mp4 *)media;
        movie_mp4_stop(mp4);
        movie_mp4_release(mp4);
        return;
    } else if (type == MEDIA_TYPE_MP3) {
        /* AUDIO_V2 的请求/解码器由 mplayer_v2_destroy 释放, 这里无需处理 */
        return;
    }
    /* TODO: 启用对应音频解码器后填入:
     *   MEDIA_TYPE_WAV  -> wave_release((WAVE *)media);
     *   MEDIA_TYPE_FLAC -> flac_release((flac_t *)media); */
}

luat_mplayer_t *luat_mplayer_open(const char *path) {
    if (!path) return NULL;

    MediaType type = luat_mplayer_detect_type(path);
    if (type == MEDIA_TYPE_UNKNOWN) return NULL;

    void *media = NULL;

    if (type == MEDIA_TYPE_MP3) {

    } else {
        media = luat_mplayer_load(type, path);
        if (!media) {
            LLOGE("open %s failed: decoder not support", path);
            return NULL;
        }
    }

    luat_mplayer_t *m = (luat_mplayer_t *)luat_heap_malloc(sizeof(luat_mplayer_t));
    if (!m) {
        if (media) luat_mplayer_unload_media(media, type);
        return NULL;
    }
    m->media = media;
    m->media_type = type;
    m->is_open = 1;
    m->decode_running = 0;
    m->decode_task = NULL;
    m->done_sem = NULL;
    return m;
}

int luat_mplayer_close(luat_mplayer_t *m) {
    if (!m || !m->is_open) return -1;
    /* 先停解码线程(解码线程可能因 pump 在跑, 需先回收),
     * 最后释放解码器与显示缓冲 */
    if (m->media_type == MEDIA_TYPE_MP4) {
        mplayer_stop_mp4_thread(m);
    } else if (m->media_type == MEDIA_TYPE_MP3) {
        /* AUDIO_V2 请求取消 + 上下文释放 */
    }
    if (m->media) {
        luat_mplayer_unload_media(m->media, m->media_type);
        m->media = NULL;
    }

    /* 视频层缓冲是全局单实例(LCDC 只有一层视频层), MP4 播放器关闭时关层并归还 */
    if (m->media_type == MEDIA_TYPE_MP4) {
        mplayer_video_buf_release();
    }

    m->is_open = 0;
    luat_heap_free(m);
    return 0;
}

int luat_mplayer_play(luat_mplayer_t *m) {
    if (!m || !m->is_open) return -1;
    if (m->media_type == MEDIA_TYPE_MP3) {

        return 0;
    }
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        movie_mp4 *mp4 = (movie_mp4 *)m->media;
        int eos = (mp4->movie_status == MOVIE_MP4_STAT_EOS);
        /* 播放中/暂停中重复 play 是空操作(不重播); EOS 后线程保持空转,
         * decode_running 恒为 1, 若直接拦截则"播完后再点播放"永远无效,
         * 故 EOS 状态放行, 复用空转线程重新 play。 */
        if (m->decode_running && !eos) return 0;
        if (movie_mp4_play(mp4) != 0) {
            printf("mplayer: movie_mp4_play failed\r\n");
            return -1;
        }
        if (!m->decode_running) {
            if (mplayer_start_mp4_thread(m) != 0) {
                printf("mplayer: start decode thread failed\r\n");
                movie_mp4_stop(mp4);
                return -1;
            }
        }
        /* 解码线程内联泵帧+渲染与帧节拍, 无需独立渲染线程 */
        return 0;
    }
    /* TODO: 按类型播放, 例如:
     *   MEDIA_TYPE_WAV  -> return wave_play((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_play((flac_t *)m->media); */
    return -1;
}

int luat_mplayer_pause(luat_mplayer_t *m) {
    if (!m || !m->is_open) return -1;
    if (m->media_type == MEDIA_TYPE_MP3) {

    }
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_pause((movie_mp4 *)m->media);
    }
    /* TODO: 按类型暂停, 例如:
     *   MEDIA_TYPE_WAV  -> return wave_pause((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_pause((flac_t *)m->media); */
    return -1;
}

int luat_mplayer_resume(luat_mplayer_t *m) {
    if (!m || !m->is_open) return -1;
    if (m->media_type == MEDIA_TYPE_MP3) {

    }
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_resume((movie_mp4 *)m->media);
    }
    /* TODO: 按类型恢复, 例如:
     *   MEDIA_TYPE_WAV  -> return wave_resume((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_resume((flac_t *)m->media); */
    return -1;
}

int luat_mplayer_stop(luat_mplayer_t *m) {
    if (!m || !m->is_open) return -1;
    if (m->media_type == MEDIA_TYPE_MP3) {

        return 0;
    }
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        mplayer_stop_mp4_thread(m);
        return movie_mp4_stop((movie_mp4 *)m->media);
    }
    /* TODO: 按类型停止, 例如:
     *   MEDIA_TYPE_WAV  -> return wave_stop((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_stop((flac_t *)m->media); */
    return -1;
}

int luat_mplayer_is_playing(luat_mplayer_t *m) {
    if (!m || !m->is_open) return -1;
    if (m->media_type == MEDIA_TYPE_MP3) {

    }
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_isplay((movie_mp4 *)m->media);
    }
    /* TODO: 按类型查询, 例如:
     *   MEDIA_TYPE_WAV  -> return wave_isplay((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_isplay((flac_t *)m->media); */
    return 0;
}

int luat_mplayer_set_rect(luat_mplayer_t *m, int x, int y, int w, int h) 
{
    if (!m || !m->is_open) return -1;
    if (!m->media) return -1;
    if (m->media_type != MEDIA_TYPE_MP4) {
        /* 音频类型无视频图层 */
        return -1;
    }

    struct luat_display* display = luat_display_get_default();
    if (display == NULL || display->display_funcs == NULL ||
        display->display_funcs->set_layer == NULL) {
        LLOGE("display not ready");
        return -1;
    }

    movie_mp4 *mp4 = (movie_mp4 *)m->media;
    int vw = mp4->video_width;
    int vh = mp4->video_height;
    if (vw <= 0 || vh <= 0) {
        LLOGE("invalid video size %dx%d", vw, vh);
        return -1;
    }

    /* x/y 传 -1 表示居中(见 binding 里 mplayer.set_rect 的 API 文档) */
    if (x < 0 || y < 0) {
        int scr_w = display->fb_info ? (int)display->fb_info->width  : 0;
        int scr_h = display->fb_info ? (int)display->fb_info->height : 0;
        if (x < 0) x = (scr_w - vw) / 2;
        if (y < 0) y = (scr_h - vh) / 2;
        /* 视频比屏幕大时上面的居中会算成负坐标, 归零退回左上角 */
        if (x < 0) x = 0;
        if (y < 0) y = 0;
    }

    /* 视频层(L2/RGB565/不透明): 宽高取视频源尺寸; w/h 入参留给缩放, 当前忽略 */
    g_video_layer.enable   = 1;
    g_video_layer.layer_id = 1;
    g_video_layer.area_id  = 0;
    g_video_layer.alpha    = 0xFF;
    g_video_layer.format   = LUAT_DISPLAY_FORMAT_RGB565;
    g_video_layer.area.x1  = x;
    g_video_layer.area.y1  = y;
    g_video_layer.area.x2  = x + vw;
    g_video_layer.area.y2  = y + vh;

    /* 申请显示缓冲(PSRAM + 32 字节对齐); 视频源尺寸变化时会重建 */
    if (mplayer_video_buf_prepare(vw, vh) != 0) {
        return -1;
    }

    if (display->display_funcs->set_layer(&g_video_layer) != 0) {
        LLOGE("set video layer failed");
        return -1;
    }

    /* 注册逐帧回调: 解码线程拿到 YUV420P 后由 disp_output 转 RGB565 写入视频层缓冲 */
    return movie_mp4_set_disp_adapter(mp4, disp_output);    //设置显示器
}

int luat_mplayer_set_audio_enable(luat_mplayer_t *m, int en) {
    if (!m || !m->is_open) return -1;
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        /* 写 movie->audio_en, 解码线程轮询生效; 播放中/暂停均可切换 */
        movie_mp4 *mp4 = (movie_mp4 *)m->media;
        mp4->audio_en = en;
        return 0;
    }
    /* 音频类型无此语义 */
    return -1;
}

int luat_mplayer_set_layer_visible(luat_mplayer_t *m, int visible) {
    if (!m || !m->is_open) return -1;
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return 0;//movie_mp4_set_layer_visible((movie_mp4 *)m->media, visible);
    }
    /* 音频类型无视频图层 */
    return -1;
}

int luat_mplayer_is_paused(luat_mplayer_t *m) {
    if (!m || !m->is_open) return -1;
    if (m->media_type == MEDIA_TYPE_MP3) {

    }
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_ispause((movie_mp4 *)m->media);
    }
    /* 音频解码器(wav/flac)未提供"是否暂停"查询, 直接视为未暂停 */
    return 0;
}

int luat_mplayer_info(luat_mplayer_t *m, luat_mplayer_info_t *info) {
    if (!m || !info) return -1;
    memset(info, 0, sizeof(*info));
    if (!m->is_open) return -1;

    info->media_type = m->media_type;
    if (m->media_type == MEDIA_TYPE_MP3) {

        return 0;
    }
    if (!m->media) return -1;
    if (m->media_type != MEDIA_TYPE_MP4) {
        /* 其余音频类型(wav/flac): 仅返回类型, 各解码器信息字段结构不同 */
        return 0;
    }

    movie_mp4 *mp4 = (movie_mp4 *)m->media;
    info->fps               = (int)mp4->video_fps;
    info->width             = mp4->video_width;
    info->height            = mp4->video_height;
    info->audio_sample_rate = mp4->audio_sampleRate;
    info->audio_channels    = mp4->audio_numChannels;
    info->timestamp_ms      = (int)mp4->time_tr_ms;
    switch (mp4->movie_status) {
        case MOVIE_MP4_STAT_STOP:  info->status = LUAT_MPLAYER_STAT_STOP;  break;
        case MOVIE_MP4_STAT_PLAY:  info->status = LUAT_MPLAYER_STAT_PLAY;  break;
        case MOVIE_MP4_STAT_PAUSE: info->status = LUAT_MPLAYER_STAT_PAUSE; break;
        case MOVIE_MP4_STAT_EOS:   info->status = LUAT_MPLAYER_STAT_EOS;   break;
        default:                   info->status = LUAT_MPLAYER_STAT_UNKNOWN; break;
    }
    return 0;
}