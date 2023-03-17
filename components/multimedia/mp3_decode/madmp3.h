#include "mad.h"
#include "stdint.h"
typedef struct
{
    struct mad_stream stream;
    struct mad_frame frame;
    struct mad_synth synth;
    mad_fixed_t overlap[2][32][18];
    unsigned char main_data[MAD_BUFFER_MDLEN];
}madmp3_t;

void madmp3_init(madmp3_t *mp3dec);
int madmp3_decode(madmp3_t *mp3dec, const uint8_t *mp3, int mp3_bytes, int16_t *pcm);
