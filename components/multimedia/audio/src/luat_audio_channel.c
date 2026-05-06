#include "luat_audio_channel.h"
#include "luat_rtos.h"

/**
 * @brief 初始化音频通道
 * @param channel 音频通道指针
 * @param fifo_size_power FIFO大小的2的幂次方，用于计算FIFO的大小，默认值为LUAT_AUDIO_CHANNEL_FIFO_DEFAULT_SIZE_POWER
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
 */
int luat_audio_channel_init(luat_audio_channel_t *channel, uint32_t fifo_size_power)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (!fifo_size_power) {
        fifo_size_power = LUAT_AUDIO_CHANNEL_FIFO_DEFAULT_SIZE_POWER;
    }
    luat_rtos_task_suspend_all();
    if (!channel->lock_mutex) {
        channel->play_fifo = luat_create_fifo(fifo_size_power);
        channel->record_fifo = luat_create_fifo(fifo_size_power);
        channel->forward_fifo = luat_create_fifo(fifo_size_power);      
        channel->lock_mutex = luat_mutex_create();
    }
    luat_rtos_task_resume_all();
    return LUAT_ERROR_NONE;
}

/**
 * @brief 反初始化音频通道
 * @param channel 音频通道指针，必须指向有效的 luat_audio_channel_t 结构
 * @return int 成功返回 0，失败返回负值错误码
 * 
 * 此函数会释放音频通道占用的资源，包括互斥锁和FIFO缓冲区。
 * 调用前确保 channel 指针有效且已被初始化。
 */
int luat_audio_channel_deinit(luat_audio_channel_t *channel)
{
    if (!channel) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    luat_rtos_task_suspend_all();
    luat_deinit_fifo(channel->play_fifo);
    luat_deinit_fifo(channel->record_fifo);
    luat_deinit_fifo(channel->forward_fifo);
    if (channel->lock_mutex)
    {
        luat_mutex_release(channel->lock_mutex);
        channel->lock_mutex = NULL;
    }
    luat_rtos_task_resume_all();
    return LUAT_ERROR_NONE;
}
