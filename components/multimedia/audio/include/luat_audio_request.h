#ifndef __LUAT_AUDIO_REQUEST__
#define __LUAT_AUDIO_REQUEST__

/**
 * @file luat_audio_request.h
 * @brief LuatOS 音频请求块定义头文件
 * 
 * 定义音频播放/录音请求的数据结构
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


typedef struct {
    union {
        const char *path;                /**< 文件路径*/
        FILE *fd;                       /**< 文件描述符*/
        const uint8_t *rom_data;   /**< ROM数组地址 */
    };
    uint32_t rom_data_len;     /**< ROM数组长度, 0 表示文件模式 */
    uint32_t rom_data_offset;  /**< ROM数组偏移量 */
    uint32_t fail_continue;    /**< 如果解码失败是否跳过继续下一个，如果是最后一个文件，强制停止并设置错误信息 */
} luat_audio_play_file_info_t;

/**
 * @brief 音频请求回调函数
 * 
 * 用于处理音频播放或录音请求的事件，如数据接收、错误通知等。
 * @param event 事件类型，见LUAT_AUDIO_REQUEST_EVENT_xxx
 * @param data 事件数据指针，根据事件类型不同而不同
 * @param len 事件数据长度，根据事件类型不同而不同
 * @param user_data 用户数据指针，用于传递自定义数据
 */
typedef void (*luat_audio_request_cb_t)(uint32_t event, uint8_t *data, uint32_t len, struct luat_audio_request_block *request_block);
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
    void *done_sem;                             /**< 完成信号量，用于同步等待 */
    void *cancel_sem;                             /**< 取消信号量，用于同步等待 */
    uint8_t *temp_buff;                         /**< 临时缓冲区*/
    union {
        struct {                                /**< 流媒体模式下的必须字段 */
            uint32_t *play_buff;                /**< 流媒体数据缓冲区指针 */
            uint32_t one_block_len;             /**< 每个数据块的长度 */
            uint32_t block_nums;                /**< 数据块数量 */
            uint32_t record_fifo_enough_data_level; /**< 录音模式下，回调函数触发条件，FIFO缓冲区数据量是否足够 */
        };
        struct {                                /**< 文件模式下的必须字段 */
            luat_audio_play_file_info_t *file_info;  /**< 音频文件信息数组指针*/
            uint32_t file_info_cnt;                  /**< 音频文件信息数组的元素数量 */
            uint32_t file_done_cnt;                  /**< 已处理的文件信息数量 */
        };
        struct {                                /**< 文本转语音模式下的必须字段 */
            const char *tts_data;               /**< 文本转语音数据指针*/
            uint32_t tts_data_size;             /**< 文本转语音数据长度 */
        };
    };
    luat_fifo_t *record_data_fifo;            /**< 录音数据缓冲区 */
    luat_fifo_t *org_input_data_fifo;            /**< 原始数据输入缓冲区 */
    luat_buffer_t out_buffer;                /**< 输出数据缓冲区 */
    luat_audio_dsp_t *dsp;                  /**< 关联的DSP处理实例 */
    luat_audio_data_codec_t codec;          /**< 关联的编解码器实例 */
    luat_audio_channel_t *data_channel;      /**< 关联的音频通道 */
    uint8_t driver_work_mode;                /**< 驱动工作模式，见LUAT_AUDIO_DRIVER_MODE_xxx */
    uint8_t priority;                        /**< 请求优先级 (0-255)，数值越大优先级越高 */
    uint8_t play_blank_data_cnt;                        /**< 播放空白数据计数 */
    uint8_t is_stream:1;                       /**< 是否为流式请求 */
    uint8_t is_tts:1;                          /**< 是否为文本转语音请求 */
    uint8_t is_user_stop:1;                       /**< 用户是否请求停止 */
    uint8_t is_error_stop:1;                   /**< 是否为错误停止 */
    uint8_t is_data_callback_stop:1;                   /**< 是否为回调函数请求停止 */
    uint8_t is_input_end:1;                   /**< 是否为输入结束请求 */
    uint8_t is_wait_play_end:1;                   /**< 是否等待播放结束 */
    uint8_t is_stream_end:1;                   /**< 是否为流式请求结束 */
};

typedef struct luat_audio_request_block luat_audio_request_block_t;

// 高等级接口，通常1个任务只需要调用1个接口
/**
 * @brief 播放音频文件
 * 
 * 此函数用于播放音频文件，支持指定文件路径和播放参数。
 * 
 * @param request_block 音频请求块指针，用于存储播放参数
 * @param probe 音频驱动匹配结构，用于指定要使用的音频驱动，如果为NULL，则使用默认驱动。一般不需要指定。
 * @param codec_opts 音频解码器选项结构，用于指定要使用的音频解码器，如果为NULL，则会自动选择合适的解码器。一般不需要指定。
 * @param files 音频文件信息指针，每个元素为一个音频文件信息，request直接使用该指针，不复制数据，注意数据的生命周期必须大于请求块的生命周期
 * @param files_num 音频文件信息数组的元素数量
 * @param priority 请求优先级，0-255，数值越大优先级越高
 * @param is_sync 是否为同步请求，0-异步，1-同步
 * @param cb 请求回调函数，用于在播放完成或错误时通知应用层
 * @param user_data 用户数据指针，用于传递自定义数据
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */
int luat_audio_request_play_files(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const luat_audio_data_codec_opts_t *codec_opts, luat_audio_play_file_info_t *files, uint32_t files_num, 
    uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data);

/**
* @brief 播放文本转语音
* 
* 此函数用于播放文本转语音，支持指定文本内容和播放参数。
* 
* @param request_block 音频请求块指针，用于存储播放参数
* @param probe 音频驱动匹配结构，用于描述驱动的匹配条件，如果为NULL，则使用默认驱动。
* @param text 要转换为语音的文本内容指针，request直接使用该指针，不复制数据，注意数据的生命周期必须大于请求块的生命周期
* @param text_len 文本长度，单位字节
* @param priority 请求优先级，0-255，数值越大优先级越高
* @param is_sync 是否为同步请求，0-异步，1-同步
* @param cb 请求回调函数，用于在播放完成或错误时通知应用层
* @param user_data 用户数据指针，用于传递自定义数据
* @return LUAT_ERROR_NONE 表示成功，其他值表示失败
*/
int luat_audio_request_play_tts(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const char *text, uint32_t text_len, 
    uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data);

/**
* @brief 播放流式音频
* 
* 此函数用于播放流式音频，支持指定流式音频数据指针和播放参数。
* 
* @param request_block 音频请求块指针，用于存储播放参数
* @param probe 音频驱动匹配结构，用于描述驱动的匹配条件，如果为NULL，则使用默认驱动。
* @param codec_opts 音频解码器选项结构，用于指定要使用的音频解码器，如果为NULL，则会自动选择合适的解码器。一般不需要指定。
* @param priority 请求优先级，0-255，数值越大优先级越高
* @param is_sync 是否为同步请求，0-异步，1-同步
* @param cb 请求回调函数，用于在播放完成或错误时通知应用层
* @param user_data 用户数据指针，用于传递自定义数据
* @return LUAT_ERROR_NONE 表示成功，其他值表示失败
*/
int luat_audio_request_play_stream(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const luat_audio_data_codec_opts_t *codec_opts,
    luat_audio_common_param_t *common_param, uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data);    
/**
 * @brief 录音音频
 * 
 * 此函数用于录音音频，支持指定录音参数和回调函数。
 * 
 * @param request_block 音频请求块指针，用于存储录音参数
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件，如果为NULL，则使用默认驱动。
 * @param record_callback_len 录音回调一次的最小音频数据长度，单位字节，允许超过驱动的rx_one_block_max_len
 * @param priority 请求优先级，0-255，数值越大优先级越高
 * @param cb 请求回调函数，用于在录音完成或错误时通知应用层
 * @param user_data 用户数据指针，用于传递自定义数据
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */
int luat_audio_request_record(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, uint32_t record_callback_len,uint8_t priority, 
    luat_audio_request_cb_t cb, void *user_data);
/**
 * @brief 通话模式，强制在最高等级
 * 
 * 
 * @param request_block 音频请求块指针，用于存储通话参数
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件，如果为NULL，则使用默认驱动。
 * @param tx_buff 通话数据缓冲区指针，用于存储通话数据，一般不需要，目前只有air780exxLTE通话需要需要指定
 * @param one_block_len 双工模式下每个数据块的长度，单位字节，同时也是录音回调一次的音频数据长度，注意不能超过驱动的tx_one_block_max_len和rx_one_block_max_len
 * @param block_num 双工模式下数据块数量
 * @param cb 请求回调函数，用于在播放完成或错误时通知应用层
 * @param user_data 用户数据指针，用于传递自定义数据
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */
int luat_audio_request_speech(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, 
    uint32_t *tx_buff, uint32_t one_block_len, uint8_t block_num,
    luat_audio_request_cb_t cb, void *user_data);

// 低等级接口，除非用户需要自行处理解码器，dsp等，否则一般不需要主动调用
/**
 * @brief 只做必要的初始化工作
 * 
 * 
 * @param request_block 音频请求块指针，用于存储请求参数
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件，如果为NULL，则使用默认驱动。
 * @param driver_work_mode 驱动工作模式，见LUAT_AUDIO_DRIVER_MODE_xxx
 * @param cb 请求回调函数，用于在请求完成或错误时通知应用层
 * @param user_data 用户数据指针，用于传递自定义数据
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */
int luat_audio_request_prepare(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, uint8_t driver_work_mode, 
    luat_audio_request_cb_t cb, void *user_data);

/**
 * @brief 初始化音频请求块，一般不需要主动调用，由luat_audio_request_prepare自动调用
 * 
 * 此函数用于初始化音频请求结构体，为后续的音频处理做准备。
 * 
 * @param request_block 音频请求结构体指针，包含请求的详细信息
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */
int luat_audio_request_init(luat_audio_request_block_t *request_block);

/**
 * @brief 释放音频请求结构体指针
 * 
 * 此函数用于释放音频请求结构体指针，释放请求资源。
 * 
 * @param request_block 音频请求结构体指针，包含请求的详细信息
 */
void luat_audio_request_deinit(luat_audio_request_block_t *request_block);
/**
 * @brief 提交音频请求
 * 
 * 此函数用于提交音频请求，请求音频框架处理音频数据。
 * 
 * @param request_block 音频请求结构体指针，包含请求的详细信息
 * @param is_sync 是否同步等待，0-异步，1-同步
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */ 
int luat_audio_request_start(luat_audio_request_block_t *request_block, uint8_t is_sync);

/**
 * @brief 取消音频请求
 * 
 * 此函数用于取消已提交的音频请求，同时释放掉请求的资源，自动调用luat_audio_request_deinit
 * 
 * @param request_block 音频请求结构体指针，包含请求的详细信息
 */
void luat_audio_request_cancel(luat_audio_request_block_t *request_block);
/** @} */
#endif
