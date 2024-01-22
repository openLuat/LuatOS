
/*
@module  cc
@summary 通话功能
@version 1.0
@date    2024.1.17
@demo    mobile
@tag LUAT_USE_VOLTE
@usage

*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
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

#define VOICE_VOL   70
#define MIC_VOL     80

//播放控制
typedef struct
{
	luat_rtos_task_handle task_handle;
	luat_i2s_conf_t *i2s_conf;
	luat_zbuff_t *up_buff[2];
	luat_zbuff_t *down_buff[2];
	int record_cb;
	HANDLE record_timer;
	uint32_t next_download_point;
	uint8_t *download_buffer;
	uint8_t total_download_cnt;
	uint8_t play_type;
	uint8_t record_type;
	uint8_t is_codec_on;
	uint8_t record_on_off;
	uint8_t record_start;
	uint8_t upload_need_stop;
	volatile uint8_t record_down_zbuff_point;
	volatile uint8_t record_up_zbuff_point;
}luat_cc_ctrl_t;
static luat_cc_ctrl_t luat_cc;

static int l_cc_handler(lua_State *L, void* ptr) {
    (void)ptr;
    //LLOGD("l_uart_handler");
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    if (luat_cc.record_on_off && luat_cc.record_cb)
    {
    	lua_geti(L, LUA_REGISTRYINDEX, luat_cc.record_cb);
        if (lua_isfunction(L, -1)) {
        	lua_pushboolean(L, msg->arg1);
        	lua_pushinteger(L, msg->arg2);
        	lua_call(L, 2, 0);
        }
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

static void mobile_voice_data_input(uint8_t *input, uint32_t len, uint32_t sample_rate, uint8_t bits){
	if (luat_cc.record_on_off) {
        luat_cc.record_down_zbuff_point = 0;
        luat_cc.download_buffer = (uint8_t *)input;
		if (1 == sample_rate)
		{
			luat_cc.total_download_cnt = 6;
		}
		else
		{
			luat_cc.total_download_cnt = 3;
		}
        memcpy(luat_cc.down_buff[0]->addr, luat_cc.download_buffer, sample_rate * 320);
        luat_cc.down_buff[0]->used = sample_rate * 320;
        luat_cc.next_download_point = 1;
		luat_start_rtos_timer(luat_cc.record_timer, 20, 1);
		if (luat_cc.down_buff[0]->used >= luat_cc.down_buff[0]->len) {
			rtos_msg_t msg;
			msg.handler = l_cc_handler;
			msg.arg1 = 1;
			msg.arg2 = 0;
			luat_msgbus_put(&msg, 0);
			luat_cc.record_down_zbuff_point = !luat_cc.record_down_zbuff_point;
			luat_cc.down_buff[luat_cc.record_down_zbuff_point]->used = 0;
		}
	}
	luat_rtos_event_send(luat_cc.task_handle, VOLTE_EVENT_PLAY_VOICE, (uint32_t)input, len, sample_rate, 0);

}

static int record_cb(uint8_t id ,luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param){
	if (luat_cc.upload_need_stop) return 0;
	switch(event){
	case LUAT_I2S_EVENT_RX_DONE:
		luat_rtos_event_send(luat_cc.task_handle, VOLTE_EVENT_RECORD_VOICE_UPLOAD, (uint32_t)rx_data, rx_len, 0, 0);
		break;
	case LUAT_I2S_EVENT_TX_DONE:
	case LUAT_I2S_EVENT_TRANSFER_DONE:
		break;
	default:
		break;
	}
	return 0;
}

static LUAT_RT_RET_TYPE download_data_callback(LUAT_RT_CB_PARAM)
{
	if (luat_cc.record_type && luat_cc.record_on_off) {
		luat_zbuff_t *buff = luat_cc.down_buff[luat_cc.record_down_zbuff_point];
		memcpy(buff->addr + buff->used, luat_cc.download_buffer + luat_cc.next_download_point * luat_cc.record_type * 320, luat_cc.record_type * 320);//20ms录音完成
		luat_cc.next_download_point = (luat_cc.next_download_point + 1) % luat_cc.total_download_cnt;
		buff->used += luat_cc.record_type * 320;
		if (buff->used >= buff->len) {
			rtos_msg_t msg;
            msg.handler = l_cc_handler;
            msg.arg2 = luat_cc.record_down_zbuff_point;
            msg.arg1 = 1;
            luat_msgbus_put(&msg, 0);
            luat_cc.record_down_zbuff_point = !luat_cc.record_down_zbuff_point;
            luat_cc.down_buff[luat_cc.record_down_zbuff_point]->used = 0;
		}
	}
}

static void luat_volte_task(void *param){
	luat_zbuff_t *zbuff = NULL;
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
    luat_cc.i2s_conf = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);

    int ret = audio_conf->codec_conf.codec_opts->init(&audio_conf->codec_conf,LUAT_CODEC_MODE_SLAVE);
    if (ret){
		LLOGE("no codec %s",audio_conf->codec_conf.codec_opts->name);
		luat_rtos_task_delete(luat_cc.task_handle);
		return;
    }else{
		LLOGD("find codec %s",audio_conf->codec_conf.codec_opts->name);

        audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_RATE,16000);
        audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_BITS,16);
		audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_FORMAT,LUAT_CODEC_FORMAT_I2S);

        // // audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_STANDBY,LUAT_CODEC_MODE_ALL);
        audio_conf->codec_conf.codec_opts->stop(&audio_conf->codec_conf);
    }
	while (1){
		luat_rtos_event_recv(luat_cc.task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
		switch(event.id)
		{
		case VOLTE_EVENT_PLAY_TONE:
			// play_tone(multimedia_id,event.param1);
            if (LUAT_MOBILE_CC_PLAY_STOP == event.param1){
                luat_cc.record_type = 0;
                luat_cc.play_type = 0;

                luat_cc.i2s_conf->is_full_duplex = 0;
                luat_i2s_close(luat_cc.i2s_conf->id);
				if (luat_rtos_timer_is_active(luat_cc.record_timer))
				{
					luat_rtos_timer_stop(luat_cc.record_timer);
					rtos_msg_t msg;
					msg.handler = l_cc_handler;
					msg.arg2 = luat_cc.record_up_zbuff_point;
					msg.arg1 = 0;
					luat_msgbus_put(&msg, 0);
					msg.arg2 = luat_cc.record_down_zbuff_point;
					msg.arg1 = 1;
					luat_msgbus_put(&msg, 0);
				}
                if (luat_cc.is_codec_on){
                    luat_cc.is_codec_on = 0;
                    audio_conf->codec_conf.codec_opts->stop(&audio_conf->codec_conf);
                    // audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_STANDBY,LUAT_CODEC_MODE_ALL);
                }
	            LLOGD("VOLTE_EVENT_PLAY_STOP");
                break;
            }

            // luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, NULL, 1600, 2, 1);
            // luat_cc.is_codec_on = 1;
            // audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_NORMAL,LUAT_CODEC_MODE_ALL);


            // audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);

			break;
		case VOLTE_EVENT_RECORD_VOICE_START:
			luat_cc.is_codec_on = 1;
			luat_cc.record_type = event.param1;
//			luat_i2s_close(luat_cc.i2s_conf->id);
//			luat_rtos_task_sleep(1);
			luat_cc.i2s_conf->is_full_duplex = 1;
			luat_cc.i2s_conf->cb_rx_len = 320 * luat_cc.record_type;
			luat_i2s_modify(audio_conf->codec_conf.i2s_id, LUAT_I2S_CHANNEL_RIGHT, LUAT_I2S_BITS_16, luat_cc.record_type * 8000);
			luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, NULL, 3200, 2, 0);	//address传入空地址就是播放空白音
    //         // audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
			audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_NORMAL,LUAT_CODEC_MODE_ALL);
            luat_cc.record_up_zbuff_point = 0;
            if (luat_cc.record_on_off) {
            	luat_cc.up_buff[0]->used = 0;
            }

            LLOGD("VOLTE_EVENT_RECORD_VOICE_START");
			break;
		case VOLTE_EVENT_RECORD_VOICE_UPLOAD:
			if (luat_cc.upload_need_stop) {
				LLOGD("VOLTE RECORD VOICE ALREADY STOP");
				break;
			}
			if (luat_cc.record_on_off && luat_cc.record_type) {
				zbuff = luat_cc.up_buff[luat_cc.record_up_zbuff_point];
				memcpy(zbuff->addr + zbuff->used, (uint8_t *)event.param1, event.param2);
				zbuff->used += event.param2;
			}
            if (luat_cc.record_type) {
				luat_mobile_speech_upload((uint8_t *)event.param1, event.param2);
			}
            if (luat_cc.record_on_off && luat_cc.record_type) {
				if (zbuff->used >= zbuff->len) {
					rtos_msg_t msg;
					msg.handler = l_cc_handler;
					msg.arg2 = luat_cc.record_up_zbuff_point;
					msg.arg1 = 0;
					luat_msgbus_put(&msg, 0);
					luat_cc.record_up_zbuff_point = !luat_cc.record_up_zbuff_point;
					luat_cc.up_buff[luat_cc.record_up_zbuff_point]->used = 0;
				}
            }
			break;
		case VOLTE_EVENT_PLAY_VOICE:

			luat_cc.play_type = event.param3; //1 = 8K 2 = 16K
			if (!luat_cc.record_type){
				luat_cc.i2s_conf->is_full_duplex = 0;
				luat_i2s_modify(audio_conf->codec_conf.i2s_id, LUAT_I2S_CHANNEL_RIGHT, LUAT_I2S_BITS_16, luat_cc.play_type * 8000);
				if (2 == luat_cc.play_type){
					luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, (uint8_t *)event.param1, event.param2/3, 3, 0);
				}else{
					luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, (uint8_t *)event.param1, event.param2/6, 6, 0);
				}
				if (!luat_cc.is_codec_on){
					luat_cc.is_codec_on = 1;
                    // audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
					audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_NORMAL,LUAT_CODEC_MODE_ALL);
				}
			}else{
//                LLOGD("%d,%d,%d", luat_cc.play_type, luat_cc.record_type, event.param2);
				if (2 == luat_cc.record_type){
					luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, (uint8_t *)event.param1, event.param2/3, 3, 0);
				}else{
					luat_i2s_transfer_loop(audio_conf->codec_conf.i2s_id, (uint8_t *)event.param1, event.param2/6, 6, 0);
				}
			}
			LLOGD("VOLTE_EVENT_PLAY_VOICE");
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
    luat_cc.record_timer = luat_create_rtos_timer(download_data_callback, NULL, NULL);
    luat_rtos_task_create(&luat_cc.task_handle, 4*1024, 100, "volte", luat_volte_task, multimedia_id, 64);
    lua_pushboolean(L, 1);
    return 1;
}

/**
录音通话
@api cc.record(on_off,upload_zbuff1, upload_zbuff2, download_zbuff1, download_zbuff2)
@boolean 开启关闭通话录音功能，false或者nil关闭，其他开启
@zbuff 上行数据保存区1,zbuff创建时的空间容量必须是640的倍数,下同
@zbuff 上行数据保存区2,和上行数据保存区1组成双缓冲区
@zbuff 下行数据保存区1
@zbuff 下行数据保存区2,和下行数据保存区1组成双缓冲区
@return bool 成功与否，如果处于通话状态，会失败
@usage
buff1 = zbuff.create(6400,0,zbuff.HEAP_AUTO)
buff2 = zbuff.create(6400,0,zbuff.HEAP_AUTO)
buff3 = zbuff.create(6400,0,zbuff.HEAP_AUTO)
buff4 = zbuff.create(6400,0,zbuff.HEAP_AUTO)
cc.on("record", function(type, buff_point)
 log.info(type, buff_point) -- type==true是下行数据，false是上行数据 buff_point指示双缓存中返回了哪一个
end)
cc.record(true, buff1, buff2, buff3, buff4)
*/
static int l_cc_record_call(lua_State* L) {
	if (luat_cc.record_type)
	{
		lua_pushboolean(L, 0);
		return 1;
	}
    luat_cc.record_on_off = lua_toboolean(L, 1);
    if (luat_cc.record_on_off)
    {
    	luat_cc.up_buff[0] = (luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
    	luat_cc.up_buff[1] = (luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE);
    	luat_cc.down_buff[0] = (luat_zbuff_t *)luaL_checkudata(L, 4, LUAT_ZBUFF_TYPE);
    	luat_cc.down_buff[1] = (luat_zbuff_t *)luaL_checkudata(L, 5, LUAT_ZBUFF_TYPE);
    }
    else
    {
    	luat_cc.up_buff[0] = NULL;
    	luat_cc.up_buff[1] = NULL;
    	luat_cc.down_buff[0] = NULL;
    	luat_cc.down_buff[1] = NULL;
    }

    lua_pushboolean(L, 1);
    return 1;
}

/**
获取当前通话质量
@api cc.quality()
@return int 1为低音质(8K)，2为高音质(16k)，0没有在通话
 */
static int l_cc_get_quality(lua_State* L) {
    lua_pushinteger(L, luat_cc.record_type);
    return 1;
}

/**
注册通话回调
@api    cc.on(event, func)
@string 事件名称 音频录音数据为"record"
@function 回调方法
@return nil 无返回值
@usage
cc.on("record", function(type, buff_point)
 log.info(type, buff_point) -- type==true是下行数据，false是上行数据 buff_point指示双缓存中返回了哪一个
end)
*/
static int l_cc_on(lua_State *L) {
    const char* event = luaL_checkstring(L, 1);
    if (!strcmp("record", event)) {
        if (luat_cc.record_cb != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, luat_cc.record_cb);
            luat_cc.record_cb = 0;
        }
        if (lua_isfunction(L, 2)) {
            lua_pushvalue(L, 2);
            luat_cc.record_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    return 0;
}


#include "rotable2.h"
static const rotable_Reg_t reg_cc[] =
{
    { "init" ,      ROREG_FUNC(l_cc_speech_init)},
    { "dial" ,      ROREG_FUNC(l_cc_make_call)},
    { "accept" ,    ROREG_FUNC(l_cc_answer_call)},
    { "hangUp" ,    ROREG_FUNC(l_cc_hangup_call)},
    { "lastNum" ,   ROREG_FUNC(l_cc_get_last_call_num)},
	{ "quality" ,   ROREG_FUNC(l_cc_get_quality)},
    { "on" ,        ROREG_FUNC(l_cc_on)},
    { "record", ROREG_FUNC(l_cc_record_call)},
	{ NULL,          {}}
};

LUAMOD_API int luaopen_cc( lua_State *L ) {
    luat_newlib2(L, reg_cc);
    return 1;
}



void luat_cc_start_speech(uint32_t param)
{
	luat_cc.upload_need_stop = 0;
	luat_rtos_event_send(luat_cc.task_handle, VOLTE_EVENT_RECORD_VOICE_START, param, 0, 0, 0);
}

void luat_cc_play_tone(uint32_t param)
{
	if (!param) luat_cc.upload_need_stop = 1;
	luat_rtos_event_send(luat_cc.task_handle, VOLTE_EVENT_PLAY_TONE, param, 0, 0, 0);
}

