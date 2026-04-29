#ifndef __LUAT_AUDIO_REQUEST__
#define __LUAT_AUDIO_REQUEST__
#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_common_api.h"
#include "luat_audio_define.h"
#include "luat_audio_channel.h"
#include "luat_audio_driver.h"
#include "luat_fs.h"

typedef struct
{
	luat_llist_head node;
	FILE *fd;
	luat_fifo_t *input_data_fifo;
	luat_buffer_t out_buffer;
	luat_audio_data_codec_t *codec;
    luat_audio_channel_t *data_channel;
} luat_audio_request_block_t;

#endif
