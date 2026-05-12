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

typedef struct
{
	char *path;		//文件路径，如果为NULL，则表示是ROM数组
	uint32_t address;	//ROM数组地址
	uint32_t rom_data_len;	//ROM数组长度
	uint32_t fail_continue;	//如果解码失败是否跳过继续下一个，如果是最后一个文件，强制停止并设置错误信息
}luat_audio_play_file_info_t;

typedef void (*luat_audio_request_cb_t)(uint32_t request_id, uint8_t is_stream_end);
/**
 * @brief 音频请求块结构
 * 
 * 表示一个音频播放或录音请求，包含所有必要的上下文信息。
 * 请求块通过链表节点组织，可以支持多个并发请求的排队和管理。
 */
struct luat_audio_request_block {
    luat_llist_head node;                       /**< 链表节点，用于请求队列管理 */
    uint32_t request_id;                       /**< 请求ID，用于标识请求 */
    luat_audio_request_cb_t cb;                 /**< 请求回调函数 */
    void *user_data;                           /**< 用户数据指针，用于传递自定义数据 */
    luat_audio_play_file_info_t *file_info;     /**< 音频文件信息 */
    void *tts_data;                             /**< 文本转语音数据指针 */
    uint32_t tts_data_size_or_file_info_cnt;    /**< 文本转语音数据大小或文件信息数量，根据fail_continue判断 */
    uint32_t file_info_done_cnt;                /**< 已处理的文件信息数量 */
    FILE *fd;                                /**< 音频文件句柄 */
    luat_fifo_t *input_data_fifo;            /**< 输入数据FIFO缓冲区 */
    luat_buffer_t out_buffer;                /**< 输出数据缓冲区 */
    luat_audio_dsp_t *dsp;                  /**< 关联的DSP处理实例 */
    luat_audio_data_codec_t codec;          /**< 关联的编解码器实例 */
    luat_audio_channel_t *data_channel;      /**< 关联的音频通道 */
    //uint8_t decode_state;                    /**< 解码状态 */
    uint8_t is_stream;                       /**< 是否为流式请求 */
    uint8_t is_stream_end;                   /**< 是否为流式请求结束 */
    uint8_t user_stop;                       /**< 用户是否请求停止 */
    uint8_t priority;                        /**< 请求优先级 (0-255) */
};

typedef struct luat_audio_request_block luat_audio_request_block_t;

#endif

/** @} */
