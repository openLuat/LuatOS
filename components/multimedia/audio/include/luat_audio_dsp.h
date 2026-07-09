#ifndef __LUAT_AUDIO_DSP__
#define __LUAT_AUDIO_DSP__

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

#include "luat_audio_data_codec.h"
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
     * @brief 初始化DSP实例
     * @param dsp DSP实例指针
     * @return 处理结果，0表示成功，负值表示失败
     */
    int (*init)(struct luat_audio_dsp *dsp);
    /**
     * @brief 销毁DSP实例
     * @param dsp DSP实例指针
     */
    void (*deinit)(struct luat_audio_dsp *dsp);
    /**
     * @brief 创建重采样采样上下文
     * @param dsp DSP实例指针
     * @param src_param 输入音频参数指针
     * @param dst_param 输出音频参数指针
     * @param quality 重采样质量（0-100）
     * @return 返回DSP算法的私有上下文指针
     */
    void* (*create_resample_ctx)(struct luat_audio_dsp *dsp, 
        const luat_audio_common_param_t *src_param,
        const luat_audio_common_param_t *dst_param,int quality);

    /**
     * @brief 销毁重采样采样上下文
     * @param dsp DSP实例指针
     * @param ctx 重采样采样上下文指针
     */
    void (*destroy_resample_ctx)(struct luat_audio_dsp *dsp, void *ctx);
    
    /**
     * @brief 创建回声抑制上下文
     * @param dsp DSP实例指针
     * @param common_param 通用音频参数指针
     * @param filter_sample_size 过滤器大小（单位：采样点）
     * @return 返回DSP算法的私有上下文指针
     */
    void* (*create_echo_ctx)(struct luat_audio_dsp *dsp, 
        const luat_audio_common_param_t *common_param,
        uint32_t filter_sample_size);

    /**
     * @brief 销毁回声抑制上下文
     * @param dsp DSP实例指针
     * @param ctx 回声抑制上下文指针
     */
    void (*destroy_echo_ctx)(struct luat_audio_dsp *dsp, void *ctx);

    /**
     * @brief 创建预处理上下文
     * @param dsp DSP实例指针
     * @param common_param 通用音频参数指针
     * @return 返回DSP算法的私有上下文指针
     */
    void* (*create_preprocess_ctx)(struct luat_audio_dsp *dsp, 
        const luat_audio_common_param_t *common_param);
    
    /**
     * @brief 销毁预处理上下文
     * @param dsp DSP实例指针
     * @param ctx 预处理上下文指针
     */
    void (*destroy_preprocess_ctx)(struct luat_audio_dsp *dsp, void *ctx);

    /**
     * @brief 执行DSP处理，处理1帧数据
     * @param dsp DSP实例指针
     * @param common_param 通用音频参数指针
     * @param echo_ctx 回声抑制上下文指针
     * @param preprocess_ctx 预处理上下文指针
     * @param input 输入音频数据缓冲区
     * @param ref_input 参考输入（用于回声消除等算法），可为NULL
     * @param output 输出音频数据缓冲区
     * @return 处理结果，0表示成功，负值表示失败
     */
    int (*process)(struct luat_audio_dsp* dsp, 
                  const luat_audio_common_param_t *common_param,
                  void *echo_ctx, void *preprocess_ctx,
                  const void *input,
                  const void *ref_input,
                  uint32_t *output);
    
    /**
     * @brief 重采样音频数据
     * @param dsp DSP实例指针
     * @param common_param 通用音频参数指针
     * @param resample_ctx 重采样采样上下文指针
     * @param input 输入音频数据缓冲区
     * @param input_sample_size 输入音频数据大小（单位：采样点）
     * @param output 输出音频数据缓冲区
     * @param output_buf_sample_size 输出音频数据缓冲区大小（单位：采样点）
     * @param used_sample_size 实际使用的采样点数（单位：采样点）
     * @param output_sample_size 输出音频数据大小（单位：采样点）
     * @return 处理结果，0表示成功，负值表示失败
     */
    int (*resample)(struct luat_audio_dsp* dsp, 
                  const luat_audio_common_param_t *common_param,
                  void *resample_ctx,
                  const void *input,
                  uint32_t input_sample_size,
                  uint32_t *output,
                  uint32_t output_buf_sample_size, 
                  uint32_t *used_sample_size,
                  uint32_t *output_sample_size);
    uint8_t type;
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
} luat_audio_dsp_t;

const luat_audio_dsp_opts_t *luat_audio_dsp_get_opts(uint8_t type);
int luat_audio_dsp_bind(luat_audio_dsp_t *dsp, const luat_audio_dsp_opts_t *opts);
void luat_audio_dsp_unbind(luat_audio_dsp_t *dsp);
#endif

/** @} */
