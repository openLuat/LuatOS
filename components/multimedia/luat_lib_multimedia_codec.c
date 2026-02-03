
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
#include "luat_fs.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "codec"
#include "luat_log.h"

#ifdef LUAT_SUPPORT_AMR
#include "interf_enc.h"
#include "interf_dec.h"
#include "dec_if.h"
static const uint8_t  amr_nb_byte_len[16] = {12, 13, 15, 17, 19, 20, 26, 31, 5, 0, 0, 0, 0, 0, 0, 0};
static const uint8_t  amr_wb_byte_len[16] = {17, 23, 32, 36, 40, 46, 50, 58, 60, 5,0, 0, 0, 0, 0, 0};
typedef void (*amr_decode_fun_t)(void* state, const unsigned char* in, short* out, int bfi);
#endif

#ifdef LUAT_USE_AUDIO_G711
#include "g711_codec/g711_codec.h"
#endif

#ifdef LUAT_USE_AUDIO_DTMF
#include "dtmf_codec/dtmf_codec.h"
#endif

#ifndef G711_PCM_SAMPLES
#define G711_PCM_SAMPLES 160
#endif

#ifndef MINIMP3_MAX_SAMPLES_PER_FRAME
#define MINIMP3_MAX_SAMPLES_PER_FRAME (2*1152)
#endif
/**
创建编解码用的codec
@api codec.create(type, isDecoder, quality)
@int 多媒体类型，目前支持codec.MP3 codec.AMR
@boolean 是否是解码器，true解码器，false编码器，默认true，是解码器
@int 编码等级，部分bsp有内部编解码器，可能需要提前输入编解码等级，不知道的就填7
@return userdata 成功返回一个数据结构,否则返回nil
@usage
-- 目前支持：
-- codec.MP3 解码
-- codec.AMR 编码+解码
-- codec.AMR_WB 编码(部分BSP支持，例如Air780EHM,Air8000)+解码
-- codec.WAV WAV本身就是PCM数据，无需编解码
-- codec.ULAW codec.ALAW 编码+解码
-- 创建解码器
local decoder = codec.create(codec.MP3)--创建一个mp3的decoder
-- 创建编码器
local encoder = codec.create(codec.AMR, false)--创建一个amr的encoder
-- 创建编码器
local encoder = codec.create(codec.AMR_WB, false, 8)--创建一个amr-wb的encoder，编码等级默认8
 */
static int l_codec_create(lua_State *L) {
    uint8_t type = luaL_optinteger(L, 1, LUAT_MULTIMEDIA_DATA_TYPE_MP3);
    uint8_t is_decoder = 1;
    if (lua_isboolean(L, 2)) {
    	is_decoder = lua_toboolean(L, 2);
    }
#ifdef LUAT_SUPPORT_AMR
#ifdef LUAT_USE_INTER_AMR
	uint8_t encode_level = 7;
	switch (type) {
		case LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB:
			encode_level = luaL_optinteger(L, 3, 7);
			break;
		case LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB:
			encode_level = luaL_optinteger(L, 3, 8);
			break;
		default:
			break;
	}
#endif
#endif

    luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)lua_newuserdata(L, sizeof(luat_multimedia_codec_t));
    if (coder == NULL) {
    	lua_pushnil(L);
    } else {
    	memset(coder, 0, sizeof(luat_multimedia_codec_t));
    	coder->type = type;
    	coder->is_decoder = is_decoder;
        if (lua_istable(L, 3)) {
            lua_pushstring(L, "channels");
            if (LUA_TNUMBER == lua_gettable(L, 3)) {
                coder->num_channels = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "sample_rate");
            if (LUA_TNUMBER == lua_gettable(L, 3)) {
                coder->sample_rate = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
        }
        if (coder->sample_rate == 0){
            coder->sample_rate = 16000;
        }
        if (coder->num_channels == 0){
            coder->num_channels = 1;
        }

    	if (is_decoder)
    	{
        	switch (type) {
        	case LUAT_MULTIMEDIA_DATA_TYPE_MP3:
            	coder->mp3_decoder = mp3_decoder_create();
            	if (!coder->mp3_decoder) {
            		lua_pushnil(L);
            		return 1;
            	}
            	break;
#ifdef LUAT_SUPPORT_AMR
        	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB:
        		coder->amr_coder = Decoder_Interface_init();
            	if (!coder->amr_coder) {
            		lua_pushnil(L);
            		return 1;
            	}
         		break;
         	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB:
        		coder->amr_coder = D_IF_init();
            	if (!coder->amr_coder) {
            		lua_pushnil(L);
            		return 1;
            	}
             	break;
#endif
#ifdef LUAT_USE_AUDIO_G711
         	case LUAT_MULTIMEDIA_DATA_TYPE_ULAW:
         	case LUAT_MULTIMEDIA_DATA_TYPE_ALAW:
             	// 使用专门的g711_codec字段存储G711解码器
             	coder->g711_codec = g711_decoder_create(type);
             	if (!coder->g711_codec) {
             		lua_pushnil(L);
             		return 1;
             	}
             	break;
 #endif
#ifdef LUAT_SUPPORT_OPUS
        	// case LUAT_MULTIMEDIA_DATA_TYPE_OGG_OPUS:
            //     coder->opus_coder = luat_ogg_opus_decoder_create(type);
            // 	if (!coder->opus_coder) {
            // 		lua_pushnil(L);
            // 		return 1;
            // 	}
            // 	break;
        	case LUAT_MULTIMEDIA_DATA_TYPE_OPUS:
                int ret  = luat_opus_decoder_create(coder);
            	if (ret) {
            		lua_pushnil(L);
            		return 1;
            	}
            	break;
#endif
        	}
    	}
    	else
    	{
        	switch (type) {
#ifdef LUAT_SUPPORT_AMR
#ifdef LUAT_USE_INTER_AMR
        	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB:
            	coder->amr_coder = luat_audio_inter_amr_coder_init(0, encode_level);
            	if (!coder->amr_coder) {
            		lua_pushnil(L);
            		return 1;
            	}
            	break;
        	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB:
        		coder->amr_coder = luat_audio_inter_amr_coder_init(1, encode_level);
            	if (!coder->amr_coder) {
            		lua_pushnil(L);
            		return 1;
            	}
            	break;
#else
        	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB:
            	coder->amr_coder = Encoder_Interface_init(0);
            	if (!coder->amr_coder) {
            		lua_pushnil(L);
            		return 1;
            	}
            	break;
#endif
#endif
#ifdef LUAT_USE_AUDIO_G711
         	case LUAT_MULTIMEDIA_DATA_TYPE_ULAW:
         	case LUAT_MULTIMEDIA_DATA_TYPE_ALAW:
             	// 使用专门的g711_codec字段存储G711编码器
             	coder->g711_codec = g711_encoder_create(type);
             	if (!coder->g711_codec) {
             		lua_pushnil(L);
             		return 1;
             	}
             	break;
#endif
#ifdef LUAT_SUPPORT_OPUS
        	// case LUAT_MULTIMEDIA_DATA_TYPE_OGG_OPUS:
            // 	int ret = luat_ogg_opus_encoder_create(coder);
            //     if (ret) {
            //         lua_pushnil(L);
            //         return 1;
            //     }
            //     break;
            case LUAT_MULTIMEDIA_DATA_TYPE_OPUS:
                int ret = luat_opus_encoder_create(coder);
                if (ret) {
                    lua_pushnil(L);
                    return 1;
                }
                break;
#endif
        	default:
        		lua_pushnil(L);
        		return 1;
        	}
    	}
    	luaL_setmetatable(L, LUAT_M_CODE_TYPE);
    }
    return 1;
}

int luat_codec_get_audio_info(const char *file_path, luat_multimedia_codec_t *coder){
	uint32_t jump, i;
	uint8_t temp[32];
	int result = 0;
    coder->is_signed = 1;
    coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_NONE;
    coder->num_channels = 0;
    coder->sample_rate = 0;
    coder->bits_per_sample = 16;

	uint32_t align;
    size_t len;
    FILE *fd = luat_fs_fopen(file_path, "r");
    if (fd && coder){
		switch(coder->type){
		case LUAT_MULTIMEDIA_DATA_TYPE_MP3:
			mp3_decoder_init(coder->mp3_decoder);
			coder->buff.addr = luat_heap_malloc(MP3_FRAME_LEN);

			coder->buff.len = MP3_FRAME_LEN;
			coder->buff.used = luat_fs_fread(temp, 10, 1, fd);
			if (coder->buff.used != 10){
				break;
			}
			if (!memcmp(temp, "ID3", 3)){
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
			result = mp3_decoder_get_info(coder->mp3_decoder, coder->buff.addr, coder->buff.used, &coder->sample_rate, &coder->num_channels);
			mp3_decoder_init(coder->mp3_decoder);
			coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
			break;
		case LUAT_MULTIMEDIA_DATA_TYPE_WAV:
			luat_fs_fread(temp, 12, 1, fd);
			if (!memcmp(temp, "RIFF", 4) || !memcmp(temp + 8, "WAVE", 4)){
				luat_fs_fread(temp, 8, 1, fd);
				if (!memcmp(temp, "fmt ", 4)){
					memcpy(&len, temp + 4, 4);
					coder->buff.addr = luat_heap_malloc(len);
					luat_fs_fread(coder->buff.addr, len, 1, fd);
					coder->audio_format = coder->buff.addr[0];
					coder->num_channels = coder->buff.addr[2];
					memcpy(&coder->sample_rate, coder->buff.addr + 4, 4);
					align = coder->buff.addr[12];
					coder->bits_per_sample = coder->buff.addr[14];
					coder->read_len = (align * coder->sample_rate >> 3) & ~(3);
//					LLOGD("size %d", coder->read_len);
					luat_heap_free(coder->buff.addr);
					coder->buff.addr = NULL;
					luat_fs_fread(temp, 8, 1, fd);
					if (!memcmp(temp, "fact", 4)){
						memcpy(&len, temp + 4, 4);
						luat_fs_fseek(fd, len, SEEK_CUR);
						luat_fs_fread(temp, 8, 1, fd);
					}
					if (!memcmp(temp, "data", 4)){
						result = 1;
					}else{
						LLOGD("no data");
						result = 0;
					}
				}else{
					LLOGD("no fmt");
				}
			}else{
				LLOGD("head error");
			}
			break;
#ifdef LUAT_SUPPORT_AMR
		case LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB:
			luat_fs_fread(temp, 6, 1, fd);
			if (!memcmp(temp, "#!AMR\n", 6)){
				coder->buff.addr = luat_heap_malloc(320);
				if (coder->buff.addr){
					coder->num_channels = 1;
					coder->sample_rate = 8000;
					coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
					result = 1;
				}
			}else{
				result = 0;
			}
			break;
		case LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB:
			luat_fs_fread(temp, 9, 1, fd);
			if (!memcmp(temp, "#!AMR-WB\n", 9)){
				coder->buff.addr = luat_heap_malloc(640);
				if (coder->buff.addr){
					coder->num_channels = 1;
					coder->sample_rate = 16000;
					coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
					result = 1;
				}
			}else{
				result = 0;
			}
			break;
#endif
#ifdef LUAT_USE_AUDIO_G711
		case LUAT_MULTIMEDIA_DATA_TYPE_ULAW:
		case LUAT_MULTIMEDIA_DATA_TYPE_ALAW:
			// G711固定参数：8kHz采样率, 单声道, 8位深度
			coder->sample_rate = 8000;
			coder->num_channels = 1;
			coder->bits_per_sample = 8;
			coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
			result = 1;
			break;
#endif
#ifdef LUAT_SUPPORT_OPUS
        case LUAT_MULTIMEDIA_DATA_TYPE_OGG:
            luat_fs_fread(temp, 28, 1, fd);
            if (!memcmp(temp, "OggS", 4)){
                luat_fs_fread(temp, 19, 1, fd);
                coder->num_channels = temp[9];
                coder->sample_rate = *(uint32_t*)&temp[12];
                coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
                result = 1;
			} else {
				result = 0;
			}
            result = 1;
            break;
#endif
		default:
			break;
		}
    }
    if (!result){
    	luat_fs_fclose(fd);
    }else{
    	coder->fd = fd;
    }
	return result;
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
local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed= codec.info(coder, "xxx")
 */
static int l_codec_get_audio_info(lua_State *L) {
    size_t len;
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
    const char *file_path = luaL_checklstring(L, 2, &len);
    int result = luat_codec_get_audio_info(file_path, coder);
	lua_pushboolean(L, result);
	lua_pushinteger(L, coder->audio_format);
	lua_pushinteger(L, coder->num_channels);
	lua_pushinteger(L, coder->sample_rate);
	lua_pushinteger(L, coder->bits_per_sample);
	lua_pushboolean(L, coder->is_signed);
	return 6;
}

/**
decoder从文件中解析出原始音频数据，比如从MP3文件里解析出PCM数据，这里的文件路径已经在codec.info传入，不需要再次传入
@api codec.data(decoder, out_buff, size)
@userdata 解码用的decoder
@zbuff 存放输出数据的zbuff，空间必须不少于16KB
@int   最少解码出多少字节的音频数据,默认16384
@return boolean 是否成功解析
@usage
-- 大内存设备
local buff = zbuff.create(16*1024)
local result = codec.data(coder, buff, 8192)
-- 小内存设备
local buff = zbuff.create(8*1024)
local result = codec.data(coder, buff, 4096)
 */
static int l_codec_get_audio_data(lua_State *L) {
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
#ifdef LUAT_SUPPORT_AMR
	amr_decode_fun_t decode_if;
	uint32_t frame_len;
	uint8_t *size_table;
	uint8_t size;
	uint8_t temp[64];
#endif
	uint32_t pos = 0;
	int read_len;
	int result = 0;
	luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	uint32_t is_not_end = 1;
	uint32_t hz, out_len, used;
	size_t mini_output = luaL_optinteger(L, 3, 16384);
	if (mini_output > 16384)
		mini_output = 16384;
	else if (mini_output < 4 * 1024)
		mini_output = 4 * 1024;
	out_buff->used = 0;
	if (coder)
    {
		switch(coder->type)
		{
		case LUAT_MULTIMEDIA_DATA_TYPE_MP3:
GET_MP3_DATA:
			if (coder->buff.used < MINIMP3_MAX_SAMPLES_PER_FRAME)
			{
				read_len = luat_fs_fread((void*)(coder->buff.addr + coder->buff.used), MINIMP3_MAX_SAMPLES_PER_FRAME, 1, coder->fd);
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
				if (result < 0) {
					return 0;
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
				if ((out_buff->used < mini_output) && is_not_end)
				{
					goto GET_MP3_DATA;
				}
				result = 1;
			}
			break;
		case LUAT_MULTIMEDIA_DATA_TYPE_WAV:
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
#ifdef LUAT_SUPPORT_AMR
        	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB:
         	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB:
         		if (coder->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB)
         		{
         			frame_len = 320;
         			size_table = amr_nb_byte_len;
         			decode_if = Decoder_Interface_Decode;
         		}
         		else
         		{
         			frame_len = 640;
         			size_table = amr_wb_byte_len;
         			decode_if = D_IF_decode;
         		}

         		while ((out_buff->used < mini_output) && is_not_end && ((out_buff->len - out_buff->used) >= frame_len))
				{
         			read_len = luat_fs_fread(temp, 1, 1, coder->fd);
    				if (read_len <= 0)
    				{
    					is_not_end = 0;
    					break;
    				}
    				size = size_table[(temp[0] >> 3) & 0x0f];
    				if (size > 0)
					{
						read_len = luat_fs_fread(temp + 1, 1, size, coder->fd);
						if (read_len <= 0)
						{
	    					is_not_end = 0;
	    					break;
						}
					}
    				decode_if(coder->amr_coder, temp, coder->buff.addr, 0);
    				memcpy(out_buff->addr + out_buff->used, coder->buff.addr, frame_len);
    				out_buff->used += frame_len;
				}
         		result = 1;
             	break;
#endif
#ifdef LUAT_USE_AUDIO_G711
		case LUAT_MULTIMEDIA_DATA_TYPE_ULAW:
		case LUAT_MULTIMEDIA_DATA_TYPE_ALAW:
			// 动态分配缓冲区
			if (!coder->buff.addr) {
				coder->buff.addr = luat_heap_malloc(G711_PCM_SAMPLES);  // G711每帧160字节
				coder->buff.len = G711_PCM_SAMPLES;
				coder->buff.used = 0;
			}

			// 读取G711数据
			if (coder->buff.used < G711_PCM_SAMPLES) {
				read_len = luat_fs_fread((void*)(coder->buff.addr + coder->buff.used),
									G711_PCM_SAMPLES, 1, coder->fd);
				if (read_len > 0) {
					coder->buff.used += read_len;
				} else {
					is_not_end = 0;
				}
			}

			// 解码G711数据为PCM
 			if (coder->buff.used >= G711_PCM_SAMPLES) {
 				result = g711_decoder_get_data(coder->g711_codec, coder->buff.addr,
 											coder->buff.used, (int16_t*)out_buff->addr + out_buff->used,
 											&out_len, &used);
				if (result > 0) {
					out_buff->used += out_len;
				}
				// 移动缓冲区数据
				memmove(coder->buff.addr, coder->buff.addr + used, coder->buff.used - used);
				coder->buff.used -= used;
			}
			break;
#endif
#ifdef LUAT_SUPPORT_OPUS
        case LUAT_MULTIMEDIA_DATA_TYPE_OPUS:
            // 初始化Opus解码器
            if (coder->opus_coder == NULL){
                /* code */
            }
            


            // // 每次读取512字节的Opus数据进行解码
            // while ((out_buff->used < mini_output) && is_not_end && ((out_buff->len - out_buff->used) >= MINIMP3_MAX_SAMPLES_PER_FRAME * 2)) {
            //     read_len = luat_fs_fread(temp, 512, 1, coder->fd);
            //     if (read_len <= 0) {
            //         is_not_end = 0;
            //         break;
            //     }
            //     int decoded_samples = opus_decoder_get_data(coder->opus_decoder, temp, read_len,
            //                                                (int16_t*)out_buff->addr + (out_buff->used / 2),
            //                                                &out_len);
            //     if (decoded_samples > 0) {
            //         out_buff->used += out_len;
            //     }
            // }
            // result = 1;
            break;
#endif
		default:
			break;
		}

    }
	lua_pushboolean(L, result);
	return 1;
}


/**
编码音频数据，由于flash和ram空间一般比较有限，除了部分bsp有内部amr编码功能以外只支持amr-nb编码
@api codec.encode(coder, in_buffer, out_buffer, mode)
@userdata codec.create创建的编解码用的coder
@zbuff 输入的数据,zbuff形式,从0到used
@zbuff 输出的数据,zbuff形式,自动添加到buff的尾部,如果空间大小不足,会自动扩展,但是会额外消耗时间,甚至会失败,所以尽量一开始就给足空间
@int amr_nb的编码等级 0~7(即 MR475~MR122)值越大消耗的空间越多,音质越高,默认0 amr_wb的编码等级 0~8,值越大消耗的空间越多,音质越高,默认0
@return boolean 成功返回true,失败返回false
@usage
codec.encode(amr_coder, inbuf, outbuf, codec.AMR_)
 */
static int l_codec_encode_audio_data(lua_State *L) {
#ifdef LUAT_SUPPORT_AMR
#ifdef LUAT_USE_INTER_AMR
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
	luat_zbuff_t *in_buff;
	if (luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)){
		in_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	}else{
		in_buff = ((luat_zbuff_t *)lua_touserdata(L, 2));
	}
	luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE));
	if (!coder || !in_buff || !out_buff || (coder->type != LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB && coder->type != LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB && coder->type != LUAT_MULTIMEDIA_DATA_TYPE_ULAW && coder->type != LUAT_MULTIMEDIA_DATA_TYPE_ALAW) || coder->is_decoder)
	{
		lua_pushboolean(L, 0);
		return 1;
	}
#ifdef LUAT_USE_AUDIO_G711
	if (coder->type == LUAT_MULTIMEDIA_DATA_TYPE_ULAW || coder->type == LUAT_MULTIMEDIA_DATA_TYPE_ALAW) {
		// G711编码处理 - 使用栈上分配的临时缓冲区，避免长期占用堆内存
		uint8_t outbuf[G711_PCM_SAMPLES];  // 栈上分配，用完即释放
		int16_t *pcm = (int16_t *)in_buff->addr;
		uint32_t total_len = in_buff->used >> 1;  // 16位PCM转字节数
		uint32_t done_len = 0;
		uint32_t frame_size = G711_PCM_SAMPLES;  // G711每帧160个PCM样本
		uint32_t out_len;

		// 处理完整的160样本帧
		while ((total_len - done_len) >= frame_size) {
			// 编码一帧PCM数据为G711
			int result = g711_encoder_get_data(coder->g711_codec, &pcm[done_len], frame_size,
											 outbuf, &out_len);

			if (result > 0 && out_len > 0) {
				// 检查输出缓冲区空间
				if ((out_buff->len - out_buff->used) < out_len) {
					if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len)) {
						lua_pushboolean(L, 0);
						return 1;
					}
				}
				// 复制编码后的数据到输出缓冲区
				memcpy(out_buff->addr + out_buff->used, outbuf, out_len);
				out_buff->used += out_len;
			} else {

			}
			done_len += frame_size;
		}

		// 处理剩余的PCM样本（不足160个样本的部分）
		uint32_t remaining_len = total_len - done_len;
		if (remaining_len > 0) {

			// 用零填充到160个样本
			int16_t padded_frame[G711_PCM_SAMPLES] = {0};
			memcpy(padded_frame, &pcm[done_len], remaining_len * sizeof(int16_t));

			int result = g711_encoder_get_data(coder->g711_codec, padded_frame, frame_size,
											 outbuf, &out_len);

			if (result > 0 && out_len > 0) {
				// 检查输出缓冲区空间
				if ((out_buff->len - out_buff->used) < out_len) {
					if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len)) {
						lua_pushboolean(L, 0);
						return 1;
					}
				}
				// 复制编码后的数据到输出缓冲区
				memcpy(out_buff->addr + out_buff->used, outbuf, out_len);
				out_buff->used += out_len;
			}
		}

		lua_pushboolean(L, 1);
		return 1;
	}
#endif

	// AMR编码处理
	uint8_t outbuf[128];
	int16_t *pcm = (int16_t *)in_buff->addr;
	uint32_t total_len = in_buff->used >> 1;
	uint32_t done_len = 0;
	uint32_t pcm_len = (coder->type - LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB + 1) * 160;
	uint8_t out_len;

	while ((total_len - done_len) >= pcm_len)
	{
		luat_audio_inter_amr_coder_encode(coder->amr_coder, &pcm[done_len], outbuf, &out_len);
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
		done_len += pcm_len;
	}
	lua_pushboolean(L, 1);
	return 1;
#else
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
	luat_zbuff_t *in_buff;
	if (luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)){
		in_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	}else{
		in_buff = ((luat_zbuff_t *)lua_touserdata(L, 2));
	}
	luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE));
	int mode = luaL_optinteger(L, 4, MR475);
	if (!coder || !in_buff || !out_buff || (coder->type != LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) || coder->is_decoder)
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
#endif
#elif defined(LUAT_SUPPORT_OPUS)
	luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
	luat_zbuff_t *in_buff;
	if (luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)){
		in_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	}else{
		in_buff = ((luat_zbuff_t *)lua_touserdata(L, 2));
	}
	luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE));
	// int mode = luaL_optinteger(L, 4, MR475);
	// if (!coder || !in_buff || !out_buff || (coder->type != LUAT_MULTIMEDIA_DATA_TYPE_OPUS) || coder->is_decoder){
	// 	lua_pushboolean(L, 0);
	// 	return 1;
	// }
    
#else
	lua_pushboolean(L, 0);
	return 1;
#endif
}

#ifdef LUAT_USE_AUDIO_DTMF
static uint32_t l_codec_dtmf_ratio_to_q10(lua_State *L, int index, uint32_t def_q10) {
	if (lua_isnumber(L, index)) {
		double v = lua_tonumber(L, index);
		if (v < 0) v = 0;
		return (uint32_t)(v * 1024.0 + 0.5);
	}
	return def_q10;
}

static void l_codec_dtmf_decode_opts(lua_State *L, int index, dtmf_decode_opts_t* opts) {
	int step_set = 0;
	// 解析解码参数表
	dtmf_decode_opts_default(opts);
	if (!lua_istable(L, index)) {
		return;
	}
	lua_getfield(L, index, "frameMs");
	if (lua_isnumber(L, -1)) {
		opts->frame_ms = (uint32_t)lua_tointeger(L, -1);
	}
	lua_pop(L, 1);
	lua_getfield(L, index, "stepMs");
	if (lua_isnumber(L, -1)) {
		opts->step_ms = (uint32_t)lua_tointeger(L, -1);
		step_set = 1;
	}
	lua_pop(L, 1);
	lua_getfield(L, index, "detectRatio");
	if (lua_isnumber(L, -1)) {
		opts->detect_ratio_q10 = l_codec_dtmf_ratio_to_q10(L, -1, opts->detect_ratio_q10);
	}
	lua_pop(L, 1);
	lua_getfield(L, index, "powerRatio");
	if (lua_isnumber(L, -1)) {
		opts->power_ratio_q10 = l_codec_dtmf_ratio_to_q10(L, -1, opts->power_ratio_q10);
	}
	lua_pop(L, 1);
	lua_getfield(L, index, "twistDb");
	if (lua_isnumber(L, -1)) {
		int32_t db = (int32_t)lua_tointeger(L, -1);
		if (db < 0) db = 0;
		if (db > 12) db = 12;
		opts->twist_db = (uint32_t)db;
	}
	lua_pop(L, 1);
	lua_getfield(L, index, "minConsecutive");
	if (lua_isnumber(L, -1)) {
		opts->min_consecutive = (uint32_t)lua_tointeger(L, -1);
	}
	lua_pop(L, 1);
	if (!step_set) {
		opts->step_ms = opts->frame_ms;
	}
}

static void l_codec_dtmf_encode_opts(lua_State *L, int index, dtmf_encode_opts_t* opts) {
	// 解析编码参数表
	dtmf_encode_opts_default(opts);
	if (!lua_istable(L, index)) {
		return;
	}
	lua_getfield(L, index, "toneMs");
	if (lua_isnumber(L, -1)) {
		opts->tone_ms = (uint32_t)lua_tointeger(L, -1);
	}
	lua_pop(L, 1);
	lua_getfield(L, index, "pauseMs");
	if (lua_isnumber(L, -1)) {
		opts->pause_ms = (uint32_t)lua_tointeger(L, -1);
	}
	lua_pop(L, 1);
	lua_getfield(L, index, "amplitude");
	if (lua_isnumber(L, -1)) {
		double v = lua_tonumber(L, -1);
		if (v <= 1.0) {
			int32_t q15 = (int32_t)(v * 32767.0 + 0.5);
			if (q15 < 0) q15 = 0;
			if (q15 > 32767) q15 = 32767;
			opts->amplitude_q15 = (uint16_t)q15;
		} else {
			int32_t q15 = (int32_t)(v + 0.5);
			if (q15 < 0) q15 = 0;
			if (q15 > 32767) q15 = 32767;
			opts->amplitude_q15 = (uint16_t)q15;
		}
	}
	lua_pop(L, 1);
}

static int l_codec_dtmf_get_samples(lua_State *L, int index, int16_t** out_samples, uint32_t* out_count) {
	// 统一解析输入PCM: zbuff/string/table
	if (luaL_testudata(L, index, LUAT_ZBUFF_TYPE)) {
		luat_zbuff_t *buff = (luat_zbuff_t *)luaL_checkudata(L, index, LUAT_ZBUFF_TYPE);
		uint32_t len = buff->used;
		uint32_t sample_count = len >> 1;
		int16_t *samples = (int16_t *)luat_heap_malloc(sample_count * sizeof(int16_t));
		if (!samples && sample_count > 0) {
			return 0;
		}
		for (uint32_t i = 0; i < sample_count; ++i) {
			uint8_t b0 = buff->addr[i * 2];
			uint8_t b1 = buff->addr[i * 2 + 1];
			samples[i] = (int16_t)((uint16_t)b0 | ((uint16_t)b1 << 8));
		}
		*out_samples = samples;
		*out_count = sample_count;
		return 1;
	}
	if (lua_isstring(L, index)) {
		size_t len = 0;
		const uint8_t *data = (const uint8_t *)luaL_checklstring(L, index, &len);
		uint32_t sample_count = (uint32_t)(len >> 1);
		int16_t *samples = (int16_t *)luat_heap_malloc(sample_count * sizeof(int16_t));
		if (!samples && sample_count > 0) {
			return 0;
		}
		for (uint32_t i = 0; i < sample_count; ++i) {
			uint8_t b0 = data[i * 2];
			uint8_t b1 = data[i * 2 + 1];
			samples[i] = (int16_t)((uint16_t)b0 | ((uint16_t)b1 << 8));
		}
		*out_samples = samples;
		*out_count = sample_count;
		return 1;
	}
	if (lua_istable(L, index)) {
		uint32_t sample_count = (uint32_t)lua_rawlen(L, index);
		int16_t *samples = (int16_t *)luat_heap_malloc(sample_count * sizeof(int16_t));
		if (!samples && sample_count > 0) {
			return 0;
		}
		for (uint32_t i = 0; i < sample_count; ++i) {
			lua_geti(L, index, i + 1);
			int32_t v = (int32_t)luaL_optinteger(L, -1, 0);
			if (v > 32767) v = 32767;
			if (v < -32768) v = -32768;
			samples[i] = (int16_t)v;
			lua_pop(L, 1);
		}
		*out_samples = samples;
		*out_count = sample_count;
		return 1;
	}
	return 0;
}

/**
DTMF 解码
@api codec.dtmf_decode(pcm, sample_rate, opts)
@string/zbuff/table PCM16LE 数据或样本表
@int 采样率(Hz),默认8000
@table 可选配置
@return string 解码到的DTMF序列
@return table 事件列表
@usage
local seq, events = codec.dtmf_decode(pcm, 8000, {frameMs = 40, stepMs = 40})
*/
static int l_codec_dtmf_decode(lua_State *L) {
	uint32_t sample_rate = (uint32_t)luaL_optinteger(L, 2, 8000);
	dtmf_decode_opts_t opts;
	l_codec_dtmf_decode_opts(L, 3, &opts);

	int16_t *samples = NULL;
	uint32_t sample_count = 0;
	if (!l_codec_dtmf_get_samples(L, 1, &samples, &sample_count)) {
		lua_pushliteral(L, "");
		lua_newtable(L);
		return 2;
	}
	if (!samples || sample_count == 0 || sample_rate == 0) {
		if (samples) {
			luat_heap_free(samples);
		}
		lua_pushliteral(L, "");
		lua_newtable(L);
		return 2;
	}

	uint32_t frame_len = (uint32_t)((float)sample_rate * opts.frame_ms / 1000.0f);
	uint32_t step_len = (uint32_t)((float)sample_rate * opts.step_ms / 1000.0f);
	if (frame_len < 1) frame_len = 1;
	if (step_len < 1) step_len = 1;
	uint32_t max_events = (sample_count / step_len) + 2;
	if (max_events < 4) max_events = 4;
	// 预估事件数量后分配结果缓冲

	char *seq = (char *)luat_heap_malloc(max_events + 1);
	dtmf_event_t *events = (dtmf_event_t *)luat_heap_malloc(max_events * sizeof(dtmf_event_t));
	uint32_t event_count = 0;
	int seq_len = 0;
	if (seq && events) {
		seq_len = dtmf_decode_pcm16(samples, sample_count, sample_rate, &opts,
							seq, max_events + 1, events, &event_count, max_events);
	} else {
		if (seq) {
			seq[0] = 0;
		}
		if (events) {
			event_count = 0;
		}
	}

	if (seq) {
		lua_pushlstring(L, seq, seq_len);
	} else {
		lua_pushliteral(L, "");
	}
	lua_newtable(L);
	if (events) {
		for (uint32_t i = 0; i < event_count; ++i) {
			lua_newtable(L);
			lua_pushlstring(L, &events[i].symbol, 1);
			lua_setfield(L, -2, "symbol");
			lua_pushinteger(L, events[i].start_sample);
			lua_setfield(L, -2, "startSample");
			lua_pushinteger(L, events[i].end_sample);
			lua_setfield(L, -2, "endSample");
			lua_pushinteger(L, events[i].frames);
			lua_setfield(L, -2, "frames");
			lua_seti(L, -2, i + 1);
		}
	}

	if (samples) luat_heap_free(samples);
	if (seq) luat_heap_free(seq);
	if (events) luat_heap_free(events);
	return 2;
}

/**
DTMF 编码
@api codec.dtmf_encode(seq, sample_rate, opts)
@string DTMF字符串,支持 0-9 A-D * #
@int 采样率(Hz),默认8000
@table 可选配置
@return zbuff PCM16LE数据
@usage
local pcm = codec.dtmf_encode("123#", 8000, {toneMs = 100, pauseMs = 50, amplitude = 0.7})
*/
static int l_codec_dtmf_encode(lua_State *L) {
	size_t len = 0;
	const char *digits = luaL_checklstring(L, 1, &len);
	uint32_t sample_rate = (uint32_t)luaL_optinteger(L, 2, 8000);
	dtmf_encode_opts_t opts;
	l_codec_dtmf_encode_opts(L, 3, &opts);

	uint32_t sample_count = dtmf_encode_calc_samples(digits, sample_rate, &opts);
	uint32_t byte_len = sample_count * 2;

	luat_zbuff_t *buff = (luat_zbuff_t *)lua_newuserdata(L, sizeof(luat_zbuff_t));
	// 输出为PCM16LE zbuff
	if (buff == NULL) {
		lua_pushnil(L);
		return 1;
	}
	memset(buff, 0, sizeof(luat_zbuff_t));
	buff->type = LUAT_HEAP_SRAM;
	if (byte_len > 0) {
		buff->addr = (uint8_t *)luat_heap_opt_malloc(buff->type, byte_len);
		if (!buff->addr) {
			lua_pushnil(L);
			return 1;
		}
		buff->len = byte_len;
		buff->used = byte_len;
		uint32_t out_count = 0;
		dtmf_encode_pcm16(digits, sample_rate, &opts, (int16_t *)buff->addr, sample_count, &out_count);
		buff->used = out_count * 2;
	} else {
		buff->addr = NULL;
		buff->len = 0;
		buff->used = 0;
	}
	luaL_setmetatable(L, LUAT_ZBUFF_TYPE);
	return 1;
}
#endif


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
		coder->buff.addr = NULL;
		memset(&coder->buff, 0, sizeof(luat_zbuff_t));
	}
	switch(coder->type) {
	case LUAT_MULTIMEDIA_DATA_TYPE_MP3:
		if (coder->is_decoder && coder->mp3_decoder) {
			luat_heap_free(coder->mp3_decoder);
			coder->mp3_decoder = NULL;
		}
		break;
#ifdef LUAT_SUPPORT_AMR
	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB:
		if (coder->amr_coder)
		{
			if (!coder->is_decoder)
			{
#ifdef LUAT_USE_INTER_AMR
				luat_audio_inter_amr_coder_deinit(coder->amr_coder);
#else
				Encoder_Interface_exit(coder->amr_coder);
#endif
			}
			else
			{
				Decoder_Interface_exit(coder->amr_coder);
			}
			coder->amr_coder = NULL;
		}
		break;
	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB:
		if (coder->amr_coder)
		{
			if (!coder->is_decoder)
			{
#ifdef LUAT_USE_INTER_AMR
				luat_audio_inter_amr_coder_deinit(coder->amr_coder);
#else
#endif
			}
			else
			{
				D_IF_exit(coder->amr_coder);
			}
			coder->amr_coder = NULL;
		}
		break;
#endif
#ifdef LUAT_USE_AUDIO_G711
 	case LUAT_MULTIMEDIA_DATA_TYPE_ULAW:
 	case LUAT_MULTIMEDIA_DATA_TYPE_ALAW:
 		if (coder->g711_codec) {
 			if (coder->is_decoder) {
 				// 清理G711解码器
 				g711_decoder_destroy(coder->g711_codec);
 			} else {
 				// 清理G711编码器
 				g711_encoder_destroy(coder->g711_codec);
 			}
 			coder->g711_codec = NULL;
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

    { "info" , 		 	 ROREG_FUNC(l_codec_get_audio_info)},
    { "data",  		 	 ROREG_FUNC(l_codec_get_audio_data)},
	{ "encode",  		 ROREG_FUNC(l_codec_encode_audio_data)},
#ifdef LUAT_USE_AUDIO_DTMF
	{ "dtmf_decode",    ROREG_FUNC(l_codec_dtmf_decode)},
	{ "dtmf_encode",    ROREG_FUNC(l_codec_dtmf_encode)},
#endif
    { "release",         ROREG_FUNC(l_codec_release)},
    //@const MP3 number MP3格式
	{ "MP3",             ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_MP3)},
    //@const WAV number WAV格式
	{ "WAV",             ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_WAV)},
	//@const AMR number AMR-NB格式，一般意义上的AMR
	{ "AMR",             ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB)},
	//@const AMR_WB number AMR-WB格式
	{ "AMR_WB",          ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB)},
	//@const ULAW number G711 μ-law格式
	{ "ULAW",            ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_ULAW)},
	//@const ALAW number G711 A-law格式
	{ "ALAW",            ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_ALAW)},
    //@const OPUS number OPUS格式
	{ "OPUS",            ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_OPUS)},
    //@const OGG_OPUS number OGG封装OPUS格式
	{ "OGG_OPUS",        ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_OGG_OPUS)},
	//@const VDDA_3V3 number codec 电压: 3.3V
	{ "VDDA_3V3",        ROREG_INT(LUAT_CODEC_VDDA_3V3)},
	//@const VDDA_1V8 number codec 电压: 1.8V
	{ "VDDA_1V8",        ROREG_INT(LUAT_CODEC_VDDA_1V8)},
	{ NULL,              ROREG_INT(0)}
};

LUAMOD_API int luaopen_multimedia_codec( lua_State *L ) {
    luat_newlib2(L, reg_codec);
    luaL_newmetatable(L, LUAT_M_CODE_TYPE); /* create metatable for file handles */
    lua_pushcfunction(L, l_codec_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1); /* pop new metatable */
    return 1;
}

