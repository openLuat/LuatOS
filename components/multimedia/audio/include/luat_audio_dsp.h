/**
 * @file luat_audio_dsp.h
 * @brief LuatOS 音频DSP处理模块接口定义
 * 
 * 该文件定义了音频DSP（数字信号处理）的通用接口框架，用于实现各种音频处理算法，
 * 如降噪、回声消除、音频增强等。采用面向对象的设计模式，通过操作函数表实现多态。
 * 
 * @defgroup luat_audio_dsp 音频DSP处理模块
 * @ingroup audio
 * @{
 */

#ifndef __LUAT_AUDIO_DSP__
#define __LUAT_AUDIO_DSP__

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_common_api.h"
#include "luat_audio_define.h"

/**
 * @brief DSP操作函数表
 * 
 * 定义DSP模块的基础操作接口，具体DSP算法实现需实现这些接口函数。
 */
typedef struct luat_audio_dsp_opts {
    /**
     * @brief 创建DSP实例的上下文
     * @param dsp DSP实例指针
     * @return 返回DSP算法的私有上下文指针
     */
    void* (*create)(struct luat_audio_dsp *dsp);

    /**
     * @brief 销毁DSP实例的上下文
     * @param dsp DSP实例指针
     */
    void (*destroy)(struct luat_audio_dsp *dsp);
    
    /**
     * @brief 执行DSP处理
     * @param dsp DSP实例指针
     * @param input 输入音频数据缓冲区
     * @param ref_input 参考输入（用于回声消除等算法），可为NULL
     * @param output 输出音频数据缓冲区
     * @return 处理结果，0表示成功，负值表示失败
     */
    int (*process)(struct luat_audio_dsp* dsp,
                  const void *input,
                  const void *ref_input,
                  uint32_t *output);

} luat_audio_dsp_opts_t;


/**
 * @brief DSP实例结构体
 * 
 * 表示一个音频DSP处理实例，包含操作函数表和运行时参数。
 */
typedef struct luat_audio_dsp {
    const luat_audio_dsp_opts_t *opts;  /**< DSP操作函数表指针 */
    void *dsp_ctx;                       /**< DSP算法私有上下文 */
    void *user_data;                     /**< 用户自定义数据 */
    uint32_t sample_rate;                /**< 采样率（Hz） */
    uint32_t frame_size;                 /**< 每帧采样数 */
    uint8_t bits_per_sample;             /**< 每样本位数（如16位） */
} luat_audio_dsp_t;

#endif

/** @} */
