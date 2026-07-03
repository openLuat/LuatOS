#define SDL_MAIN_HANDLED

#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_audio_pc.h"
#include "luat_audio_data_codec.h"
#include "luat_audio_driver.h"
#include "luat_common_api.h"
#include <SDL2/SDL.h>
#include <limits.h>
#include <string.h>

#define LUAT_LOG_TAG "audio_v2.pc"
#include "luat_log.h"

#ifdef LUAT_USE_AUDIO_V2

#define PC_AUDIO_MAX_BLOCK_LEN 8000U
#define PC_AUDIO_DEFAULT_RATE 16000U
#define PC_AUDIO_DEFAULT_ALIGN 2U
#define PC_AUDIO_DEFAULT_CHANNELS 1U
#define PC_AUDIO_CALLBACK_FRAMES_MIN 128U
#define PC_AUDIO_CALLBACK_FRAMES_MAX 4096U

typedef struct {
    luat_audio_driver_ctrl_t *ctrl;
    SDL_AudioDeviceID tx_device;
    SDL_AudioDeviceID rx_device;
    uint8_t *tx_buffer;
    uint8_t *rx_buffer;
    uint32_t tx_block_len;
    uint32_t rx_block_len;
    uint32_t tx_block_num;
    uint32_t rx_block_num;
    uint32_t tx_block_pos;
    uint32_t rx_block_pos;
    uint32_t tx_block_offset;
    uint32_t rx_block_offset;
} pc_audio_v2_driver_t;

static pc_audio_v2_driver_t g_pc_audio_v2;

static int pc_audio_start_tx(luat_audio_driver_ctrl_t *ctrl, uint32_t **play_buff,
                             uint32_t one_block_len, uint32_t block_num);
static int pc_audio_start_rx(luat_audio_driver_ctrl_t *ctrl, uint32_t **record_buff,
                             uint32_t one_block_len, uint32_t block_num);
static void pc_audio_stop(luat_audio_driver_ctrl_t *ctrl);

static SDL_AudioFormat pc_audio_sdl_format(uint8_t data_align)
{
    switch (data_align) {
    case 1:
        return AUDIO_S8;
    case 2:
        return AUDIO_S16SYS;
    case 4:
        return AUDIO_S32SYS;
    default:
        return 0;
    }
}

static Uint16 pc_audio_callback_frames(const luat_audio_common_param_t *param, uint32_t block_len)
{
    uint32_t bytes_per_frame = (uint32_t)param->data_align * param->channel_nums;
    uint32_t frames = bytes_per_frame ? block_len / bytes_per_frame : 0;
    if (frames < PC_AUDIO_CALLBACK_FRAMES_MIN) {
        frames = PC_AUDIO_CALLBACK_FRAMES_MIN;
    } else if (frames > PC_AUDIO_CALLBACK_FRAMES_MAX) {
        frames = PC_AUDIO_CALLBACK_FRAMES_MAX;
    }
    return (Uint16)frames;
}

static int pc_audio_make_spec(luat_audio_driver_ctrl_t *ctrl,
                              const luat_audio_common_param_t *param, uint32_t block_len,
                              SDL_AudioCallback callback, SDL_AudioSpec *spec)
{
    SDL_AudioFormat format = pc_audio_sdl_format(param->data_align);
    if (!format || !param->sample_rate ||
        (param->channel_nums != 1 && param->channel_nums != 2)) {
        return -LUAT_ERROR_PARAM_INVALID;
    }

    SDL_zero(*spec);
    spec->freq = (int)param->sample_rate;
    spec->format = format;
    spec->channels = param->channel_nums;
    spec->samples = pc_audio_callback_frames(param, block_len);
    spec->callback = callback;
    spec->userdata = ctrl->driver_data;
    return LUAT_ERROR_NONE;
}

static void SDLCALL pc_audio_tx_callback(void *userdata, Uint8 *stream, int len)
{
    pc_audio_v2_driver_t *driver = (pc_audio_v2_driver_t *)userdata;
    int rest = len;

    memset(stream, 0, (size_t)len);
    if (!driver || !driver->ctrl || !driver->tx_buffer ||
        !driver->tx_block_len || !driver->tx_block_num) {
        return;
    }
    while (rest > 0) {
        uint32_t block_rest = driver->tx_block_len - driver->tx_block_offset;
        uint32_t copy_len = block_rest < (uint32_t)rest ? block_rest : (uint32_t)rest;
        uint8_t *block = driver->tx_buffer + driver->tx_block_pos * driver->tx_block_len;
        memcpy(stream, block + driver->tx_block_offset, copy_len);
        stream += copy_len;
        rest -= (int)copy_len;
        driver->tx_block_offset += copy_len;

        if (driver->tx_block_offset == driver->tx_block_len) {
            driver->tx_block_offset = 0;
            driver->tx_block_pos = (driver->tx_block_pos + 1) % driver->tx_block_num;
            luat_audio_driver_event_callback(LUAT_AUDIO_DRIVER_EVENT_TX_ONE_BLOCK_DONE,
                                             NULL, 0, driver->ctrl);
        }
    }
}

static void SDLCALL pc_audio_rx_callback(void *userdata, Uint8 *stream, int len)
{
    pc_audio_v2_driver_t *driver = (pc_audio_v2_driver_t *)userdata;
    int rest = len;

    if (!driver || !driver->ctrl || !driver->rx_buffer ||
        !driver->rx_block_len || !driver->rx_block_num) {
        return;
    }
    while (rest > 0) {
        uint32_t block_rest = driver->rx_block_len - driver->rx_block_offset;
        uint32_t copy_len = block_rest < (uint32_t)rest ? block_rest : (uint32_t)rest;
        uint8_t *block = driver->rx_buffer + driver->rx_block_pos * driver->rx_block_len;
        memcpy(block + driver->rx_block_offset, stream, copy_len);
        stream += copy_len;
        rest -= (int)copy_len;
        driver->rx_block_offset += copy_len;

        if (driver->rx_block_offset == driver->rx_block_len) {
            driver->rx_block_offset = 0;
            driver->rx_block_pos = (driver->rx_block_pos + 1) % driver->rx_block_num;
            luat_audio_driver_event_callback(LUAT_AUDIO_DRIVER_EVENT_RX_ONE_BLOCK_DONE,
                                             block, driver->rx_block_len, driver->ctrl);
        }
    }
}

static void pc_audio_close_tx(pc_audio_v2_driver_t *driver)
{
    if (driver->tx_device) {
        SDL_PauseAudioDevice(driver->tx_device, 1);
        SDL_CloseAudioDevice(driver->tx_device);
        driver->tx_device = 0;
    }
    if (driver->tx_buffer) {
        SDL_free(driver->tx_buffer);
        driver->tx_buffer = NULL;
    }
    driver->tx_block_len = 0;
    driver->tx_block_num = 0;
    driver->tx_block_pos = 0;
    driver->tx_block_offset = 0;
}

static void pc_audio_close_rx(pc_audio_v2_driver_t *driver)
{
    if (driver->rx_device) {
        SDL_PauseAudioDevice(driver->rx_device, 1);
        SDL_CloseAudioDevice(driver->rx_device);
        driver->rx_device = 0;
    }
    if (driver->rx_buffer) {
        SDL_free(driver->rx_buffer);
        driver->rx_buffer = NULL;
    }
    driver->rx_block_len = 0;
    driver->rx_block_num = 0;
    driver->rx_block_pos = 0;
    driver->rx_block_offset = 0;
}

static int pc_audio_init(luat_audio_driver_ctrl_t *ctrl)
{
    pc_audio_v2_driver_t *driver = (pc_audio_v2_driver_t *)ctrl->driver_data;
    if (!driver) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    memset(driver, 0, sizeof(*driver));
    driver->ctrl = ctrl;
    ctrl->tx_param.sample_rate = PC_AUDIO_DEFAULT_RATE;
    ctrl->tx_param.data_align = PC_AUDIO_DEFAULT_ALIGN;
    ctrl->tx_param.channel_nums = PC_AUDIO_DEFAULT_CHANNELS;
    ctrl->tx_param.is_signed = 1;
    ctrl->rx_param = ctrl->tx_param;
    return LUAT_ERROR_NONE;
}

static int pc_audio_config(luat_audio_driver_ctrl_t *ctrl, uint32_t param,
                           uint32_t value1, uint32_t value2)
{
    (void)ctrl;
    (void)param;
    (void)value1;
    (void)value2;
    return -LUAT_ERROR_PERMISSION_DENIED;
}

static int pc_audio_activate(luat_audio_driver_ctrl_t *ctrl)
{
    const char *backend;

    (void)ctrl;

    if ((SDL_WasInit(SDL_INIT_AUDIO) & SDL_INIT_AUDIO) == 0 &&
        SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
        LLOGE("SDL audio init failed: %s", SDL_GetError());
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    backend = SDL_GetCurrentAudioDriver();
    LLOGI("SDL audio backend: %s", backend ? backend : "unknown");
    if (backend && !strcmp(backend, "dummy")) {
        LLOGW("SDL dummy backend selected; audio is processed but cannot be heard");
    }
    return LUAT_ERROR_NONE;
}

static int pc_audio_modify(luat_audio_driver_ctrl_t *ctrl, uint32_t sample_rate,
                           uint8_t data_align, uint8_t channel_nums, uint8_t is_rx_dir)
{
    pc_audio_v2_driver_t *driver = (pc_audio_v2_driver_t *)ctrl->driver_data;
    luat_audio_common_param_t *param;
    uint8_t restart;
    uint32_t block_len;
    uint32_t block_num;
    int ret;

    if (!driver || !sample_rate || !data_align || !channel_nums) {
        return -LUAT_ERROR_PARAM_INVALID;
    }

    if (data_align == 3) {
        data_align = 4;
    }
    if (data_align != 1 && data_align != 2 && data_align != 4) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (channel_nums != 1 && channel_nums != 2) {
        return -LUAT_ERROR_PARAM_INVALID;
    }

    param = is_rx_dir ? &ctrl->rx_param : &ctrl->tx_param;
    if (param->sample_rate == sample_rate &&
        param->data_align == data_align &&
        param->channel_nums == channel_nums) {
        return LUAT_ERROR_NONE;
    }

    if (is_rx_dir) {
        restart = (driver->rx_device || driver->rx_buffer) ? 1 : 0;
        block_len = driver->rx_block_len;
        block_num = driver->rx_block_num;
    } else {
        restart = (driver->tx_device || driver->tx_buffer) ? 1 : 0;
        block_len = driver->tx_block_len;
        block_num = driver->tx_block_num;
    }

    if (restart) {
        LLOGI("restart SDL %s device for format change: %uHz/%uch/%ubit -> %uHz/%uch/%ubit",
              is_rx_dir ? "input" : "output", param->sample_rate, param->channel_nums,
              param->data_align * 8U, sample_rate, channel_nums, data_align * 8U);
        if (is_rx_dir) {
            pc_audio_close_rx(driver);
            ctrl->record_buff = NULL;
        } else {
            pc_audio_close_tx(driver);
            ctrl->play_buff = NULL;
            ctrl->current_play_cnt = 0;
        }
    }

    param->sample_rate = sample_rate;
    param->data_align = data_align;
    param->channel_nums = channel_nums;
    param->is_signed = 1;

    if (restart) {
        if (is_rx_dir) {
            ret = pc_audio_start_rx(ctrl, &ctrl->record_buff, block_len, block_num);
        } else {
            ret = pc_audio_start_tx(ctrl, &ctrl->play_buff, block_len, block_num);
        }
        if (ret) {
            pc_audio_stop(ctrl);
            ctrl->state = LUAT_AUDIO_DRIVER_STATE_ACTIVE;
            return ret;
        }
    }
    return LUAT_ERROR_NONE;
}

static int pc_audio_fill(luat_audio_driver_ctrl_t *ctrl, uint8_t *play_buff,
                         uint32_t len_bytes, uint8_t is_signed, uint8_t align)
{
    (void)ctrl;
    (void)is_signed;
    (void)align;
    if (!play_buff) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    memset(play_buff, 0, len_bytes);
    return LUAT_ERROR_NONE;
}

static int pc_audio_start_tx(luat_audio_driver_ctrl_t *ctrl, uint32_t **play_buff,
                             uint32_t one_block_len, uint32_t block_num)
{
    pc_audio_v2_driver_t *driver = (pc_audio_v2_driver_t *)ctrl->driver_data;
    SDL_AudioSpec spec;
    size_t total_len;

    if (!driver || !play_buff || !one_block_len || !block_num || driver->tx_device || driver->tx_buffer) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (pc_audio_make_spec(ctrl, &ctrl->tx_param, one_block_len, pc_audio_tx_callback, &spec)) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    total_len = (size_t)one_block_len * block_num;
    if (total_len > UINT_MAX) {
        return -LUAT_ERROR_PARAM_OVERFLOW;
    }

    driver->tx_buffer = (uint8_t *)SDL_calloc(1, total_len);
    if (!driver->tx_buffer) {
        return -LUAT_ERROR_NO_MEMORY;
    }
    driver->tx_block_len = one_block_len;
    driver->tx_block_num = block_num;
    driver->tx_block_pos = 0;
    driver->tx_block_offset = 0;
    *play_buff = (uint32_t *)driver->tx_buffer;
    ctrl->one_play_block_len = one_block_len;

    driver->tx_device = SDL_OpenAudioDevice(NULL, 0, &spec, NULL, 0);
    if (!driver->tx_device) {
        LLOGE("open default output failed: %s", SDL_GetError());
        pc_audio_close_tx(driver);
        *play_buff = NULL;
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    LLOGI("output ready: %s, %uHz %uch %ubit block=%u x %u",
          SDL_GetAudioDeviceName(0, 0) ? SDL_GetAudioDeviceName(0, 0) : "default",
           ctrl->tx_param.sample_rate, ctrl->tx_param.channel_nums,
           ctrl->tx_param.data_align * 8U, one_block_len, block_num);
    SDL_PauseAudioDevice(driver->tx_device, 0);
    return LUAT_ERROR_NONE;
}

static int pc_audio_start_rx(luat_audio_driver_ctrl_t *ctrl, uint32_t **record_buff,
                             uint32_t one_block_len, uint32_t block_num)
{
    pc_audio_v2_driver_t *driver = (pc_audio_v2_driver_t *)ctrl->driver_data;
    SDL_AudioSpec spec;
    size_t total_len;

    if (!driver || !record_buff || !one_block_len || !block_num || driver->rx_device || driver->rx_buffer) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (pc_audio_make_spec(ctrl, &ctrl->rx_param, one_block_len, pc_audio_rx_callback, &spec)) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    total_len = (size_t)one_block_len * block_num;
    if (total_len > UINT_MAX) {
        return -LUAT_ERROR_PARAM_OVERFLOW;
    }

    driver->rx_buffer = (uint8_t *)SDL_calloc(1, total_len);
    if (!driver->rx_buffer) {
        return -LUAT_ERROR_NO_MEMORY;
    }
    driver->rx_block_len = one_block_len;
    driver->rx_block_num = block_num;
    driver->rx_block_pos = 0;
    driver->rx_block_offset = 0;
    *record_buff = (uint32_t *)driver->rx_buffer;
    ctrl->one_record_block_len = one_block_len;

    driver->rx_device = SDL_OpenAudioDevice(NULL, 1, &spec, NULL, 0);
    if (!driver->rx_device) {
        LLOGE("open default input failed: %s", SDL_GetError());
        pc_audio_close_rx(driver);
        *record_buff = NULL;
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    LLOGI("input ready: %s, %uHz %uch %ubit block=%u x %u",
          SDL_GetAudioDeviceName(0, 1) ? SDL_GetAudioDeviceName(0, 1) : "default",
           ctrl->rx_param.sample_rate, ctrl->rx_param.channel_nums,
           ctrl->rx_param.data_align * 8U, one_block_len, block_num);
    SDL_PauseAudioDevice(driver->rx_device, 0);
    return LUAT_ERROR_NONE;
}

static void pc_audio_stop(luat_audio_driver_ctrl_t *ctrl)
{
    pc_audio_v2_driver_t *driver = (pc_audio_v2_driver_t *)ctrl->driver_data;
    if (!driver) {
        return;
    }
    pc_audio_close_rx(driver);
    pc_audio_close_tx(driver);
    ctrl->play_buff = NULL;
    ctrl->record_buff = NULL;
}

static void pc_audio_deactivate(luat_audio_driver_ctrl_t *ctrl)
{
    pc_audio_stop(ctrl);
}

static void pc_audio_deinit(luat_audio_driver_ctrl_t *ctrl)
{
    pc_audio_v2_driver_t *driver = (pc_audio_v2_driver_t *)ctrl->driver_data;
    pc_audio_stop(ctrl);
    if (driver) {
        driver->ctrl = NULL;
    }
}

const luat_audio_driver_opts_t luat_audio_sdl_opts = {
    .init = pc_audio_init,
    .config_private_param = pc_audio_config,
    .activate = pc_audio_activate,
    .modify_audio_common_param = pc_audio_modify,
    .dac_data_align = NULL,
    .fill = pc_audio_fill,
    .start_tx_loop = pc_audio_start_tx,
    .start_rx_loop = pc_audio_start_rx,
    .start_full_loop = NULL,
    .start_full_loop_with_play_buff = NULL,
    .cache_sync = NULL,
    .stop = pc_audio_stop,
    .deactivate = pc_audio_deactivate,
    .deinit = pc_audio_deinit,
    .tx_one_block_max_len = PC_AUDIO_MAX_BLOCK_LEN,
    .rx_one_block_max_len = PC_AUDIO_MAX_BLOCK_LEN,
    .support_tx_loop = 1,
    .support_rx_loop = 1,
    .support_full_loop = 0,
    .support_continue = 1,
    .is_tx_signed = 1,
    .is_rx_signed = 1,
};

void luat_audio_data_codec_register_all(void)
{
#ifdef LUAT_SUPPORT_AMR
    luat_audio_data_codec_register(&luat_audio_data_codec_amr_nb_opts);
    luat_audio_data_codec_register(&luat_audio_data_codec_amr_wb_opts);
#endif
    luat_audio_data_codec_register(&luat_audio_data_codec_mp3_opts);
    luat_audio_data_codec_register(&luat_audio_data_codec_wav_opts);
    luat_audio_data_codec_register(&luat_audio_data_codec_raw_opts);
#ifdef LUAT_USE_AUDIO_G711
    luat_audio_data_codec_register(&luat_audio_data_codec_g711_ulaw_opts);
    luat_audio_data_codec_register(&luat_audio_data_codec_g711_alaw_opts);
#endif
}

void luat_audio_driver_register_all(void)
{
    luat_audio_driver_probe_t probe = {
        .tx_bus_type = LUAT_AUDIO_DRIVER_TYPE_USB,
        .tx_bus_id = 0,
        .rx_bus_type = LUAT_AUDIO_DRIVER_TYPE_USB,
        .rx_bus_id = 0,
    };

    if (luat_audio_driver_register(&luat_audio_sdl_opts, probe, &g_pc_audio_v2)) {
        LLOGE("register default SDL full-duplex driver failed");
    }
}

#endif
