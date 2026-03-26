
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

extern const luat_codec_opts_t mp3_codec_opts;
extern const luat_codec_opts_t wav_codec_opts;
#ifdef LUAT_USE_AUDIO_G711
extern const luat_codec_opts_t g711_codec_opts;
#endif
#ifdef LUAT_SUPPORT_AMR
extern const luat_codec_opts_t amr_codec_opts;
#endif
#ifdef LUAT_SUPPORT_OPUS
extern const luat_codec_opts_t opus_codec_opts;
#endif

static const luat_codec_opts_t* const codec_opts_table[] = {
    [LUAT_MULTIMEDIA_DATA_TYPE_MP3]       = &mp3_codec_opts,
    [LUAT_MULTIMEDIA_DATA_TYPE_WAV]       = &wav_codec_opts,
#ifdef LUAT_SUPPORT_AMR
    [LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB]    = &amr_codec_opts,
    [LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB]    = &amr_codec_opts,
#endif
#ifdef LUAT_USE_AUDIO_G711
    [LUAT_MULTIMEDIA_DATA_TYPE_ULAW]      = &g711_codec_opts,
    [LUAT_MULTIMEDIA_DATA_TYPE_ALAW]      = &g711_codec_opts,
#endif
#ifdef LUAT_SUPPORT_OPUS
    [LUAT_MULTIMEDIA_DATA_TYPE_OPUS]      = &opus_codec_opts,
#endif
    [LUAT_MULTIMEDIA_DATA_TYPE_OGG]       = NULL,
    [LUAT_MULTIMEDIA_DATA_TYPE_OGG_OPUS]  = NULL,
};

#define CODEC_OPTS_TABLE_SIZE (sizeof(codec_opts_table) / sizeof(codec_opts_table[0]))

#ifdef LUAT_SUPPORT_AMR
#include "interf_enc.h"
#include "interf_dec.h"
#include "dec_if.h"
static const uint8_t  amr_nb_byte_len[16] = {12, 13, 15, 17, 19, 20, 26, 31, 5, 0, 0, 0, 0, 0, 0, 0};
static const uint8_t  amr_wb_byte_len[16] = {17, 23, 32, 36, 40, 46, 50, 58, 60, 5, 0, 0, 0, 0, 0, 0};
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

#define OPUS_MAX_PACKET_SIZE (3*1276)

#ifndef MINIMP3_MAX_SAMPLES_PER_FRAME
#define MINIMP3_MAX_SAMPLES_PER_FRAME (2*1152)
#endif

const luat_codec_opts_t* luat_codec_get_ops(uint8_t type) {
    if (type < CODEC_OPTS_TABLE_SIZE) {
        return codec_opts_table[type];
    }
    return NULL;
}

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
    int encode_level = 7;  // 编码等级，AMR-NB默认7，AMR-WB默认8

    if (lua_isboolean(L, 2)) {
        is_decoder = lua_toboolean(L, 2);
    }

#ifdef LUAT_SUPPORT_AMR
#ifdef LUAT_USE_INTER_AMR
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
        return 1;
    }

    memset(coder, 0, sizeof(luat_multimedia_codec_t));
    coder->type = type;
    coder->is_decoder = is_decoder;
    coder->encode_level = encode_level;

    if (lua_istable(L, 3)) {
        lua_pushstring(L, "num_channels");
        if (LUA_TNUMBER == lua_gettable(L, 3)) {
            coder->num_channels = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushstring(L, "sample_rate");
        if (LUA_TNUMBER == lua_gettable(L, 3)) {
            coder->sample_rate = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushstring(L, "bits_per_sample");
        if (LUA_TNUMBER == lua_gettable(L, 3)) {
            coder->bits_per_sample = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
    }

    if (coder->sample_rate == 0) coder->sample_rate = 16000;
    if (coder->num_channels == 0) coder->num_channels = 1;
    if (coder->bits_per_sample == 0) coder->bits_per_sample = 16;

    const luat_codec_opts_t* opts = luat_codec_get_ops(type);
    if (opts && opts->create) {
        coder->ops = opts;
        coder->ctx = opts->create(coder);
        if (!coder->ctx) {
            LLOGE("codec create failed for type %d", type);
            lua_pushnil(L);
            return 1;
        }
    } else {
        LLOGE("no codec available for type %d", type);
        lua_pushnil(L);
        return 1;
    }

    luaL_setmetatable(L, LUAT_M_CODE_TYPE);
    return 1;
}

int luat_codec_get_audio_info(const char *file_path, luat_multimedia_codec_t *coder){
    int result = 0;
    coder->is_signed = 1;
    coder->bits_per_sample = 16;

    FILE *fd = luat_fs_fopen(file_path, "r");
    if (!fd || !coder) {
        return 0;
    }

    if (coder->ops && coder->ops->get_info) {
        result = coder->ops->get_info(coder, fd);
    }

    if (!result){
        luat_fs_fclose(fd);
    } else {
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
    luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
    size_t mini_output = luaL_optinteger(L, 3, 16384);

    if (mini_output > 16384)
        mini_output = 16384;
    else if (mini_output < 4 * 1024)
        mini_output = 4 * 1024;

    out_buff->used = 0;
    int result = 0;

    if (coder && coder->fd && coder->ops && coder->ops->decode_file_data) {
        result = coder->ops->decode_file_data(coder, out_buff, mini_output);
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
    luat_multimedia_codec_t *coder = (luat_multimedia_codec_t *)luaL_checkudata(L, 1, LUAT_M_CODE_TYPE);
	luat_zbuff_t *in_buff;
	if (luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)){
		in_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	}else{
		in_buff = ((luat_zbuff_t *)lua_touserdata(L, 2));
	}
	luat_zbuff_t *out_buff = ((luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE));
	int mode = luaL_optinteger(L, 4, 0);

	if (!coder || !in_buff || !out_buff || coder->is_decoder) {
		lua_pushboolean(L, 0);
		return 1;
	}

    if (!coder->ops || !coder->ops->encode) {
        LLOGE("no encode callback for type %d", coder->type);
        lua_pushboolean(L, 0);
        return 1;
    }

    int result = coder->ops->encode(coder, in_buff, out_buff, mode);
    lua_pushboolean(L, result > 0 ? 1 : 0);
    return 1;
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

    if (coder->buff.addr) {
        luat_heap_free(coder->buff.addr);
        coder->buff.addr = NULL;
        memset(&coder->buff, 0, sizeof(luat_zbuff_t));
    }

    if (coder->ops && coder->ops->destroy && coder->ctx) {
        coder->ops->destroy(coder);
        coder->ops = NULL;
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

