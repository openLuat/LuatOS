#include "luat_audio_channel.h"
#include "luat_common_api.h"
#include "luat_rtos.h"
#include <stdint.h>
#define LUAT_LOG_TAG "audio_ch"
#include "luat_log.h"

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

int luat_audio_channel_init(luat_audio_channel_t *channel, uint32_t fifo_size_power)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (!fifo_size_power) {
        fifo_size_power = LUAT_AUDIO_CHANNEL_FIFO_DEFAULT_SIZE_POWER;
    }
    luat_rtos_task_suspend_all();
    if (!channel->play_lock_mutex) {
        channel->play_fifo = luat_fifo_create(fifo_size_power);
        channel->record_fifo = luat_fifo_create(fifo_size_power);
        channel->forward_fifo = luat_fifo_create(fifo_size_power);      
        channel->play_lock_mutex = luat_mutex_create();
        channel->play_fifo_need_data_level = channel->play_fifo->size >> 1;
        channel->soft_vol = 100;
    }
    luat_rtos_task_resume_all();
    return LUAT_ERROR_NONE;
}

int luat_audio_channel_deinit(luat_audio_channel_t *channel)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    luat_rtos_task_suspend_all();
    luat_fifo_destroy(channel->play_fifo);
    luat_fifo_destroy(channel->record_fifo);
    luat_fifo_destroy(channel->forward_fifo);
    if (channel->play_lock_mutex)
    {
        luat_mutex_release(channel->play_lock_mutex);
        channel->play_lock_mutex = NULL;
    }
    luat_rtos_task_resume_all();
    return LUAT_ERROR_NONE;
}

int luat_audio_channel_play(luat_audio_channel_t *channel, uint8_t is_play)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    channel->play_state = is_play;
    return LUAT_ERROR_NONE;
}

int luat_audio_channel_record(luat_audio_channel_t *channel, uint8_t record_state)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    channel->record_state = record_state;
    return LUAT_ERROR_NONE;
}

static void _audio_channel_play_vol_16bit(int16_t *data, uint32_t len_bytes, uint16_t vol)
{
    uint32_t i = 0;
    uint32_t pos = 0;
    int32_t temp;
    while(pos < len_bytes)
    {
        temp = data[i];
        temp = temp * vol / 100;
        if (temp > 32767)
        {
            temp = 32767;
        }
        else if (temp < -32768)
        {
            temp = -32768;
        }
        data[i] = temp;
        i++;
        pos += 2;
    }
}

static void _audio_channel_play_vol_32bit(int32_t *data, uint32_t len_bytes, uint32_t vol)
{
    uint32_t i = 0;
    uint32_t pos = 0;
    int64_t temp;
    while(pos < len_bytes)
    {
        temp = data[i];
        temp = temp * vol / 100;
        if (temp > 2147483647)
        {
            temp = 2147483647;
        }
        else if (temp < -2147483648)
        {
            temp = -2147483648;
        }
        data[i] = temp;
        i++;
        pos += 4;
    }
}

int luat_audio_channel_write_data(luat_audio_channel_t *channel, void *data, uint32_t len_bytes, uint32_t *written_bytes, uint8_t is_signed,uint8_t data_align, uint8_t channel_nums)
{
    *written_bytes = 0;
    if (!channel || !data || !written_bytes) {
        return -LUAT_ERROR_PARAM_INVALID;
    }

    luat_data_union_t data_union;
    data_union.p = data;

    if (channel->soft_vol && channel->soft_vol != 100) {     // 音量软件调节
        switch (data_align) {
            case 2:
                _audio_channel_play_vol_16bit(data_union.i16, len_bytes, channel->soft_vol);
                break;
            case 3:
            case 4:
                _audio_channel_play_vol_32bit(data_union.i32, len_bytes, channel->soft_vol);
                break;
            default:
                return -LUAT_ERROR_PARAM_INVALID;
                break;
        }
    }
    if (is_signed != channel->driver_ctrl->opts->is_signed) { // 数据有无符号转换
        if (channel->driver_ctrl->opts->is_signed) {
            switch (data_align) {
                case 1:
                    for(uint32_t i = 0; i < len_bytes; i++){
			            data_union.p8[i] ^= 0x80;
	                }
                    break;
                case 2:
                    for(uint32_t i = 0; i < len_bytes >> 1; i++){
			            data_union.p16[i] ^= 0x8000;
	                }
                    break;
                case 3:
                    for(uint32_t i = 0; i < len_bytes >> 2; i++){
			            data_union.p32[i] = data_union.p32[i] ^ 0x800000;
	                }
                    break;
                case 4:
                    for(uint32_t i = 0; i < len_bytes >> 2; i++){
			            data_union.p32[i] ^= 0x80000000;
	                }
                    break;
                default:
                    break;
            }
        } else {
            switch (data_align) {
                case 1:
                    for(uint32_t i = 0; i < len_bytes; i++){
			            data_union.i8[i] = data_union.p8[i] - 0x80;
	                }
                    break;
                case 2:
                    for(uint32_t i = 0; i < len_bytes >> 1; i++){
			            data_union.i16[i] = data_union.p16[i] - 0x8000;
	                }
                    break;
                case 3:
                    for(uint32_t i = 0; i < len_bytes >> 2; i++){
                        data_union.i32[i] = (data_union.p32[i]- 0x800000) & 0xffffff; 
                    }
                    break;
                case 4:
                    for(uint32_t i = 0; i < len_bytes >> 2; i++){
			            data_union.i32[i] = data_union.p32[i] - 0x80000000;
	                }
                    break;
                default:
                    break;
            }
        }
    }

    if (data_align == channel->driver_ctrl->data_align && channel_nums == channel->driver_ctrl->channel_nums) {
        luat_mutex_lock(channel->play_lock_mutex);
		luat_fifo_write(channel->play_fifo, data, len_bytes);
		luat_mutex_unlock(channel->play_lock_mutex);
        *written_bytes = len_bytes;
        return LUAT_ERROR_NONE;
    } else if (data_align == channel->driver_ctrl->data_align) { // 音频通道数匹配
        uint32_t pcm_data_len, new_data_len, new_data_bytes = 0;
        luat_data_union_t new_data_union;
        new_data_union.p = NULL;
        switch (data_align) {
            case 1:
                pcm_data_len = len_bytes;
                new_data_len = (pcm_data_len / channel_nums) * channel->driver_ctrl->channel_nums;
                new_data_bytes = new_data_len;
                if (new_data_bytes > luat_fifo_check_free_space(channel->play_fifo)) {
                    return -LUAT_ERROR_PARAM_OVERFLOW;
                }
                new_data_union.p = luat_heap_malloc(new_data_bytes);
                if (!new_data_union.p) {
                    return -LUAT_ERROR_NO_MEMORY;
                }
                if (channel_nums > channel->driver_ctrl->channel_nums) {    // 解码后数据通道数大于音频通道数, 需要减少数据
                    if (1 == channel->driver_ctrl->channel_nums) {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j++){
                            new_data_union.i8[j] = data_union.i8[i];
                        }
                    } else {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j += channel->driver_ctrl->channel_nums){
                            memcpy(&new_data_union.i8[j], &data_union.i8[i], channel->driver_ctrl->channel_nums);
                        }
                    }
                } else {    // 解码后数据通道数小于音频通道数, 需要增加数据
                    if (1 == channel_nums) {
                        if (2 == channel->driver_ctrl->channel_nums) {
                            for(uint32_t i = 0, j = 0; i < pcm_data_len; i++, j += channel->driver_ctrl->channel_nums){
                                new_data_union.i8[j] = data_union.i8[i];
                                new_data_union.i8[j+1] = data_union.i8[i];
                            }
                        } else {
                            for(uint32_t i = 0, j = 0; i < pcm_data_len; i++, j += channel->driver_ctrl->channel_nums){
                                for (uint8_t k = 0; k < channel->driver_ctrl->channel_nums; k++){
                                    new_data_union.i8[j+k] = data_union.i8[i];
                                }
                            }
                        }
                    } else {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j += channel->driver_ctrl->channel_nums){
                            memcpy(&new_data_union.i8[j], &data_union.i8[i], channel_nums);
                            for (uint8_t k = channel_nums; k < channel->driver_ctrl->channel_nums; k++){
                                new_data_union.i8[j+k] = data_union.i8[i + channel_nums - 1];
                            }
                        }
                    }
                }
                break;
            case 2:
                pcm_data_len = len_bytes >> 1;
                new_data_len = (pcm_data_len / channel_nums) * channel->driver_ctrl->channel_nums;
                new_data_bytes = new_data_len << 1;
                if (new_data_bytes > luat_fifo_check_free_space(channel->play_fifo)) {
                    return -LUAT_ERROR_PARAM_OVERFLOW;
                }
                new_data_union.p = luat_heap_malloc(new_data_bytes);
                if (!new_data_union.p) {
                    return -LUAT_ERROR_NO_MEMORY;
                }
                if (channel_nums > channel->driver_ctrl->channel_nums) {    // 解码后数据通道数大于音频通道数, 需要减少数据
                    if (1 == channel->driver_ctrl->channel_nums) {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j++){
                            new_data_union.i16[j] = data_union.i16[i];
                        }
                    } else {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j+= channel->driver_ctrl->channel_nums){
                            memcpy(&new_data_union.i16[j], &data_union.i16[i], channel->driver_ctrl->channel_nums << 1);
                        }
                    }
                } else {    // 解码后数据通道数小于音频通道数, 需要增加数据
                    if (1 == channel_nums) {
                        if (2 == channel->driver_ctrl->channel_nums) {
                            for(uint32_t i = 0, j = 0; i < pcm_data_len; i++, j+= channel->driver_ctrl->channel_nums){
                                new_data_union.i16[j] = data_union.i16[i];
                                new_data_union.i16[j+1] = data_union.i16[i];
                            }
                        } else {
                            for(uint32_t i = 0, j = 0; i < pcm_data_len; i++, j+= channel->driver_ctrl->channel_nums){
                                for (uint8_t k = 0; k < channel->driver_ctrl->channel_nums; k++){
                                    new_data_union.i16[j+k] = data_union.i16[i];
                                }
                            }
                        }
                    } else {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j+= channel->driver_ctrl->channel_nums){
                            memcpy(&new_data_union.i16[j], &data_union.i16[i], channel_nums << 1);
                            for (uint8_t k = channel_nums; k < channel->driver_ctrl->channel_nums; k++){
                                new_data_union.i16[j+k] = data_union.i16[i + channel_nums - 1];
                            }
                        }
                    }
                }
                break;
            case 3:
            case 4:
                pcm_data_len = len_bytes >> 2;
                new_data_len = (pcm_data_len / channel_nums) * channel->driver_ctrl->channel_nums;
                new_data_bytes = new_data_len << 2;
                if (new_data_bytes > luat_fifo_check_free_space(channel->play_fifo)) {
                    return -LUAT_ERROR_PARAM_OVERFLOW;
                }
                new_data_union.p = luat_heap_malloc(new_data_bytes);
                if (!new_data_union.p) {
                    return -LUAT_ERROR_NO_MEMORY;
                }
                if (channel_nums > channel->driver_ctrl->channel_nums) {    // 解码后数据通道数大于音频通道数, 需要减少数据
                    if (1 == channel->driver_ctrl->channel_nums) {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j++){
                            new_data_union.i32[j] = data_union.i32[i];
                        }
                    } else {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j+= channel->driver_ctrl->channel_nums){
                            memcpy(&new_data_union.i32[j], &data_union.i32[i], channel->driver_ctrl->channel_nums << 2);
                        }
                    }
                } else {    // 解码后数据通道数小于音频通道数, 需要增加数据
                    if (1 == channel_nums) {
                        if (2 == channel->driver_ctrl->channel_nums) {
                            for(uint32_t i = 0, j = 0; i < pcm_data_len; i++, j+= channel->driver_ctrl->channel_nums){
                                new_data_union.i32[j] = data_union.i32[i];
                                new_data_union.i32[j+1] = data_union.i32[i];
                            }
                        } else {
                            for(uint32_t i = 0, j = 0; i < pcm_data_len; i++, j+= channel->driver_ctrl->channel_nums){
                                for (uint8_t k = 0; k < channel->driver_ctrl->channel_nums; k++){
                                    new_data_union.i32[j+k] = data_union.i32[i];
                                }
                            }
                        }
                    } else {
                        for(uint32_t i = 0, j = 0; i < pcm_data_len; i += channel_nums, j+= channel->driver_ctrl->channel_nums){
                            memcpy(&new_data_union.i32[j], &data_union.i32[i], channel_nums << 2);
                            for (uint8_t k = channel_nums; k < channel->driver_ctrl->channel_nums; k++){
                                new_data_union.i32[j+k] = data_union.i32[i + channel_nums - 1];
                            }
                        }
                    }
                }
                break;
            default:
                return -LUAT_ERROR_PARAM_INVALID;
                break;
        }
        *written_bytes = new_data_bytes;
        luat_fifo_write(channel->play_fifo, new_data_union.p, new_data_bytes);
        luat_heap_free(new_data_union.p8);
    } else if (channel_nums == channel->driver_ctrl->channel_nums) {
        uint32_t pcm_data_len, new_data_bytes = 0;
        luat_data_union_t new_data_union;
        new_data_union.p = NULL;
        switch (data_align) {
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
        switch (channel->driver_ctrl->data_align) {
            case 1:
                new_data_bytes = pcm_data_len;
                break;
            case 2:
                new_data_bytes = pcm_data_len << 1;
                break;
            case 3:
            case 4:
                new_data_bytes = pcm_data_len << 2;
                break;
            default:
                return -LUAT_ERROR_PARAM_INVALID;
                break;
        }
        if (new_data_bytes > luat_fifo_check_free_space(channel->play_fifo)) {
            return -LUAT_ERROR_PARAM_OVERFLOW;
        }
        new_data_union.p = luat_heap_malloc(new_data_bytes);
        if (!new_data_union.p) {
            return -LUAT_ERROR_NO_MEMORY;
        }
        switch (data_align) {
            case 1:
                switch (channel->driver_ctrl->data_align) {
                    case 2:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p16[i] = data_union.p8[i] << 8;
                        }
                        break;
                    case 3:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p32[i] = data_union.p8[i] << 16;
                        }
                        break;
                    case 4:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p32[i] = data_union.p8[i] << 24;
                        }
                        break;
                    default:
                        return -LUAT_ERROR_PARAM_INVALID;
                        break;
                }
                break;
            case 2:
                switch (channel->driver_ctrl->data_align) {
                    case 1:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p8[i] = data_union.p16[i] >> 8;
                        }
                        break;
                    case 3:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p32[i] = data_union.p16[i] << 8;
                        }
                        break;
                    case 4:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p32[i] = data_union.p16[i] << 16;
                        }
                        break;
                    default:
                        return -LUAT_ERROR_PARAM_INVALID;
                        break;
                }
                break;
            case 3:
                switch (channel->driver_ctrl->data_align) {
                    case 1:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p8[i] = data_union.p32[i] >> 16;
                        }
                        break;
                    case 2:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p16[i] = data_union.p32[i] >> 8;
                        }
                        break;
                    case 4:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p32[i] = data_union.p32[i] << 8;
                        }
                        break;
                    default:
                        return -LUAT_ERROR_PARAM_INVALID;
                        break;
                }
                break;
            case 4:
                switch (channel->driver_ctrl->data_align) {
                    case 1:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p8[i] = data_union.p32[i] >> 24;
                        }
                        break;
                    case 2:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p16[i] = data_union.p32[i] >> 16;
                        }
                        break;
                    case 3:
                        for (uint32_t i = 0;i < pcm_data_len;i++){
                            new_data_union.p32[i] = (data_union.p32[i] >> 8) & 0x00FFFFFF;
                        }
                        break;
                    default:
                        return -LUAT_ERROR_PARAM_INVALID;
                        break;
                }
                break;
            default:
                return -LUAT_ERROR_PARAM_INVALID;
                break;
        }

        *written_bytes = new_data_bytes;
        luat_fifo_write(channel->play_fifo, new_data_union.p, new_data_bytes);
        luat_heap_free(new_data_union.p8);
    } else {
        
        LLOGE("data_align not match and channel_nums not match, can not deal with data");
        return -LUAT_ERROR_PARAM_INVALID;
    }
    return LUAT_ERROR_NONE;
}
