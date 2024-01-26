#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_audio.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "tm8211"
#include "luat_log.h"

static luat_rtos_timer_t pa_delay_timer;

static LUAT_RT_RET_TYPE pa_delay_timer_cb(LUAT_RT_CB_PARAM){
    luat_audio_codec_conf_t* conf = (luat_audio_codec_conf_t*)param;
    luat_gpio_set(conf->pa_pin, conf->pa_on_level);
}

static int tm8211_codec_init(luat_audio_codec_conf_t* conf,uint8_t mode){
    if (conf->pa_pin != LUAT_CODEC_PA_NONE){
        luat_gpio_mode(conf->pa_pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, !conf->pa_on_level);
        luat_gpio_set(conf->pa_pin, !conf->pa_on_level);
        luat_rtos_timer_create(&pa_delay_timer);
    }
    //如果有dac pin 初始化dac pin
    return 0;
}

static int tm8211_codec_deinit(luat_audio_codec_conf_t* conf){
    if (conf->pa_pin != LUAT_CODEC_PA_NONE){
        luat_gpio_close(conf->pa_pin);
    }
    //如果有dac pin 控制断电后去初始化
    return 0;
}

static void tm8211_codec_pa(luat_audio_codec_conf_t* conf,uint8_t on){
    if (conf->pa_pin == LUAT_CODEC_PA_NONE) return;
	if (on){
        if (conf->after_sleep_ready_time)
            luat_rtos_timer_start(pa_delay_timer,conf->after_sleep_ready_time,0,pa_delay_timer_cb,(void*)conf);
        else
            luat_gpio_set(conf->pa_pin, conf->pa_on_level);
	}else{
        luat_gpio_set(conf->pa_pin, !conf->pa_on_level);
	}
}

static int tm8211_codec_control(luat_audio_codec_conf_t* conf,luat_audio_codec_ctl_t cmd,uint32_t data){
    switch (cmd){
        case LUAT_CODEC_SET_PA:
            tm8211_codec_pa(conf,(uint8_t)data);
            break;
        default:
            break;
    }
    return 0;
}

static int tm8211_codec_start(luat_audio_codec_conf_t* conf){
	tm8211_codec_pa(conf,1);
    //dac pin 控制上电
    return 0;
}

static int tm8211_codec_stop(luat_audio_codec_conf_t* conf){
	tm8211_codec_pa(conf,0);
    //dac pin 控制断电
    return 0;
}

luat_audio_codec_opts_t codec_opts_tm8211 = {
    .name = "tm8211",
    .init = tm8211_codec_init,
    .deinit = tm8211_codec_deinit,
    .control = tm8211_codec_control,
    .start = tm8211_codec_start,
    .stop = tm8211_codec_stop,
	.no_control = 1,
};
































