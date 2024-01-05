#include "luat_base.h"
#include "luat_gpio.h"
#include"luat_i2s.h"
#include "luat_audio.h"
#include "luat_multimedia.h"

#define LUAT_LOG_TAG "audio"
#include "luat_log.h"

LUAT_WEAK luat_audio_conf_t *luat_audio_get_config(uint8_t multimedia_id){
    return NULL;
}

LUAT_WEAK int luat_audio_play_multi_files(uint8_t multimedia_id, uData_t *info, uint32_t files_num, uint8_t error_stop){

}

LUAT_WEAK int luat_audio_play_file(uint8_t multimedia_id, const char *path){

}

LUAT_WEAK uint8_t luat_audio_is_finish(uint8_t multimedia_id){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            luat_i2s_conf_t * i2s_conf = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);
            i2s_conf->state==LUAT_I2S_STATE_STOP?1:0;
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_play_stop(uint8_t multimedia_id){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            return luat_i2s_close(audio_conf->codec_conf.i2s_id);
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_play_get_last_error(uint8_t multimedia_id){

}

LUAT_WEAK int luat_audio_start_raw(uint8_t multimedia_id, uint8_t audio_format, uint8_t num_channels, uint32_t sample_rate, uint8_t bits_per_sample, uint8_t is_signed){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            luat_i2s_conf_t * i2s_conf = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);
            i2s_conf->data_bits = bits_per_sample;
            i2s_conf->sample_rate = sample_rate,
            luat_i2s_modify(audio_conf->codec_conf.i2s_id,i2s_conf->channel_format,i2s_conf->data_bits, i2s_conf->sample_rate);
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_RATE,sample_rate);
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_PA,audio_conf->codec_conf.pa_on_level);
        }
    }
    return 0;
}

LUAT_WEAK int luat_audio_write_raw(uint8_t multimedia_id, uint8_t *data, uint32_t len){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            int send_bytes = 0;
            while (send_bytes < len) {
                int length = luat_i2s_send(audio_conf->codec_conf.i2s_id,data + send_bytes, len - send_bytes);
                if (length > 0) {
                    send_bytes += length;
                }
                luat_rtos_task_sleep(1);
            }
        }
    }
    return 0;
}

LUAT_WEAK int luat_audio_stop_raw(uint8_t multimedia_id){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            return luat_i2s_close(audio_conf->codec_conf.i2s_id);
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_pause_raw(uint8_t multimedia_id, uint8_t is_pause){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            if (is_pause){
                audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_PA,!audio_conf->codec_conf.pa_on_level);
                luat_i2s_pause(audio_conf->codec_conf.i2s_id);
            }else{
                audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_PA,audio_conf->codec_conf.pa_on_level);
                luat_i2s_resume(audio_conf->codec_conf.i2s_id);
            }
            return 0;
        }
    }
    return -1;
}

LUAT_WEAK void luat_audio_config_pa(uint8_t multimedia_id, uint32_t pin, int level, uint32_t dummy_time_len, uint32_t pa_delay_time){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            if (pin != 255){
                audio_conf->codec_conf.pa_pin = pin;
                audio_conf->codec_conf.pa_on_level = level;
                luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, !level);
                luat_gpio_set(pin, !level);
            }else{
                audio_conf->codec_conf.pa_pin = LUAT_CODEC_PA_NONE;
            }
            audio_conf->codec_conf.dummy_time_len = dummy_time_len;
            audio_conf->codec_conf.pa_delay_time = pa_delay_time;
        }
    }
}

LUAT_WEAK void luat_audio_config_dac(uint8_t multimedia_id, int pin, int level, uint32_t dac_off_delay_time){}

LUAT_WEAK uint16_t luat_audio_vol(uint8_t multimedia_id, uint16_t vol){
    if(vol < 0 || vol > 100){
		return -1;
    }
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL,vol);
            return audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_VOICE_VOL,0);
        }
    }
    return -1;
}

LUAT_WEAK void luat_audio_set_bus_type(uint8_t multimedia_id,uint8_t bus_type){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (bus_type == MULTIMEDIA_AUDIO_BUS_I2S){
            audio_conf->bus_type = MULTIMEDIA_AUDIO_BUS_I2S;
            audio_conf->codec_conf.codec_opts->init(&audio_conf->codec_conf,LUAT_CODEC_MODE_SLAVE);
        }
    }
}


































