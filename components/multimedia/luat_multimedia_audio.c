#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_i2s.h"
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
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            luat_i2s_conf_t * i2s_conf = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);
            i2s_conf->state==LUAT_I2S_STATE_STOP?1:0;
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_play_stop(uint8_t multimedia_id){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
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
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            luat_i2s_conf_t * i2s_conf = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);
            i2s_conf->data_bits = bits_per_sample;
            i2s_conf->sample_rate = sample_rate,
            luat_i2s_modify(audio_conf->codec_conf.i2s_id,i2s_conf->channel_format,i2s_conf->data_bits, i2s_conf->sample_rate);
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_RATE,sample_rate);
            luat_audio_pa(multimedia_id,1,0);
        }
    }
    return 0;
}

LUAT_WEAK int luat_audio_write_raw(uint8_t multimedia_id, uint8_t *data, uint32_t len){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
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
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            return luat_i2s_close(audio_conf->codec_conf.i2s_id);
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_pause_raw(uint8_t multimedia_id, uint8_t is_pause){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            if (is_pause){
                luat_audio_pa(multimedia_id,0,0);
                luat_i2s_pause(audio_conf->codec_conf.i2s_id);
            }else{
                luat_audio_pa(multimedia_id,1,0);
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
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            if (pin != LUAT_GPIO_NONE && pin<LUAT_GPIO_PIN_MAX && pin>0){
                audio_conf->pa_pin = pin;
                audio_conf->pa_on_level = level;
                luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, !level);
                luat_gpio_set(pin, !level);
            }else{
                audio_conf->pa_pin = LUAT_GPIO_NONE;
            }
            audio_conf->after_sleep_ready_time = dummy_time_len;
            audio_conf->pa_delay_time = pa_delay_time;
        }
    }
}

LUAT_WEAK void luat_audio_config_dac(uint8_t multimedia_id, int pin, int level, uint32_t dac_off_delay_time){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            if (pin != LUAT_GPIO_NONE){
                audio_conf->power_pin = pin;
                audio_conf->power_on_level = level;
                audio_conf->power_off_delay_time = dac_off_delay_time;
            }else{
                audio_conf->power_pin = LUAT_GPIO_NONE;
            }
        }
    }
}

static LUAT_RT_RET_TYPE pa_delay_timer_cb(LUAT_RT_CB_PARAM){
    uint8_t multimedia_id = (uint8_t)param;
    luat_audio_pa(multimedia_id,1, 0);
}

LUAT_WEAK void luat_audio_pa(uint8_t multimedia_id,uint8_t on, uint32_t delay){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->pa_pin == LUAT_GPIO_NONE) return;
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            if (audio_conf->pa_delay_timer!=NULL&&delay>0){
                luat_rtos_timer_start(audio_conf->pa_delay_timer,delay,0,pa_delay_timer_cb,(void*)multimedia_id);
            }
            else{
                luat_gpio_set(audio_conf->pa_pin, on?audio_conf->pa_on_level:!audio_conf->pa_on_level);
                audio_conf->pa_on_enable = 1;
            }
        }
    }
}

LUAT_WEAK void luat_audio_power(uint8_t multimedia_id,uint8_t on){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->power_pin == LUAT_GPIO_NONE) return;
        luat_gpio_set(audio_conf->power_pin, on?audio_conf->power_on_level:!audio_conf->power_on_level);
    }
}

LUAT_WEAK uint16_t luat_audio_vol(uint8_t multimedia_id, uint16_t vol){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf == NULL || vol < 0 || vol > 1000) return -1;
    audio_conf->soft_vol = vol<=100?100:vol;
    if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
        if (vol <= 100){
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL,vol);
            return audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_VOICE_VOL,0);
        }else{
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL,100);
            return vol;
        }
    }
    return -1;
}

LUAT_WEAK uint8_t luat_audio_mic_vol(uint8_t multimedia_id, uint16_t vol){
    if(vol < 0 || vol > 100) return -1;
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            if (audio_conf->codec_conf.codec_opts->no_control) return -1;
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MIC_VOL,vol);
            return audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_MIC_VOL,0);
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_setup_codec(uint8_t multimedia_id, const luat_audio_codec_conf_t *codec_conf){
	luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            audio_conf->codec_conf= *codec_conf;
            return 0;
        }
    }
    return -1;
}

//TODO
LUAT_WEAK int luat_audio_play_blank(uint8_t multimedia_id){
    return -1;
}

LUAT_WEAK int luat_audio_init(uint8_t multimedia_id, uint16_t init_vol, uint16_t init_mic_vol){
	luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf == NULL) return -1;

    if (audio_conf->pa_pin != LUAT_GPIO_NONE){
        luat_rtos_timer_create(&audio_conf->pa_delay_timer);
    }

    audio_conf->is_sleep = 0;
    audio_conf->last_wakeup_time_ms = luat_mcu_tick64_ms();
    if (audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
        int result = audio_conf->codec_conf.codec_opts->init(&audio_conf->codec_conf, LUAT_CODEC_MODE_SLAVE);
        if (result) return result;
        LLOGD("codec init %s ",audio_conf->codec_conf.codec_opts->name);
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_RATE, LUAT_I2S_HZ_16k);
        if (result) return result;
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_BITS, LUAT_I2S_BITS_16);
        if (result) return result;
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_FORMAT,LUAT_CODEC_FORMAT_I2S);
        if (result) return result;
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL, init_vol);
        if (result) return result;
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MIC_VOL, init_mic_vol);
        if (result) return result;

        luat_audio_pm_request(multimedia_id,LUAT_AUDIO_PM_STANDBY); //默认进入standby模式

        //不应该默认进normal模式，会增加功耗，无pa控制应该根据pa是否传入有效引脚去播放白音或者用户自己控制
        // result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_RESUME,LUAT_CODEC_MODE_ALL);
        // if (result) return result;
        return 0;
    }
	return 0;
}

LUAT_WEAK int luat_audio_set_bus_type(uint8_t multimedia_id,uint8_t bus_type){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
            audio_conf->codec_conf.multimedia_id = multimedia_id;
            audio_conf->bus_type = LUAT_MULTIMEDIA_AUDIO_BUS_I2S;
            return 0;
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_pm_request(uint8_t multimedia_id,luat_audio_pm_mode_t mode){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf!=NULL && audio_conf->bus_type == LUAT_MULTIMEDIA_AUDIO_BUS_I2S){
        switch (mode){
        case LUAT_AUDIO_PM_RESUME:
            //同下,何时传输空白音
            // if (!audio_conf->speech_uplink_type && !audio_conf->speech_downlink_type && !audio_conf->record_mode)
			// 	luat_audio_play_blank(multimedia_id);
            audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
			audio_conf->wakeup_ready = 0;
			audio_conf->pa_on_enable = 0;
			audio_conf->last_wakeup_time_ms = luat_mcu_tick64_ms();
            audio_conf->is_sleep = 0;
            break;
        case LUAT_AUDIO_PM_STANDBY:
            audio_conf->codec_conf.codec_opts->stop(&audio_conf->codec_conf);
            //非控制的关闭i2s输出?输出白噪音?此处或codec具体处理
            // luat_i2s_close(audio_conf->codec_conf.i2s_id);
            audio_conf->is_sleep = 1;
            break;
        case LUAT_AUDIO_PM_SHUTDOWN:
            luat_audio_pa(multimedia_id,0,0);
			if (audio_conf->power_off_delay_time)
				luat_rtos_task_sleep(audio_conf->power_off_delay_time);
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_PWRDOWN,0);
            //非控制的关闭i2s输出?
            // luat_i2s_close(audio_conf->codec_conf.i2s_id);
			audio_conf->wakeup_ready = 0;
			audio_conf->pa_on_enable = 0;
            audio_conf->is_sleep = 1;
            break;
        default:
            return -1;
        }
        return 0;
    }
    return -1;
}





