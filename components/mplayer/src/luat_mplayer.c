/*
 * luat_mplayer.c - 媒体播放器 API 层
 * 负责: 按媒体类型选择解码器并分发所有控制操作。
 * 当前仅 MP4 解码器已接入; MP3/WAV/FLAC 解码器未编入固件, 分支为 TODO。
 */

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_mplayer.h"

/** MP4 解码器*/
#include "mp4_decode.h"

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
#define MPLAYER_DS_PRIO      50   /* luat_rtos_task_create 用百分比优先级 */
#define MPLAYER_DS_STOP_TO   500   /* 停线程等待 ms */

/* 渲染线程参数 */
#define MPLAYER_RS_STACK     8 * 1024
#define MPLAYER_RS_PRIO      45   /* 略低于解码线程, 不抢占解码 */

/* MP4 解码线程入口: 周期泵 movie_mp4_task(解复用+解码+音频启动) 与
 * movie_render_task(按 PTS 对比音频主时钟渲染/丢帧), 节拍 10ms;
 * EOS 后保持空转等待上层 close(与旧版 mplayer_mp4_thread 语义一致) */
static void mplayer_mp4_task_entry(void *arg) {
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

int luat_mplayer_set_rect(luat_mplayer_t *m, int x, int y, int w, int h) {
    if (!m || !m->is_open) return -1;
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        /* 坐标进 mp4 视频层(luat_display set_layer), 播放前/播放中均可调;
         * x/y=-1 居中; w/h 目前透传预留(不做缩放) */
        return movie_mp4_set_rect((movie_mp4 *)m->media, x, y, w, h);
    }
    /* 音频类型无视频图层 */
    return -1;
}

int luat_mplayer_set_audio_enable(luat_mplayer_t *m, int en) {
    if (!m || !m->is_open) return -1;
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        /* 写 movie->audio_en, 解码线程轮询生效; 播放中/暂停均可切换 */
        return movie_mp4_set_audio_enable((movie_mp4 *)m->media, en);
    }
    /* 音频类型无此语义 */
    return -1;
}

int luat_mplayer_set_layer_visible(luat_mplayer_t *m, int visible) {
    if (!m || !m->is_open) return -1;
    if (!m->media) return -1;
    if (m->media_type == MEDIA_TYPE_MP4) {
        return movie_mp4_set_layer_visible((movie_mp4 *)m->media, visible);
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