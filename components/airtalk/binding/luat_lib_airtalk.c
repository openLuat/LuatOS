/*
@module  airtalk
@summary 设备之间，设备与PC、手机，对讲处理
@catalog 综合应用API
@version 1.0
@date    2025.07.1
@demo airtalk
@tag LUAT_USE_AIRTALK
@usage
-- 本库仅部分BSP支持
-- 主要是 Air8000 和 Air780EXX 系列
-- 详细用法请参考demo
*/


#include "luat_base.h"
#include "libemqtt.h"
#include "luat_airtalk.h"
#include "luat_malloc.h"
#include "luat_mqtt.h"
#include "luat_audio.h"
#include "airtalk_api.h"

#define LUAT_LOG_TAG "airtalk"
#include "luat_log.h"

#include "rotable.h"
#define LUAT_MQTT_CTRL_TYPE "MQTTCTRL*"


static int l_airtalk_cb;
static int l_airtalk_handler(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);

    if (l_airtalk_cb) {
        lua_geti(L, LUA_REGISTRYINDEX, l_airtalk_cb);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, msg->arg1);
            lua_pushinteger(L, msg->arg2);
            lua_call(L, 2, 0);
        }
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}


/*
配置airtalk参数
@api airtalk.config(protocol,netc,cache_time,encode_cnt,decode_cnt,audio_pm_mode_when_stop)
@int 语音数据传输协议类型，见airtalk.PROTOCOL_XXX
@userdata network_ctrl或者mqtt客户端，如果协议是mqtt类型，传入mqtt.create返回值，如果是其他类型，传入socket.create的返回值
@int 缓冲时间，单位ms，默认500ms，值越小，delay越小，抗网络波动能力越差
@int 单次编码帧数，默认值5，不能低于2，不能高于5
@int 单次解码帧数，如果缓冲没有足够的帧数，自动补0，默认值5，不能低于2，不能高于10，不能低于encode_cnt, decode_cnt * 4 必须是 encode_cnt的整数倍
@int 对讲停止后，audio的pm状态，默认是audio.SHUTDOWN
@return nil
@usage
mqttc = mqtt.create(nil,"120.55.137.106", 1884)
airtalk.config(airtalk.PROTOCOL_MQTT, mqttc)
*/
static int l_airtalk_config(lua_State *L)
{
	int airtalk_protocol = luaL_optinteger(L, 1, LUAT_AIRTALK_PROTOCOL_MQTT);
	int cache_time = luaL_optinteger(L, 3, 500);
	int encode_cnt = luaL_optinteger(L, 4, 5);
	int decode_cnt = luaL_optinteger(L, 5, 5);
	int audio_pm_mode_when_stop = luaL_optinteger(L, 6, LUAT_AUDIO_PM_SHUTDOWN);
	luat_mqtt_ctrl_t * mqtt_ctrl;
	switch (airtalk_protocol)
	{
	case LUAT_AIRTALK_PROTOCOL_MQTT:
		if (luaL_testudata(L, 2, LUAT_MQTT_CTRL_TYPE)){
			mqtt_ctrl = ((luat_mqtt_ctrl_t *)luaL_checkudata(L, 2, LUAT_MQTT_CTRL_TYPE));
		}else{
			mqtt_ctrl = ((luat_mqtt_ctrl_t *)lua_touserdata(L, 2));
		}
		if (!mqtt_ctrl)
		{
			LLOGE("protocol %d no mqttc", airtalk_protocol);
			return 0;
		}
		luat_airtalk_net_param_config(airtalk_protocol, cache_time);
		luat_airtalk_net_set_mqtt_ctrl(mqtt_ctrl);
		luat_airtalk_speech_audio_param_config(0, audio_pm_mode_when_stop);
		luat_airtalk_speech_set_one_block_frame_cnt(decode_cnt, encode_cnt);
		luat_airtalk_net_mqtt_init();
		break;
	default:
		LLOGE("protocol %d no support!", airtalk_protocol);
		break;

	}

    return 0;
}

/*
注册airtalk事件回调
@api airtalk.on(func)
@function 回调方法
@return nil 无返回值
@usage
airtalk.on(function(event, param)
    log.info("airtalk event", event, param)
end)
*/
static int l_airtalk_on(lua_State *L) {
	if (l_airtalk_cb)
	{
		luaL_unref(L, LUA_REGISTRYINDEX, l_airtalk_cb);
		l_airtalk_cb = 0;
	}
    if (lua_isfunction(L, 1)) {
        lua_pushvalue(L, 1);
        l_airtalk_cb = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    return 0;
}

/*
airtalk启动
@api airtalk.start()
@return nil
@usage
mqttc = mqtt.create(nil,"120.55.137.106", 1884)
airtalk.config(airtalk.PROTOCOL_MQTT, mqttc)
airtalk.on(function(event, param)
    log.info("airtalk event", event, param)
end)
airtalk.start()
*/
static int l_airtalk_start(lua_State *L)
{
    luat_airtalk_speech_init();
    luat_airtalk_net_init();
    return 0;
}
/*
配置airtalk RTP协议中的SSRC
@api airtalk.set_ssrc(ssrc)
@int/string ssrc，可以是int也是可以8字节string
@return nil
@usage

*/
static int l_airtalk_set_ssrc(lua_State *L)
{
	if (lua_isstring(L, 1))
	{
		size_t len;
	    const char *id = lua_tolstring(L, 1, &len);//取出字符串数据;
	    uint32_t ssrc = strtol(id, NULL, 16);
	    luat_airtalk_net_set_ssrc(ssrc);
	}
	else
	{
		luat_airtalk_net_set_ssrc(lua_tointeger(L, 1));
	}

    return 0;
}

/*
配置airtalk mqtt类型语音数据的专用topic
@api airtalk.set_topic(topic)
@string topic
@return nil
@usage
airtalk.set_topic("xxxxxxxxxx")
*/
static int l_airtalk_set_mqtt_topic(lua_State *L)
{
	size_t len;
    const char *id = lua_tolstring(L, 1, &len);//取出字符串数据;
    luat_airtalk_net_set_mqtt_topic(id, len + 1);
    return 0;
}

/*
airtalk对讲工作启动/停止
@api airtalk.speech(on_off, mode, sample)
@boolean 启停控制，true开始，false停止
@int 工作模式，见airtalk.MODE_XXX
@int 音频采样率，目前只有8000和16000，默认16000
@return nil
@usage
--1对1对讲开始
airtalk.speech(true,airtalk.MODE_PERSON,16000)
--1对多对讲开始
airtalk.speech(true,airtalk.MODE_GROUP,16000)
--对讲停止
airtalk.speech(false)
*/
static int l_airtalk_speech(lua_State *L)
{
	int mode = luaL_optinteger(L, 2, LUAT_AIRTALK_SPEECH_MODE_PERSON);
	int sample = luaL_optinteger(L, 3, 16000);
	int on_off = lua_toboolean(L, 1);
	if (on_off)
	{
		switch(mode)
		{
		case LUAT_AIRTALK_SPEECH_MODE_PERSON:
			luat_airtalk_use_16k(sample == 16000);
			luat_airtalk_net_transfer_start(mode);
			luat_airtalk_speech_record_switch(1);
			break;
		case LUAT_AIRTALK_SPEECH_MODE_GROUP:
			luat_airtalk_use_16k(sample == 16000);
			luat_airtalk_net_transfer_start(mode);
			break;
		}
	}
	else
	{
		luat_airtalk_net_transfer_stop();
		luat_airtalk_speech_record_switch(0);
	}

    return 0;
}


/*
airtalk上行控制
@api airtalk.uplink(on_off)
@boolean  录音上行控制，true开始，false停止
@return nil
@usage
--开始录音
airtalk.uplink(true)
--停止录音
airtalk.uplink(false)
*/
static int l_airtalk_uplink(lua_State *L)
{
	luat_airtalk_speech_record_switch(lua_toboolean(L, 1));
    return 0;
}

/*
airtalk的详细调试信息开关
@api airtalk.debug(on_off)
@boolean 调试信息开关，true打开，false关闭
@return nil
*/
static int l_airtalk_debug(lua_State *L)
{
	uint8_t on_off = lua_toboolean(L, 1);
	luat_airtalk_net_debug_switch(on_off);
	luat_airtalk_speech_debug_switch(on_off);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_airtalk[] =
{
	{ "speech",      ROREG_FUNC(l_airtalk_speech)},
    { "config",      ROREG_FUNC(l_airtalk_config)},
    { "on",         ROREG_FUNC(l_airtalk_on)},
    { "start",      ROREG_FUNC(l_airtalk_start)},
	{ "set_ssrc",      ROREG_FUNC(l_airtalk_set_ssrc)},
	{ "set_topic",      ROREG_FUNC(l_airtalk_set_mqtt_topic)},
    { "uplink",      ROREG_FUNC(l_airtalk_uplink)},
	{ "debug",      ROREG_FUNC(l_airtalk_debug)},
	//@const PROTOCOL_MQTT number 语音数据用MQTT传输
    { "PROTOCOL_MQTT",        ROREG_INT(LUAT_AIRTALK_PROTOCOL_MQTT)},
	//@const MODE_PERSON number 对讲工作模式1对1
    { "MODE_PERSON",        ROREG_INT(LUAT_AIRTALK_SPEECH_MODE_PERSON)},
	//@const MODE_GROUP number 对讲工作模式多人
    { "MODE_GROUP",        ROREG_INT(LUAT_AIRTALK_SPEECH_MODE_GROUP)},
	//@const EVENT_OFF_LINE number airtalk离线
    { "EVENT_OFF_LINE",       ROREG_INT(LUAT_AIRTALK_CB_ON_LINE_IDLE)},
	//@const EVENT_ON_LINE_IDLE number airtalk在线处于空闲状态
    { "EVENT_ON_LINE_IDLE",       ROREG_INT(LUAT_AIRTALK_CB_ON_LINE_IDLE)},
	//@const EVENT_PLAY_START number airtalk下行播放开始
    { "EVENT_PLAY_START",       ROREG_INT(LUAT_AIRTALK_CB_PLAY_START)},
	//@const EVENT_PLAY_END number airtalk下行播放结束
    { "EVENT_PLAY_END",       ROREG_INT(LUAT_AIRTALK_CB_PLAY_END)},
	//@const EVENT_RECORD_START number airtalk录音上行开始
    { "EVENT_RECORD_START",       ROREG_INT(LUAT_AIRTALK_CB_RECORD_START)},
	//@const EVENT_RECORD_END number airtalk录音上行结束
    { "EVENT_RECORD_END",       ROREG_INT(LUAT_AIRTALK_CB_RECORD_END)},
	//@const EVENT_AUDIO_START number airtalk audio启动，只要上行和下行有一个开始就启动
    { "EVENT_AUDIO_START",       ROREG_INT(LUAT_AIRTALK_CB_AUDIO_START)},
	//@const EVENT_AUDIO_END number airtalk audio停止，上行和下行都结束才停止
    { "EVENT_AUDIO_END",       ROREG_INT(LUAT_AIRTALK_CB_AUDIO_END)},
	//@const EVENT_ERROR number airtalk发生异常，后续param为异常值
    { "EVENT_ERROR",       ROREG_INT(LUAT_AIRTALK_CB_ERROR)},

    { NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_airtalk(lua_State *L)
{
    luat_newlib2(L, reg_airtalk);
    return 1;
}

LUAT_WEAK void luat_airtalk_callback(uint32_t event, void *param, uint32_t param_len)
{
    rtos_msg_t msg = {0};
    msg.handler = l_airtalk_handler;
    msg.ptr = param;
    msg.arg1 = event;
    msg.arg2 = param_len;
    luat_msgbus_put(&msg, 0);
}
