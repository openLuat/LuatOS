#include "luat_base.h"
#include "luat_common_api.h"
#include "luat_audio_core.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "luat_amr"
#include "luat_log.h"

#include "dec_if.h"
#include <stdlib.h>
#include <string.h>
#include <pvamrwbdecoder_api.h>
#include <pvamrwbdecoder.h>
#include <pvamrwbdecoder_cnst.h>
#include <dtx.h>
#if 1
#include <voAMRWB.h>
#include <cmnMemory.h>
#endif

static const uint8_t amr_wb_byte_len[16] = {17, 23, 32, 36, 40, 46, 50, 58, 60, 5, 0, 0, 0, 0, 0, 0};


struct state {
	void *st; /*   State structure  */
	unsigned char *pt_st;
	int16 *ScratchMem;

	uint8* iInputBuf;
	int16* iInputSampleBuf;
	int16* iOutputBuf;

	uint8 quality;
	int16 mode;
	int16 mode_old;
	int16 frame_type;

	int16 reset_flag;
	int16 reset_flag_old;
	int16 status;
	RX_State rx_state;
};
#if 1
struct encoder_state {
	VO_AUDIO_CODECAPI audioApi;
	VO_HANDLE handle;
	VO_MEM_OPERATOR memOperator;
	VO_CODEC_INIT_USERDATA userData;
};
#endif


static void* _E_IF_init(void) {
	struct encoder_state* state = (struct encoder_state*) luat_heap_malloc(sizeof(struct encoder_state));
	if (!state) {
		return NULL;
	}
    int frameType = VOAMRWB_RFC3267;
	voGetAMRWBEncAPI(&state->audioApi);
	state->memOperator.Alloc = cmnMemAlloc;
	state->memOperator.Copy = cmnMemCopy;
	state->memOperator.Free = cmnMemFree;
	state->memOperator.Set = cmnMemSet;
	state->memOperator.Check = cmnMemCheck;
	state->userData.memflag = VO_IMF_USERMEMOPERATOR;
	state->userData.memData = (VO_PTR)&state->memOperator;
	state->audioApi.Init(&state->handle, VO_AUDIO_CodingAMRWB, &state->userData);
	state->audioApi.SetParam(state->handle, VO_PID_AMRWB_FRAMETYPE, &frameType);
	return state;
}

static void _E_IF_exit(void* s) {
	struct encoder_state* state = (struct encoder_state*) s;
	state->audioApi.Uninit(state->handle);
	luat_heap_free(state);
}

static int _E_IF_encode(void* s, int mode, const short* speech, unsigned char* out, int dtx) {
	VO_CODECBUFFER inData, outData;
	VO_AUDIO_OUTPUTINFO outFormat;
	struct encoder_state* state = (struct encoder_state*) s;

	state->audioApi.SetParam(state->handle, VO_PID_AMRWB_MODE, &mode);
	state->audioApi.SetParam(state->handle, VO_PID_AMRWB_DTX, &dtx);
	inData.Buffer = (unsigned char*) speech;
	inData.Length = 640;
	outData.Buffer = out;
	state->audioApi.SetInputData(state->handle, &inData);
	state->audioApi.GetOutputData(state->handle, &outData, &outFormat);
	return outData.Length;
}

int luat_audio_amr_wb_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info)
{
    if (input_buffer->pos < 9) {
        *jump_offset_bytes = 0;
        *need_bytes = 9;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }

    if (!memcmp(input_buffer->data, "#!AMR-WB\n", 9)) {
        info->channel_nums = 1;
        info->data_align = 2;
        info->is_signed = 1;
        *jump_offset_bytes = 9;
        *need_bytes = 0;
        info->sample_rate = 16000;
    } else {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    return LUAT_ERROR_NONE;
}

void luat_audio_codec_amr_wb_set_record_info(struct luat_audio_data_codec *codec, luat_audio_common_param_t *info)
{
    if (info->sample_rate != 16000) {
        info->sample_rate = 16000;
    }
    if (info->channel_nums != 1) {
        info->channel_nums = 1;
    }
    if (info->data_align != 2) {
        info->data_align = 2;
    }
    if (info->is_signed != 1) {
        info->is_signed = 1;
    }
    codec->common_param.sample_rate = info->sample_rate;
    codec->common_param.channel_nums = info->channel_nums;
    codec->common_param.data_align = info->data_align;
    codec->common_param.is_signed = info->is_signed;
    codec->common_param.one_frame_sample_cnt = 320;
    codec->common_param.one_frame_bytes = 640;
}

void luat_audio_codec_amr_wb_pre_decode(luat_audio_data_codec_t* codec, const uint8_t *input, uint32_t input_size, uint32_t *frame_size_bytes)
{
    *frame_size_bytes = amr_wb_byte_len[(input[0] >> 3) & 0x0f] + 1;
}

int luat_audio_codec_amr_wb_make_head(luat_audio_data_codec_t* codec, uint32_t total_len, luat_buffer_t *out_buffer)
{
    luat_buffer_write(out_buffer, "#!AMR-WB\n", 9);
    return LUAT_ERROR_NONE;
}


static int _amr_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    if (is_encode) {
        if (codec->encode_ctx) {
            return LUAT_ERROR_NONE;
        }
        codec->encode_ctx = _E_IF_init();
        if (!codec->encode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
        codec->param.amr_encode_speed = 8;
        codec->param.dtx_enable = 1;
        return LUAT_ERROR_NONE;
    } else {
        if (codec->decode_ctx) {
            return LUAT_ERROR_NONE;
        }
        struct state* state = (struct state*) luat_heap_malloc(sizeof(struct state));
        if (!state) {
            return -LUAT_ERROR_NO_MEMORY;
        }
        memset(state, 0, sizeof(*state));
        
        state->iInputSampleBuf = (int16*) luat_heap_malloc(sizeof(int16)*KAMRWB_NB_BITS_MAX);
        if (!state->iInputSampleBuf) {
            luat_heap_free(state);
            return -LUAT_ERROR_NO_MEMORY;
        }

        state->reset_flag = 0;
        state->reset_flag_old = 1;
        state->mode_old = 0;
        state->rx_state.prev_ft = RX_SPEECH_GOOD;
        state->rx_state.prev_mode = 0;
        state->pt_st = (unsigned char*) luat_heap_malloc(pvDecoder_AmrWbMemRequirements());
        if (!state->pt_st) {
            luat_heap_free(state);
            luat_heap_free(state->iInputSampleBuf);
            return -LUAT_ERROR_NO_MEMORY;
        }
        pvDecoder_AmrWb_Init(&state->st, state->pt_st, &state->ScratchMem);
        codec->decode_ctx = state;
        if (!codec->decode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
    }
    return LUAT_ERROR_NONE;
}

static void _amr_codec_deinit(luat_audio_data_codec_t* codec) {
    if (codec->encode_ctx) {
        _E_IF_exit(codec->encode_ctx);
        codec->encode_ctx = NULL;
    } 
    if (codec->decode_ctx) {
        struct state* state = (struct state*)codec->decode_ctx;
        luat_heap_free(state->pt_st);
        luat_heap_free(state->iInputSampleBuf);
        luat_heap_free(state);
        codec->decode_ctx = NULL;
    }
}

static void _D_IF_decode(void* s, const unsigned char* in, short* out, int bfi) {
	struct state* state = (struct state*) s;

	state->mode = (in[0] >> 3) & 0x0f;
	in++;

	state->quality = 1; /* ? */
	mime_unsorting((uint8*) in, state->iInputSampleBuf, &state->frame_type, &state->mode, state->quality, &state->rx_state);
	
	if ((state->frame_type == RX_NO_DATA) | (state->frame_type == RX_SPEECH_LOST)) {
		state->mode = state->mode_old;
		state->reset_flag = 0;
	} else {
		state->mode_old = state->mode;

		/* if homed: check if this frame is another homing frame */
		if (state->reset_flag_old == 1) {
			/* only check until end of first subframe */
			state->reset_flag = pvDecoder_AmrWb_homing_frame_test_first(state->iInputSampleBuf, state->mode);
		}
	}

	/* produce encoder homing frame if homed & input=decoder homing frame */
	if ((state->reset_flag != 0) && (state->reset_flag_old != 0)) {
		/* set homing sequence ( no need to decode anything */

		for (int16 i = 0; i < AMR_WB_PCM_FRAME; i++) {
			out[i] = EHF_MASK;
		}
	} else {
		int16 frameLength;
		state->status = pvDecoder_AmrWb(state->mode,
						   state->iInputSampleBuf,
						   out,
						   &frameLength,
						   state->st,
						   state->frame_type,
						   state->ScratchMem);
	}

	for (int16 i = 0; i < AMR_WB_PCM_FRAME; i++) {  /* Delete the 2 LSBs (14-bit output) */
		out[i] &= 0xfffC;
	}

	/* if not homed: check whether current frame is a homing frame */
	if (state->reset_flag_old == 0) {
		/* check whole frame */
		state->reset_flag = pvDecoder_AmrWb_homing_frame_test(state->iInputSampleBuf, state->mode);
	}
	/* reset decoder if current frame is a homing frame */
	if (state->reset_flag != 0) {
		pvDecoder_AmrWb_Reset(state->st, 1);
	}
	state->reset_flag_old = state->reset_flag;

}

static int _amr_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, 
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size)
{

    memset(output, 0, 640);
    *decoded_used_size = amr_wb_byte_len[(input[0] >> 3) & 0x0f] + 1;
    *decoded_output_size = 640;
    _D_IF_decode(codec->decode_ctx, input, (short*)output, 0);
    return LUAT_ERROR_NONE;
}



static int _amr_codec_encode(luat_audio_data_codec_t* codec,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size)
{
    *encoded_used_size = 640;
    *encoded_output_size = _E_IF_encode(codec->encode_ctx, codec->param.amr_encode_speed, (int16_t *)input, output, codec->param.dtx_enable);
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_amr_wb_opts = {
    .init = _amr_codec_init,
    .deinit = _amr_codec_deinit,
    .get_play_info = luat_audio_amr_wb_get_play_info,
    .set_record_info = luat_audio_codec_amr_wb_set_record_info,
    .pre_decode = luat_audio_codec_amr_wb_pre_decode,
    .decode = _amr_codec_decode,
    .make_head = luat_audio_codec_amr_wb_make_head,
    .encode = _amr_codec_encode,
    .decode_min_input_len = 1,
    .decode_max_output_len = 640,
    .encode_min_input_len = 640,
    .encode_max_output_len = 61,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_AMR_WB,
    .is_hardware = 0,
    .support_detect = 1,
    .encode_raw_mode = 0,
};