#define SDL_MAIN_HANDLED

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_i2s.h"
#include "lua.h"

#include <SDL.h>
#include <string.h>

#define LUAT_LOG_TAG "i2s_pc"
#include "luat_log.h"

#ifndef I2S_MAX_DEVICE
#define I2S_MAX_DEVICE 1
#endif

typedef struct {
    SDL_AudioDeviceID dev;            // SDL playback device id
    SDL_AudioSpec spec;               // Negotiated audio spec
    size_t queue_limit;               // Soft cap for queued audio bytes
    luat_i2s_conf_t conf;             // Last applied I2S configuration
} i2s_pc_device_t;

static i2s_pc_device_t g_i2s[I2S_MAX_DEVICE];
static uint8_t g_sdl_audio_ready = 0;

static int sdl_audio_init_once(void) {
    if (g_sdl_audio_ready) {
        return 0;
    }
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
        LLOGE("SDL audio init failed: %s", SDL_GetError());
        return -1;
    }
    g_sdl_audio_ready = 1;
    return 0;
}

static SDL_AudioFormat map_bits_to_sdl(uint8_t bits) {
    switch (bits) {
    case 8:
        return AUDIO_S8;
    case 16:
        return AUDIO_S16LSB;
    case 24:
    case 32:
        return AUDIO_S32LSB; // SDL does not expose 24-bit, pad to 32-bit
    default:
        return AUDIO_S16LSB;
    }
}

static uint8_t calc_channels(uint8_t channel_format) {
    return channel_format == LUAT_I2S_CHANNEL_STEREO ? 2 : 1;
}

static size_t bytes_per_second(const SDL_AudioSpec* spec) {
    const uint8_t bytes = (uint8_t)(SDL_AUDIO_BITSIZE(spec->format) / 8);
    return (size_t)spec->freq * (size_t)spec->channels * bytes;
}

int luat_i2s_setup(const luat_i2s_conf_t *conf) {
    if (conf == NULL || conf->id >= I2S_MAX_DEVICE) {
        LLOGE("i2s setup: invalid id");
        return -1;
    }

    if (sdl_audio_init_once()) {
        return -1;
    }

    i2s_pc_device_t *dev = &g_i2s[conf->id];
    if (dev->dev) {
        SDL_ClearQueuedAudio(dev->dev);
        SDL_CloseAudioDevice(dev->dev);
        dev->dev = 0;
    }

    SDL_AudioSpec desired;
    SDL_zero(desired);
    desired.freq = conf->sample_rate ? conf->sample_rate : LUAT_I2S_HZ_44k;
    desired.format = map_bits_to_sdl(conf->data_bits);
    desired.channels = calc_channels(conf->channel_format);
    desired.samples = 1024; // 1024 frames per callback (SDL handles buffering)
    desired.callback = NULL; // use SDL_QueueAudio

    SDL_AudioSpec obtained;
    SDL_zero(obtained);
    dev->dev = SDL_OpenAudioDevice(NULL, 0, &desired, &obtained, 0);
    if (dev->dev == 0) {
        LLOGE("i2s[%d] SDL_OpenAudioDevice failed: %s", conf->id, SDL_GetError());
        return -1;
    }

    if (obtained.format != desired.format || obtained.channels != desired.channels || obtained.freq != desired.freq) {
        LLOGE("i2s[%d] SDL format mismatch req=%dch %dHz %dbit got=%dch %dHz %dbit", conf->id,
              desired.channels, desired.freq, SDL_AUDIO_BITSIZE(desired.format),
              obtained.channels, obtained.freq, SDL_AUDIO_BITSIZE(obtained.format));
        SDL_CloseAudioDevice(dev->dev);
        dev->dev = 0;
        return -1;
    }

    SDL_PauseAudioDevice(dev->dev, 0);
    dev->spec = obtained;

    const size_t bps = bytes_per_second(&obtained);
    dev->queue_limit = bps ? bps / 2 : 4096; // 0.5s buffer cap
    if (dev->queue_limit < 4096) {
        dev->queue_limit = 4096;
    }

    memcpy(&dev->conf, conf, sizeof(luat_i2s_conf_t));
    dev->conf.state = LUAT_I2S_STATE_RUNING;

        LLOGI("i2s[%d] ready: %dHz %dch %dbit queue_limit=%u", conf->id, obtained.freq,
            obtained.channels, SDL_AUDIO_BITSIZE(obtained.format), (unsigned)dev->queue_limit);

    return 0;
}

int luat_i2s_modify(uint8_t id, uint8_t channel_format, uint8_t data_bits, uint32_t sample_rate) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }
    luat_i2s_conf_t conf = g_i2s[id].conf;
    conf.channel_format = channel_format;
    conf.data_bits = data_bits;
    conf.sample_rate = sample_rate;
    return luat_i2s_setup(&conf);
}

int luat_i2s_send(uint8_t id, uint8_t* buff, size_t len) {
    if (id >= I2S_MAX_DEVICE || buff == NULL || len == 0) {
        return -1;
    }

    i2s_pc_device_t *dev = &g_i2s[id];
    if (dev->dev == 0) {
        LLOGE("i2s[%d] send before setup", id);
        return -1;
    }

    const size_t queued = SDL_GetQueuedAudioSize(dev->dev);
    if (queued >= dev->queue_limit) {
        // LLOGD("i2s[%d] queue full queued=%u limit=%u", id, (unsigned)queued, (unsigned)dev->queue_limit);
        return 0; // caller will retry after yielding
    }

    if (SDL_QueueAudio(dev->dev, buff, (Uint32)len) != 0) {
        LLOGE("i2s[%d] queue failed: %s", id, SDL_GetError());
        return -1;
    }
    return (int)len;
}

int luat_i2s_recv(uint8_t id, uint8_t* buff, size_t len) {
    (void)buff;
    (void)len;
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }
    LLOGW("i2s[%d] recv not supported on PC", id);
    return -1;
}

int luat_i2s_transfer(uint8_t id, uint8_t* txbuff, size_t len) {
    (void)id;
    (void)txbuff;
    (void)len;
    return -1;
}

int luat_i2s_transfer_loop(uint8_t id, uint8_t* buff, uint32_t one_truck_byte_len, uint32_t total_trunk_cnt, uint8_t need_callback) {
    (void)id;
    (void)buff;
    (void)one_truck_byte_len;
    (void)total_trunk_cnt;
    (void)need_callback;
    return -1;
}

int luat_i2s_pause(uint8_t id) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }
    i2s_pc_device_t *dev = &g_i2s[id];
    if (dev->dev == 0) {
        return -1;
    }
    SDL_PauseAudioDevice(dev->dev, 1);
    dev->conf.state = LUAT_I2S_STATE_STOP;
    return 0;
}

int luat_i2s_resume(uint8_t id) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }
    i2s_pc_device_t *dev = &g_i2s[id];
    if (dev->dev == 0) {
        return -1;
    }
    SDL_PauseAudioDevice(dev->dev, 0);
    dev->conf.state = LUAT_I2S_STATE_RUNING;
    return 0;
}

int luat_i2s_close(uint8_t id) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }

    i2s_pc_device_t *dev = &g_i2s[id];
    if (dev->dev) {
        SDL_ClearQueuedAudio(dev->dev);
        SDL_CloseAudioDevice(dev->dev);
        dev->dev = 0;
    }
    dev->conf.state = LUAT_I2S_STATE_STOP;
    return 0;
}

luat_i2s_conf_t *luat_i2s_get_config(uint8_t id) {
    if (id >= I2S_MAX_DEVICE) {
        return NULL;
    }
    return &g_i2s[id].conf;
}

int luat_i2s_save_old_config(uint8_t id) {
    (void)id;
    return 0;
}

int luat_i2s_load_old_config(uint8_t id) {
    (void)id;
    return 0;
}

int luat_i2s_txbuff_info(uint8_t id, size_t *buffsize, size_t* remain) {
    if (id >= I2S_MAX_DEVICE || buffsize == NULL || remain == NULL) {
        return -1;
    }

    i2s_pc_device_t *dev = &g_i2s[id];
    if (dev->dev == 0) {
        *buffsize = 0;
        *remain = 0;
        return -1;
    }

    const size_t queued = SDL_GetQueuedAudioSize(dev->dev);
    *buffsize = dev->queue_limit;
    *remain = (queued >= dev->queue_limit) ? 0 : (dev->queue_limit - queued);
    return 0;
}

int luat_i2s_rxbuff_info(uint8_t id, size_t *buffsize, size_t* remain) {
    if (id >= I2S_MAX_DEVICE || buffsize == NULL || remain == NULL) {
        return -1;
    }
    *buffsize = 0;
    *remain = 0;
    return -1;
}

int luat_i2s_set_user_data(uint8_t id, void *user_data) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }

    g_i2s[id].conf.userdata = user_data;
    return 0;
}

LUAT_WEAK int l_i2s_play(lua_State *L) {
    LLOGD("i2s.play not supported on PC");
    return 0;
}

LUAT_WEAK int l_i2s_pause(lua_State *L) {
    LLOGD("i2s.pause not supported on PC");
    return 0;
}

LUAT_WEAK int l_i2s_stop(lua_State *L) {
    LLOGD("i2s.stop not supported on PC");
    return 0;
}
