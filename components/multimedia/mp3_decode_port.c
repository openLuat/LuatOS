#include "luat_base.h"
#include "luat_mem.h"
#undef LUAT_BSP_SUPPORT_FLOAT
#ifdef LUAT_BSP_SUPPORT_FLOAT
#include "mp3_decode/minimp3.h"
#else
#include "mp3_decode/madmp3.h"
#endif

void *mp3_decoder_create(void)
{
#ifdef LUAT_BSP_SUPPORT_FLOAT
	return luat_heap_malloc(sizeof(mp3dec_t));
#else
	return luat_heap_malloc(sizeof(madmp3_t));
#endif
}
void mp3_decoder_init(void *decoder)
{
#ifdef LUAT_BSP_SUPPORT_FLOAT
	memset(decoder, 0, sizeof(mp3dec_t));
	mp3dec_init(decoder);
#else
	madmp3_init(decoder);
#endif
}
int mp3_decoder_get_info(void *decoder, const uint8_t *input, uint32_t len, uint32_t *hz, uint8_t *channel)
{
#ifdef LUAT_BSP_SUPPORT_FLOAT
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
#else
	if (madmp3_decode(decoder, input, len, NULL) > 0)
	{
		madmp3_t *mad = (madmp3_t *)decoder;
		*hz = mad->frame.header.samplerate;
		if (mad->frame.header.mode)
		{
			*channel = 2;
		}
		else
		{
			*channel = 1;
		}
		return 1;
	}
	else
	{
		return 0;
	}
#endif

}
int mp3_decoder_get_data(void *decoder, const uint8_t *input, uint32_t len, int16_t *pcm, uint32_t *out_len, uint32_t *hz, uint32_t *used)
{
#ifdef LUAT_BSP_SUPPORT_FLOAT
	mp3dec_frame_info_t info;
	int result = mp3dec_decode_frame(decoder, input, len, pcm, &info);
	*hz = info.hz;
	*out_len = (result * info.channels * 2);
	*used = info.frame_bytes;
	return result;
#else
	madmp3_t *mad = (madmp3_t *)decoder;
	mad->stream.md_len = 0;
	if (madmp3_decode(decoder, input, len, pcm) > 0)
	{
		*hz = mad->frame.header.samplerate;
		*out_len = (mad->synth.pcm.length * mad->synth.pcm.channels * 2);
		*used = (uint32_t)mad->stream.next_frame - (uint32_t)input;
	}
#endif
}
