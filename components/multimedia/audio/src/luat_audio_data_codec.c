#include "luat_audio_data_codec.h"
#include "luat_common_api.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "audio_codec"
#include "luat_log.h"

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

int luat_audio_data_codec_init(luat_audio_data_codec_t *codec, const luat_audio_data_codec_opts_t *opts, void *user_data, uint8_t is_tts)
{
    if (!codec || !opts) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    memset(codec, 0, sizeof(luat_audio_data_codec_t));
    // 初始化编解码器上下文
    codec->input_buffer = luat_heap_malloc(opts->decode_min_input_len);
    if (!codec->input_buffer) {
        return -LUAT_ERROR_NO_MEMORY;
    }
    codec->opts = opts;
    codec->user_data = user_data;
    codec->is_tts = is_tts;
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_deinit(luat_audio_data_codec_t *codec)
{
    if (!codec) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    luat_heap_free(codec->input_buffer);
    codec->input_buffer = NULL;
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_decode_once(luat_audio_data_codec_t *codec, luat_fifo_t *input_data_fifo, luat_buffer_t *output_data_buffer, uint8_t is_end)
{
    if (!codec || !input_data_fifo || !output_data_buffer) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    uint32_t input_data_len = 0;
    uint32_t out_len, used_len;
    int ret;
    while ((output_data_buffer->pos + codec->opts->decode_max_output_len) <= output_data_buffer->max_len) {
        if (luat_fifo_check_used_space(input_data_fifo) < codec->opts->decode_min_input_len) {
            if (is_end) {   // 最后一次解码，读取所有数据
                input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->decode_min_input_len);
            } else {
                // 非最后一次解码，返回0
                return LUAT_ERROR_NONE;
            }
        } else {
            input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->decode_min_input_len);
        }
        // 使用codec解码数据
        ret = codec->opts->decode(codec, &codec->play_info, codec->input_buffer, input_data_len,
                                                        output_data_buffer->data + output_data_buffer->pos, 
                                &out_len, &used_len);
        luat_fifo_delete(input_data_fifo, used_len);
        if (!ret) {
            output_data_buffer->pos += out_len;
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
    uint32_t out_len;
    int ret;
    while ((output_data_buffer->pos + codec->opts->encode_max_output_len) <= output_data_buffer->max_len) {
        if (luat_fifo_check_used_space(input_data_fifo) >= codec->opts->encode_min_input_len) {
            input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->encode_min_input_len);
        } else {
            return LUAT_ERROR_NONE;
        }
        // 使用codec编码数据
        ret = codec->opts->encode(codec, &codec->play_info, codec->input_buffer, input_data_len,
                                                        output_data_buffer->data + output_data_buffer->pos, 
                                &out_len);
        luat_fifo_delete(input_data_fifo, input_data_len);
        if (!ret) {
            output_data_buffer->pos += out_len;
        } else {
            LLOGE("encode failed, ret = %d", ret);
        }
    }
    return LUAT_ERROR_NONE;
}