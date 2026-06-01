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
    uint8_t is_busy;
}luat_audio_data_codec_item_t;

static luat_audio_data_codec_item_t _audio_data_codec_software_items[LUAT_AUDIO_DATA_CODEC_TYPE_MAX];
static luat_audio_data_codec_item_t _audio_data_codec_hardware_items[LUAT_AUDIO_DATA_CODEC_TYPE_MAX];

int luat_audio_data_codec_bind(luat_audio_data_codec_t *codec, const luat_audio_data_codec_opts_t *opts, void *user_data)
{
    if (!codec || !opts) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    memset(codec, 0, sizeof(luat_audio_data_codec_t));
    if (!opts->is_reentrant && opts->is_hardware) {
        if (_audio_data_codec_hardware_items[opts->type].is_busy) {
            return -LUAT_ERROR_DEVICE_BUSY;
        }
        else {
            _audio_data_codec_hardware_items[opts->type].is_busy = 1;
            LLOGC(luat_audio_debug_flag, "bind hardware data codec %d, now device is busy", opts->type);
        }
    }
    if (codec->input_buffer) {
        luat_heap_free(codec->input_buffer);
        codec->input_buffer = NULL;
    }
    codec->input_buffer = luat_heap_malloc(opts->decode_max_output_len > opts->encode_min_input_len ? opts->encode_min_input_len : opts->decode_max_output_len);
    if (!codec->input_buffer) {
        return -LUAT_ERROR_NO_MEMORY;
    }
    codec->opts = opts;
    codec->user_data = user_data;
    return LUAT_ERROR_NONE;
}

void luat_audio_data_codec_deinit(luat_audio_data_codec_t *codec)
{
    if (!codec) {
        return;
    }
    luat_heap_free(codec->input_buffer);
    codec->input_buffer = NULL;
    codec->opts->deinit(codec);
}

void luat_audio_data_codec_unbind(luat_audio_data_codec_t *codec)
{
    if (!codec) {
        return;
    }
    if (codec->input_buffer) {
        luat_heap_free(codec->input_buffer);
        codec->input_buffer = NULL;
        codec->opts->deinit(codec);
    }
    if (codec->opts->is_hardware) {
        _audio_data_codec_hardware_items[codec->opts->type].is_busy = 0;
    }
    else {
        _audio_data_codec_software_items[codec->opts->type].is_busy = 0;
    }
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
        if (codec->opts->decode_min_input_len) {
            input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->decode_min_input_len);
            if (!input_data_len) {
                LLOGC(luat_audio_debug_flag, "decode input fifo empty, decode end");
                return LUAT_ERROR_NONE;
            }
            if (input_data_len < codec->opts->decode_min_input_len) {  // 输入数据不足
                if (!is_end) {   // 最后一次解码，读取所有数据
                    LLOGC(luat_audio_debug_flag, "decode input fifo not enough %d/%d, decode end", input_data_len, codec->opts->decode_min_input_len);
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
                LLOGC(luat_audio_debug_flag, "decode input fifo not enough %d/%d, decode end", input_data_len, frame_byte);
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

int luat_audio_data_codec_encode_once(luat_audio_data_codec_t *codec, luat_fifo_t *input_data_fifo, luat_buffer_t *output_data_buffer)
{
    if (!codec || !input_data_fifo || !output_data_buffer) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    uint32_t input_data_len = 0;
    uint32_t out_len, used_len;
    int ret;
    while ((output_data_buffer->pos + codec->opts->encode_max_output_len) <= output_data_buffer->max_len) {
        if (luat_fifo_check_used_space(input_data_fifo) >= codec->opts->encode_min_input_len) {
            input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->encode_min_input_len);
        } else {
            return LUAT_ERROR_NONE;
        }
        // 使用codec编码数据
        ret = codec->opts->encode(codec, &codec->common_param, codec->input_buffer, input_data_len,
                                                        output_data_buffer->data + output_data_buffer->pos, 
                                &used_len, &out_len);
        luat_fifo_delete(input_data_fifo, used_len);
        if (!ret) {
            output_data_buffer->pos += out_len;
        } else {
            LLOGE("encode failed, ret = %d", ret);
        }
    }
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t* luat_audio_data_codec_find(uint8_t type)
{
    if (type >= LUAT_AUDIO_DATA_CODEC_TYPE_MAX) {
        LLOGE("type %d out of range, max %d", type, LUAT_AUDIO_DATA_CODEC_TYPE_MAX - 1);
        return NULL;
    }
    if (_audio_data_codec_hardware_items[type].opts) {
        LLOGC(luat_audio_debug_flag, "find hardware codec %d", type);
        if (!_audio_data_codec_hardware_items[type].is_busy) {
            return _audio_data_codec_hardware_items[type].opts;
        } else {
            LLOGC(luat_audio_debug_flag, "find hardware codec %d busy", type);
        }
    }
    if (_audio_data_codec_software_items[type].opts) {
        LLOGC(luat_audio_debug_flag, "find software codec %d", type);
        if (!_audio_data_codec_software_items[type].is_busy) {
            return _audio_data_codec_software_items[type].opts;
        } else {
            LLOGC(luat_audio_debug_flag, "find software codec %d busy", type);
        }
    }
    LLOGE("type %d can not find in data codec", type);
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

