#include "luat_base.h"
#include "luat_mem.h"

#ifdef LUAT_BSP_NOT_SUPPORT_FLOAT


#else
#include "mp3_decode/minimp3.h"
void *mp3_decoder_create(void)
{
	return luat_heap_malloc(sizeof(mp3dec_t));
}
void mp3_decoder_init(void *decoder)
{
	memset(decoder, 0, sizeof(mp3dec_t));
	mp3dec_init(decoder);
}
int mp3_decoder_get_info(void *decoder, const uint8_t *input, uint32_t len, uint32_t *hz, uint8_t *channel)
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
int mp3_decoder_get_data(void *decoder, const uint8_t *input, uint32_t len, int16_t *pcm, uint32_t *out_len, uint32_t *hz, uint32_t *used)
{
	mp3dec_frame_info_t info;
	int result = mp3dec_decode_frame(decoder, input, len, pcm, &info);
	*hz = info.hz;
	*out_len = (result * info.channels * 2);
	*used = info.frame_bytes;
	return result;
}
#endif
