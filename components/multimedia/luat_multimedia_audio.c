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
    return -1;
}


LUAT_WEAK int luat_audio_play_file(uint8_t multimedia_id, const char *path){
	return -1;
}

LUAT_WEAK uint8_t luat_audio_is_finish(uint8_t multimedia_id){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            luat_i2s_conf_t * i2s_conf = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);
            i2s_conf->state==LUAT_I2S_STATE_STOP?1:0;
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_play_stop(uint8_t multimedia_id){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
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
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
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
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
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
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            return luat_i2s_close(audio_conf->codec_conf.i2s_id);
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_pause_raw(uint8_t multimedia_id, uint8_t is_pause){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
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

//以上函数通用方法待实现


LUAT_WEAK void luat_audio_config_pa(uint8_t multimedia_id, uint32_t pin, int level, uint32_t dummy_time_len, uint32_t pa_delay_time){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (pin != LUAT_GPIO_NONE && pin<LUAT_GPIO_PIN_MAX && pin>0){
            audio_conf->pa_pin = pin;
            audio_conf->pa_on_level = level;
            luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, !level);
            luat_gpio_set(pin, !level);
            audio_conf->pa_is_control_enable = 1;
            luat_rtos_timer_create(&audio_conf->pa_delay_timer);
        }else{
            audio_conf->pa_pin = LUAT_GPIO_NONE;
        }
        audio_conf->after_sleep_ready_time = dummy_time_len;
        audio_conf->pa_delay_time = pa_delay_time;
    }
}

LUAT_WEAK void luat_audio_config_dac(uint8_t multimedia_id, int pin, int level, uint32_t dac_off_delay_time){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (pin != LUAT_GPIO_NONE){
            audio_conf->power_pin = pin;
            audio_conf->power_on_level = level;
            audio_conf->power_off_delay_time = dac_off_delay_time;
        }else{
            audio_conf->power_pin = LUAT_GPIO_NONE;
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
        if (!audio_conf->pa_is_control_enable) return;
        
        if (audio_conf->pa_delay_timer!=NULL&&delay>0){
            luat_rtos_timer_start(audio_conf->pa_delay_timer,delay,0,pa_delay_timer_cb,(void*)multimedia_id);
        }
        else{
            luat_gpio_set(audio_conf->pa_pin, on?audio_conf->pa_on_level:!audio_conf->pa_on_level);
            if (on) audio_conf->pa_on_enable = 1;
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
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
        uint8_t sleep_mode = audio_conf->sleep_mode;
        audio_conf->last_vol = vol;
        if (sleep_mode && audio_conf->codec_conf.codec_opts->no_control!=1) luat_audio_pm_request(multimedia_id,LUAT_AUDIO_PM_RESUME);
        if (vol <= 100){
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL,vol);
            vol = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_VOICE_VOL,0);
        }else{
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL,100);
        }
        if (sleep_mode && audio_conf->codec_conf.codec_opts->no_control!=1) luat_audio_pm_request(multimedia_id,sleep_mode);
        return vol;
    }
    return -1;
}

LUAT_WEAK uint8_t luat_audio_mic_vol(uint8_t multimedia_id, uint16_t vol){
    if(vol < 0 || vol > 100) return -1;
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            if (audio_conf->codec_conf.codec_opts->no_control) return -1;
            uint8_t sleep_mode = audio_conf->sleep_mode;
            if (sleep_mode) luat_audio_pm_request(multimedia_id,LUAT_AUDIO_PM_RESUME);
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MIC_VOL,vol);
            vol = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_MIC_VOL,0);
            if (sleep_mode) luat_audio_pm_request(multimedia_id,sleep_mode);
            audio_conf->last_mic_vol = vol;
            return vol;
        }
    }
    return -1;
}

//通用方式待实现
LUAT_WEAK int luat_audio_play_blank(uint8_t multimedia_id, uint8_t on_off){
    return -1;
}

LUAT_WEAK uint8_t luat_audio_mute(uint8_t multimedia_id, uint8_t on){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
    	if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S)
    	{
    		if (audio_conf->codec_conf.codec_opts->no_control)
    		{
    			luat_audio_play_blank(multimedia_id, 1);
    		}
    		else
    		{
    			audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MUTE,on);
    			return audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_MUTE,0);
    		}

    	}
    }
    return -1;
}

LUAT_WEAK int luat_audio_setup_codec(uint8_t multimedia_id, const luat_audio_codec_conf_t *codec_conf){
	luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            audio_conf->codec_conf= *codec_conf;
            return 0;
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_init(uint8_t multimedia_id, uint16_t init_vol, uint16_t init_mic_vol){
	luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf == NULL) return -1;
    audio_conf->last_wakeup_time_ms = luat_mcu_tick64_ms();
    audio_conf->last_vol = init_vol;
    audio_conf->last_mic_vol = init_mic_vol;
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
    	if (audio_conf->codec_conf.codec_opts->no_control)
    	{
    		audio_conf->sleep_mode = LUAT_AUDIO_PM_SHUTDOWN;
    		return 0;
    	}
    	luat_audio_power_keep_ctrl_by_bsp(1);
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

        if (!audio_conf->pa_is_control_enable)	//PA无法控制的状态，则通过静音来控制
        {
        	audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
        	audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MUTE, 1);
        }
        else
        {
            luat_audio_pm_request(multimedia_id,LUAT_AUDIO_PM_STANDBY); //默认进入standby模式

        }
        audio_conf->sleep_mode = LUAT_AUDIO_PM_STANDBY;
        return 0;
    }
	return 0;
}

LUAT_WEAK int luat_audio_set_bus_type(uint8_t multimedia_id,uint8_t bus_type){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (bus_type == LUAT_AUDIO_BUS_I2S){
            audio_conf->codec_conf.multimedia_id = multimedia_id;
            audio_conf->bus_type = LUAT_AUDIO_BUS_I2S;
            return 0;
        }
    }
    return -1;
}

LUAT_WEAK int luat_audio_pm_request(uint8_t multimedia_id,luat_audio_pm_mode_t mode){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf!=NULL && audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
    	if (!audio_conf->pa_is_control_enable)
    	{
    		if (mode)
    		{
    			luat_audio_mute(multimedia_id, 1);
    		}
    		else
    		{
    			luat_audio_mute(multimedia_id, 0);
    		}
    		audio_conf->sleep_mode = mode;
        	return 0;
    	}
    	if (audio_conf->codec_conf.codec_opts->no_control)	//codec没有寄存器的情况
    	{
			switch(mode)
			{
			case LUAT_AUDIO_PM_RESUME:
				luat_audio_power_keep_ctrl_by_bsp(1);
				luat_audio_play_blank(multimedia_id, 1);
				luat_audio_power(multimedia_id,1);
				break;
			case LUAT_AUDIO_PM_STANDBY:	//只关PA，codec不关，这样下次播放的时候不需要重新启动codec，节省启动时间
				luat_audio_power_keep_ctrl_by_bsp(1);
				luat_audio_play_blank(multimedia_id, 1);
				luat_audio_pa(multimedia_id,0,0);
				break;
			default:
				luat_audio_power_keep_ctrl_by_bsp(0);
				luat_audio_pa(multimedia_id,0,0);
				if (audio_conf->power_off_delay_time)
					luat_rtos_task_sleep(audio_conf->power_off_delay_time);
				luat_audio_power(multimedia_id,0);
				audio_conf->wakeup_ready = 0;
				audio_conf->pa_on_enable = 0;
				break;
			}
			audio_conf->sleep_mode = mode;


    	}
    	else	//codec有寄存器的情况
    	{
    		switch (mode){
			case LUAT_AUDIO_PM_RESUME:
				luat_audio_power_keep_ctrl_by_bsp(1);
				if (!audio_conf->speech_uplink_type && !audio_conf->speech_downlink_type && !audio_conf->record_mode)
				{
					luat_audio_play_blank(multimedia_id, 1);
				}
				if (LUAT_AUDIO_PM_POWER_OFF == audio_conf->sleep_mode)	//之前已经强制断电过了，就必须重新初始化
				{
					luat_audio_init(multimedia_id, audio_conf->last_vol, audio_conf->last_mic_vol);
				}
				audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
				audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL, audio_conf->last_vol);
				audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MIC_VOL, audio_conf->last_mic_vol);
				audio_conf->last_wakeup_time_ms = luat_mcu_tick64_ms();
				audio_conf->sleep_mode = LUAT_AUDIO_PM_RESUME;
				break;
			case LUAT_AUDIO_PM_STANDBY:
				luat_audio_power_keep_ctrl_by_bsp(1);
				luat_audio_pa(multimedia_id,0,0);
				audio_conf->codec_conf.codec_opts->stop(&audio_conf->codec_conf);
				audio_conf->sleep_mode = LUAT_AUDIO_PM_STANDBY;
				break;
			case LUAT_AUDIO_PM_SHUTDOWN:
				luat_audio_pa(multimedia_id,0,0);
				if (audio_conf->power_off_delay_time)
					luat_rtos_task_sleep(audio_conf->power_off_delay_time);
				audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_PWRDOWN,0);
				luat_audio_power_keep_ctrl_by_bsp(0);
				audio_conf->wakeup_ready = 0;
				audio_conf->pa_on_enable = 0;
				audio_conf->sleep_mode = LUAT_AUDIO_PM_SHUTDOWN;
				break;
			case LUAT_AUDIO_PM_POWER_OFF:
				luat_audio_pa(multimedia_id,0,0);
				if (audio_conf->power_off_delay_time)
					luat_rtos_task_sleep(audio_conf->power_off_delay_time);
				luat_audio_power(multimedia_id,0);
				luat_audio_power_keep_ctrl_by_bsp(0);
				audio_conf->wakeup_ready = 0;
				audio_conf->pa_on_enable = 0;
				audio_conf->sleep_mode = LUAT_AUDIO_PM_POWER_OFF;
				break;
			default:
				return -1;
			}
    	}

        return 0;
    }
    return -1;
}

LUAT_WEAK void luat_audio_power_keep_ctrl_by_bsp(uint8_t on_off)
{
	;
}



