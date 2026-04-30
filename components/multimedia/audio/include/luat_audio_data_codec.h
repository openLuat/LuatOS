#ifndef __LUAT_AUDIO_DATA_CODEC__
#define __LUAT_AUDIO_DATA_CODEC__

/**
 * @file luat_audio_data_codec.h
 * @brief LuatOS 音频编解码器抽象层头文件
 * 
 * 提供音频编解码器的抽象接口，允许用户绑定自定义的编码器和解码器实现。
 * 
 * @defgroup luat_audio_codec 音频编解码器模块
 * @ingroup audio
 * @{
 */

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_audio_define.h"
#include "luat_common_api.h"
#include "luat_fs.h"

/**
 * @brief 播放信息结构
 * 
 * 包含音频文件的基本播放参数信息。
 */
typedef struct {
    uint32_t frame_size;        /**< 帧大小 (bytes)，文件没有到尾部前，至少需要frame_size数量的数据才可以开始解码 */
    uint32_t sample_rate;       /**< 采样率 (Hz) */
    uint8_t channels;           /**< 声道数 (1=mono, 2=stereo) */
    uint8_t bits_per_sample;    /**< 采样位宽 (bits) */
} luat_audio_play_info_t;

/**
 * @brief 编解码器参数联合体
 * 
 * 用于存储特定编解码器的配置参数。
 */
typedef union {
    uint8_t amr_speed;  /**< AMR编码速率参数 */
} luat_audio_data_codec_param_u;


/**
 * @brief 音频编解码器操作函数集结构
 * 
 * 用户需要实现此结构中的函数来提供自定义的编解码器功能。
 */
typedef struct luat_audio_data_codec_opts {
    /**
     * @brief 创建编解码器实例
     * @param codec 编解码器上下文指针
     * @return 成功返回编解码器私有上下文指针，失败返回 NULL
     */
    void* (*create)(struct luat_audio_data_codec *codec);
    
    /**
     * @brief 销毁编解码器实例
     * @param codec 编解码器上下文指针
     */
    void (*destroy)(struct luat_audio_data_codec *codec);
    
    /**
     * @brief 探测文件是否能被解码
     * @param file 文件指针
     * @return 成功返回 0，失败返回负值错误码
     */
    int (*probe)(FILE* file);
    
    /**
     * @brief 从文件获取播放信息
     * @param codec 编解码器上下文指针
     * @param file 文件指针
     * @param info 指向存储播放信息的结构
     * @return 成功返回 0，失败返回负值错误码
     */
    int (*get_play_info_from_file)(struct luat_audio_data_codec *codec, FILE* file, luat_audio_play_info_t *info);

    /**
     * @brief 解码音频数据
     * @param codec 编解码器上下文指针
     * @param info 播放信息结构指针
     * @param input 输入编码数据缓冲区
     * @param input_size 输入数据大小（字节）
     * @param decoded_input_size 实际解码消耗的输入数据大小（字节）
     * @param output 输出解码数据缓冲区
     * @param output_size 输出缓冲区大小（字节）
     * @param decoded_output_size 实际解码产生的输出数据大小（字节）
     * @return 成功返回 0，失败返回负值错误码
     */
    int (*decode)(struct luat_audio_data_codec* codec, luat_audio_play_info_t *info,
                  const uint8_t *input, uint32_t input_size, uint32_t *decoded_input_size,
                  uint8_t *output, uint32_t output_size, 
                  uint32_t *decoded_output_size);
    
    /**
     * @brief 合成编码文件头信息
     * @param codec 编解码器上下文指针
     * @param info 播放信息结构指针
     * @param total_len 总编码数据大小（字节）
     * @param out_buffer 输出缓冲区，会动态修改大小
     * @return 成功返回 0，失败返回负值错误码
     */
    int (*make_head)(struct luat_audio_data_codec* codec, luat_audio_play_info_t *info, uint32_t total_len, luat_buffer_t *out_buffer);

    /**
     * @brief 编码音频数据
     * @param codec 编解码器上下文指针
     * @param input 输入原始音频数据缓冲区
     * @param input_size 输入数据大小（字节）
     * @param output 输出编码数据缓冲区
     * @param output_size 输出缓冲区大小（字节）
     * @param encoded_size 实际编码的数据大小（字节）
     * @return 成功返回 0，失败返回负值错误码
     */
    int (*encode)(struct luat_audio_data_codec* codec,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t output_size,
                  uint32_t *encoded_size);

} luat_audio_data_codec_opts_t;

/**
 * @brief 音频编解码器上下文结构
 */
struct luat_audio_data_codec {
    const luat_audio_data_codec_opts_t *opts;   /**< 编解码器操作函数集指针 */
    void *codec_ctx;                            /**< 编解码器私有上下文 */
    void *user_data;                            /**< 用户自定义数据 */
    luat_audio_data_codec_param_u param;        /**< 编解码器参数联合体 */
    uint32_t encode_min_input_len;              /**< 编码最小输入长度 (字节) */
    uint32_t encode_max_output_len;             /**< 编码最大输出长度 (字节) */
    uint32_t decode_min_input_len;              /**< 解码最小输入长度 (字节) */
    uint32_t decode_max_output_len;             /**< 解码最大输出长度 (字节) */
    uint8_t is_encoder;                         /**< 是否为编码器 (1=encoder, 0=decoder) */
};

typedef struct luat_audio_data_codec luat_audio_data_codec_t;

#endif

/** @} */
