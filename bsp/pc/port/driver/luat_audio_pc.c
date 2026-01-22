#define LUAT_LOG_TAG "audio_pc"

#include "luat_base.h"
#include "luat_audio.h"
#include "luat_i2s.h"
#include "luat_rtos.h"
#include "luat_log.h"

#include <string.h>

#ifndef AUDIO_PC_MAX_ID
#define AUDIO_PC_MAX_ID 1
#endif

typedef struct {
    uint32_t sample_rate;
    uint8_t bits;
    uint8_t channels;
    uint16_t vol;
    uint16_t mic_vol;
    uint8_t mute;
} pc_codec_runtime_t;

typedef struct {
    luat_audio_conf_t conf;
    pc_codec_runtime_t runtime;
    uint8_t codec_inited;
    uint8_t paused;
} pc_audio_dev_t;

static pc_audio_dev_t g_audio[AUDIO_PC_MAX_ID];

static pc_audio_dev_t* audio_dev(uint8_t id) {
    if (id >= AUDIO_PC_MAX_ID) {
        return NULL;
    }
    return &g_audio[id];
}

static pc_audio_dev_t* audio_dev_from_codec(luat_audio_codec_conf_t* conf) {
    if (!conf) {
        return NULL;
    }
    return audio_dev(conf->multimedia_id);
}

static int pc_codec_init(luat_audio_codec_conf_t* conf, uint8_t mode);
static int pc_codec_deinit(luat_audio_codec_conf_t* conf);
static int pc_codec_control(luat_audio_codec_conf_t* conf, luat_audio_codec_ctl_t cmd, uint32_t data);
static int pc_codec_start(luat_audio_codec_conf_t* conf);
static int pc_codec_stop(luat_audio_codec_conf_t* conf);

static const luat_audio_codec_opts_t codec_opts_pc = {
    .name = "pc",
    .init = pc_codec_init,
    .deinit = pc_codec_deinit,
    .control = pc_codec_control,
    .start = pc_codec_start,
    .stop = pc_codec_stop,
    .no_control = 0,
};

// 为了兼容通用/ES8311配置入口，导出同名opts符号，内部走PC实现
const luat_audio_codec_opts_t codec_opts_common = {
    .name = "pc_common",
    .init = pc_codec_init,
    .deinit = pc_codec_deinit,
    .control = pc_codec_control,
    .start = pc_codec_start,
    .stop = pc_codec_stop,
    .no_control = 0,
};

const luat_audio_codec_opts_t codec_opts_es8311 = {
    .name = "pc_es8311",
    .init = pc_codec_init,
    .deinit = pc_codec_deinit,
    .control = pc_codec_control,
    .start = pc_codec_start,
    .stop = pc_codec_stop,
    .no_control = 0,
};

static void audio_defaults(pc_audio_dev_t* dev, uint8_t id) {
    if (!dev) {
        return;
    }
    if (dev->conf.codec_conf.codec_opts == NULL) {
        memset(&dev->conf, 0, sizeof(luat_audio_conf_t));
        dev->conf.codec_conf.codec_opts = &codec_opts_pc;
        dev->conf.codec_conf.i2s_id = 0;
        dev->conf.codec_conf.multimedia_id = id;
        dev->conf.bus_type = LUAT_AUDIO_BUS_I2S;
        dev->conf.soft_vol = 100;
        dev->conf.last_vol = 100;
        dev->conf.last_mic_vol = 100;
        dev->runtime.vol = 100;
        dev->runtime.mic_vol = 100;
        dev->runtime.bits = LUAT_I2S_BITS_16;
        dev->runtime.sample_rate = LUAT_I2S_HZ_44k;
        dev->runtime.channels = 2;
    }
}

luat_audio_conf_t *luat_audio_get_config(uint8_t multimedia_id) {
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return NULL;
    }
    audio_defaults(dev, multimedia_id);
    return &dev->conf;
}

int luat_audio_set_bus_type(uint8_t multimedia_id,uint8_t bus_type){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return -1;
    }
    audio_defaults(dev, multimedia_id);
    if (bus_type != LUAT_AUDIO_BUS_I2S) {
        return -1;
    }
    dev->conf.bus_type = LUAT_AUDIO_BUS_I2S;
    return 0;
}

int luat_audio_setup_codec(uint8_t multimedia_id, const luat_audio_codec_conf_t *codec_conf){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev || !codec_conf) {
        return -1;
    }
    audio_defaults(dev, multimedia_id);
    dev->conf.codec_conf = *codec_conf;
    return 0;
}

static int ensure_codec_ready(pc_audio_dev_t* dev){
    if (!dev) {
        return -1;
    }
    audio_defaults(dev, dev->conf.codec_conf.multimedia_id);
    if (!dev->codec_inited) {
        if (dev->conf.codec_conf.codec_opts->init(&dev->conf.codec_conf, LUAT_CODEC_MODE_SLAVE) != 0) {
            return -1;
        }
        dev->codec_inited = 1;
    }
    return 0;
}

int luat_audio_init(uint8_t multimedia_id, uint16_t init_vol, uint16_t init_mic_vol){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return -1;
    }
    audio_defaults(dev, multimedia_id);
    dev->conf.last_vol = init_vol;
    dev->conf.last_mic_vol = init_mic_vol;
    dev->runtime.vol = init_vol;
    dev->runtime.mic_vol = init_mic_vol;
    return ensure_codec_ready(dev);
}

int luat_audio_start_raw(uint8_t multimedia_id, uint8_t audio_format, uint8_t num_channels, uint32_t sample_rate, uint8_t bits_per_sample, uint8_t is_signed){
    (void)audio_format;
    (void)is_signed;
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return -1;
    }
    if (ensure_codec_ready(dev)) {
        return -1;
    }
    dev->runtime.channels = num_channels ? num_channels : 2;
    dev->runtime.sample_rate = sample_rate ? sample_rate : LUAT_I2S_HZ_44k;
    dev->runtime.bits = bits_per_sample ? bits_per_sample : LUAT_I2S_BITS_16;
    pc_codec_control(&dev->conf.codec_conf, LUAT_CODEC_SET_CHANNEL, dev->runtime.channels);
    pc_codec_control(&dev->conf.codec_conf, LUAT_CODEC_SET_BITS, dev->runtime.bits);
    pc_codec_control(&dev->conf.codec_conf, LUAT_CODEC_SET_RATE, dev->runtime.sample_rate);
    dev->paused = 0;
    return 0;
}

int luat_audio_write_raw(uint8_t multimedia_id, uint8_t *data, uint32_t len){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev || !data || len == 0) {
        return -1;
    }
    if (ensure_codec_ready(dev)) {
        return -1;
    }
    uint32_t sent = 0;
    while (sent < len) {
        int ret = luat_i2s_send(dev->conf.codec_conf.i2s_id, data + sent, len - sent);
        if (ret < 0) {
            LLOGE("audio_pc: i2s send err at %u", sent);
            return -1;
        }
        if (ret == 0) {
            luat_rtos_task_sleep(1);
            continue;
        }
        sent += (uint32_t)ret;
    }
    return 0;
}

int luat_audio_stop_raw(uint8_t multimedia_id){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return -1;
    }
    luat_i2s_close(dev->conf.codec_conf.i2s_id);
    dev->paused = 0;
    return 0;
}

int luat_audio_pause_raw(uint8_t multimedia_id, uint8_t is_pause){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return -1;
    }
    if (is_pause) {
        luat_i2s_pause(dev->conf.codec_conf.i2s_id);
        dev->paused = 1;
    } else {
        luat_i2s_resume(dev->conf.codec_conf.i2s_id);
        dev->paused = 0;
    }
    return 0;
}

uint8_t luat_audio_is_finish(uint8_t multimedia_id){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return 1;
    }
    size_t total = 0, remain = 0;
    if (luat_i2s_txbuff_info(dev->conf.codec_conf.i2s_id, &total, &remain) != 0) {
        return 1;
    }
    return remain == total;
}

int luat_audio_play_stop(uint8_t multimedia_id){
    return luat_audio_stop_raw(multimedia_id);
}

int luat_audio_play_file(uint8_t multimedia_id, const char *path){
    (void)multimedia_id;
    (void)path;
    LLOGW("audio_pc: play_file not implemented");
    return -1;
}

int luat_audio_play_multi_files(uint8_t multimedia_id, uData_t *info, uint32_t files_num, uint8_t error_stop){
    (void)multimedia_id;
    (void)info;
    (void)files_num;
    (void)error_stop;
    LLOGW("audio_pc: multi file playback not implemented");
    return -1;
}

int luat_audio_play_get_last_error(uint8_t multimedia_id){
    (void)multimedia_id;
    return 0;
}

int luat_audio_play_blank(uint8_t multimedia_id, uint8_t on_off){
    (void)multimedia_id;
    (void)on_off;
    return 0;
}

uint16_t luat_audio_vol(uint8_t multimedia_id, uint16_t vol){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return (uint16_t)-1;
    }
    dev->runtime.vol = vol;
    dev->conf.last_vol = vol;
    return vol;
}

uint8_t luat_audio_mic_vol(uint8_t multimedia_id, uint16_t vol){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return (uint8_t)-1;
    }
    dev->runtime.mic_vol = (uint16_t)vol;
    dev->conf.last_mic_vol = (uint16_t)vol;
    return (uint8_t)vol;
}

uint8_t luat_audio_mute(uint8_t multimedia_id, uint8_t on){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return (uint8_t)-1;
    }
    dev->runtime.mute = on;
    if (on) {
        luat_i2s_pause(dev->conf.codec_conf.i2s_id);
    } else if (dev->paused == 0) {
        luat_i2s_resume(dev->conf.codec_conf.i2s_id);
    }
    return dev->runtime.mute;
}

void luat_audio_config_pa(uint8_t multimedia_id, uint32_t pin, int level, uint32_t dummy_time_len, uint32_t pa_delay_time){
    (void)multimedia_id;
    (void)pin;
    (void)level;
    (void)dummy_time_len;
    (void)pa_delay_time;
}

void luat_audio_config_dac(uint8_t multimedia_id, int pin, int level, uint32_t dac_off_delay_time){
    (void)multimedia_id;
    (void)pin;
    (void)level;
    (void)dac_off_delay_time;
}

void luat_audio_pa(uint8_t multimedia_id,uint8_t on, uint32_t delay){
    (void)multimedia_id;
    (void)on;
    (void)delay;
}

void luat_audio_power(uint8_t multimedia_id,uint8_t on){
    (void)multimedia_id;
    (void)on;
}

int luat_audio_pm_request(uint8_t multimedia_id,luat_audio_pm_mode_t mode){
    pc_audio_dev_t* dev = audio_dev(multimedia_id);
    if (!dev) {
        return -1;
    }
    dev->conf.sleep_mode = mode;
    return 0;
}

void luat_audio_power_keep_ctrl_by_bsp(uint8_t on_off){
    (void)on_off;
}

void luat_audio_run_callback_in_task(void *api, uint8_t *data, uint32_t len){
    (void)api;
    (void)data;
    (void)len;
}

void luat_audio_setup_record_callback(uint8_t multimedia_id, luat_audio_record_callback callback, void *param){
    (void)multimedia_id;
    (void)callback;
    (void)param;
}

static int pc_codec_init(luat_audio_codec_conf_t* conf, uint8_t mode){
    (void)mode;
    pc_audio_dev_t* dev = audio_dev_from_codec(conf);
    if (!dev) {
        return -1;
    }
    luat_i2s_conf_t i2s_conf = {0};
    i2s_conf.id = conf->i2s_id;
    i2s_conf.mode = LUAT_I2S_MODE_MASTER;
    i2s_conf.sample_rate = dev->runtime.sample_rate;
    i2s_conf.data_bits = dev->runtime.bits;
    i2s_conf.channel_format = dev->runtime.channels == 2 ? LUAT_I2S_CHANNEL_STEREO : LUAT_I2S_CHANNEL_LEFT;
    i2s_conf.standard = LUAT_I2S_MODE_I2S;
    i2s_conf.channel_bits = dev->runtime.bits;
    return luat_i2s_setup(&i2s_conf);
}

static int pc_codec_deinit(luat_audio_codec_conf_t* conf){
    pc_audio_dev_t* dev = audio_dev_from_codec(conf);
    if (!dev) {
        return -1;
    }
    luat_i2s_close(conf->i2s_id);
    dev->codec_inited = 0;
    return 0;
}

static int pc_codec_control(luat_audio_codec_conf_t* conf, luat_audio_codec_ctl_t cmd, uint32_t data){
    pc_audio_dev_t* dev = audio_dev_from_codec(conf);
    if (!dev) {
        return -1;
    }
    switch (cmd) {
    case LUAT_CODEC_SET_RATE:
        dev->runtime.sample_rate = data;
        luat_i2s_modify(conf->i2s_id, dev->runtime.channels == 2 ? LUAT_I2S_CHANNEL_STEREO : LUAT_I2S_CHANNEL_LEFT, dev->runtime.bits, dev->runtime.sample_rate);
        return 0;
    case LUAT_CODEC_SET_BITS:
        dev->runtime.bits = (uint8_t)data;
        luat_i2s_modify(conf->i2s_id, dev->runtime.channels == 2 ? LUAT_I2S_CHANNEL_STEREO : LUAT_I2S_CHANNEL_LEFT, dev->runtime.bits, dev->runtime.sample_rate);
        return 0;
    case LUAT_CODEC_SET_CHANNEL:
        dev->runtime.channels = (uint8_t)data;
        luat_i2s_modify(conf->i2s_id, dev->runtime.channels == 2 ? LUAT_I2S_CHANNEL_STEREO : LUAT_I2S_CHANNEL_LEFT, dev->runtime.bits, dev->runtime.sample_rate);
        return 0;
    case LUAT_CODEC_SET_MUTE:
        dev->runtime.mute = (uint8_t)data;
        return 0;
    case LUAT_CODEC_GET_MUTE:
        return dev->runtime.mute;
    case LUAT_CODEC_SET_VOICE_VOL:
        dev->runtime.vol = (uint16_t)data;
        return 0;
    case LUAT_CODEC_GET_VOICE_VOL:
        return dev->runtime.vol;
    case LUAT_CODEC_SET_MIC_VOL:
        dev->runtime.mic_vol = (uint16_t)data;
        return 0;
    case LUAT_CODEC_GET_MIC_VOL:
        return dev->runtime.mic_vol;
    case LUAT_CODEC_SET_FORMAT:
        return 0;
    default:
        return 0;
    }
}

static int pc_codec_start(luat_audio_codec_conf_t* conf){
    return luat_i2s_resume(conf->i2s_id);
}

static int pc_codec_stop(luat_audio_codec_conf_t* conf){
    return luat_i2s_pause(conf->i2s_id);
}

int luat_audio_end_raw(uint8_t multimedia_id){
    return 0;
}
