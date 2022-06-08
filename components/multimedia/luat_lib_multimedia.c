
/*
@module  multimedia
@summary 多媒体
@version 1.0
@date    2022.03.11
@demo multimedia
*/
#include "luat_base.h"
#include "luat_multimedia.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "multimedia"
#include "luat_log.h"

#include <stddef.h>
#include "mp3_decode/minimp3.h"
#define LUAT_M_CODE_TYPE "MCODER*"
#define MP3_FRAME_LEN 4 * 1152


typedef struct
{

	union
	{
		mp3dec_t *mp3_decoder;
		uint32_t read_len;
	};
	FILE* fd;
	luat_zbuff_t buff;
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

/**
注册audio播放事件回调
@api    audio.on(id, event, func)
@int audio id, audio 0写0, audio 1写1
@function 回调方法
@return nil 无返回值
@usage
audio.on(0, function(id, str)
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

/*
播放或者停止播放一个文件，播放完成后，会回调一个audio.DONE消息，可以用pause来暂停或者恢复，其他API不可用。考虑到读SD卡速度比较慢而拖累luavm进程的速度，所以尽量使用本API
@api audio.play(id, path)
@int 音频通道
@string 文件名，如果为空，则表示停止播放
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
    if (lua_isstring(L, 2))
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
        char *path = luat_heap_malloc(len + 1);
        memcpy(path, buf, len);
        path[len] = 0;

        result = luat_audio_play_file(multimedia_id, path);
    	lua_pushboolean(L, !result);
    	luat_heap_free(path);
    }
    else
    {
    	luat_audio_play_stop(multimedia_id);
    	lua_pushboolean(L, 1);
    }
    return 1;
}

/**
检查当前文件是否已经播放结束
@api audio.isEnd(id, path)
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
配置一个音频通道的特性，比如实现自动控制PA开关。注意这个不是必须的，一般在调用play的时候才需要自动控制，其他情况比如你手动控制播放时，就可以自己控制PA开关
@api audio.config(id, paPin, onLevel)
@int 音频通道
@int PA控制IO
@int PA打开时的电平
@return 无
@usage
audio.config(0, pin.PC0, 1)	--PA控制脚是PC0，高电平打开
*/
static int l_audio_config(lua_State *L) {
    luat_audio_config_pa(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 255), luaL_optinteger(L, 3, 1));
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
    	memset(coder, 0, sizeof(luat_multimedia_codec_t));
    	coder->type = type;
    	coder->is_decoder = is_decoder;
    	if (is_decoder)
    	{
        	switch (type) {
        	case MULTIMEDIA_DATA_TYPE_MP3:
            	coder->mp3_decoder = luat_heap_malloc(sizeof(mp3dec_t));
            	if (!coder->mp3_decoder) {
            		lua_pushnil(L);
            		return 1;
            	}
            	break;
        	}

    	}
    	luaL_setmetatable(L, LUAT_M_CODE_TYPE);
    }
    return 1;
}

/**
decoder从文件中解析出音频信息
@api codec.info(decoder, file_path)
@coder 解码用的decoder
@string 文件路径
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
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
	uint32_t jump, i;
	uint8_t temp[16];
	int result = 0;
	int audio_format;
	int num_channels;
	int sample_rate;
	int bits_per_sample = 16;
	uint32_t align;
	int is_signed = 1;
    size_t len;
    mp3dec_frame_info_t info;
    const char *file_path = luaL_checklstring(L, 2, &len);
    FILE *fd = luat_fs_fopen(file_path, "r");
    if (fd && coder)
    {

		switch(coder->type)
		{
		case MULTIMEDIA_DATA_TYPE_MP3:
			mp3dec_init(coder->mp3_decoder);
			coder->buff.addr = luat_heap_malloc(MP3_FRAME_LEN);

			coder->buff.len = MP3_FRAME_LEN;
			coder->buff.used = luat_fs_fread(temp, 10, 1, fd);
			if (coder->buff.used != 10)
			{
				break;
			}
			if (!memcmp(temp, "ID3", 3))
			{
				jump = 0;
				for(i = 0; i < 4; i++)
				{
					jump <<= 7;
					jump |= temp[6 + i] & 0x7f;
				}
//				LLOGD("jump head %d", jump);
				luat_fs_fseek(fd, jump, SEEK_SET);

			}
			coder->buff.used = luat_fs_fread(coder->buff.addr, MP3_FRAME_LEN, 1, fd);
			result = mp3dec_decode_frame(coder->mp3_decoder, coder->buff.addr, coder->buff.used, NULL, &info);
			memset(coder->mp3_decoder, 0, sizeof(mp3dec_t));
			audio_format = MULTIMEDIA_DATA_TYPE_PCM;
			num_channels = info.channels;
			sample_rate = info.hz;
			break;
		case MULTIMEDIA_DATA_TYPE_WAV:
			luat_fs_fread(temp, 12, 1, fd);
			if (!memcmp(temp, "RIFF", 4) || !memcmp(temp + 8, "WAVE", 4))
			{
				luat_fs_fread(temp, 8, 1, fd);
				if (!memcmp(temp, "fmt ", 4))
				{
					memcpy(&len, temp + 4, 4);
					coder->buff.addr = luat_heap_malloc(len);
					luat_fs_fread(coder->buff.addr, len, 1, fd);
					audio_format = coder->buff.addr[0];
					num_channels = coder->buff.addr[2];
					memcpy(&sample_rate, coder->buff.addr + 4, 4);
					align = coder->buff.addr[12];
					bits_per_sample = coder->buff.addr[14];
					coder->read_len = (align * sample_rate >> 3) & ~(3);
//					LLOGD("size %d", coder->read_len);
					luat_heap_free(coder->buff.addr);
					coder->buff.addr = NULL;
					luat_fs_fread(temp, 8, 1, fd);
					if (!memcmp(temp, "fact", 4))
					{
						memcpy(&len, temp + 4, 4);
						luat_fs_fseek(fd, len, SEEK_CUR);
						luat_fs_fread(temp, 8, 1, fd);
					}
					if (!memcmp(temp, "data", 4))
					{
						result = 1;
					}
					else
					{
						LLOGD("no data");
						result = 0;
					}
				}
				else
				{
					LLOGD("no fmt");
				}
			}
			else
			{
				LLOGD("head error");
			}
			break;
		default:
			break;
		}

    }
    if (!result)
    {
    	luat_fs_fclose(fd);
    }
    else
    {
    	coder->fd = fd;
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
@api codec.data(decoder, out_buff)
@coder 解码用的decoder
@zbuff 存放输出数据的zbuff，空间必须不少于16KB
@return
@boolean 是否成功解析
@usage
local result = codec.get_audio_data(coder, zbuff)
 */
static int l_codec_get_audio_data(lua_State *L) {
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
	uint32_t pos = 0;
	int read_len;
	int result;
	luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	uint32_t is_not_end = 1;
	mp3dec_frame_info_t info;
	out_buff->used = 0;
	if (coder)
    {
		switch(coder->type)
		{
		case MULTIMEDIA_DATA_TYPE_MP3:
GET_MP3_DATA:
			if (coder->buff.used < MINIMP3_MAX_SAMPLES_PER_FRAME)
			{
				read_len = luat_fs_fread(coder->buff.addr + coder->buff.used, MINIMP3_MAX_SAMPLES_PER_FRAME, 1, coder->fd);
				if (read_len > 0)
				{
					coder->buff.used += read_len;
				}
				else
				{
					is_not_end = 0;
				}
			}
			do
			{
				memset(&info, 0, sizeof(info));
				result = mp3dec_decode_frame(coder->mp3_decoder, coder->buff.addr + pos, coder->buff.used - pos, out_buff->addr + out_buff->used, &info);
				out_buff->used += (result * info.channels * 2);
//				if (!result) {
//					LLOGD("jump %dbyte", info.frame_bytes);
//				}
				pos += info.frame_bytes;
				if ((out_buff->len - out_buff->used) < (MINIMP3_MAX_SAMPLES_PER_FRAME * 2))
				{
					break;
				}
			} while ((coder->buff.used - pos) >= (MINIMP3_MAX_SAMPLES_PER_FRAME * is_not_end + 1));
//			LLOGD("result %u,%u,%u,%u,%u", result, out_buff->used, coder->buff.used, pos, info.frame_bytes);
			if (pos >= coder->buff.used)
			{
				coder->buff.used = 0;
			}
			else
			{
				memmove(coder->buff.addr, coder->buff.addr + pos, coder->buff.used - pos);
				coder->buff.used -= pos;
			}
			pos = 0;
			if (!out_buff->used)
			{
				if (is_not_end)
				{
					goto GET_MP3_DATA;
				}
				else
				{
					result = 0;
				}
			}
			else
			{
				if ((out_buff->used < 16384) && is_not_end)
				{
					goto GET_MP3_DATA;
				}
				result = 1;
			}
			break;
		case MULTIMEDIA_DATA_TYPE_WAV:
			read_len = luat_fs_fread(out_buff->addr + out_buff->used, coder->read_len, 1, coder->fd);
			if (read_len > 0)
			{
				out_buff->used += read_len;
				result = 1;
			}
			else
			{
				result = 0;
			}

			break;
		default:
			break;
		}

    }
	lua_pushboolean(L, result);
	return 1;
}

static int l_codec_gc(lua_State *L)
{
	luat_multimedia_codec_t *coder = ((luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE));
	if (coder->fd) {
		luat_fs_fclose(coder->fd);
		coder->fd = NULL;
	}
	if (coder->buff.addr)
	{
		luat_heap_free(coder->buff.addr);
		memset(&coder->buff, 0, sizeof(luat_zbuff_t));
	}
	switch(coder->type) {
	case MULTIMEDIA_DATA_TYPE_MP3:
		if (coder->is_decoder && coder->mp3_decoder) {
			luat_heap_free(coder->mp3_decoder);
			coder->mp3_decoder = NULL;
		}
		break;
	}
    return 0;
}

/**
释放编解码用的coder
@api codec.release(coder)
@return
codec.release(coder)
 */
static int l_codec_release(lua_State *L) {
    return l_codec_gc(L);
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
	{ "isEnd",		   ROREG_FUNC(l_audio_play_wait_end)},
	{ "config",			ROREG_FUNC(l_audio_config)},
    { "PCM",           ROREG_INT(MULTIMEDIA_DATA_TYPE_PCM)},
	{ "MORE_DATA",     ROREG_INT(MULTIMEDIA_CB_AUDIO_NEED_DATA)},
	{ "DONE",          ROREG_INT(MULTIMEDIA_CB_AUDIO_DONE)},
	{ NULL,            {}}
};

static const rotable_Reg_t reg_codec[] =
{
    { "create" ,         ROREG_FUNC(l_codec_create)},

    { "info" , 		 ROREG_FUNC(l_codec_get_audio_info)},
    { "data",  		 ROREG_FUNC(l_codec_get_audio_data)},
    { "release",         ROREG_FUNC(l_codec_release)},
	{ "MP3",             ROREG_INT(MULTIMEDIA_DATA_TYPE_MP3)},
	{ "WAV",             ROREG_INT(MULTIMEDIA_DATA_TYPE_WAV)},
	{ NULL,              {}}
};

LUAMOD_API int luaopen_multimedia_audio( lua_State *L ) {
    luat_newlib2(L, reg_audio);
    return 1;
}

LUAMOD_API int luaopen_multimedia_codec( lua_State *L ) {
    luat_newlib2(L, reg_codec);
    luaL_newmetatable(L, LUAT_M_CODE_TYPE); /* create metatable for file handles */
    lua_pushcfunction(L, l_codec_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1); /* pop new metatable */
    return 1;
}

