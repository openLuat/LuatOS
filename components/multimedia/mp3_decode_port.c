#include "luat_base.h"
#include "luat_mem.h"
#include "luat_multimedia.h"
#include "luat_mem.h"
#include "luat_fs.h"
#include "luat_multimedia_codec.h"
#ifdef LUAT_BSP_NOT_SUPPORT_FLOAT


#else
#include "mp3_decode/minimp3.h"
LUAT_WEAK void *mp3_decoder_create(void)
{
	return luat_heap_malloc(sizeof(mp3dec_t));
}
LUAT_WEAK void mp3_decoder_init(void *decoder)
{
	memset(decoder, 0, sizeof(mp3dec_t));
	mp3dec_init(decoder);
}
LUAT_WEAK void mp3_decoder_set_debug(void *decoder, uint8_t onoff)
{
	(void)decoder;
	(void)onoff;
}

LUAT_WEAK int mp3_decoder_get_info(void *decoder, const uint8_t *input, uint32_t len, uint32_t *hz, uint8_t *channel)
{

	mp3dec_frame_info_t info;
	if (mp3dec_decode_frame(decoder, input, len, NULL, &info) > 0)
	{
		*hz = info.hz;
		*channel = info.channels;
		return 1;
	}
	else
	{
		return 0;
	}


}
LUAT_WEAK int mp3_decoder_get_data(void *decoder, const uint8_t *input, uint32_t len, int16_t *pcm, uint32_t *out_len, uint32_t *hz, uint32_t *used)
{
	mp3dec_frame_info_t info;
	int result = mp3dec_decode_frame(decoder, input, len, pcm, &info);
	if (result >= 0) {
		*hz = info.hz;
		*out_len = (result * info.channels * 2);
		*used = info.frame_bytes;
	}
	else {
		*out_len = 0;
	}
	return result;
}

static void* mp3_codec_create(luat_multimedia_codec_t* coder) {
    if (!coder->is_decoder) {
        return NULL;
    }
    return mp3_decoder_create();
}

static void mp3_codec_destroy(luat_multimedia_codec_t* coder) {
    if (coder && coder->ctx) {
        luat_heap_free(coder->ctx);
        coder->ctx = NULL;
    }
}

static int mp3_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd) {
    if (!coder || !coder->ctx || !fd) return 0;

    uint8_t temp[32];
    uint32_t jump, i;
    int result = 0;

    mp3_decoder_init(coder->ctx);
    coder->buff.addr = luat_heap_malloc(MP3_FRAME_LEN);

    coder->buff.len = MP3_FRAME_LEN;
    coder->buff.used = luat_fs_fread(temp, 10, 1, fd);
    if (coder->buff.used != 10) {
        return 0;
    }
    if (!memcmp(temp, "ID3", 3)) {
        jump = 0;
        for(i = 0; i < 4; i++) {
            jump <<= 7;
            jump |= temp[6 + i] & 0x7f;
        }
        luat_fs_fseek(fd, jump, SEEK_SET);
    }
    coder->buff.used = luat_fs_fread(coder->buff.addr, MP3_FRAME_LEN, 1, fd);
    result = mp3_decoder_get_info(coder->ctx, coder->buff.addr, coder->buff.used, &coder->sample_rate, &coder->num_channels);
    mp3_decoder_init(coder->ctx);
    coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;

    return result;
}

static int mp3_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff || !coder->buff.addr) return 0;

    FILE* fd = coder->fd;
    uint32_t pos = 0;
    uint32_t hz, out_len, used;
    int result;
    uint32_t is_not_end = 1;

GET_MP3_DATA:
    if (coder->buff.used < MINIMP3_MAX_SAMPLES_PER_FRAME) {
        int read_len = luat_fs_fread(coder->buff.addr + coder->buff.used, MINIMP3_MAX_SAMPLES_PER_FRAME, 1, fd);
        if (read_len > 0) {
            coder->buff.used += read_len;
        } else {
            is_not_end = 0;
        }
    }

    do {
        result = mp3_decoder_get_data(coder->ctx, coder->buff.addr + pos, coder->buff.used - pos,
                                       (int16_t*)(out_buff->addr + out_buff->used),
                                       &out_len, &hz, &used);
        if (result > 0) {
            out_buff->used += out_len;
        }
        if (result < 0) {
            return 0;
        }
        pos += used;
        if ((out_buff->len - out_buff->used) < (MINIMP3_MAX_SAMPLES_PER_FRAME * 2)) {
            break;
        }
    } while ((coder->buff.used - pos) >= (MINIMP3_MAX_SAMPLES_PER_FRAME * is_not_end + 1));

    if (pos >= coder->buff.used) {
        coder->buff.used = 0;
    } else {
        memmove(coder->buff.addr, coder->buff.addr + pos, coder->buff.used - pos);
        coder->buff.used -= pos;
    }
    pos = 0;

    if (!out_buff->used) {
        if (is_not_end) {
            goto GET_MP3_DATA;
        } else {
            return 0;
        }
    } else {
        if ((out_buff->used < mini_output) && is_not_end) {
            goto GET_MP3_DATA;
        }
        return 1;
    }
}

const luat_codec_opts_t mp3_codec_opts = {
    .create = mp3_codec_create,
    .destroy = mp3_codec_destroy,
    .get_info = mp3_codec_get_info,
    .decode_file_data = mp3_codec_decode_file_data,
    .encode = NULL
};

#endif