#include "luat_audio_data_codec.h"
#include "luat_audio_request.h"
#include "luat_audio_define.h"
#include "luat_common_api.h"
#include "luat_fs.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "audio_codec"
#include "luat_log.h"

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

typedef struct {
    const luat_audio_data_codec_opts_t *opts;
}luat_audio_data_codec_item_t;

static luat_audio_data_codec_item_t _audio_data_codec_software_items[LUAT_AUDIO_DATA_CODEC_TYPE_MAX];
static luat_audio_data_codec_item_t _audio_data_codec_hardware_items[LUAT_AUDIO_DATA_CODEC_TYPE_MAX];

int luat_audio_data_codec_bind(luat_audio_data_codec_t *codec, const luat_audio_data_codec_opts_t *opts, void *user_data)
{
    if (!codec || !opts) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    memset(codec, 0, sizeof(luat_audio_data_codec_t));
    if (codec->input_buffer) {
        luat_heap_free(codec->input_buffer);
        codec->input_buffer = NULL;
    }
    codec->input_buffer_size = (opts->decode_max_output_len > opts->encode_min_input_len) ? opts->decode_max_output_len * 2 : opts->encode_min_input_len * 2;
    codec->input_buffer = luat_heap_malloc(codec->input_buffer_size);
    if (!codec->input_buffer) {
        LLOGC(luat_audio_debug_flag, "bind audio data codec %d failed, no memory", opts->type);
        codec->input_buffer_size = 0;
        return -LUAT_ERROR_NO_MEMORY;
    }

    codec->opts = opts;
    codec->user_data = user_data;
    return LUAT_ERROR_NONE;
}

// int luat_audio_data_codec_init_temp_buffer(luat_audio_data_codec_t *codec, luat_audio_common_param_t *new_param)
// {
//     uint32_t base_len = codec->opts->decode_max_output_len > codec->opts->encode_min_input_len ? codec->opts->decode_max_output_len : codec->opts->encode_min_input_len;
//     uint32_t data_align_len = codec->common_param.data_align > new_param->data_align ? (base_len * codec->common_param.data_align / new_param->data_align) : (base_len * new_param->data_align / codec->common_param.data_align);
//     uint32_t channel_nums_len = codec->common_param.channel_nums > new_param->channel_nums ? (data_align_len * codec->common_param.channel_nums / new_param->channel_nums) : (data_align_len * new_param->channel_nums / codec->common_param.channel_nums);
//     LLOGC(luat_audio_debug_flag, "init temp buffer, old param %d-%d new param %d-%d, base_len %d, data_align_len %d, channel__nums_len %d",
//          codec->common_param.data_align, codec->common_param.channel_nums, new_param->data_align, new_param->channel_nums, base_len, data_align_len, channel_nums_len);
//     if (codec->temp_buffer1) {
//         luat_heap_free(codec->temp_buffer1);
//         codec->temp_buffer1 = NULL;
//     }
//     codec->temp_buffer1 = luat_heap_malloc(channel_nums_len * 3);
//     if (!codec->temp_buffer1) {
//         LLOGC(luat_audio_debug_flag, "init temp buffer failed, no memory");
//         return -LUAT_ERROR_NO_MEMORY;
//     }
//     codec->temp_buffer2 = codec->temp_buffer1 + channel_nums_len;
//     codec->temp_buffer3 = codec->temp_buffer1 + channel_nums_len * 2;
//     return LUAT_ERROR_NONE;
// }

void luat_audio_data_codec_deinit(luat_audio_data_codec_t *codec)
{
    if (!codec) {
        return;
    }
    if (codec->input_buffer) {
        luat_heap_free(codec->input_buffer);
        codec->input_buffer = NULL;
    }
    if (codec->temp_buffer1) {
        luat_heap_free(codec->temp_buffer1);
        codec->temp_buffer1 = NULL;
        codec->temp_buffer2 = NULL;
        codec->temp_buffer3 = NULL;
    }
    if (codec->opts) {
        codec->opts->deinit(codec);
    }
}

void luat_audio_data_codec_unbind(luat_audio_data_codec_t *codec)
{
    if (!codec) {
        return;
    }
    luat_audio_data_codec_deinit(codec);
    codec->opts = NULL;
}

int luat_audio_data_codec_get_play_info(luat_audio_data_codec_t *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes)
{
    return codec->opts->get_play_info(codec, input_buffer, now_file_pos, jump_offset_bytes, need_bytes, &codec->common_param);
}

int luat_audio_data_codec_decode_once(luat_audio_data_codec_t *codec, luat_fifo_t *input_data_fifo, luat_buffer_t *output_data_buffer, uint8_t is_end)
{
    uint32_t input_data_len = 0;
    uint32_t out_len, used_len;
    int ret;
    // LLOGC(luat_audio_debug_flag, "start decode input fifo %d bytes, output buffer %d bytes",
    //         luat_fifo_check_used_space(input_data_fifo), output_data_buffer->pos);

    while ((output_data_buffer->pos + codec->opts->decode_max_output_len) <= output_data_buffer->max_len) {
        if (codec->opts->decode_min_input_len > 1) {
            input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->decode_min_input_len);
            if (!input_data_len) {
                LLOGC(luat_audio_debug_flag, "decode input fifo empty, decode end");
                return LUAT_ERROR_NONE;
            }
            if (input_data_len < codec->opts->decode_min_input_len) {  // 输入数据不足
                if (!is_end) {   // 最后一次解码，读取所有数据
                    LLOGC(luat_audio_debug_flag, "decode input fifo not enough %d/%d, not end, decode end", input_data_len, codec->opts->decode_min_input_len);
                    return LUAT_ERROR_NONE;
                }
            }
        } else {
            input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->encode_max_output_len);
            if (!input_data_len) {
                LLOGC(luat_audio_debug_flag, "decode input fifo empty, decode end");
                return LUAT_ERROR_NONE;
            }
            uint32_t frame_byte = 0;
            codec->opts->pre_decode(codec, codec->input_buffer, input_data_len, &frame_byte);
            if (frame_byte > input_data_len) {
                LLOGC(luat_audio_debug_flag, "decode input fifo not enough %d/%d/%d, decode end", input_data_len, frame_byte,is_end);
                if (is_end) {
                    luat_fifo_delete(input_data_fifo, input_data_fifo->size);
                }
                return LUAT_ERROR_NONE;
            }
        }
        // 使用codec解码数据
        used_len = 0;
        out_len = 0;
        ret = codec->opts->decode(codec, &codec->common_param, codec->input_buffer, input_data_len,
                                                        output_data_buffer->data + output_data_buffer->pos, 
                                &out_len, &used_len);
        luat_fifo_delete(input_data_fifo, used_len);
        if (!ret) {
            output_data_buffer->pos += out_len;
            // LLOGC(luat_audio_debug_flag, "decode used %d bytes, output %d bytes, input fifo %d bytes, output buffer %d bytes", used_len, out_len,
            //     luat_fifo_check_used_space(input_data_fifo), output_data_buffer->pos);
        } else {
            LLOGE("decode failed, ret = %d, %d, %d", ret, used_len, out_len);
            return ret;
        }
    }
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_encode_once(luat_audio_data_codec_t *codec, luat_audio_common_param_t *input_param, luat_fifo_t *input_data_fifo, luat_fifo_t *output_data_fifo)
{
    if (!codec || !input_data_fifo || !output_data_fifo) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    uint32_t min_data_len = codec->opts->encode_max_output_len;
    if (codec->opts->encode_raw_mode) {
        min_data_len = codec->common_param.one_frame_bytes;
    }
    uint32_t len_bytes = 0;
    uint32_t pcm_data_len = 0;
    uint32_t new_data_len = 0;
    uint32_t new_data_len2 = 0;
    uint32_t out_len, used_len;
    luat_data_union_t data_union;
    luat_data_union_t new_data_union;
    luat_data_union_t new_data_union2;
    int ret;
    LLOGC(luat_audio_debug_flag, "encode once, input %u,%u-%u-%u, output %u,%u-%u-%u", codec->record_one_frame_input_len, input_param->sample_rate, input_param->data_align, input_param->channel_nums, 
        min_data_len, codec->common_param.data_align, codec->common_param.channel_nums);
    while ((luat_fifo_check_used_space(input_data_fifo) >= codec->record_one_frame_input_len) && (luat_fifo_check_free_space(output_data_fifo) >= min_data_len)) {
        len_bytes =luat_fifo_read(input_data_fifo, codec->temp_buffer1, codec->record_one_frame_input_len);
        data_union.p8 = codec->temp_buffer1;
        if ((!codec->common_param.is_signed) != (!input_param->is_signed)) {
            luat_audio_channel_data_change_signed(data_union, len_bytes, input_param->data_align, input_param->is_signed);
        }
        if (input_param->channel_nums != codec->common_param.channel_nums) {
            switch (input_param->data_align) {
                case 1:
                    pcm_data_len = len_bytes;
                    
                    break;
                case 2:
                    pcm_data_len = len_bytes >> 1;
                    break;
                case 3:
                case 4:
                    pcm_data_len = len_bytes >> 2;
                    break;
                default:
                    return -LUAT_ERROR_PARAM_INVALID;
                    break;
            }
            new_data_len = (pcm_data_len / input_param->channel_nums) * codec->common_param.channel_nums;
            data_union.p8 = codec->temp_buffer1;
            new_data_union.p8 = codec->temp_buffer2;
            luat_audio_channel_data_change_channel_nums(data_union, new_data_union, pcm_data_len, input_param->data_align, input_param->channel_nums, codec->common_param.channel_nums);
        } else {
            new_data_len = len_bytes;
            new_data_union.p8 = codec->temp_buffer1;
        }

        if (input_param->data_align != codec->common_param.data_align) {
            switch (input_param->data_align) {
                case 1:
                    pcm_data_len = len_bytes;
                    break;
                case 2:
                    pcm_data_len = len_bytes >> 1;
                    break;
                case 3:
                case 4:
                    pcm_data_len = len_bytes >> 2;
                    break;
                default:
                    return -LUAT_ERROR_PARAM_INVALID;
                    break;
            }
            switch (codec->common_param.data_align) {
                case 1:
                    new_data_len2 = pcm_data_len;
                    break;
                case 2:
                    new_data_len2 = pcm_data_len << 1;
                    break;
                case 3:
                case 4:
                    new_data_len2 = pcm_data_len << 2;
                    break;
                default:
                    return -LUAT_ERROR_PARAM_INVALID;
                    break;
            }
            new_data_union2.p8 = codec->temp_buffer3;
            luat_audio_channel_data_change_align(new_data_union, new_data_union2, new_data_len2, input_param->data_align, codec->common_param.data_align);
        } else {
            new_data_union2.p8 = new_data_union.p8;
            new_data_len2 = new_data_len;
        }
        // if (ret != LUAT_ERROR_NONE) {
        //     return ret;
        // }
    }
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t* luat_audio_data_codec_find(uint8_t type)
{
    if (type >= LUAT_AUDIO_DATA_CODEC_TYPE_MAX) {
        LLOGE("type %d out of range, max %d", type, LUAT_AUDIO_DATA_CODEC_TYPE_MAX - 1);
        return NULL;
    }

    if (_audio_data_codec_software_items[type].opts) {
        LLOGC(luat_audio_debug_flag, "find software codec %d", type);
        return _audio_data_codec_software_items[type].opts;
    }

    if (_audio_data_codec_hardware_items[type].opts) {
        LLOGC(luat_audio_debug_flag, "find hardware codec %d", type);
        return _audio_data_codec_hardware_items[type].opts;
    }
    LLOGE("type %d can not find in data codec", type);
    return NULL;
}

const luat_audio_data_codec_opts_t* luat_audio_data_codec_find_hardware(uint8_t type)
{
    if (type >= LUAT_AUDIO_DATA_CODEC_TYPE_MAX) {
        LLOGE("type %d out of range, max %d", type, LUAT_AUDIO_DATA_CODEC_TYPE_MAX - 1);
        return NULL;
    }
    if (_audio_data_codec_hardware_items[type].opts) {
        LLOGC(luat_audio_debug_flag, "find hardware codec %d", type);
        return _audio_data_codec_hardware_items[type].opts;
    }
    LLOGE("type %d can not find in hardware data codec", type);
    return NULL;
}

int luat_audio_data_codec_register(const luat_audio_data_codec_opts_t *opts)
{
    if (!opts) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (opts->type >= LUAT_AUDIO_DATA_CODEC_TYPE_MAX) {
        LLOGE("type %d unknown can not register in data codec", opts->type);
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (opts->is_hardware) {
        _audio_data_codec_hardware_items[opts->type].opts = opts;
    }
    else {
        _audio_data_codec_software_items[opts->type].opts = opts;
    }
    return LUAT_ERROR_NONE;
}

