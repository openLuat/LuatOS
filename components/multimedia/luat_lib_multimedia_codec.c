
/*
@module  codec
@summary 多媒体-编解码
@version 1.0
@date    2022.03.11
@demo multimedia
@tag LUAT_USE_MEDIA
*/
#include "luat_base.h"
#include "luat_multimedia.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "codec"
#include "luat_log.h"
#ifdef LUAT_SUPPORT_AMR
#include "interf_enc.h"
#include "interf_dec.h"
#endif
#ifndef MINIMP3_MAX_SAMPLES_PER_FRAME
#define MINIMP3_MAX_SAMPLES_PER_FRAME (2*1152)
#endif
/**
创建编解码用的codec
@api codec.create(type, isDecoder)
@int 多媒体类型，目前支持codec.MP3 codec.AMR
@boolean 是否是解码器，true解码器，false编码器，默认true，是解码器
@return userdata 成功返回一个数据结构,否则返回nil
@usage
-- 创建解码器
local decoder = codec.create(codec.MP3)--创建一个mp3的decoder
-- 创建编码器
local encoder = codec.create(codec.AMR, false)--创建一个amr的encoder
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
            	coder->mp3_decoder = mp3_decoder_create();
            	if (!coder->mp3_decoder) {
            		lua_pushnil(L);
            		return 1;
            	}
            	break;
        	}

    	}
    	else
    	{
        	switch (type) {
#ifdef LUAT_SUPPORT_AMR
        	case MULTIMEDIA_DATA_TYPE_AMR_NB:
            	coder->amr_coder = Encoder_Interface_init(0);
            	if (!coder->amr_coder) {
            		lua_pushnil(L);
            		return 1;
            	}
            	break;
#endif
        	default:
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
@userdata 解码用的decoder
@string 文件路径
@return boolean 是否成功解析
@return int 音频格式
@return int 声音通道数
@return int 采样频率
@return int 采样位数
@return boolean 是否有符号
@usage
local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed= codec.get_audio_info(coder, "xxx")
 */
static int l_codec_get_audio_info(lua_State *L) {
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
	uint32_t jump, i;
	uint8_t temp[16];
	int result = 0;
	int audio_format;
	uint8_t num_channels;
	uint32_t sample_rate;
	int bits_per_sample = 16;
	uint32_t align;
	int is_signed = 1;
    size_t len;
    const char *file_path = luaL_checklstring(L, 2, &len);
    FILE *fd = luat_fs_fopen(file_path, "r");
    if (fd && coder)
    {

		switch(coder->type)
		{
		case MULTIMEDIA_DATA_TYPE_MP3:
			mp3_decoder_init(coder->mp3_decoder);
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
			result = mp3_decoder_get_info(coder->mp3_decoder, coder->buff.addr, coder->buff.used, &sample_rate, &num_channels);
			mp3_decoder_init(coder->mp3_decoder);
			audio_format = MULTIMEDIA_DATA_TYPE_PCM;
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
decoder从文件中解析出原始音频数据，比如从MP3文件里解析出PCM数据，这里的文件路径已经在codec.info传入，不需要再次传入
@api codec.data(decoder, out_buff)
@userdata 解码用的decoder
@zbuff 存放输出数据的zbuff，空间必须不少于16KB
@return boolean 是否成功解析
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
	uint32_t hz, out_len, used;
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
				result = mp3_decoder_get_data(coder->mp3_decoder, coder->buff.addr + pos, coder->buff.used - pos, out_buff->addr + out_buff->used, &out_len, &hz, &used);
				if (result > 0)
				{
					out_buff->used += out_len;
				}

//				if (!result) {
//					LLOGD("jump %dbyte", info.frame_bytes);
//				}
				pos += used;
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


/**
编码音频数据，由于flash和ram空间一般比较有限，目前只支持amr-nb编码
@api codec.encode(coder, in_buffer, out_buffer, mode)
@userdata codec.create创建的编解码用的coder
@zbuff 输入的数据,zbuff形式,从0到used
@zbuff 输出的数据,zbuff形式,自动添加到buff的尾部,如果空间大小不足,会自动扩展,但是会额外消耗时间,甚至会失败,所以尽量一开始就给足空间
@int amr_nb的编码等级 0~7(即 MR475~MR122)值越大消耗的空间越多,音质越高,默认0
@return boolean 成功返回true,失败返回false
@usage
codec.encode(amr_coder, inbuf, outbuf, codec.AMR_)
 */
static int l_codec_encode_audio_data(lua_State *L) {
#ifdef LUAT_SUPPORT_AMR
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
	luat_zbuff_t *in_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE));
	int mode = luaL_optinteger(L, 4, MR475);
	if (!coder || !in_buff || !out_buff || (coder->type != MULTIMEDIA_DATA_TYPE_AMR_NB) || coder->is_decoder)
	{
		lua_pushboolean(L, 0);
		return 1;
	}
	if (mode > MR122)
	{
		mode = MR475;
	}
	uint8_t outbuf[64];
	int16_t *pcm = (int16_t *)in_buff->addr;
	uint32_t total_len = in_buff->used >> 1;
	uint32_t done_len = 0;
	int out_len;
	while ((total_len - done_len) >= 160)
	{
		out_len = Encoder_Interface_Encode(coder->amr_coder, mode, &pcm[done_len], outbuf, 0);
		if (out_len <= 0)
		{
			LLOGE("encode error in %d,result %d", done_len, out_len);
		}
		else
		{
			if ((out_buff->len - out_buff->used) < out_len)
			{
				if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len))
				{
					lua_pushboolean(L, 0);
					return 1;
				}
			}
			memcpy(out_buff->addr + out_buff->used, outbuf, out_len);
			out_buff->used += out_len;
		}
		done_len += 160;
	}
	lua_pushboolean(L, 1);
	return 1;
#else
	lua_pushboolean(L, 0);
	return 1;
#endif
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
#ifdef LUAT_SUPPORT_AMR
	case MULTIMEDIA_DATA_TYPE_AMR_NB:
		if (!coder->is_decoder && coder->amr_coder) {
			Encoder_Interface_exit(coder->amr_coder);
			coder->amr_coder = NULL;
		}
		break;
#endif
	}
    return 0;
}

/**
释放编解码用的coder
@api codec.release(coder)
@coder codec.create创建的编解码用的coder
@usage
codec.release(coder)
 */
static int l_codec_release(lua_State *L) {
    return l_codec_gc(L);
}

static const rotable_Reg_t reg_codec[] =
{
    { "create" ,         ROREG_FUNC(l_codec_create)},

    { "info" , 		 ROREG_FUNC(l_codec_get_audio_info)},
    { "data",  		 ROREG_FUNC(l_codec_get_audio_data)},
	{ "encode",  		 ROREG_FUNC(l_codec_encode_audio_data)},
    { "release",         ROREG_FUNC(l_codec_release)},
    //@const MP3 number MP3格式
	{ "MP3",             ROREG_INT(MULTIMEDIA_DATA_TYPE_MP3)},
    //@const WAV number WAV格式
	{ "WAV",             ROREG_INT(MULTIMEDIA_DATA_TYPE_WAV)},
	//@const AMR number AMR-NB格式，一般意义上的AMR
	{ "AMR",             ROREG_INT(MULTIMEDIA_DATA_TYPE_AMR_NB)},
	//@const AMR_WB number AMR-WB格式
	{ "AMR_WB",             ROREG_INT(MULTIMEDIA_DATA_TYPE_AMR_WB)},
	{ NULL,              {}}
};

LUAMOD_API int luaopen_multimedia_codec( lua_State *L ) {
    luat_newlib2(L, reg_codec);
    luaL_newmetatable(L, LUAT_M_CODE_TYPE); /* create metatable for file handles */
    lua_pushcfunction(L, l_codec_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1); /* pop new metatable */
    return 1;
}

