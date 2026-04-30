#ifndef __LUAT_AUDIO_REQUEST__
#define __LUAT_AUDIO_REQUEST__

/**
 * @file luat_audio_request.h
 * @brief LuatOS 音频请求块定义头文件
 * 
 * 定义音频播放/录音请求的数据结构，包含文件句柄、编解码器、DSP处理等信息。
 * 
 * @defgroup luat_audio_request 音频请求模块
 * @ingroup audio
 * @{
 */

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_common_api.h"
#include "luat_audio_define.h"
#include "luat_audio_channel.h"
#include "luat_audio_data_codec.h"
#include "luat_audio_dsp.h"
#include "luat_audio_driver.h"
#include "luat_fs.h"

/**
 * @brief 音频请求块结构
 * 
 * 表示一个音频播放或录音请求，包含所有必要的上下文信息。
 * 请求块通过链表节点组织，可以支持多个并发请求的排队和管理。
 */
struct luat_audio_request_block
{
    luat_llist_head node;                    /**< 链表节点，用于请求队列管理 */
    FILE *fd;                                /**< 音频文件句柄 */
    luat_fifo_t *input_data_fifo;            /**< 输入数据FIFO缓冲区 */
    luat_buffer_t out_buffer;                /**< 输出数据缓冲区 */
    luat_audio_dsp_t *dsp;                  /**< 关联的DSP处理实例 */
    luat_audio_data_codec_t *codec;          /**< 关联的编解码器实例 */
    luat_audio_channel_t *data_channel;      /**< 关联的音频通道 */
    uint8_t priority;                        /**< 请求优先级 (0-255) */
};

typedef struct luat_audio_request_block luat_audio_request_block_t;

#endif

/** @} */
