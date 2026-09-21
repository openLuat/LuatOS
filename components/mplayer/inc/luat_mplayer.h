#ifndef LUAT_MPLAYER_H
#define LUAT_MPLAYER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 媒体类型 */
typedef enum MediaType {
    MEDIA_TYPE_UNKNOWN = 0,
    MEDIA_TYPE_MP4 = 1,   /* mp4/m4v 视频 */
    MEDIA_TYPE_MP3 = 2,   /* mp3 音乐 */
    MEDIA_TYPE_WAV = 3,   /* wav 音频 */
    MEDIA_TYPE_FLAC = 4,  /* flac 音频 */
} MediaType;

/* 播放器上下文(由 luat_mplayer_open 创建, luat_mplayer_close 销毁) */
typedef struct luat_mplayer_ctx {
    void *media;          /* 实际解码器上下文, 如 movie_mp4* / mp3_t* 等 */
    MediaType media_type;
    int is_open;
    int decode_running;   /* 解码线程运行标志(1=运行, 0=已请求停止) */
    void *decode_task;    /* 解码线程句柄 (TaskHandle_t) */
    void *done_sem;       /* 解码线程退出信号 (SemaphoreHandle_t) */
} luat_mplayer_t;

/* 播放状态(与具体解码器解耦) */
typedef enum LuatMPlayerStatus {
    LUAT_MPLAYER_STAT_UNKNOWN = 0,
    LUAT_MPLAYER_STAT_STOP    = 1,
    LUAT_MPLAYER_STAT_PLAY    = 2,
    LUAT_MPLAYER_STAT_PAUSE   = 3,
    LUAT_MPLAYER_STAT_EOS     = 4,
} LuatMPlayerStatus;

/* 媒体信息(由 luat_mplayer_info 填充) */
typedef struct luat_mplayer_info {
    MediaType media_type;
    int fps;
    int width;
    int height;
    int audio_sample_rate;
    int audio_channels;
    int timestamp_ms;
    LuatMPlayerStatus status;
} luat_mplayer_info_t;

/* 按 path 扩展名识别类型并按类型加载解码器; 失败返回 NULL */
luat_mplayer_t *luat_mplayer_open(const char *path);
/* 停止并按类型释放解码器, 销毁上下文; 成功返回 0 */
int luat_mplayer_close(luat_mplayer_t *m);
/* 播放; 成功返回 0 */
int luat_mplayer_play(luat_mplayer_t *m);
/* 暂停; 成功返回 0 */
int luat_mplayer_pause(luat_mplayer_t *m);
/* 恢复播放; 成功返回 0 */
int luat_mplayer_resume(luat_mplayer_t *m);
/* 停止播放; 成功返回 0 */
int luat_mplayer_stop(luat_mplayer_t *m);
/* 是否正在播放: 1=是 0=否 -1=失败 */
int luat_mplayer_is_playing(luat_mplayer_t *m);
/* 是否已暂停: 1=是 0=否 -1=失败 */
int luat_mplayer_is_paused(luat_mplayer_t *m);
/* 读取媒体信息到 info; 成功返回 0 */
int luat_mplayer_info(luat_mplayer_t *m, luat_mplayer_info_t *info);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_MPLAYER_H */