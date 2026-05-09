#include "luat_audio_channel.h"
#include "luat_rtos.h"

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
        channel->play_fifo = luat_fifo_create(fifo_size_power);
        channel->record_fifo = luat_fifo_create(fifo_size_power);
        channel->forward_fifo = luat_fifo_create(fifo_size_power);      
        channel->lock_mutex = luat_mutex_create();
        channel->play_fifo_need_data_level = channel->play_fifo->size >> 1;
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
    if (channel->lock_mutex)
    {
        luat_mutex_release(channel->lock_mutex);
        channel->lock_mutex = NULL;
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