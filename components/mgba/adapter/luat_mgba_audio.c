/**
 * @file luat_mgba_audio.c
 * @brief LuatOS mGBA SDL2 音频输出适配器实现
 * 
 * 该文件实现了 mGBA 音频输出到 SDL2
 */

#include "luat_conf_bsp.h"

#ifdef LUAT_USE_MGBA

#include "luat_mgba.h"

#ifdef __LUATOS__
#include "luat_malloc.h"
#include "luat_log.h"
#define LUAT_LOG_TAG "mgba.audio"
#define MGBA_MALLOC(size) luat_heap_malloc(size)
#define MGBA_FREE(ptr) luat_heap_free(ptr)
#else
#include <stdlib.h>
#include <stdio.h>
#define MGBA_MALLOC(size) malloc(size)
#define MGBA_FREE(ptr) free(ptr)
#endif

#include <string.h>

/* SDL2 头文件 - 仅在有 GUI 支持时包含 */
#ifdef LUAT_USE_GUI
#include <SDL2/SDL.h>
#else
/* 如果没有 GUI 支持，提供空实现 */
typedef struct SDL_AudioSpec SDL_AudioSpec;
typedef unsigned int SDL_AudioDeviceID;
#define SDL_INIT_AUDIO 0x10
#endif

/* ========== 音频常量 ========== */

#define DEFAULT_SAMPLE_RATE  44100
#define DEFAULT_CHANNELS     2
#define DEFAULT_BUFFER_SIZE  1024
#define DEFAULT_VOLUME       128

/* ========== 音频输出上下文结构 ========== */

struct luat_mgba_audio {
    SDL_AudioDeviceID device;
    
    int sample_rate;        /**< 采样率 */
    int channels;           /**< 声道数 */
    int buffer_size;        /**< 缓冲区大小 */
    int volume;             /**< 音量 (0-128) */
    
    int initialized;        /**< 初始化标志 */
    int paused;             /**< 暂停标志 */
    int enabled;            /**< 启用标志 */
};

/* ========== 默认配置 ========== */

static const luat_mgba_audio_config_t default_audio_config = {
    .sample_rate = DEFAULT_SAMPLE_RATE,
    .channels = DEFAULT_CHANNELS,
    .buffer_size = DEFAULT_BUFFER_SIZE,
    .enabled = 1
};

/* ========== 公共 API 实现 ========== */

void luat_mgba_audio_get_default_config(luat_mgba_audio_config_t* config) {
    if (config) {
        memcpy(config, &default_audio_config, sizeof(luat_mgba_audio_config_t));
    }
}

luat_mgba_audio_t* luat_mgba_audio_init(const luat_mgba_audio_config_t* config) {
#ifdef LUAT_USE_GUI
    luat_mgba_audio_config_t cfg;
    if (config) {
        memcpy(&cfg, config, sizeof(luat_mgba_audio_config_t));
    } else {
        memcpy(&cfg, &default_audio_config, sizeof(luat_mgba_audio_config_t));
    }
    
    /* 分配上下文 */
    luat_mgba_audio_t* audio = (luat_mgba_audio_t*)MGBA_MALLOC(sizeof(luat_mgba_audio_t));
    if (!audio) {
        return NULL;
    }
    memset(audio, 0, sizeof(luat_mgba_audio_t));
    
    if (!cfg.enabled) {
        audio->enabled = 0;
        audio->initialized = 1;
        return audio;
    }
    
    /* 初始化 SDL 音频子系统 */
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) {
        #ifdef __LUATOS__
        LLOGE("SDL_InitSubSystem(AUDIO) failed: %s", SDL_GetError());
        #endif
        MGBA_FREE(audio);
        return NULL;
    }
    
    /* 设置音频规格 */
    SDL_AudioSpec spec;
    memset(&spec, 0, sizeof(spec));
    spec.freq = cfg.sample_rate;
    spec.format = AUDIO_S16SYS;  /* 有符号 16 位小端 */
    spec.channels = cfg.channels;
    spec.samples = cfg.buffer_size;
    spec.callback = NULL;  /* 使用队列模式 */
    spec.userdata = audio;
    
    /* 打开音频设备 */
    audio->device = SDL_OpenAudioDevice(
        NULL, 0, &spec, NULL, 
        SDL_AUDIO_ALLOW_FREQUENCY_CHANGE | SDL_AUDIO_ALLOW_CHANNELS_CHANGE
    );
    
    if (audio->device == 0) {
        #ifdef __LUATOS__
        LLOGE("SDL_OpenAudioDevice failed: %s", SDL_GetError());
        #endif
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
        MGBA_FREE(audio);
        return NULL;
    }
    
    /* 开始播放 */
    SDL_PauseAudioDevice(audio->device, 0);
    
    audio->sample_rate = cfg.sample_rate;
    audio->channels = cfg.channels;
    audio->buffer_size = cfg.buffer_size;
    audio->volume = DEFAULT_VOLUME;
    audio->initialized = 1;
    audio->paused = 0;
    audio->enabled = 1;
    
    #ifdef __LUATOS__
    LLOGI("mGBA audio initialized: %d Hz, %d ch, buffer %d",
          audio->sample_rate, audio->channels, audio->buffer_size);
    #endif
    
    return audio;
    
#else /* !LUAT_USE_GUI */
    /* 没有 GUI 支持，返回禁用状态的上下文 */
    luat_mgba_audio_t* audio = (luat_mgba_audio_t*)MGBA_MALLOC(sizeof(luat_mgba_audio_t));
    if (audio) {
        memset(audio, 0, sizeof(luat_mgba_audio_t));
        audio->enabled = 0;
        audio->initialized = 1;
    }
    return audio;
#endif
}

void luat_mgba_audio_deinit(luat_mgba_audio_t* audio) {
#ifdef LUAT_USE_GUI
    if (!audio) {
        return;
    }
    
    if (audio->device) {
        SDL_CloseAudioDevice(audio->device);
        audio->device = 0;
    }
    
    /* 注意：不调用 SDL_QuitSubSystem，因为其他组件可能还在使用 SDL */
    
    audio->initialized = 0;
    MGBA_FREE(audio);
    
    #ifdef __LUATOS__
    LLOGI("mGBA audio deinitialized");
    #endif
#else
    if (audio) {
        MGBA_FREE(audio);
    }
#endif
}

int luat_mgba_audio_output(luat_mgba_audio_t* audio, const int16_t* samples, size_t count) {
#ifdef LUAT_USE_GUI
    if (!audio || !audio->initialized || !audio->enabled || !samples) {
        return -1;
    }
    
    if (audio->paused || !audio->device) {
        return 0;
    }
    
    /* 计算数据大小 (每样本 2 字节 * 声道数) */
    size_t data_size = count * audio->channels * sizeof(int16_t);
    
    /* 如果需要音量调节 (非默认音量) */
    if (audio->volume != DEFAULT_VOLUME) {
        /* 分配临时缓冲区用于音量调节 */
        int16_t* temp = (int16_t*)MGBA_MALLOC(data_size);
        if (!temp) {
            return -2;
        }
        
        /* 复制并调节音量 */
        size_t sample_count = count * audio->channels;
        for (size_t i = 0; i < sample_count; i++) {
            /* 简单的音量调节 (线性) */
            int32_t sample = (int32_t)samples[i] * audio->volume / DEFAULT_VOLUME;
            /* 限幅 */
            if (sample > 32767) sample = 32767;
            if (sample < -32768) sample = -32768;
            temp[i] = (int16_t)sample;
        }
        
        /* 送入音频队列 */
        int ret = SDL_QueueAudio(audio->device, temp, data_size);
        MGBA_FREE(temp);
        
        if (ret < 0) {
            #ifdef __LUATOS__
            LLOGE("SDL_QueueAudio failed: %s", SDL_GetError());
            #endif
            return -3;
        }
    } else {
        /* 默认音量，直接送入队列 */
        if (SDL_QueueAudio(audio->device, samples, data_size) < 0) {
            #ifdef __LUATOS__
            LLOGE("SDL_QueueAudio failed: %s", SDL_GetError());
            #endif
            return -3;
        }
    }
    
    return 0;
#else
    (void)audio;
    (void)samples;
    (void)count;
    return -1;
#endif
}

void luat_mgba_audio_pause(luat_mgba_audio_t* audio, int pause) {
#ifdef LUAT_USE_GUI
    if (!audio || !audio->initialized || !audio->enabled) {
        return;
    }
    
    if (audio->device) {
        SDL_PauseAudioDevice(audio->device, pause ? 1 : 0);
    }
    
    audio->paused = pause;
#else
    (void)audio;
    (void)pause;
#endif
}

void luat_mgba_audio_set_volume(luat_mgba_audio_t* audio, int volume) {
    if (!audio) {
        return;
    }
    
    /* 限制音量范围 */
    if (volume < 0) volume = 0;
    if (volume > 128) volume = 128;
    
    audio->volume = volume;
}

void luat_mgba_audio_clear(luat_mgba_audio_t* audio) {
#ifdef LUAT_USE_GUI
    if (!audio || !audio->initialized || !audio->enabled) {
        return;
    }
    
    if (audio->device) {
        SDL_ClearQueuedAudio(audio->device);
    }
#else
    (void)audio;
#endif
}

#endif /* LUAT_USE_MGBA */