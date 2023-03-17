#include "mp3_decode/madmp3.h"
#include "app_interface.h"
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif

static inline
signed int scale(mad_fixed_t sample)
{
  /* round */
  sample += (1L << (MAD_F_FRACBITS - 16));

  /* clip */
  if (sample >= MAD_F_ONE)
    sample = MAD_F_ONE - 1;
  else if (sample < -MAD_F_ONE)
    sample = -MAD_F_ONE;

  /* quantize */
  return sample >> (MAD_F_FRACBITS + 1 - 16);
}

void madmp3_init(madmp3_t *mp3dec)
{
	memset(mp3dec, 0, sizeof(madmp3_t));
	mp3dec->frame.overlap = mp3dec->overlap;
	mp3dec->stream.main_data = mp3dec->main_data;
	mad_stream_init(&mp3dec->stream);
	mad_frame_init(&mp3dec->frame);
	mad_synth_init(&mp3dec->synth);
}

int madmp3_decode(madmp3_t *mp3dec, const uint8_t *mp3, int mp3_bytes, int16_t *pcm)
{
	mad_stream_buffer(&mp3dec->stream, mp3, mp3_bytes);
	if (pcm)
	{
		if (mad_frame_decode(&mp3dec->frame, &mp3dec->stream) == -1)
		{
			DBG("%x", mp3dec->stream.main_data + mp3dec->stream.md_len);
			DBG("%d", mp3dec->stream.error);
			return -1;
		}
		mad_synth_frame(&mp3dec->synth, &mp3dec->frame);

		DBG("%d,%d", (uint32_t)mp3dec->stream.this_frame - (uint32_t)mp3, (uint32_t)mp3dec->stream.next_frame - (uint32_t)mp3);

		unsigned int nchannels, length, i;
		mad_fixed_t const *left_ch, *right_ch;

		/* pcm->samplerate contains the sampling frequency */

		nchannels = mp3dec->synth.pcm.channels;
		length  = mp3dec->synth.pcm.length;
		left_ch   = mp3dec->synth.pcm.samples[0];
		right_ch  = mp3dec->synth.pcm.samples[1];
		if (mp3dec->synth.pcm.channels > 1)
		{
			for(i = 0; i < length; i++)
			{
				pcm[i << 1] = scale(left_ch[i]);
				pcm[(i << 1) + 1] = scale(right_ch[i]);
			}
		}
		else
		{
			for(i = 0; i < length; i++)
			{
				pcm[i] = scale(left_ch[i]);
			}
		}
		return length;
	}
	else
	{
		if (mad_header_decode(&mp3dec->frame.header, &mp3dec->stream) == -1)
		{
			return -1;
		}
		return 1;
	}
}
