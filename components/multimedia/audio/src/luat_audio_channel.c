#include "luat_audio_channel.h"
#include "luat_rtos.h"

/**
 * @brief 初始化音频通道
 * @param channel 音频通道指针
 * @return 成功返回 0，失败返回负值错误码
 */
int luat_audio_channel_init(luat_audio_channel_t *channel)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    
    channel->play_fifo = NULL;
    channel->record_fifo = NULL;
    channel->forward_fifo = NULL;
    channel->lock_mutex = luat_mutex_create();
    channel->driver_ctrl = NULL;
    
    return 0;
}
