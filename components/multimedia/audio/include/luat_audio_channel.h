#ifndef __LUAT_AUDIO_CHANNEL__
#define __LUAT_AUDIO_CHANNEL__

/**
 * @file luat_audio_channel.h
 * @brief LuatOS 音频通道管理头文件
 * 
 * 提供音频通道的初始化、数据读写和资源管理功能。
 * 音频通道是音频数据流的基本单元，每个通道包含独立的FIFO缓冲区，
 * 支持多输入源场景下的数据隔离和选择。
 * 
 * @defgroup luat_audio_channel 音频通道管理模块
 * @ingroup audio
 * @{
 */

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_common_api.h"
#include "luat_audio_define.h"
#include "luat_audio_driver.h"

/**
 * @brief 音频通道结构
 * 
 * 此结构代表一个音频通道，用于管理音频数据流。
 * 在多输入源场景中，每个输入源可以绑定到独立的通道，
 * 通过通道选择机制实现单输出切换。
 */
struct luat_audio_channel {
    luat_fifo_t *play_fifo;                    /**< 播放数据FIFO缓冲区，只能在驱动回调的中断里读出，只有1个消费者 */
    uint32_t play_fifo_low_level;        /**< 播放缓存低水位, 默认为播放缓冲区大小的25%时, 触发数据请求 */
    uint32_t play_fifo_high_level;        /**< 播放缓存高水位, 不再解码数据 */
    void *play_lock_mutex;                          /**< 播放数据写入保护 */
    struct luat_audio_driver_ctrl *driver_ctrl; /**< 关联的音频驱动控制器指针 */
    struct luat_audio_request_block *play_request_block;   /**< 当前播放请求块指针 */
    struct luat_audio_request_block *record_request_block; /**< 当前录音请求块指针 */
    uint32_t soft_volume;                          /**< 软件音量控制（0-1000） 1000为10倍 */
    // uint8_t play_state;                        /**< 当前播放状态（0=停止, 1=播放） */
    // uint8_t record_state;                      /**< 当前录音状态（0=停止, 1=录音, 2=转发） */
    uint8_t error_record_overflow;             /**< 录音溢出错误标志位 */
    uint8_t data_align;                        /**< 数据对齐方式（2=16位, 3=24位, 4=32位, 其他8位） */
    uint8_t record_jump_cnt;
    uint8_t user_play_stop:1;
    uint8_t user_record_stop:1;
};
typedef struct luat_audio_channel luat_audio_channel_t;

/**
 * @brief 创建音频通道的FIFO缓冲区
 * @param channel 音频通道指针，必须指向有效的 luat_audio_channel_t 结构
 * @param play_fifo_size_power 播放FIFO缓冲区大小，必须是2的幂次方
 * @param low_level 播放缓存低水位, 默认为播放缓冲区大小的25%时, 触发数据请求
 * @param high_level 播放缓存高水位, 不再解码数据
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回其他错误码
 * 
 */
int luat_audio_channel_create_fifo(luat_audio_channel_t *channel, uint32_t play_fifo_size_power, uint32_t low_level, uint32_t high_level);

/**
 * @brief 销毁音频通道的FIFO缓冲区
 * @param channel 音频通道指针，必须指向有效的 luat_audio_channel_t 结构
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回其他错误码
 * 
 */
int luat_audio_channel_destroy_fifo(luat_audio_channel_t *channel);

/**
 * @brief 播放音频通道数据
 * @param channel 音频通道指针，必须指向有效的 luat_audio_channel_t 结构
 * @param is_play 是否播放（1=播放，0=停止）
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回其他错误码
 * 
 * 此函数会根据 is_play 参数判断是否播放音频数据。
 * 调用前确保 channel 指针有效且已被初始化。
 */
int luat_audio_channel_play(luat_audio_channel_t *channel, uint8_t is_play);

/**
 * @brief 录音音频通道数据
 * @param channel 音频通道指针，必须指向有效的 luat_audio_channel_t 结构
 * @param is_record 是否录音（1=录音，0=停止）
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回其他错误码
 * 
 * 此函数会根据 record_state 参数判断是否录音音频数据。
 * 调用前确保 channel 指针有效且已被初始化。
 */
int luat_audio_channel_record(luat_audio_channel_t *channel, uint8_t is_record);
/**
 * @brief 设置音频通道的软件音量
 * @param channel 音频通道指针，必须指向有效的 luat_audio_channel_t 结构
 * @param volume 软件音量控制（0-1000） 1000为10倍
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回其他错误码
 * 
 * 此函数会根据 volume 参数设置音频通道的软件音量。
 * 调用前确保 channel 指针有效且已被初始化。
 */
int luat_audio_channel_set_soft_volume(luat_audio_channel_t *channel,uint32_t volume);
/**
 * @brief 写入音频通道数据
 * @param channel 音频通道指针，必须指向有效的 luat_audio_channel_t 结构
 * @param data 数据指针，指向要写入的音频数据
 * @param len_bytes 数据长度（字节）
 * @param written_bytes 实际写入的字节数指针，用于返回写入的字节数
 * @param is_signed 是否有符号（1=有符号，0=无符号）
 * @param data_align 数据对齐方式（2=16位, 3=24位, 4=32位）
 * @param channel_nums 通道数（1=单声道, 2=双声道）
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回其他错误码
 * 
 * 此函数会将指定的音频数据写入音频通道的播放FIFO缓冲区。
 * 调用前确保 channel 指针有效且已被初始化。
 */
int luat_audio_channel_write_data(luat_audio_channel_t *channel, void *data, uint32_t len_bytes, uint32_t *written_bytes, uint8_t is_signed,uint8_t data_align, uint8_t channel_nums);
#endif

/** @} */
