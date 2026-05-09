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

struct luat_audio_driver_probe
{
    uint8_t bus_type;
    uint8_t bus_id;
};
/**
 * @brief 音频驱动控制器结构
 * 
 * 此结构用于管理音频驱动实例，包含回调函数、用户数据和驱动操作函数集。
 */
struct luat_audio_driver_ctrl
{
    const struct luat_audio_driver_opts *driver_opts;  /**< 驱动操作函数集指针 */
    void *driver_data;  /**< 驱动私有数据指针 */
    void *user_data;     /**< 用户自定义数据指针 */
    struct luat_audio_channel *data_channel;  /**< 关联的音频通道指针 */
    struct luat_audio_driver_probe probe;  /**< 驱动匹配结构 */
    uint8_t *play_buff;
    uint8_t *record_buff;
    volatile uint32_t last_play_cnt;
    volatile uint32_t current_play_cnt;
    volatile uint32_t current_record_cnt;
    uint32_t one_play_block_len;
    uint32_t one_record_block_len;
    uint8_t is_init;  /**< 是否初始化 */
    uint8_t is_running;  /**< 是否正在运行 */
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
     * @return int 成功返回LUAT_ERROR_NONE，失败返回负值错误码
     */
    int (*init)(struct luat_audio_driver_ctrl *ctrl);
    
    /**
     * @brief 配置音频驱动
     * @param ctrl 驱动控制器指针
     * @param param 配置参数，见LUAT_AUDIO_DRIVER_CONFIG_PARAM_* 枚举
     * @param value1 第一个配置值，根据具体参数而定
     * @param value2 第二个配置值，根据具体参数而定
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*config)(struct luat_audio_driver_ctrl *ctrl, uint32_t param, uint32_t value1, uint32_t value2);
    
    /**
     * @brief 激活音频驱动, 初始化和配置完成后调用，主要包括退出低功耗，提供I2S MCLK等
     * @param ctrl 驱动控制器指针
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*activate)(struct luat_audio_driver_ctrl *ctrl);
    /**
     * @brief 修改音频参数
     * @param ctrl 驱动控制器指针
     * @param sample_rate 采样率 (Hz)
     * @param data_bits 数据位宽 (bits)
     * @param channel 声道配置 (见 LUAT_AUDIO_CHANNEL_* 枚举)
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*modify)(struct luat_audio_driver_ctrl *ctrl, uint32_t sample_rate, uint8_t data_bits, uint8_t channel);
    
    /**
     * @brief 填充播放缓存区空白音，确保播放缓存区有数据可播放
     * @param ctrl 驱动控制器指针
     * @param play_buff 播放缓冲区数组指针
     * @param len_bytes 要填充的数据长度 (字节)
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*fill)(struct luat_audio_driver_ctrl *ctrl, uint8_t *play_buff, uint32_t len_bytes, uint8_t is_signed, uint8_t align);
    /**
     * @brief 启动播放循环，必须确保没有未播放完成的数据残留，播放缓存区由驱动生成
     * @param ctrl 驱动控制器指针
     * @param play_buff 播放缓冲区数组指针
     * @param one_play_block_len 单个播放缓冲区块长度 (字节)
     * @param block_num 播放缓冲区块数量
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*start_tx_loop)(struct luat_audio_driver_ctrl *ctrl, uint32_t **play_buff, uint32_t one_block_len, uint32_t block_num);
    
    /**
     * @brief 启动录音循环, 录音缓存区由驱动生成
     * @param ctrl 驱动控制器指针
     * @param record_buff 录音缓冲区数组指针
     * @param one_record_block_len 单个录音缓冲区块长度 (字节)
     * @param block_num 录音缓存区块数量
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*start_rx_loop)(struct luat_audio_driver_ctrl *ctrl, uint32_t **record_buff, uint32_t one_block_len, uint32_t block_num);
    
    /**
     * @brief 启动全双工循环 (同时播放和录音), 播放和录音缓存区由驱动生成
     * @param ctrl 驱动控制器指针
     * @param play_buff 播放缓冲区数组指针
     * @param one_play_block_len 单个播放缓冲区块长度 (字节)
     * @param play_block_num 播放缓冲区块数量
     * @param record_buff 录音缓冲区数组指针
     * @param one_record_block_len 单个录音缓冲区块长度 (字节)
     * @param record_block_num 录音缓存区块数量 
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*start_full_loop)(struct luat_audio_driver_ctrl *ctrl, uint32_t **play_buff, uint32_t one_play_block_len, uint32_t play_block_num,uint32_t **record_buff, uint32_t one_record_block_len, uint32_t record_block_num);
    
    /**
     * @brief 启动全双工循环 (同时播放和录音), 提供播放缓冲区，录音缓存区由驱动生成
     * @param ctrl 驱动控制器指针
     * @param play_buff 播放缓冲区数组指针
     * @param one_play_block_len 单个播放缓冲区块长度 (字节)
     * @param play_block_num 播放缓冲区块数量
     * @param record_buff 录音缓冲区数组指针
     * @param one_record_block_len 单个录音缓冲区块长度 (字节)
     * @param record_block_num 录音缓存区块数量 
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*start_full_loop_with_play_buff)(struct luat_audio_driver_ctrl *ctrl, uint32_t *play_buff, uint32_t one_play_block_len, uint32_t play_block_num,uint32_t **record_buff, uint32_t one_record_block_len, uint32_t record_block_num);
    /**
     * @brief 停止播放循环、录音循环或全双工循环
     * @param ctrl 驱动控制器指针
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*stop)(struct luat_audio_driver_ctrl *ctrl);

    /**
     * @brief 反激活音频驱动，主要包括进入低功耗模式，关闭I2S MCLK等
     * @param ctrl 驱动控制器指针
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*deactivate)(struct luat_audio_driver_ctrl *ctrl);
    /**
     * @brief 反初始化驱动
     * @param ctrl 驱动控制器指针
     * @return int 成功返回0，失败返回负值错误码
     */
    int (*deinit)(struct luat_audio_driver_ctrl *ctrl);

    uint32_t tx_one_block_max_len;  /**< 最大播放单块长度 (字节) */
    uint32_t rx_one_block_max_len;  /**< 最大录音单块长度 (字节) */
    uint32_t support_tx_loop:1;  /**< 是否支持播放循环 */
    uint32_t support_rx_loop:1;  /**< 是否支持录音循环 */
    uint32_t support_full_loop:1;  /**< 是否支持全双工循环 */
    uint32_t is_signed:1;  /**< 是否为有符号数据 */
    uint32_t support_bytes:3;  /**< 支持的字节数 */
   } luat_audio_driver_opts_t;

/**
 * @brief 音频驱动控制器类型定义
 */
typedef struct luat_audio_driver_ctrl luat_audio_driver_ctrl_t;
typedef struct luat_audio_driver_probe luat_audio_driver_probe_t;

int luat_audio_driver_fill_default(struct luat_audio_driver_ctrl *ctrl, uint8_t *play_buff, uint32_t len_bytes, uint8_t is_signed, uint8_t align);
#endif

/** @} */
