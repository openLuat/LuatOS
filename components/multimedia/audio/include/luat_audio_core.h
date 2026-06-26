#ifndef __LUAT_AUDIO_CORE__
#define __LUAT_AUDIO_CORE__

/**
 * @file luat_audio_core.h
 * @brief LuatOS 音频框架核心API头文件
 * 
 * 提供音频框架的初始化和核心接口声明。
 * 
 * @defgroup luat_audio_core 音频核心API组
 * @ingroup audio
 * @{
 */

#include "luat_audio_define.h"
#include "luat_audio_channel.h"
#include "luat_audio_data_codec.h"
#include "luat_audio_driver.h"
#include "luat_audio_request.h"

/**
 * @brief 初始化音频框架基础模块，必须在BSP里，并且在luavm初始化前调用
 * 
 * 此函数负责初始化音频框架的核心组件，包括通道管理、编解码器注册等。
 * 应在系统启动时调用一次。
 */
void luat_audio_base_init(void);

/**
 * @brief 音频框架详细调试信息输出开关
 * 
 * 此函数用于切换音频框架的详细调试信息输出开关，开启后会打印详细的调试信息志，关闭后会打印正常日志。
 * 
 * @param on_off 0 表示关闭调试信息输出，1 表示开启调试信息输出
 */
void luat_audio_debug_switch(uint8_t on_off);
/**
 * @brief 注册音频驱动
 * 
 * 此函数用于向音频框架注册一个音频驱动，注册后该驱动可被音频通道使用。第一个注册的驱动会被默认使用。
 * 
 * @param opts 音频驱动操作接口结构体指针，包含驱动的具体实现函数
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件
 * @param driver_data 驱动私有数据指针，用于存储驱动的私有数据
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */
int luat_audio_driver_register(const luat_audio_driver_opts_t *opts, luat_audio_driver_probe_t probe, void *driver_data);

/**
 * @brief 探测音频驱动
 * 
 * 此函数用于探测音频框架是否支持指定音频驱动。
 * 
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件，如果为NULL，则返回第一个注册的驱动控制器。
 * @return 驱动控制器指针，成功返回非NULL，失败返回NULL
 */
luat_audio_driver_ctrl_t *luat_audio_driver_probe(luat_audio_driver_probe_t *probe);

/**
 * @brief 设置默认音频驱动
 * 
 * 此函数用于设置音频框架的默认音频驱动，后续的音频请求会使用该驱动。
 * 
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */
int luat_audio_driver_set_default(luat_audio_driver_probe_t *probe);

/**
 * @brief 获取所有已注册的音频驱动控制器
 * 
 * 此函数用于获取所有已注册的音频驱动控制器，包括默认驱动。
 * 
 * @param all_nums 输出参数，用于返回已注册的音频驱动控制器数量
 * @param default_index 输出参数，用于返回默认音频驱动的索引
 * @return 音频驱动控制器指针数组，成功返回非NULL，失败返回NULL
 */
luat_audio_driver_ctrl_t *luat_audio_driver_get_ctrl_info(uint8_t *all_nums, uint8_t *default_index);
/**
 * @brief 获取音频文件的播放信息
 * 
 * 此函数用于获取音频文件的播放信息，如采样率、声道数、采样深度等。
 * 
 * @param codec 音频编解码器指针
 * @param play_file 音频文件播放结构体指针
 * @return LUAT_ERROR_NONE 表示成功，其他值表示失败
 */
int luat_audio_get_play_info_from_file(luat_audio_data_codec_t *codec, luat_audio_play_file_info_t *play_file);

/**
 * @brief 音频驱动事件回调函数，已经有默认实现，CSDK用户可以自定义实现，但是不建议修改默认实现的基本逻辑，除非打算自己实现audio功能
 * 
 * 此函数用于处理音频驱动的事件，如数据接收、错误通知等。
 * 
 * @param event 音频驱动事件类型
 * @param rx_data 接收的音频数据指针
 * @param param 事件参数
 * @param ctrl 音频驱动控制器指针
 */
void luat_audio_driver_event_callback(uint32_t event, uint8_t *rx_data, uint32_t param, luat_audio_driver_ctrl_t *ctrl);

/**
 * @brief 检查所有音频请求是否完成
 * 
 * 此函数用于检查所有音频请求是否完成，包括解码、播放等。
 * 
 * @param ctrl 音频驱动控制器指针, 用于指定要检查的音频驱动，如果为NULL，则检查所有音频驱动的请求
 * @return 0 表示有请求未完成，1 表示所有请求已完成
 */
uint8_t luat_audio_is_request_all_done(luat_audio_driver_ctrl_t *ctrl);

/**
 * @brief 简易文件解码结构
 * 
 */
typedef struct {
    luat_audio_data_codec_t codec;          /**< 关联的播放编解码器实例 */
    uint8_t *temp_buff;                         /**< 临时缓冲区*/
    union {
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
    luat_fifo_t *decode_save_fifo;            /**< 解码后数据缓冲区*/
    luat_fifo_t *org_input_data_fifo;            /**< 原始数据输入缓冲区，在audio task里读出，可能在多个地方写入，需要在写入时做线程安全保护 */
    luat_buffer_t out_buffer;                /**< 输出数据缓冲区 */
    uint8_t is_stream:1;                       /**< 是否为流式请求 */
    uint8_t is_tts:1;                          /**< 是否为文本转语音请求 */
    uint8_t is_input_end:1;                   /**< 是否为输入结束请求 */
    uint8_t is_stream_end:1;                   /**< 是否为流式请求结束 */
}luat_audio_decode_file_ctrl_t;

int luat_audio_decode_file_start(luat_audio_decode_file_ctrl_t *ctrl,const luat_audio_data_codec_opts_t *codec_opts, luat_audio_play_file_info_t *files, uint32_t files_num, 
    luat_audio_request_cb_t cb, void *user_data);

int luat_audio_decode_tts_start(luat_audio_decode_file_ctrl_t *ctrl,const char *text, uint32_t text_len, 
    luat_audio_request_cb_t cb, void *user_data);

#ifdef __LUATOS__
void l_audio_init(void);
#endif

#endif

/** @} */
