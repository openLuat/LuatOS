/*
 * luat_mplayer.c - 媒体播放器 API 层
 * 负责: 按媒体类型选择解码器并分发所有控制操作。
 * 当前仅 MP4 解码器已接入; MP3/WAV/FLAC 解码器未编入固件, 分支为 TODO。
 */

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_mplayer.h"

/* MP4 解码器(已接入) */
#include "mp4_decode.h"
/* H.264 解码通过 h264_set_disp_callback 把解出帧回传, 用 avcodec 子目录形式含入 */
#include "avcodec/h264_decode.h"

/* 解码线程(基于 FreeRTOS; 信号量/挂起操作用到) */
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

#include <string.h>

#define LUAT_LOG_TAG "mplayer"
#include "luat_log.h"

/* 解码线程参数 */
#define MPLAYER_DS_STACK     24 * 1024
#define MPLAYER_DS_PRIO      50   /* luat_rtos_task_create 用百分比优先级 */
#define MPLAYER_DS_STOP_TO   500   /* 停线程等待 ms */

/* ---- 视频显示链路 + mp4 解码线程已移入 mp4_decode.c(声明见 mp4_decode.h) ----
 * 数据流: H.264 解出帧(YUV420P) -> YUV_RGB_565 汇编转 RGB565
 *         -> display_funcs->set_layer 挂到 LCDC 视频层(layer 1) 直接扫描显示 */

/* 启动 mp4 解码线程 */
static int mplayer_start_mp4_thread(luat_mplayer_t *m) {
    SemaphoreHandle_t sem = xSemaphoreCreateBinary();
    if (!sem) return -1;
    m->done_sem = sem;

    m->decode_running = 1;
    m->decode_task = NULL;
    /* 必须走 luat_rtos_task_create: 内部 soc_create_event_task 会为任务挂
     * task_ext_ctrl(delay_timer/event_timer), 否则 soc_task_sleep_ms 崩溃。 */
    if (luat_rtos_task_create((luat_rtos_task_handle *)&m->decode_task, MPLAYER_DS_STACK,
                              MPLAYER_DS_PRIO, "mplayer", mplayer_mp4_thread, m, 0) != 0) {
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
    }
    /* TODO: 启用对应音频解码器后填入:
     *   MEDIA_TYPE_MP3  -> return load_mp3((char*)path);
     *   MEDIA_TYPE_WAV  -> return load_wave((char*)path);
     *   MEDIA_TYPE_FLAC -> return load_flac((char*)path); */
    return NULL;
}

/* 按媒体类型停止并释放解码器 */
static void luat_mplayer_unload_media(void *media, MediaType type) {
    if (type == MEDIA_TYPE_MP4) {
        movie_mp4 *mp4 = (movie_mp4 *)media;
        movie_mp4_stop(mp4);
        /* 释放解码器前先注销 H.264 解出帧回调, 避免悬垂指针 */
        h264_set_disp_callback(NULL);
        movie_mp4_release(mp4);
        return;
    }
    /* TODO: 启用对应音频解码器后填入:
     *   MEDIA_TYPE_MP3  -> mp3_release((mp3_t *)media);
     *   MEDIA_TYPE_WAV  -> wave_release((WAVE *)media);
     *   MEDIA_TYPE_FLAC -> flac_release((flac_t *)media); */
}

luat_mplayer_t *luat_mplayer_open(const char *path) {
    if (!path) return NULL;

    MediaType type = luat_mplayer_detect_type(path);
    void *media = luat_mplayer_load(type, path);
    if (!media) {
        LLOGE("open %s failed: decoder not support", path);
        return NULL;
    }

    luat_mplayer_t *m = (luat_mplayer_t *)luat_heap_malloc(sizeof(luat_mplayer_t));
    if (!m) {
        luat_mplayer_unload_media(media, type);
        return NULL;
    }
    m->media = media;
    m->media_type = type;
    m->is_open = 1;
    m->decode_running = 0;
    m->decode_task = NULL;
    m->done_sem = NULL;
    /* MP4: 注册 H.264 解出帧回调(仅验证 got_frame) */
    if (type == MEDIA_TYPE_MP4) {
        h264_set_disp_callback(mplayer_h264_disp_cb);
    }
    return m;
}

int luat_mplayer_close(luat_mplayer_t *m) {
    if (!m || !m->is_open) return -1;
    /* 先停解码线程, 再释放解码器, 最后销毁上下文 */
    mplayer_stop_mp4_thread(m);
    if (m->media) {
        luat_mplayer_unload_media(m->media, m->media_type);
        m->media = NULL;
    }
#if defined(LUAT_USE_DISPLAY)
    /* 注销显示回调时视频层缓冲已不再被引用, 一并释放 */
    mplayer_video_layer_deinit();
#endif
    m->is_open = 0;
    luat_heap_free(m);
    return 0;
}

int luat_mplayer_play(luat_mplayer_t *m) {
    if (!m || !m->is_open || !m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        if (m->decode_running) return 0;   /* 已在播放 */
        if (movie_mp4_play((movie_mp4 *)m->media) != 0) {
            return -1;
        }
        if (mplayer_start_mp4_thread(m) != 0) {
            movie_mp4_stop((movie_mp4 *)m->media);
            return -1;
        }
        return 0;
    }
    /* TODO: 按类型播放, 例如:
     *   MEDIA_TYPE_MP3  -> return mp3_play((mp3_t *)m->media);
     *   MEDIA_TYPE_WAV  -> return wave_play((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_play((flac_t *)m->media); */
    return -1;
}

int luat_mplayer_pause(luat_mplayer_t *m) {
    if (!m || !m->is_open || !m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_pause((movie_mp4 *)m->media);
    }
    /* TODO: 按类型暂停, 例如:
     *   MEDIA_TYPE_MP3  -> return mp3_pause((mp3_t *)m->media);
     *   MEDIA_TYPE_WAV  -> return wave_pause((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_pause((flac_t *)m->media); */
    return -1;
}

int luat_mplayer_resume(luat_mplayer_t *m) {
    if (!m || !m->is_open || !m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_resume((movie_mp4 *)m->media);
    }
    /* TODO: 按类型恢复, 例如:
     *   MEDIA_TYPE_MP3  -> return mp3_resume((mp3_t *)m->media);
     *   MEDIA_TYPE_WAV  -> return wave_resume((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_resume((flac_t *)m->media); */
    return -1;
}

int luat_mplayer_stop(luat_mplayer_t *m) {
    if (!m || !m->is_open || !m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        mplayer_stop_mp4_thread(m);
        return movie_mp4_stop((movie_mp4 *)m->media);
    }
    /* TODO: 按类型停止, 例如:
     *   MEDIA_TYPE_MP3  -> return mp3_stop((mp3_t *)m->media);
     *   MEDIA_TYPE_WAV  -> return wave_stop((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_stop((flac_t *)m->media); */
    return -1;
}

int luat_mplayer_is_playing(luat_mplayer_t *m) {
    if (!m || !m->is_open || !m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_isplay((movie_mp4 *)m->media);
    }
    /* TODO: 按类型查询, 例如:
     *   MEDIA_TYPE_MP3  -> return mp3_isplay((mp3_t *)m->media);
     *   MEDIA_TYPE_WAV  -> return wave_isplay((WAVE *)m->media);
     *   MEDIA_TYPE_FLAC -> return flac_isplay((flac_t *)m->media); */
    return 0;
}

int luat_mplayer_is_paused(luat_mplayer_t *m) {
    if (!m || !m->is_open || !m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_ispause((movie_mp4 *)m->media);
    }
    /* 音频解码器(mp3/wav/flac)未提供"是否暂停"查询, 直接视为未暂停 */
    return 0;
}

/* 平台未编入 minimimp3 解码器栈, 但 mp4_decode 的 USER_MP3_DECODER 路径在链接期引用了
 * mp3_decode_frame。提供弱引用 stub: 音频线程拿到 samples=0 会提前返回、不触 sound 设备。
 * 后续接入真正 MP3 解码器时, 该符号会被强符号(如 audio_decode/mp3/mp3player.c 的实现)覆盖。 */
unsigned int __attribute__((weak)) mp3_decode_frame(unsigned char *d, unsigned int n, short *pcm, int *sr, int *ch) {
    (void)d; (void)n; (void)pcm; (void)sr; (void)ch;
    return 0;
}

int luat_mplayer_info(luat_mplayer_t *m, luat_mplayer_info_t *info) {
    if (!m || !info) return -1;
    memset(info, 0, sizeof(*info));
    if (!m->is_open || !m->media) return -1;

    info->media_type = m->media_type;
    if (m->media_type != MEDIA_TYPE_MP4) {
        /* 音频类型: 仅返回类型, 各解码器信息字段结构不同 */
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