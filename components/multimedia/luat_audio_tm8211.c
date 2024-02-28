#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_audio.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "tm8211"
#include "luat_log.h"

//static int tm8211_codec_init(luat_audio_codec_conf_t* conf,uint8_t mode){
//    return 0;
//}
//
//static int tm8211_codec_deinit(luat_audio_codec_conf_t* conf){
//    return 0;
//}
//
//static int tm8211_mode_resume(luat_audio_codec_conf_t* conf,uint8_t selece){
//    luat_audio_power(conf->multimedia_id,1);
//    return 0;
//}
//
//
//static int tm8211_mode_pwrdown(luat_audio_codec_conf_t* conf){
//    luat_audio_power(conf->multimedia_id,0);
//    return 0;
//}
//
//static int tm8211_codec_control(luat_audio_codec_conf_t* conf,luat_audio_codec_ctl_t cmd,uint32_t data){
//    switch (cmd){
//        case LUAT_CODEC_MODE_RESUME:
//            tm8211_mode_resume(conf,(uint8_t)data);
//            break;
//        case LUAT_CODEC_MODE_STANDBY:
//        case LUAT_CODEC_MODE_PWRDOWN:
//            tm8211_mode_pwrdown(conf);
//            break;
//        default:
//            break;
//    }
//    return 0;
//}
//
//static int tm8211_codec_start(luat_audio_codec_conf_t* conf){
//    luat_audio_power(conf->multimedia_id,1);
//    return 0;
//}
//
//static int tm8211_codec_stop(luat_audio_codec_conf_t* conf){
//	luat_audio_power(conf->multimedia_id,0);
//    return 0;
//}

const luat_audio_codec_opts_t codec_opts_tm8211 = {
    .name = "tm8211",
    .init = NULL,
    .deinit = NULL,
    .control = NULL,
    .start = NULL,
    .stop = NULL,
	.no_control = 1,
};

const luat_audio_codec_opts_t codec_opts_common = {
    .name = "common",
    .init = NULL,
    .deinit = NULL,
    .control = NULL,
    .start = NULL,
    .stop = NULL,
	.no_control = 1,
};






























