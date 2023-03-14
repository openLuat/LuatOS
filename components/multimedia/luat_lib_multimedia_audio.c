
/*
@module  audio
@summary 多媒体-音频
@version 1.0
@date    2022.03.11
@demo multimedia
@tag LUAT_USE_MEDIA
*/
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "audio"
#include "luat_log.h"

#include "luat_multimedia.h"

#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif


static luat_multimedia_cb_t multimedia_cbs[MAX_DEVICE_COUNT];

int l_multimedia_raw_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    if (multimedia_cbs[msg->arg2].function_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, multimedia_cbs[msg->arg2].function_ref);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, msg->arg2);
            lua_pushinteger(L, msg->arg1);
            lua_call(L, 2, 0);
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}

/*
启动一个多媒体通道准备播放音频
@api audio.start(id, audio_format, num_channels, sample_rate, bits_per_sample, is_signed)
@int 多媒体播放通道号，0或者1
@int 音频格式
@int 声音通道数
@int 采样频率
@int 采样位数
@boolean 是否有符号，默认true
@return boolean 成功true, 失败false
@usage
audio.start(0, audio.PCM, 1, 16000, 16)
*/

static int l_audio_start_raw(lua_State *L){
	int multimedia_id = luaL_checkinteger(L, 1);
	int audio_format = luaL_checkinteger(L, 2);
	int num_channels= luaL_checkinteger(L, 3);
	int sample_rate = luaL_checkinteger(L, 4);
	int bits_per_sample = luaL_checkinteger(L, 5);
	int is_signed = 1;
	if (lua_isboolean(L, 6))
	{
		is_signed = lua_toboolean(L, 6);
	}
	lua_pushboolean(L, !luat_audio_start_raw(multimedia_id, audio_format, num_channels, sample_rate, bits_per_sample, is_signed));
    return 1;
}
/**
往一个多媒体通道写入音频数据
@api audio.write(id, data)
@string or zbuff 音频数据
@return boolean 成功返回true,否则返回false
@usage
audio.write(0, "xxxxxx")
*/
static int l_audio_write_raw(lua_State *L) {
    int multimedia_id = luaL_checkinteger(L, 1);
    size_t len;
    uint8_t *buf;
    if(lua_isuserdata(L, 2))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        len = buff->used;
        buf = (const char *)(buff->addr);
    }
    else
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
    }
	lua_pushboolean(L, !luat_audio_write_raw(multimedia_id, buf, len));
    return 1;
}

/**
停止指定的多媒体通道
@api audio.stop(id)
@int audio id,例如0
@return boolean 成功返回true,否则返回false
@usage
audio.stop(0)
*/
static int l_audio_stop_raw(lua_State *L) {
    lua_pushboolean(L, !luat_audio_stop_raw(luaL_checkinteger(L, 1)));
    return 1;
}

/**
暂停/恢复指定的多媒体通道
@api audio.pause(id, pause)
@int audio id,例如0
@boolean onoff true 暂停，false 恢复
@return boolean 成功返回true,否则返回false
@usage
audio.pause(0, true) --暂停通道0
audio.pause(0, false) --恢复通道0
*/
static int l_audio_pause_raw(lua_State *L) {
    lua_pushboolean(L, !luat_audio_pause_raw(luaL_checkinteger(L, 1), lua_toboolean(L, 2)));
    return 1;
}

/**
注册audio播放事件回调
@api    audio.on(id, event, func)
@int audio id, audio 0写0, audio 1写1
@function 回调方法，回调时传入参数为1、int 通道ID 2、int 消息值，只有audio.MORE_DATA和audio.DONE
@return nil 无返回值
@usage
audio.on(0, function(audio_id, msg)
    log.info("msg", audio_id, msg)
end)
*/
static int l_audio_raw_on(lua_State *L) {
    int multimedia_id = luaL_checkinteger(L, 1);
	if (multimedia_cbs[multimedia_id].function_ref != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, multimedia_cbs[multimedia_id].function_ref);
		multimedia_cbs[multimedia_id].function_ref = 0;
	}
	if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		multimedia_cbs[multimedia_id].function_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

    return 0;
}

/*
播放或者停止播放一个文件，播放完成后，会回调一个audio.DONE消息，可以用pause来暂停或者恢复，其他API不可用。考虑到读SD卡速度比较慢而拖累luavm进程的速度，所以尽量使用本API
@api audio.play(id, path, errStop)
@int 音频通道
@string/table 文件名，如果为空，则表示停止播放，如果是table，则表示连续播放多个文件，主要应用于云喇叭，目前只有EC618支持，并且会用到errStop参数
@boolean 是否在文件解码失败后停止解码，只有在连续播放多个文件时才有用，默认true，遇到解码错误自动停止
@return boolean 成功返回true,否则返回false
@usage
audio.play(0, "xxxxxx")		--开始播放某个文件
audio.play(0)				--停止播放某个文件
*/
static int l_audio_play(lua_State *L) {
    int multimedia_id = luaL_checkinteger(L, 1);
    size_t len, i;
    int result = 0;
    const uint8_t *buf;
    uint8_t is_error_stop = 1;
    if (lua_istable(L, 2))
    {
    	size_t len = lua_rawlen(L, 2); //返回数组的长度
    	if (!len)
    	{
        	luat_audio_play_stop(multimedia_id);
        	lua_pushboolean(L, 1);
        	return 1;
    	}
        uData_t *info = (uData_t *)luat_heap_malloc(len * sizeof(uData_t));
        for (size_t i = 0; i < len; i++)
        {
            lua_rawgeti(L, 2, 1 + i);
            info[i].value.asBuffer.buffer = lua_tolstring(L, -1, &info[i].value.asBuffer.length);
            info[i].Type = UDATA_TYPE_OPAQUE;
            lua_pop(L, 1); //将刚刚获取的元素值从栈中弹出
        }
    	if (lua_isboolean(L, 3))
    	{
    		is_error_stop = lua_toboolean(L, 3);
    	}
        result = luat_audio_play_multi_files(multimedia_id, info, len, is_error_stop);
    	lua_pushboolean(L, !result);
    	luat_heap_free(info);
    }
    else if (LUA_TSTRING == (lua_type(L, (2))))
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
        result = luat_audio_play_file(multimedia_id, buf);
    	lua_pushboolean(L, !result);
    }
    else
    {
    	luat_audio_play_stop(multimedia_id);
    	lua_pushboolean(L, 1);
    }
    return 1;
}
#ifdef LUAT_USE_TTS
/*
TTS播放或者停止
@api audio.tts(id, data)
@int 音频通道
@string/zbuff 需要播放的内容
@return boolean 成功返回true,否则返回false
@tag LUAT_USE_TTS
@usage
audio.tts(0, "测试一下")		--开始播放
audio.tts(0)				--停止播放
-- Air780E的TTS功能详细说明
-- https://wiki.luatos.com/chips/air780e/tts.html
*/
static int l_audio_play_tts(lua_State *L) {
    int multimedia_id = luaL_checkinteger(L, 1);
    size_t len, i;
    int result = 0;
    const uint8_t *buf;
    uint8_t is_error_stop = 1;
    if (LUA_TSTRING == (lua_type(L, (2))))
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
        result = luat_audio_play_tts_text(multimedia_id, buf, len);
    	lua_pushboolean(L, !result);
    }
    else if(lua_isuserdata(L, 2))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        result = luat_audio_play_tts_text(multimedia_id, buff->addr, buff->used);
    	lua_pushboolean(L, !result);
    }
    else
    {
    	luat_audio_play_stop(multimedia_id);
    	lua_pushboolean(L, 1);
    }
    return 1;
}
#endif
/**
停止播放文件，和audio.play(id)是一样的作用
@api audio.playStop(id)
@int audio id,例如0
@return boolean 成功返回true,否则返回false
@usage
audio.playStop(0)
*/
static int l_audio_play_stop(lua_State *L) {
    lua_pushboolean(L, !luat_audio_play_stop(luaL_checkinteger(L, 1)));
    return 1;
}


/**
检查当前文件是否已经播放结束
@api audio.isEnd(id)
@int 音频通道
@return boolean 成功返回true,否则返回false
@usage
audio.isEnd(0)

*/
static int l_audio_play_wait_end(lua_State *L) {
    int multimedia_id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_audio_is_finish(multimedia_id));
    return 1;
}

/*
获取最近一次播放结果，不是所有平台都支持的，目前只有EC618支持
@api audio.getError(id)
@int 音频通道
@return boolean 是否全部播放成功，true成功，false有文件播放失败
@return boolean 如果播放失败，是否是用户停止，true是，false不是
@return int 第几个文件失败了，从1开始
@usage
local result, user_stop, file_no = audio.getError(0)
*/
static int l_audio_play_get_last_error(lua_State *L) {
	int result = luat_audio_play_get_last_error(luaL_checkinteger(L, 1));
	lua_pushboolean(L, 0 == result);
	lua_pushboolean(L, result < 0);
	lua_pushinteger(L, result > 0?result:0);
    return 3;
}

/*
配置一个音频通道的特性，比如实现自动控制PA开关。注意这个不是必须的，一般在调用play的时候才需要自动控制，其他情况比如你手动控制播放时，就可以自己控制PA开关
@api audio.config(id, paPin, onLevel, dacDelay, paDelay, dacPin, dacLevel, dacTimeDelay)
@int 音频通道
@int PA控制IO
@int PA打开时的电平
@int 在DAC启动前插入的冗余时间，单位100ms，一般用于外部DAC
@int 在DAC启动后，延迟多长时间打开PA，单位1ms
@int 外部dac电源控制IO，如果不填，则表示使用平台默认IO，比如Air780E使用DACEN脚，air105则不启用
@int 外部dac打开时，电源控制IO的电平，默认拉高
@int 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms，默认0ms
@usage
audio.config(0, pin.PC0, 1)	--PA控制脚是PC0，高电平打开，air105用这个配置就可以用了
audio.config(0, 25, 1, 6, 200)	--PA控制脚是GPIO25，高电平打开，Air780E云喇叭板用这个配置就可以用了
*/
static int l_audio_config(lua_State *L) {
    luat_audio_config_pa(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 255), luaL_optinteger(L, 3, 1), luaL_optinteger(L, 4, 5), luaL_optinteger(L, 5, 200));
    luat_audio_config_dac(luaL_checkinteger(L, 1), luaL_optinteger(L, 6, -1), luaL_optinteger(L, 7, 1), luaL_optinteger(L, 8, 0));
    return 0;
}

/*
配置一个音频通道的音量调节，直接将原始数据放大或者缩小，不是所有平台都支持，建议尽量用硬件方法去缩放
@api audio.vol(id, value)
@int 音频通道
@int 音量，百分比，1%~1000%，默认100%，就是不调节
@return int 当前音量
@usage
local result = audio.vol(0, 90)	--通道0的音量调节到90%，result存放了调节后的音量水平，有可能仍然是100
*/
static int l_audio_vol(lua_State *L) {
    lua_pushinteger(L, luat_audio_vol(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 100)));
    return 1;
}

/*
配置一个音频通道的硬件输出总线，只有对应soc软硬件平台支持才设置对应类型
@api audio.vol(id, bus_type)
@int 音频通道
@int 总线类型
@return
@usage
audio.setBus(0, audio.BUS_SOFT_DAC)	--通道0的硬件输出通道设置为软件DAC
audio.setBus(0, audio.BUS_I2S)	--通道0的硬件输出通道设置为I2S
*/
static int l_audio_set_output_bus(lua_State *L) {
	luat_audio_set_bus_type(luaL_checkinteger(L, 2));
    return 0;
}




#include "rotable2.h"
static const rotable_Reg_t reg_audio[] =
{
    { "start" ,        ROREG_FUNC(l_audio_start_raw)},
    { "write" ,        ROREG_FUNC(l_audio_write_raw)},
    { "pause",         ROREG_FUNC(l_audio_pause_raw)},
	{ "stop",		   ROREG_FUNC(l_audio_stop_raw)},
    { "on",            ROREG_FUNC(l_audio_raw_on)},
	{ "play",		   ROREG_FUNC(l_audio_play)},
#ifdef LUAT_USE_TTS
	{ "tts",		   ROREG_FUNC(l_audio_play_tts)},
#endif
	{ "playStop",	   ROREG_FUNC(l_audio_play_stop)},
	{ "isEnd",		   ROREG_FUNC(l_audio_play_wait_end)},
	{ "config",			ROREG_FUNC(l_audio_config)},
	{ "vol",			ROREG_FUNC(l_audio_vol)},
	{ "getError",			ROREG_FUNC(l_audio_play_get_last_error)},
	{ "setBus",			ROREG_FUNC(l_audio_set_output_bus)},
	//@const PCM number PCM格式，即原始ADC数据
    { "PCM",           ROREG_INT(MULTIMEDIA_DATA_TYPE_PCM)},
	//@const MORE_DATA number audio.on回调函数传入参数的值，表示底层播放完一段数据，可以传入更多数据
	{ "MORE_DATA",     ROREG_INT(MULTIMEDIA_CB_AUDIO_NEED_DATA)},
	//@const DONE number audio.on回调函数传入参数的值，表示底层播放完全部数据了
	{ "DONE",          ROREG_INT(MULTIMEDIA_CB_AUDIO_DONE)},
	//@const BUS_DAC number 硬件输出总线，DAC类型
	{ "BUS_DAC", 		ROREG_INT(MULTIMEDIA_AUDIO_BUS_DAC)},
	//@const BUS_I2S number 硬件输出总线，I2S类型
	{ "BUS_I2S", 		ROREG_INT(MULTIMEDIA_AUDIO_BUS_I2S)},
	//@const BUS_SOFT_DAC number 硬件输出总线，软件模式DAC类型
	{ "BUS_SOFT_DAC", 		ROREG_INT(MULTIMEDIA_AUDIO_BUS_SOFT_DAC)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_multimedia_audio( lua_State *L ) {
    luat_newlib2(L, reg_audio);
    return 1;
}
