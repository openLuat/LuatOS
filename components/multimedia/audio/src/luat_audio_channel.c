#include "luat_audio_channel.h"
#include "luat_audio_define.h"
#include "luat_common_api.h"
#include "luat_rtos.h"
#include "luat_rtos_legacy.h"
#include <stdint.h>
#define LUAT_LOG_TAG "audio_ch"
#include "luat_log.h"

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

int luat_audio_channel_create_fifo(luat_audio_channel_t *channel, uint32_t play_fifo_size_power, uint32_t low_level, uint32_t high_level)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (!play_fifo_size_power) {
        play_fifo_size_power = LUAT_AUDIO_CHANNEL_FIFO_DEFAULT_SIZE_POWER;
    }

    luat_mutex_lock(channel->play_lock_mutex);
    if (channel->play_fifo) luat_fifo_destroy(channel->play_fifo);
    channel->play_fifo = luat_fifo_create(play_fifo_size_power);
    channel->play_fifo_low_level = low_level;
    channel->play_fifo_high_level = high_level;
    luat_mutex_unlock(channel->play_lock_mutex);
    return LUAT_ERROR_NONE;
}

int luat_audio_channel_destroy_fifo(luat_audio_channel_t *channel)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    luat_mutex_lock(channel->play_lock_mutex);
    luat_fifo_destroy(channel->play_fifo);
    channel->play_fifo = NULL;
    luat_mutex_unlock(channel->play_lock_mutex);
    return LUAT_ERROR_NONE;
}

int luat_audio_channel_play(luat_audio_channel_t *channel, uint8_t is_play)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    channel->user_play_stop = !is_play;
    return LUAT_ERROR_NONE;
}

int luat_audio_channel_record(luat_audio_channel_t *channel, uint8_t is_record)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    channel->user_record_stop = !is_record;
    return LUAT_ERROR_NONE;
}

int luat_audio_channel_set_soft_volume(luat_audio_channel_t *channel,uint32_t volume)
{
    if (!channel || volume > 1000) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    channel->soft_volume = volume;
    LLOGC(luat_audio_debug_flag,"set soft volume %u", volume);
    return LUAT_ERROR_NONE;
}

static void _audio_channel_play_vol_16bit(int16_t *data, uint32_t len_bytes, uint16_t vol, uint8_t is_signed)
{
    uint32_t i = 0;
    uint32_t pos = 0;
    
    if (is_signed) {
        int32_t temp;
        while(pos < len_bytes) {
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
    } else {
        uint32_t temp;
        while(pos < len_bytes) {
            temp = data[i];
            temp = temp * vol / 100;
            if (temp > 0xFFFF) {
                temp = 0xFFFF;
            }
            data[i] = temp;
            i++;
            pos += 2;
        }
    }

}

static void _audio_channel_play_vol_24bit(int32_t *data, uint32_t len_bytes, uint32_t vol, uint8_t is_signed)
{
    uint32_t i = 0;
    uint32_t pos = 0;
    if (is_signed) {
        int64_t temp;
        while(pos < len_bytes) {
            temp = data[i] << 8;
            temp = temp * vol / 100;
            if (temp > 2147483647)
            {
                temp = 2147483647;
            }
            else if (temp < -2147483648)
            {
                temp = -2147483648;
            }
            data[i] = temp >> 8;
            i++;
            pos += 4;
        }
    } else {
        uint64_t temp;
        while(pos < len_bytes) {
            temp = data[i];
            temp = temp * vol / 100;
            if (temp > 0xFFFFFFFF) {
                temp = 0xFFFFFFFF;
            }
            data[i] = temp;
            i++;
            pos += 4;
        }
    }   
}

static void _audio_channel_play_vol_32bit(int32_t *data, uint32_t len_bytes, uint32_t vol, uint8_t is_signed)
{
    uint32_t i = 0;
    uint32_t pos = 0;
    if (is_signed) {
        int64_t temp;
        while(pos < len_bytes) {
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
    } else {
        uint64_t temp;
        while(pos < len_bytes) {
            temp = data[i];
            temp = temp * vol / 100;
            if (temp > 0xFFFFFFFF) {
                temp = 0xFFFFFFFF;
            }
            data[i] = temp;
            i++;
            pos += 4;
        }
    }   
}

void luat_audio_channel_data_change_signed(luat_data_union_t data_union, uint32_t len_bytes, uint8_t data_align,uint8_t is_signed)
{
    if (is_signed) {
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


void luat_audio_channel_data_change_align(luat_data_union_t data_union, luat_data_union_t new_data_union, uint32_t len_bytes, uint32_t pcm_data_len, uint8_t data_align, uint8_t new_data_align)
{
    switch (data_align) {
        case 1:
            switch (new_data_align) {
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
                    break;
            }
            break;
        case 2:
            switch (new_data_align) {
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
                    break;
            }
            break;
        case 3:
            switch (new_data_align) {
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
                    break;
            }
            break;
        case 4:
            switch (new_data_align) {
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
                    break;
            }
            break;
        default:
            break;
    }
}

void luat_audio_channel_data_change_channel_nums(luat_data_union_t data_union, luat_data_union_t new_data_union, uint32_t len_bytes, uint32_t pcm_data_len, uint8_t data_align, uint8_t channel_nums, uint8_t new_channel_nums)
{
    uint32_t i,j;
    uint8_t k;
    if (channel_nums > new_channel_nums) {
        switch (data_align) {
            case 1:
                if (1 == new_channel_nums) {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j++){
                        new_data_union.i8[j] = data_union.i8[i];
                    }
                } else {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j += new_channel_nums){
                        memcpy(&new_data_union.i8[j], &data_union.i8[i], new_channel_nums);
                    }
                }
                break;
            case 2:
                if (1 == new_channel_nums) {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j++){
                        new_data_union.i16[j] = data_union.i16[i];
                    }
                } else {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j+= new_channel_nums){
                        memcpy(&new_data_union.i16[j], &data_union.i16[i], new_channel_nums << 1);
                    }
                }
                break;
            case 3:
            case 4:
                if (1 == new_channel_nums) {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j++){
                        new_data_union.i32[j] = data_union.i32[i];
                    }
                } else {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j+= new_channel_nums){
                        memcpy(&new_data_union.i32[j], &data_union.i32[i], new_channel_nums << 2);
                    }
                }
                break;
            default:
                break;
        }
    } else {
        switch (data_align) {
            case 1:
                if (1 == channel_nums) {
                    if (2 == new_channel_nums) {
                        for(i = 0, j = 0; i < pcm_data_len; i++, j += new_channel_nums){
                            new_data_union.i8[j] = data_union.i8[i];
                            new_data_union.i8[j+1] = data_union.i8[i];
                        }
                    } else {
                        for(i = 0, j = 0; i < pcm_data_len; i++, j += new_channel_nums){
                            for (k = 0; k < new_channel_nums; k++){
                                new_data_union.i8[j+k] = data_union.i8[i];
                            }
                        }
                    }
                } else {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j += new_channel_nums){
                        memcpy(&new_data_union.i8[j], &data_union.i8[i], channel_nums);
                        for (k = channel_nums; k < new_channel_nums; k++){
                            new_data_union.i8[j+k] = data_union.i8[i + channel_nums - 1];
                        }
                    }
                }
                break;
            case 2:
                if (1 == channel_nums) {
                    if (2 == new_channel_nums) {
                        for(i = 0, j = 0; i < pcm_data_len; i++, j+= new_channel_nums){
                            new_data_union.i16[j] = data_union.i16[i];
                            new_data_union.i16[j+1] = data_union.i16[i];
                        }
                    } else {
                        for(i = 0, j = 0; i < pcm_data_len; i++, j+= new_channel_nums){
                            for (k = 0; k < new_channel_nums; k++){
                                new_data_union.i16[j+k] = data_union.i16[i];
                            }
                        }
                    }
                } else {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j+= new_channel_nums){
                        memcpy(&new_data_union.i16[j], &data_union.i16[i], channel_nums << 1);
                        for (k = channel_nums; k < new_channel_nums; k++){
                            new_data_union.i16[j+k] = data_union.i16[i + channel_nums - 1];
                        }
                    }
                }
                break;
            case 3:
            case 4:
                if (1 == channel_nums) {
                    if (2 == new_channel_nums) {
                        for(i = 0, j = 0; i < pcm_data_len; i++, j+= new_channel_nums){
                            new_data_union.i32[j] = data_union.i32[i];
                            new_data_union.i32[j+1] = data_union.i32[i];
                        }
                    } else {
                        for(i = 0, j = 0; i < pcm_data_len; i++, j+= new_channel_nums){
                            for (k = 0; k < new_channel_nums; k++){
                                new_data_union.i32[j+k] = data_union.i32[i];
                            }
                        }
                    }
                } else {
                    for(i = 0, j = 0; i < pcm_data_len; i += channel_nums, j+= new_channel_nums){
                        memcpy(&new_data_union.i32[j], &data_union.i32[i], channel_nums << 2);
                        for (k = channel_nums; k < new_channel_nums; k++){
                            new_data_union.i32[j+k] = data_union.i32[i + channel_nums - 1];
                        }
                    }
                }
                break;
            default:
                break;
        }        
    }
}


int luat_audio_channel_write_data(luat_audio_channel_t *channel, void *data, uint32_t len_bytes, uint32_t *written_bytes, uint8_t is_signed,uint8_t data_align, uint8_t channel_nums)
{
    // if (!channel || !data || !written_bytes) {
    //     return -LUAT_ERROR_PARAM_INVALID;
    // }
    uint32_t rest_space = luat_fifo_check_free_space(channel->play_fifo);
    uint32_t one_channel_pcm_len = rest_space / channel->driver_ctrl->common_param.channel_nums / channel->driver_ctrl->common_param.data_align;
    uint32_t max_data_bytes = one_channel_pcm_len * channel_nums * data_align;
    // LLOGC(luat_audio_debug_flag,"input param %d-%d output param %d-%d rest space %u, one_channel_pcm_len %u, max_data_bytes %u, len_bytes %u", 
    //     data_align, channel_nums, channel->driver_ctrl->common_param.data_align, channel->driver_ctrl->common_param.channel_nums, 
    //     rest_space, one_channel_pcm_len, max_data_bytes, len_bytes);
    if (len_bytes > max_data_bytes) {
        *written_bytes = 0;
        return LUAT_ERROR_NONE;
    }
    *written_bytes = len_bytes;
    luat_data_union_t data_union;
    data_union.p = data;
    // LLOGC(luat_audio_debug_flag,"write data to channel len_bytes %u, is_signed %u, data_align %u, channel_nums %u volume %u", len_bytes, is_signed, data_align, channel_nums, channel->soft_volume);
    if (channel->soft_volume != 100) {     // 音量软件调节
        switch (data_align) {
            case 2:
                _audio_channel_play_vol_16bit(data_union.i16, len_bytes, channel->soft_volume, is_signed);
                break;
            case 3:
                _audio_channel_play_vol_24bit(data_union.i32, len_bytes, channel->soft_volume, is_signed);
                break;
            case 4:
                _audio_channel_play_vol_32bit(data_union.i32, len_bytes, channel->soft_volume, is_signed);
                break;
            default:
                return -LUAT_ERROR_PARAM_INVALID;
                break;
        }
    }
    if (is_signed != channel->driver_ctrl->opts->is_tx_signed) { // 数据有无符号转换
        luat_audio_channel_data_change_signed(data_union, len_bytes, data_align, channel->driver_ctrl->opts->is_tx_signed);
    }

    if (data_align == channel->driver_ctrl->common_param.data_align && channel_nums == channel->driver_ctrl->common_param.channel_nums) {
        //luat_mutex_lock(channel->play_lock_mutex);
        if (channel->driver_ctrl->opts->dac_data_align) {
            channel->driver_ctrl->opts->dac_data_align(channel->driver_ctrl, data, len_bytes, data_align);
        }
		luat_fifo_write(channel->play_fifo, data, len_bytes);
		//luat_mutex_unlock(channel->play_lock_mutex);
        return LUAT_ERROR_NONE;
    } else { 
        uint32_t pcm_data_len, new_data_len, new_data_bytes = 0;
        luat_data_union_t new_data_union;
        new_data_union.p = NULL;
        luat_data_union_t new_data_union2;
        new_data_union2.p = NULL;
        if (channel_nums != channel->driver_ctrl->common_param.channel_nums) {
            LLOGC(luat_audio_debug_flag,"channel_nums %u change to %u, len_bytes %u, data_align %u", channel_nums, channel->driver_ctrl->common_param.channel_nums, len_bytes, data_align);
            switch (data_align) {
                case 1:
                    pcm_data_len = len_bytes;
                    new_data_len = (pcm_data_len / channel_nums) * channel->driver_ctrl->common_param.channel_nums;
                    new_data_bytes = new_data_len;
                    new_data_union.p = luat_heap_malloc(new_data_bytes);
                    if (!new_data_union.p) {
                        return -LUAT_ERROR_NO_MEMORY;
                    }
                    break;
                case 2:
                    pcm_data_len = len_bytes >> 1;
                    new_data_len = (pcm_data_len / channel_nums) * channel->driver_ctrl->common_param.channel_nums;
                    new_data_bytes = new_data_len << 1;

                    new_data_union.p = luat_heap_malloc(new_data_bytes);
                    if (!new_data_union.p) {
                        return -LUAT_ERROR_NO_MEMORY;
                    }
                    break;
                case 3:
                case 4:
                    pcm_data_len = len_bytes >> 2;
                    new_data_len = (pcm_data_len / channel_nums) * channel->driver_ctrl->common_param.channel_nums;
                    new_data_bytes = new_data_len << 2;
                    new_data_union.p = luat_heap_malloc(new_data_bytes);
                    if (!new_data_union.p) {
                        return -LUAT_ERROR_NO_MEMORY;
                    }
                    break;
                default:
                    return -LUAT_ERROR_PARAM_INVALID;
                    break;
            }
            luat_audio_channel_data_change_channel_nums(data_union, new_data_union, len_bytes, pcm_data_len, data_align, channel_nums, channel->driver_ctrl->common_param.channel_nums);       
            channel_nums = channel->driver_ctrl->common_param.channel_nums;
            len_bytes = new_data_bytes;
        }
        if (data_align != channel->driver_ctrl->common_param.data_align) {
            LLOGC(luat_audio_debug_flag,"data_align %u change to %u, len_bytes %u, channel_nums %u", data_align, channel->driver_ctrl->common_param.data_align, len_bytes, channel_nums);
            pcm_data_len = 0;
            new_data_bytes = 0;
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
                    luat_heap_free(new_data_union.p8);
                    return -LUAT_ERROR_PARAM_INVALID;
                    break;
            }
            switch (channel->driver_ctrl->common_param.data_align) {
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
                    luat_heap_free(new_data_union.p8);
                    return -LUAT_ERROR_PARAM_INVALID;
                    break;
            }
            new_data_union2.p = luat_heap_malloc(new_data_bytes);
            if (!new_data_union2.p) {
                luat_heap_free(new_data_union.p8);
                return -LUAT_ERROR_NO_MEMORY;
            }
            if (new_data_union.p8) {
                luat_audio_channel_data_change_align(new_data_union, new_data_union2, len_bytes, pcm_data_len, data_align, channel->driver_ctrl->common_param.data_align);
            } else {
                luat_audio_channel_data_change_align(data_union, new_data_union2, len_bytes, pcm_data_len, data_align, channel->driver_ctrl->common_param.data_align);
            }
            
            data_align = channel->driver_ctrl->common_param.data_align;
            len_bytes = new_data_bytes;
        }

        if (channel->driver_ctrl->opts->dac_data_align) {
            channel->driver_ctrl->opts->dac_data_align(channel->driver_ctrl, new_data_union.p, new_data_bytes, data_align);
        }
        luat_fifo_write(channel->play_fifo, new_data_union.p, new_data_bytes);
        if (new_data_union.p8) {
            luat_heap_free(new_data_union.p8);
        }
        if (new_data_union2.p8) {
            luat_heap_free(new_data_union2.p8);
        }
    }
    return LUAT_ERROR_NONE;
}
