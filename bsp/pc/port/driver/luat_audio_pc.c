#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#endif

#include "ffmpeg.h"

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_audio.h"
#include "luat_rtos.h"
#include "luat_timer.h"
#include "luat_fs.h"
#include "luat_i2s.h"
#include <string.h>

#define LUAT_LOG_TAG "audio_pc"
#include "luat_log.h"

#ifdef LUAT_USE_GUI
#include <SDL2/SDL.h>
#endif

extern int l_multimedia_raw_handler(lua_State *L, void* ptr);

// dll动态链接是否开启标志
uint8_t luat_audio_dll_enable = 0;

// ffmepg必须要求通道号-0
#define AUDIO_DEVICE_ID 0
static luat_audio_conf_t audio_config = {0};

luat_audio_conf_t *luat_audio_get_config(uint8_t multimedia_id) {
    if (multimedia_id != AUDIO_DEVICE_ID) {
        return NULL;
    }
    return &audio_config;
}


static void luat_audio_event_cb(uint32_t event, void *param){
	rtos_msg_t msg = {0};
	switch(event)
	{
	case LUAT_MULTIMEDIA_CB_AUDIO_DECODE_START:
		luat_audio_check_ready(0);
		break;
	case LUAT_MULTIMEDIA_CB_AUDIO_OUTPUT_START:
		break;
	case LUAT_MULTIMEDIA_CB_AUDIO_NEED_DATA:
		break;
	case LUAT_MULTIMEDIA_CB_TTS_INIT:
		break;
	case LUAT_MULTIMEDIA_CB_TTS_DONE:
		break;
	case LUAT_MULTIMEDIA_CB_AUDIO_DONE:
		luat_audio_play_blank(0,1);
		msg.handler = l_multimedia_raw_handler;
		msg.arg1 = LUAT_MULTIMEDIA_CB_AUDIO_DONE;
		msg.arg2 = 0;
		luat_msgbus_put(&msg, 1);
		break;
	}
}

int luat_audio_play_multi_files(uint8_t multimedia_id, uData_t *info, uint32_t files_num, uint8_t error_stop) {

    if(!luat_audio_dll_enable) {
        if(luat_load_ffmpeg_dlls()  == 0) {
            luat_audio_dll_enable = 1;
        } else {
            LLOGE("Failed to load ffmpeg dlls");
            return -1;
        }
    }

    for(uint32_t i = 0; i < files_num; i++) {
        const char* file_path = NULL;

        // 从 uData_t 获取文件路径
        if (info[i].Type == UDATA_TYPE_OPAQUE) {
            file_path = (const char*)info[i].value.asBuffer.buffer;
        } else {
            LLOGE("Invalid file info type at index %d, type=%d", i, info[i].Type);
            if (error_stop) {
                LLOGE("Stopping playback due to error");
                luat_audio_event_cb(LUAT_MULTIMEDIA_CB_AUDIO_DONE, (void*)(uintptr_t)multimedia_id);
                return -1;
            }
            continue;
        }

        int ret = luat_ffmpeg_play_file(file_path);
        if (ret != 0) {
            LLOGE("Failed to play file: %s", file_path);
            if (error_stop) {
                luat_audio_event_cb(LUAT_MULTIMEDIA_CB_AUDIO_DONE, (void*)(uintptr_t)multimedia_id);
                return -1;
            }
        }
    }
    luat_audio_event_cb(LUAT_MULTIMEDIA_CB_AUDIO_DONE, (void*)(uintptr_t)multimedia_id);

    return 0;
}

int luat_audio_play_file(uint8_t multimedia_id, const char *path) {
    uData_t info[1];
    info[0].value.asBuffer.buffer = (void*)path;
    info[0].value.asBuffer.length = strlen(path);
    info[0].Type = UDATA_TYPE_OPAQUE;

    return luat_audio_play_multi_files(multimedia_id, info, 1, 1);
}

int luat_audio_stop_raw(uint8_t multimedia_id) {
    luat_audio_play_stop(multimedia_id);
#ifdef _WIN32
    // 卸载FFmpeg DLL
    luat_unload_ffmpeg_dlls();
    luat_audio_dll_enable = 0;
#endif
    return 0;
}

uint16_t luat_audio_vol(uint8_t multimedia_id, uint16_t vol) {
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf) {
        audio_conf->soft_vol = vol;
        LLOGD("audio.vol: set to %d", vol);
    }
    return vol;
}

// void luat_audio_set_debug(uint8_t on_off) {
//     if (on_off) {
//         luat_ffmpeg_set_debug(1);
//     } else {
//         luat_ffmpeg_set_debug(0);
//     }
// }

/* ------------PC模拟器使用ffmpeg不支持的部分-------------- */
int luat_audio_check_ready(uint8_t multimedia_id) {
    (void)multimedia_id;
    return 0;
}

int luat_audio_start_raw(uint8_t multimedia_id, uint8_t audio_format, uint8_t num_channels, uint32_t sample_rate, uint8_t bits_per_sample, uint8_t is_signed) {
    (void)multimedia_id;
    (void)audio_format;
    (void)num_channels;
    (void)sample_rate;
    (void)bits_per_sample;
    (void)is_signed;
    return 0;
}

uint8_t luat_audio_is_finish(uint8_t multimedia_id) {
    (void)multimedia_id;
    return 1; // 总是返回完成状态
}

int luat_audio_play_stop(uint8_t multimedia_id) {
    (void)multimedia_id;
    return 0;
}

int luat_audio_write_raw(uint8_t multimedia_id, uint8_t *data, uint32_t len) {
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf) {
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S) {
            return 0;
        }
    }
    return -1;
}

int luat_audio_pause_raw(uint8_t multimedia_id, uint8_t is_pause) {
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf) {
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S) {
            if (is_pause) {
                return 0;
            } else {
                return 0;
            }
        }
    }
    return -1;
}

void luat_audio_config_pa(uint8_t multimedia_id, uint32_t pin, int level, uint32_t dummy_time_len, uint32_t pa_delay_time) {
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf) {
        audio_conf->pa_pin = pin;
        audio_conf->pa_on_level = level;
        audio_conf->after_sleep_ready_time = dummy_time_len;
        audio_conf->pa_delay_time = pa_delay_time;
        LLOGD("audio.config_pa: pin=%d, level=%d", pin, level);
    }
}

void luat_audio_config_dac(uint8_t multimedia_id, int pin, int level, uint32_t dac_off_delay_time) {
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf) {
        audio_conf->power_pin = pin;
        audio_conf->power_on_level = level;
        audio_conf->power_off_delay_time = dac_off_delay_time;
        LLOGD("audio.config_dac: pin=%d, level=%d", pin, level);
    }
}

uint8_t luat_audio_mic_vol(uint8_t multimedia_id, uint16_t vol) {
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf) {
        audio_conf->last_mic_vol = vol;
        LLOGD("audio.micVol: set to %d", vol);
    }
    return vol;
}

int luat_audio_pm_request(uint8_t multimedia_id, luat_audio_pm_mode_t mode) {
    (void)multimedia_id;
    (void)mode;
    return 0;
}

int luat_audio_play_blank(uint8_t multimedia_id, uint8_t on_off) {
    (void)multimedia_id;
    (void)on_off;
    return 0;
}

int luat_audio_play_get_last_error(uint8_t multimedia_id) {
    (void)multimedia_id;
    return 0;
}

void luat_audio_play_debug_onoff(uint8_t multimedia_id, uint8_t onoff) {
    (void)multimedia_id;
    (void)onoff;
}

void luat_audio_pa(uint8_t multimedia_id, uint8_t on, uint32_t delay) {
    (void)multimedia_id;
    (void)on;
    (void)delay;
}

void luat_audio_power(uint8_t multimedia_id, uint8_t on) {
    (void)multimedia_id;
    (void)on;
}

void luat_audio_power_keep_ctrl_by_bsp(uint8_t on_off) {
    (void)on_off;
}

void luat_audio_run_callback_in_task(void *api, uint8_t *data, uint32_t len) {
    (void)api;
    (void)data;
    (void)len;
}

int luat_audio_set_bus_type(uint8_t multimedia_id, uint8_t bus_type) {
    (void)multimedia_id;
    (void)bus_type;
    return 0;
}

int luat_audio_init(uint8_t multimedia_id, uint16_t init_vol, uint16_t init_mic_vol) {
    (void)init_vol;
    (void)init_mic_vol;
    return 0;
}

