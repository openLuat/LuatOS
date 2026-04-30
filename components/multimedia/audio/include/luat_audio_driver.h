#ifndef __LUAT_AUDIO_DRIVER__
#define __LUAT_AUDIO_DRIVER__

/**
 * @file luat_audio_driver.h
 * @brief LuatOS 音频驱动抽象层头文件
 * 
 * 提供音频硬件驱动的抽象接口，允许用户绑定自定义的硬件驱动实现。
 * 通过函数指针表的方式，实现硬件无关的音频框架设计。
 * 
 * @defgroup luat_audio_driver 音频驱动抽象层
 * @ingroup audio
 * @{
 */

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_common_api.h"
#include "luat_audio_define.h"

/**
 * @brief 音频驱动控制器结构
 * 
 * 此结构用于管理音频驱动实例，包含回调函数、用户数据和驱动操作函数集。
 */
struct luat_audio_driver_ctrl
{
    const struct luat_audio_driver_opts *driver_opts;  /**< 驱动操作函数集指针 */
    
    /**
     * @brief 音频驱动事件回调函数
     * 
     * 当驱动发生特定事件时（如数据接收完成、错误等），会调用此回调函数。
     * 
     * @param event 事件类型
     * @param rx_data 接收的数据指针（如果适用）
     * @param param 附加参数，播放相关事件时，是当前第几块缓存播放完成了，录音相关事件时，是接收数据长度
     * @param ctrl 驱动控制器指针
     * @return int 返回值，0表示成功，负值表示错误
     */
    int (*luat_audio_driver_event_callback)(uint32_t event, uint8_t *rx_data, uint32_t param, struct luat_audio_driver_ctrl *ctrl);
    
    void *private_data;  /**< 驱动私有数据指针 */
    void *user_data;     /**< 用户自定义数据指针 */
    struct luat_audio_channel *data_channel;  /**< 关联的音频通道指针 */
};

/**
 * @brief 音频驱动操作函数集结构
 * 
 * 定义音频驱动必须实现的核心操作函数。
 * 用户在实现自定义驱动时，需要填充此结构中的函数指针。
 */
typedef struct luat_audio_driver_opts {
    /**
     * @brief 初始化驱动
     * @param ctrl 驱动控制器指针
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*init)(struct luat_audio_driver_ctrl *ctrl);
    
    /**
     * @brief 修改音频参数
     * @param ctrl 驱动控制器指针
     * @param sample_rate 采样率 (Hz)
     * @param data_bits 数据位宽 (bits)
     * @param channel 声道配置 (见 LUAT_AUDIO_CHANNEL_* 枚举)
     * @param format 音频格式
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*modify)(struct luat_audio_driver_ctrl *ctrl, uint32_t sample_rate, uint8_t data_bits, uint8_t channel, uint8_t format);
    
    /**
     * @brief 启动播放循环
     * @param ctrl 驱动控制器指针
     * @param play_buff 播放缓冲区数组指针
     * @param one_block_len 单个缓冲区块长度 (字节)
     * @param block_num 缓冲区块数量
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*start_tx_loop)(struct luat_audio_driver_ctrl *ctrl, uint32_t **play_buff, uint32_t one_block_len, uint32_t block_num);
    
    /**
     * @brief 启动录音循环
     * @param ctrl 驱动控制器指针
     * @param record_buff 录音缓冲区数组指针
     * @param one_block_len 单个缓冲区块长度 (字节)
     * @param block_num 缓冲区块数量
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*start_rx_loop)(struct luat_audio_driver_ctrl *ctrl, uint32_t **record_buff, uint32_t one_block_len, uint32_t block_num);
    
    /**
     * @brief 启动全双工循环 (同时播放和录音)
     * @param ctrl 驱动控制器指针
     * @param play_buff 播放缓冲区数组指针
     * @param record_buff 录音缓冲区数组指针
     * @param one_block_len 单个缓冲区块长度 (字节)
     * @param block_num 缓冲区块数量
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*start_full_loop)(struct luat_audio_driver_ctrl *ctrl, uint32_t **play_buff, uint32_t **record_buff, uint32_t one_block_len, uint32_t block_num);
    
    /**
     * @brief 反初始化驱动
     * @param ctrl 驱动控制器指针
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*deinit)(struct luat_audio_driver_ctrl *ctrl);

    uint32_t tx_one_block_max_len;  /**< 最大播放单块长度 (字节) */
    uint32_t rx_one_block_max_len;  /**< 最大录音单块长度 (字节) */
    uint8_t support_loop_mode;      /**< 支持的循环模式位掩码 */
} luat_audio_driver_opts_t;

/**
 * @brief 音频驱动控制器类型定义
 */
typedef struct luat_audio_driver_ctrl luat_audio_driver_ctrl_t;

#endif

/** @} */
