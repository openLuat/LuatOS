
/*
@module  multimedia
@summary 多媒体
@version 1.0
@date    2022.03.11
*/
#include "luat_base.h"
#include "luat_multimedia.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "multimedia"
#include "luat_log.h"

#include <stddef.h>
#include "mp3_decode/minimp3.h"


typedef struct
{

	union
	{
		mp3dec_t *mp3_decoder;
	};
	uint8_t type;
	uint8_t is_decoder;
}luat_multimedia_codec_t;

#define MAX_DEVICE_COUNT 2

typedef struct luat_multimedia_cb {
    int function_ref;
} luat_multimedia_cb_t;

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

/*
注册audio播放事件回调
@api    audio.on(id, event, func)
@int audio id, audio 0写0, audio 1写1
@function 回调方法
@return nil 无返回值
@usage
camera.on(0, function(id, str)
    print(id, str)
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


/**
创建编解码用的codec
@api codec.create(codec.MP3)
@int 多媒体类型，目前支持decode.MP3
@boolean 是否是编码器，默认true，是解码器
@return userdata 成功返回一个数据结构,否则返回nil
@usage
-- 创建decoder
local decoder = codec.create(codec.MP3)--创建一个mp3的decoder
 */
static int l_codec_create(lua_State *L) {
    uint8_t type = luaL_optinteger(L, 1, MULTIMEDIA_DATA_TYPE_MP3);
    uint8_t is_decoder = 1;
    if (lua_isboolean(L, 2)) {
    	is_decoder = lua_toboolean(L, 2);
    }
    luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)lua_newuserdata(L, sizeof(luat_multimedia_codec_t));
    if (coder == NULL) {
    	lua_pushnil(L);
    } else {
    	coder->type = type;
    	coder->is_decoder = is_decoder;
    	if (is_decoder)
    	{
        	switch (type) {
        	case MULTIMEDIA_DATA_TYPE_MP3:
            	coder->mp3_decoder = luat_heap_malloc(sizeof(mp3dec_t));
            	if (!coder->mp3_decoder) {
            		lua_pushnil(L);
            	}
            	break;
        	}
    	}

    }
    return 1;
}

/**
decoder从文件数据中解析出音频信息
@api codec.get_audio_info(decoder, data)
@coder 解码用的decoder
@string 文件数据，必须是开头的数据
@return
@boolean 是否成功解析
@int 音频格式
@int 声音通道数
@int 采样频率
@int 采样位数
@boolean 是否有符号
@usage
local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed= codec.get_audio_info(coder, "xxx")
 */
static int l_codec_get_audio_info(lua_State *L) {
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)lua_touserdata(L, 1);
	int result = 0;
	int audio_format;
	int num_channels;
	int sample_rate;
	int bits_per_sample = 16;
	int is_signed = 1;
    size_t len;
    mp3dec_frame_info_t info;
    const char *data = luaL_checklstring(L, 2, &len);
	if (coder)
    {

		switch(coder->type)
		{
		case MULTIMEDIA_DATA_TYPE_MP3:
			mp3dec_init(coder->mp3_decoder);

			result = mp3dec_decode_frame(coder->mp3_decoder, data, len, NULL, &info);
			memset(coder->mp3_decoder, 0, sizeof(mp3dec_t));
			audio_format = MULTIMEDIA_DATA_TYPE_PCM;
			num_channels = info.channels;
			sample_rate = info.hz;
			break;
		default:
			break;
		}

    }
	lua_pushboolean(L, result);
	lua_pushinteger(L, audio_format);
	lua_pushinteger(L, num_channels);
	lua_pushinteger(L, sample_rate);
	lua_pushinteger(L, bits_per_sample);
	lua_pushboolean(L, is_signed);
	return 6;
}

/**
decoder从文件数据中解析出音频数据
@api codec.get_audio_data(decoder, in_buff, out_buff)
@coder 解码用的decoder
@zbuff 存放输入数据的zbuff
@zbuff 存放输出数据的zbuff，空间必须不少于16KB
@return
@boolean 是否成功解析
@usage
local result = codec.get_audio_data(coder, "xxx", zbuff)
 */
static int l_codec_get_audio_data(lua_State *L) {
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)lua_touserdata(L, 1);
	uint32_t pos = 0;
	int result;
	luat_zbuff_t *in_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE));
	mp3dec_frame_info_t info;
	out_buff->used = 0;
	if (coder)
    {
		switch(coder->type)
		{
		case MULTIMEDIA_DATA_TYPE_MP3:
			do
			{
				result = mp3dec_decode_frame(coder->mp3_decoder, in_buff->addr + pos, in_buff->used - pos, out_buff->addr + out_buff->used, &info);
//				LLOGD("result %u,%u,%u,%u", result, info.frame_bytes, pos, coder->mp3_decoder->reserv);
				out_buff->used += (result * info.channels * 2);
				if (result)
				{
					pos += info.frame_bytes;
				}
				if ((out_buff->len - out_buff->used) < MINIMP3_MAX_SAMPLES_PER_FRAME)
				{
					__zbuff_resize(out_buff, out_buff->len * 2);
				}
			} while ((result > 0) && ((in_buff->used - pos) >= info.frame_bytes));
//			LLOGD("result %u,%u,%u", result, in_buff->used - pos, info.frame_bytes);
			if (pos >= in_buff->used)
			{
				in_buff->used = 0;
			}
			else
			{
				memmove(in_buff->addr, in_buff->addr + pos, in_buff->used - pos);
				in_buff->used -= pos;
			}
			break;
		default:
			break;
		}

    }
	lua_pushboolean(L, result);
	return 1;
}

/**
释放编解码用的coder
@api codec.release(coder)
@return
codec.release(coder)
 */
static int l_codec_release(lua_State *L) {
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)lua_touserdata(L, 1);
	if (coder) {
		switch(coder->type) {
		case MULTIMEDIA_DATA_TYPE_MP3:
			if (coder->is_decoder) {
				luat_heap_free(coder->mp3_decoder);
			}
			break;
		}
	} else {
		luaL_error(L, "no codec");
	}
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
    { "PCM",           ROREG_INT(MULTIMEDIA_DATA_TYPE_PCM)},
	{ "MORE_DATA",     ROREG_INT(MULTIMEDIA_CB_AUDIO_NEED_DATA)},
	{ "DONE",          ROREG_INT(MULTIMEDIA_CB_AUDIO_DONE)},
	{ NULL,            {}}
};

static const rotable_Reg_t reg_codec[] =
{
    { "create" ,         ROREG_FUNC(l_codec_create)},
    { "get_audio_info" , ROREG_FUNC(l_codec_get_audio_info)},
    { "get_audio_data",  ROREG_FUNC(l_codec_get_audio_data)},
    { "release",         ROREG_FUNC(l_codec_release)},
	{ "MP3",             ROREG_INT(MULTIMEDIA_DATA_TYPE_MP3)},
	{ NULL,              {}}
};

LUAMOD_API int luaopen_multimedia_audio( lua_State *L ) {
    luat_newlib2(L, reg_audio);
    return 1;
}

LUAMOD_API int luaopen_multimedia_codec( lua_State *L ) {
    luat_newlib2(L, reg_codec);
    return 1;
}

