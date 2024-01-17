
/*
@module  cc
@summary 通话功能
@version 1.0
@date    2024.1.17
@demo    mobile
@tag LUAT_USE_MOBILE
@usage

*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"

#include "luat_mobile.h"
#include "luat_network_adapter.h"

#include "luat_i2s.h"
#include "luat_audio.h"

#define LUAT_LOG_TAG "cc"
#include "luat_log.h"
enum{
	VOLTE_EVENT_PLAY_TONE = 1,
	VOLTE_EVENT_RECORD_VOICE_START,
	VOLTE_EVENT_RECORD_VOICE_UPLOAD,
	VOLTE_EVENT_PLAY_VOICE,
};
static luat_rtos_task_handle luat_volte_task_handle;

#define VOICE_VOL   70
#define MIC_VOL     80

//播放控制
static uint8_t g_s_codec_is_on;
static uint8_t g_s_record_type;
static uint8_t g_s_play_type;
static luat_i2s_conf_t *g_s_i2s_conf;

static void mobile_voice_data_input(uint8_t *input, uint32_t len, uint32_t sample_rate, uint8_t bits){
	luat_rtos_event_send(luat_volte_task_handle, VOLTE_EVENT_PLAY_VOICE, (uint32_t)input, len, sample_rate, 0);
}

static int record_cb(uint8_t id ,luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param){
	switch(event){
	case LUAT_I2S_EVENT_RX_DONE:
		luat_rtos_event_send(luat_volte_task_handle, VOLTE_EVENT_RECORD_VOICE_UPLOAD, (uint32_t)rx_data, rx_len, 0, 0);
		break;
	case LUAT_I2S_EVENT_TX_DONE:
	case LUAT_I2S_EVENT_TRANSFER_DONE:
		break;
	default:
		break;
	}
	return 0;
}

static void luat_volte_task(void *param){
	luat_event_t event;
	uint8_t multimedia_id = (int)param;
	luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);

    luat_i2s_conf_t i2s_conf = {
        .id = audio_conf->codec_conf.i2s_id,
        .mode = LUAT_I2S_MODE_MASTER,
        .channel_format = LUAT_I2S_CHANNEL_RIGHT,
        .standard = LUAT_I2S_MODE_LSB,
        .channel_bits = LUAT_I2S_BITS_16,
        .data_bits = LUAT_I2S_BITS_16,
        .luat_i2s_event_callback = record_cb,
    };

	luat_i2s_setup(&i2s_conf);
    g_s_i2s_conf = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);

    int ret = audio_conf->codec_conf.codec_opts->init(&audio_conf->codec_conf,LUAT_CODEC_MODE_SLAVE);
    if (ret){
		LLOGE("no codec %s",audio_conf->codec_conf.codec_opts->name);
		luat_rtos_task_delete(luat_volte_task_handle);
		return;
    }else{
		LLOGD("find codec %s",audio_conf->codec_conf.codec_opts->name);

        audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_RATE,16000);
        audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_BITS,16);
		audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_FORMAT,LUAT_CODEC_FORMAT_I2S);

        audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL,70);
        audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MIC_VOL,80);

        // // audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_STANDBY,LUAT_CODEC_MODE_ALL);
        audio_conf->codec_conf.codec_opts->stop(&audio_conf->codec_conf);
    }
	while (1){
		luat_rtos_event_recv(luat_volte_task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
		switch(event.id)
		{
		case VOLTE_EVENT_PLAY_TONE:
            LLOGD("VOLTE_EVENT_PLAY_TONE %d",event.param1);

			// play_tone(multimedia_id,event.param1);
            if (LUAT_MOBILE_CC_PLAY_STOP == event.param1){
                g_s_record_type = 0;
                g_s_play_type = 0;
                if (g_s_codec_is_on){
                    g_s_codec_is_on = 0;
                    audio_conf->codec_conf.codec_opts->stop(&audio_conf->codec_conf);
                    // audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_STANDBY,LUAT_CODEC_MODE_ALL);
                }
                g_s_i2s_conf->is_full_duplex = 0;
                break;
            }

            // luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, NULL, 1600, 2, 1);
            // g_s_codec_is_on = 1;
            // audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_NORMAL,LUAT_CODEC_MODE_ALL);


            // audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);

			break;
		case VOLTE_EVENT_RECORD_VOICE_START:
            LLOGD("VOLTE_EVENT_RECORD_VOICE_START");
			g_s_codec_is_on = 1;
			g_s_record_type = event.param1;
			luat_rtos_task_sleep(1);
			g_s_i2s_conf->is_full_duplex = 1;
			g_s_i2s_conf->cb_rx_len = 320 * g_s_record_type;
			luat_i2s_modify(audio_conf->codec_conf.i2s_id, LUAT_I2S_CHANNEL_RIGHT, LUAT_I2S_BITS_16, g_s_record_type * 8000);
			luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, NULL, 3200, 2, 0);	//address传入空地址就是播放空白音
    //         // audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
			audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_NORMAL,LUAT_CODEC_MODE_ALL);

			break;
		case VOLTE_EVENT_RECORD_VOICE_UPLOAD:
            if (g_s_record_type){
				luat_mobile_speech_upload((uint8_t *)event.param1, event.param2);
			}
			break;
		case VOLTE_EVENT_PLAY_VOICE:
            LLOGD("VOLTE_EVENT_PLAY_VOICE");
			g_s_play_type = event.param3; //1 = 8K 2 = 16K
			if (!g_s_record_type){
				g_s_i2s_conf->is_full_duplex = 0;
				luat_i2s_modify(audio_conf->codec_conf.i2s_id, LUAT_I2S_CHANNEL_RIGHT, LUAT_I2S_BITS_16, g_s_play_type * 8000);
				if (2 == g_s_play_type){
					luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, (uint8_t *)event.param1, event.param2/3, 3, 0);
				}else{
					luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, (uint8_t *)event.param1, event.param2/6, 6, 0);
				}
				if (!g_s_codec_is_on){
					g_s_codec_is_on = 1;
                    // audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
					audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_NORMAL,LUAT_CODEC_MODE_ALL);
				}
			}else{
				LLOGD("%x,%d", event.param1, event.param2);
				if (2 == g_s_record_type){
					luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, (uint8_t *)event.param1, event.param2/3, 3, 0);
				}else{
					luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, (uint8_t *)event.param1, event.param2/6, 6, 0);
				}
			}
			break;
		}
	}
}

/**
获取最后一次通话的号码
@api cc.lastNum()
@return string 获取最后一次通话的号码
 */
static int l_cc_get_last_call_num(lua_State* L) {
    char number[64] = {0};
    luat_mobile_get_last_call_num(number, sizeof(number));
    lua_pushlstring(L, (const char*)(number),strlen(number));
    return 1;
}

/**
拨打电话
@api cc.dial(sim_id,number)
@number sim_id
@number 电话号码
@return bool 拨打电话成功与否
 */
static int l_cc_make_call(lua_State* L) {
    uint8_t sim_id = luaL_optinteger(L, 1, 0);
    size_t len = 0;
	char* number = luaL_checklstring(L, 2, &len);
    lua_pushboolean(L, !luat_mobile_make_call(sim_id,number, len));
    return 1;
}

/**
挂断电话
@api cc.hangUp(sim_id)
@number sim_id
 */
static int l_cc_hangup_call(lua_State* L) {
    uint8_t sim_id = luaL_optinteger(L, 1, 0);
    luat_mobile_hangup_call(sim_id);
    return 0;
}

/**
接听电话
@api cc.accept(sim_id)
@number sim_id
@return bool 接听电话成功与否
 */
static int l_cc_answer_call(lua_State* L) {
    uint8_t sim_id = luaL_optinteger(L, 1, 0);
    lua_pushboolean(L, !luat_mobile_answer_call(sim_id));
    return 1;
}

/**
初始化电话功能
@api cc.init(multimedia_id)
@number multimedia_id 多媒体id
@return bool 成功与否
 */
static int l_cc_speech_init(lua_State* L) {
    uint8_t multimedia_id = luaL_optinteger(L, 1, 0);
    if (luat_mobile_speech_init(multimedia_id,mobile_voice_data_input)){
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_rtos_task_create(&luat_volte_task_handle, 4*1024, 100, "volte", luat_volte_task, multimedia_id, 64);
    lua_pushboolean(L, 1);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_cc[] =
{
    { "init" ,      ROREG_FUNC(l_cc_speech_init)},
    { "dial" ,      ROREG_FUNC(l_cc_make_call)},
    { "accept" ,    ROREG_FUNC(l_cc_answer_call)},
    { "hangUp" ,    ROREG_FUNC(l_cc_hangup_call)},
    { "lastNum" ,   ROREG_FUNC(l_cc_get_last_call_num)},
    // { "recordCall" , ROREG_FUNC(l_cc_get_last_call_num)},
	{ NULL,          {}}
};

LUAMOD_API int luaopen_cc( lua_State *L ) {
    luat_newlib2(L, reg_cc);
    return 1;
}



void luat_cc_start_speech(uint32_t param)
{
	luat_rtos_event_send(luat_volte_task_handle, VOLTE_EVENT_RECORD_VOICE_START, param, 0, 0, 0);
}

void luat_cc_play_tone(uint32_t param)
{
	luat_rtos_event_send(luat_volte_task_handle, VOLTE_EVENT_PLAY_TONE, param, 0, 0, 0);
}

