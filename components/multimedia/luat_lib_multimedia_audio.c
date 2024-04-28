
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
#include "luat_audio.h"
#include "luat_mem.h"

#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif
#ifdef LUAT_USE_RECORD
static luat_record_ctrl_t g_s_record = {0};
#endif
static luat_multimedia_cb_t multimedia_cbs[MAX_DEVICE_COUNT];

int l_multimedia_raw_handler(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (multimedia_cbs[msg->arg2].function_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, multimedia_cbs[msg->arg2].function_ref);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, msg->arg2);
            lua_pushinteger(L, msg->arg1);
#ifdef LUAT_USE_RECORD
            if (msg->arg1 == LUAT_MULTIMEDIA_CB_RECORD_DATA){
                lua_pushlightuserdata(L, g_s_record.record_buffer[(int)msg->ptr]);
                lua_call(L, 3, 0);
            }else{
                lua_call(L, 2, 0);
                if (msg->arg1 == LUAT_MULTIMEDIA_CB_RECORD_DONE){
                    luaL_unref(L,LUA_REGISTRYINDEX, g_s_record.zbuff_ref[0]);
                    if (g_s_record.record_buffer[0]->addr){
                        luat_heap_opt_free(g_s_record.record_buffer[0]->type,g_s_record.record_buffer[0]->addr);
                        g_s_record.record_buffer[0]->addr = NULL;
                        g_s_record.record_buffer[0]->len = 0;
                        g_s_record.record_buffer[0]->used = 0;
                    }
                    luaL_unref(L,LUA_REGISTRYINDEX, g_s_record.zbuff_ref[1]);
                    if (g_s_record.record_buffer[1]->addr){
                        luat_heap_opt_free(g_s_record.record_buffer[1]->type,g_s_record.record_buffer[1]->addr);
                        g_s_record.record_buffer[1]->addr = NULL;
                        g_s_record.record_buffer[1]->len = 0;
                        g_s_record.record_buffer[1]->used = 0;
                    }
                }
            }
#else
            lua_call(L, 2, 0);
#endif
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}

/*
启动一个多媒体通道准备播放音频
@api audio.start(id, audio_format, num_channels, sample_rate, bits_per_sample, is_signed)
@int 多媒体播放通道号
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

#ifdef LUAT_USE_RECORD

#ifdef LUAT_SUPPORT_AMR
#include "interf_enc.h"
#include "interf_dec.h"
#endif
#include "luat_fs.h"
#define RECORD_ONCE_LEN	10	   //单声道 8K录音单次10个编码块，总共200ms回调 320B 20ms，amr编码要求，20ms一个块

#ifdef LUAT_SUPPORT_AMR
static void record_encode_amr(uint8_t *data, uint32_t len){
	uint8_t outbuf[64];
	int16_t *pcm = (int16_t *)data;
	uint32_t total_len = len >> 1;
	uint32_t done_len = 0;
	uint8_t out_len;

	while ((total_len - done_len) >= 160){
#ifdef LUAT_USE_INTER_AMR
		luat_audio_inter_amr_coder_encode(g_s_record.encoder_handler, &pcm[done_len], outbuf,&out_len);
#else
        out_len = Encoder_Interface_Encode(g_s_record.encoder_handler, g_s_record.quailty , &pcm[done_len], outbuf, 0);
#endif
		if (out_len <= 0){
			LLOGD("encode error in %d,result %d", done_len, out_len);
		}else{
            luat_fs_fwrite(outbuf, out_len, 1, g_s_record.fd);
		}
		done_len += 160;
	}
}

static void record_stop_encode_amr(void){
	luat_audio_record_stop(g_s_record.multimedia_id);
	luat_audio_pm_request(g_s_record.multimedia_id, LUAT_AUDIO_PM_STANDBY);
    if (g_s_record.fd){
#ifdef LUAT_USE_INTER_AMR
        luat_audio_inter_amr_coder_deinit(g_s_record.encoder_handler);
#else
        Encoder_Interface_exit(g_s_record.encoder_handler);
#endif
        g_s_record.encoder_handler = NULL;
        luat_fs_fclose(g_s_record.fd);
        g_s_record.fd = NULL;
    }
	luat_i2s_conf_t *i2s = luat_i2s_get_config(g_s_record.multimedia_id);
    memcpy(i2s, &g_s_record.i2s_back, sizeof(luat_i2s_conf_t));
}
#endif

int record_cb(uint8_t id ,luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param)
{
	switch(event)
	{
	case LUAT_I2S_EVENT_RX_DONE:
        luat_rtos_event_send(g_s_record.task_handle, LUAT_I2S_EVENT_RX_DONE, (uint32_t)rx_data, rx_len, 0, 0);
		break;
	case LUAT_I2S_EVENT_TRANSFER_DONE:
		break;
	default:
		break;
	}
	return 0;
}

static void record_task(void *arg)
{
    luat_event_t event;
    rtos_msg_t msg = {0};
    msg.handler = l_multimedia_raw_handler;
	luat_i2s_conf_t *i2s = luat_i2s_get_config(g_s_record.multimedia_id);
    memcpy(&g_s_record.i2s_back, i2s, sizeof(luat_i2s_conf_t));
    i2s->cb_rx_len = g_s_record.record_buffer[g_s_record.record_buffer_index]->len;
	i2s->is_full_duplex = 1;
	i2s->luat_i2s_event_callback = record_cb;
    if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB){
        i2s->sample_rate = 8000;
    }else if(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
        i2s->sample_rate = 16000;
    }
    
    if (g_s_record.fd){
        if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB||g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_SUPPORT_AMR
#ifdef LUAT_USE_INTER_AMR
            g_s_record.encoder_handler = luat_audio_inter_amr_coder_init(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB?0:1, g_s_record.quailty);
#else
            g_s_record.encoder_handler = Encoder_Interface_init(g_s_record.quailty);
#endif
            luat_fs_fwrite("#!AMR\n", 6, 1, g_s_record.fd);
#endif
        }
    }

    luat_audio_record_and_play(g_s_record.multimedia_id, i2s->sample_rate, NULL, 3200, 2);

    while (1)
    {
        luat_rtos_event_recv(g_s_record.task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
        switch(event.id){
        case LUAT_I2S_EVENT_RX_DONE:
            if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB||g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_SUPPORT_AMR
                if (g_s_record.fd){
                    record_encode_amr((uint8_t *)event.param1, event.param2);
                }else{
                    memcpy(g_s_record.record_buffer[g_s_record.record_buffer_index]->addr, (uint8_t *)event.param1, event.param2);
                    g_s_record.record_buffer[g_s_record.record_buffer_index]->used = event.param2;
                    
                    msg.arg1 = LUAT_MULTIMEDIA_CB_RECORD_DATA;
                    msg.arg2 = g_s_record.multimedia_id;
                    msg.ptr = g_s_record.record_buffer_index;
                    luat_msgbus_put(&msg, 1);
                    g_s_record.record_buffer_index = !g_s_record.record_buffer_index;
                }
                g_s_record.record_time_tmp++;
                if (g_s_record.record_time_tmp >= (g_s_record.record_time * (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB?5:10) ))	//8K 5秒 16K 10秒
                {
                    record_stop_encode_amr();
                    msg.arg1 = LUAT_MULTIMEDIA_CB_RECORD_DONE;
                    msg.arg2 = g_s_record.multimedia_id;
                    luat_msgbus_put(&msg, 1);
                    goto end;
                }
#endif
            }
            break;
        }
    }
end:
    g_s_record.record_time_tmp = 0;
    g_s_record.is_run = 0;
    g_s_record.record_buffer_index = 0;
    luat_rtos_task_delete(g_s_record.task_handle);
}

/**
录音
@api audio.record(id, record_type, record_time, amr_quailty, path)
@int id             多媒体播放通道号
@int record_type    录音文件音频格式,支持 audio.AMR audio.PCM 
@int record_time    录制时长 单位秒
@int amr_quailty    质量,audio.AMR下有效
@string path        录音文件路径,可选,不指定则不保存,可在audio.on回调函数中处理原始PCM数据
@return boolean     成功返回true,否则返回false
@usage
err,info = audio.record(id, type, record_time, quailty, path)
*/
static int l_audio_record(lua_State *L){
    size_t len;
    uint32_t record_buffer_len;
    g_s_record.multimedia_id = luaL_checkinteger(L, 1);
    g_s_record.type = luaL_optinteger(L, 2,LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB);
    g_s_record.record_time = luaL_checkinteger(L, 3);
    g_s_record.quailty = luaL_optinteger(L, 4, 0);
    if (lua_isstring(L, 5)) {
        const char *path = luaL_checklstring(L, 5, &len);
        luat_fs_remove(path);
        g_s_record.fd = luat_fs_fopen(path, "wb+");
        if(!g_s_record.fd){
            LLOGE("open file %s failed", path);
            return 0;
        }
    }
    if (g_s_record.is_run){
        LLOGE("record is running");
        return 0;
    }

    if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB||g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_SUPPORT_AMR
    if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB){
        record_buffer_len = 320 * RECORD_ONCE_LEN;
    }else if(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_USE_INTER_AMR
        record_buffer_len = 640 * RECORD_ONCE_LEN;
#else
    LLOGE("not support 16k");
    return 0;
#endif
    }
    
    g_s_record.record_buffer[0] = lua_newuserdata(L, sizeof(luat_zbuff_t));
    g_s_record.record_buffer[0]->type = LUAT_HEAP_SRAM;
    g_s_record.record_buffer[0]->len = record_buffer_len;
    g_s_record.record_buffer[0]->addr = luat_heap_opt_malloc(LUAT_HEAP_SRAM,g_s_record.record_buffer[0]->len);
    lua_pushlightuserdata(L, g_s_record.record_buffer[0]);
    g_s_record.zbuff_ref[0] = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);

    g_s_record.record_buffer[1] = lua_newuserdata(L, sizeof(luat_zbuff_t));
    g_s_record.record_buffer[1]->type = LUAT_HEAP_SRAM;
    g_s_record.record_buffer[1]->len = record_buffer_len;
    g_s_record.record_buffer[1]->addr = luat_heap_opt_malloc(LUAT_HEAP_SRAM,g_s_record.record_buffer[1]->len);
    lua_pushlightuserdata(L, g_s_record.record_buffer[1]);
    g_s_record.zbuff_ref[1] = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);

#else
    LLOGE("not support AMR");
    return 0;
#endif
    }else if(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_PCM){
        // 不需要特殊处理
    }else{
        LLOGE("not support %d", g_s_record.type);
        return 0;
    }

    luat_rtos_task_create(&g_s_record.task_handle, 8*1024, 100, "record_task", record_task, NULL, 0);
    g_s_record.is_run = 1;
    lua_pushboolean(L, 1);
    return 1;
}

/**
录音停止
@api audio.recordStop(id)
@int id         多媒体播放通道号
@return boolean 成功返回true,否则返回false
@usage
audio.recordStop(0)
*/
static int l_audio_record_stop(lua_State *L) {
    rtos_msg_t msg = {0};
    msg.handler = l_multimedia_raw_handler;
    if (g_s_record.is_run) {
        if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB||g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_SUPPORT_AMR
            record_stop_encode_amr();
#endif
        }else if(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_PCM){
            // 不需要特殊处理
        }else{
            LLOGE("not support %d", g_s_record.type);
            return 0;
        }
        msg.arg1 = LUAT_MULTIMEDIA_CB_RECORD_DONE;
        msg.arg2 = g_s_record.multimedia_id;
        luat_msgbus_put(&msg, 1);
        g_s_record.record_time_tmp = 0;
        g_s_record.is_run = 0;
        g_s_record.record_buffer_index = 0;
        luat_rtos_task_delete(g_s_record.task_handle);
        lua_pushboolean(L, 1);
        return 1;
    } else {
        LLOGE("record is not running");
        return 0;
    }
}

#endif

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
    const char *buf;
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
	lua_pushboolean(L, !luat_audio_write_raw(multimedia_id, (uint8_t*)buf, len));
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
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, !luat_audio_stop_raw(id));
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
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, !luat_audio_pause_raw(id, lua_toboolean(L, 2)));
    return 1;
}

/**
注册audio播放事件回调
@api    audio.on(audio_id, func)
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
    size_t len = 0;
    int result = 0;
    const char *buf;
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
            info[i].value.asBuffer.buffer = (void*)lua_tolstring(L, -1, &info[i].value.asBuffer.length);
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
    size_t len = 0;
    int result = 0;
    const char *buf;
    if (LUA_TSTRING == (lua_type(L, (2))))
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
        result = luat_audio_play_tts_text(multimedia_id, (void*)buf, len);
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
    int multimedia_id = luaL_checkinteger(L, 1);
	int result = luat_audio_play_get_last_error(multimedia_id);
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
    int id = luaL_checkinteger(L, 1);
    int pa_pin = luaL_optinteger(L, 2, -1);
    int level = luaL_optinteger(L, 3, 1);
    int dac_pre_delay = luaL_optinteger(L, 4, 5);
    int dac_last_delay = luaL_optinteger(L, 5, 200);
    int dac_power_pin = luaL_optinteger(L, 6, -1);
    int dac_power_level = luaL_optinteger(L, 7, 1);
    int pa_dac_delay = luaL_optinteger(L, 8, 0);
    if (pa_dac_delay < 0)
        pa_dac_delay = 0;
    if (dac_pre_delay < 0)
        dac_pre_delay = 0;
    if (dac_last_delay < 0)
        dac_last_delay = 0;
    luat_audio_config_pa(id, pa_pin, level, (uint32_t)dac_pre_delay, (uint32_t)dac_last_delay);
    luat_audio_config_dac(id, dac_power_pin, dac_power_level, (uint32_t)pa_dac_delay);
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
    int id = luaL_checkinteger(L, 1);
    int vol = luaL_optinteger(L, 2, 100);
    lua_pushinteger(L, luat_audio_vol(id, vol));
    return 1;
}

/*
配置一个音频通道的mic音量调节
@api audio.micVol(id, value)
@int 音频通道
@int mic音量，百分比，1%~100%，默认100%，就是不调节
@return int 当前mic音量
@usage
local result = audio.vol(0, 90)	--通道0的音量调节到90%，result存放了调节后的音量水平，有可能仍然是100
*/
static int l_audio_mic_vol(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int mic_vol = luaL_optinteger(L, 2, 100);
    lua_pushinteger(L, luat_audio_mic_vol(id, mic_vol));
    return 1;
}

/*
配置一个音频通道的硬件输出总线，只有对应soc软硬件平台支持才设置对应类型
@api audio.setBus(id, bus_type)
@int 音频通道,例如0
@int 总线类型, 例如 audio.BUS_SOFT_DAC
@int 硬件id, 例如 总线类型为audio.BUS_I2S时,硬件id即为i2s codec的i2c id
@return nil 无返回值
@usage
audio.setBus(0, audio.BUS_SOFT_DAC)	--通道0的硬件输出通道设置为软件DAC
audio.setBus(0, audio.BUS_I2S)	--通道0的硬件输出通道设置为I2S
*/
static int l_audio_set_output_bus(lua_State *L) {
    size_t len;
    int id = luaL_checkinteger(L, 1);
    luat_audio_conf_t* audio_conf = luat_audio_get_config(id);
    int tp = luaL_checkinteger(L, 2);
    int ret = luat_audio_set_bus_type(id,tp);
    if (audio_conf!=NULL && lua_istable(L,3) && tp==LUAT_AUDIO_BUS_I2S){
        audio_conf->codec_conf.multimedia_id = id;
        audio_conf->bus_type = LUAT_AUDIO_BUS_I2S;
        audio_conf->codec_conf.codec_opts = &codec_opts_common;
		lua_pushstring(L, "chip");
		if (LUA_TSTRING == lua_gettable(L, 3)) {
            const char *chip = luaL_checklstring(L, -1,&len);
            if(strcmp(chip,"es8311") == 0){
                audio_conf->codec_conf.codec_opts = &codec_opts_es8311;
            }
		}
		lua_pop(L, 1);
		lua_pushstring(L, "i2cid");
		if (LUA_TNUMBER == lua_gettable(L, 3)) {
			audio_conf->codec_conf.i2c_id = luaL_checknumber(L, -1);
		}
		lua_pop(L, 1);
		lua_pushstring(L, "i2sid");
		if (LUA_TNUMBER == lua_gettable(L, 3)) {
			audio_conf->codec_conf.i2s_id = luaL_checknumber(L, -1);
		}
		lua_pop(L, 1);
    }
    ret |= luat_audio_init(id, 0, 0);
    lua_pushboolean(L, !ret);
    return 1;
}

LUAT_WEAK void luat_audio_set_debug(uint8_t on_off)
{
	(void)on_off;
}
/*
配置调试信息输出
@api audio.debug(on_off)
@boolean true开 false关
@return
@usage
audio.debug(true)	--开启调试信息输出
audio.debug(false)	--关闭调试信息输出
*/
static int l_audio_set_debug(lua_State *L) {
	luat_audio_set_debug(lua_toboolean(L, 1));
    return 0;
}

/*
audio 休眠控制(一般会自动调用不需要手动执行)
@api audio.pm(id,pm_mode)
@int 音频通道
@int 休眠模式 
@return boolean true成功
@usage
audio.pm(multimedia_id,audio.RESUME)
*/
static int l_audio_pm_request(lua_State *L) {
    lua_pushboolean(L, !luat_audio_pm_request(luaL_checkinteger(L, 1),luaL_checkinteger(L, 2)));
    return 1;
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
    { "micVol",			ROREG_FUNC(l_audio_mic_vol)},
	{ "getError",		ROREG_FUNC(l_audio_play_get_last_error)},
	{ "setBus",			ROREG_FUNC(l_audio_set_output_bus)},
	{ "debug",			ROREG_FUNC(l_audio_set_debug)},
    { "pm",			    ROREG_FUNC(l_audio_pm_request)},
#ifdef LUAT_USE_RECORD
    { "record",			ROREG_FUNC(l_audio_record)},
    { "recordStop",		ROREG_FUNC(l_audio_record_stop)},
    
#endif
	//@const RESUME number PM模式 工作模式
    { "RESUME",         ROREG_INT(LUAT_AUDIO_PM_RESUME)},
    //@const STANDBY number PM模式 待机模式，PA断电，codec待机状态，系统不能进低功耗状态，如果PA不可控，codec进入静音模式
    { "STANDBY",        ROREG_INT(LUAT_AUDIO_PM_STANDBY)},
    //@const SHUTDOWN number PM模式 关机模式，PA断电，可配置的codec关机状态，不可配置的codec断电，系统能进低功耗状态
    { "SHUTDOWN",       ROREG_INT(LUAT_AUDIO_PM_SHUTDOWN)},
	//@const POWEROFF number PM模式 断电模式，PA断电，codec断电，系统能进低功耗状态
    { "POWEROFF",         ROREG_INT(LUAT_AUDIO_PM_POWER_OFF)},
	//@const PCM number PCM格式，即原始ADC数据
    { "PCM",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_PCM)},
    //@const MP3 number MP3格式
    { "MP3",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_MP3)},
    //@const WAV number WAV格式
    { "WAV",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_WAV)},
    //@const AMR number AMR_NB格式
    { "AMR",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB)},
    //@const AMR_NB number AMR_NB格式
    { "AMR_NB",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB)},
    //@const AMR_WB number AMR_WB格式
    { "AMR_WB",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB)},
	//@const MORE_DATA number audio.on回调函数传入参数的值，表示底层播放完一段数据，可以传入更多数据
	{ "MORE_DATA",     ROREG_INT(LUAT_MULTIMEDIA_CB_AUDIO_NEED_DATA)},
	//@const DONE number audio.on回调函数传入参数的值，表示底层播放完全部数据了
	{ "DONE",          ROREG_INT(LUAT_MULTIMEDIA_CB_AUDIO_DONE)},
	//@const RECORD_DATA number audio.on回调函数传入参数的值，表示录音数据
	{ "RECORD_DATA",     ROREG_INT(LUAT_MULTIMEDIA_CB_RECORD_DATA)},
	//@const RECORD_DONE number audio.on回调函数传入参数的值，表示录音完成
	{ "RECORD_DONE",          ROREG_INT(LUAT_MULTIMEDIA_CB_RECORD_DONE)},
	//@const BUS_DAC number 硬件输出总线，DAC类型
	{ "BUS_DAC", 		ROREG_INT(LUAT_AUDIO_BUS_DAC)},
	//@const BUS_I2S number 硬件输出总线，I2S类型
	{ "BUS_I2S", 		ROREG_INT(LUAT_AUDIO_BUS_I2S)},
	//@const BUS_SOFT_DAC number 硬件输出总线，软件模式DAC类型
	{ "BUS_SOFT_DAC", 		ROREG_INT(LUAT_AUDIO_BUS_SOFT_DAC)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_multimedia_audio( lua_State *L ) {
    luat_newlib2(L, reg_audio);
    return 1;
}
