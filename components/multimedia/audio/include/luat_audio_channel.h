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
struct luat_audio_channel
{
    luat_fifo_t *play_fifo;                    /**< 播放数据FIFO缓冲区 */
    luat_fifo_t *record_fifo;                  /**< 录音数据FIFO缓冲区 */
    luat_fifo_t *forward_fifo;                 /**< 转发数据FIFO缓冲区（用于音频转发） */
    void *lock_mutex;                          /**< 互斥锁指针，用于线程安全的数据访问 */
    struct luat_audio_driver_ctrl *driver_ctrl; /**< 关联的音频驱动控制器指针 */
    struct luat_audio_request_block *play_request_block;   /**< 当前播放请求块指针 */
    struct luat_audio_request_block *record_request_block; /**< 当前录音请求块指针 */
    uint8_t play_state;                        /**< 当前播放状态（0=停止, 1=播放, 2=暂停） */
    uint8_t record_state;                      /**< 当前录音状态（0=停止, 1=录音, 2=转发） */
};
typedef struct luat_audio_channel luat_audio_channel_t;

/**
 * @brief 初始化音频通道
 * @param channel 音频通道指针，必须指向有效的 luat_audio_channel_t 结构
 * @return int 成功返回 0，失败返回负值错误码
 * 
 * 此函数会创建互斥锁。
 * 调用前确保 channel 指针有效且未被初始化过。
 * 初始化后的通道状态为停止状态。
 */
int luat_audio_channel_init(luat_audio_channel_t *channel);

#endif

/** @} */
