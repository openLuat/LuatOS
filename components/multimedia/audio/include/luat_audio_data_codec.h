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
    uint8_t channel_nums;           /**< 声道数 (1=mono, 2=stereo) */
    uint8_t data_align;         /**< 数据对齐方式 */
    uint8_t is_signed;          /**< 是否有符号数据 */
    uint8_t driver_work_mode;          /**< 工作模式 */
} luat_audio_common_param_t;

/**
 * @brief 编解码器参数联合体
 * 
 * 用于存储特定编解码器的配置参数。
 */
typedef union {
    struct {
        uint8_t encode_speed;  /**< AMR编码速率参数 */
        uint8_t is_wb;
    } amr_param;
    /**
    * @brief tts输出回调函数
    * 
    * 用于在tts解码完成后调用，将解码后的音频数据传递给播放器。
    * @param data 解码后的音频数据指针
    * @param param 解码参数，如果data为null，param为播放采样率，否则为解码后的音频数据大小
    * @param user_data 用户自定义数据指针，用于传递额外信息
    * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
    */
    int (*tts_output_callback_t)(void *data, uint32_t param, void *user_data);
} luat_audio_data_codec_param_u;


/**
 * @brief 音频编解码器操作函数集结构
 * 
 * 用户需要实现此结构中的函数来提供自定义的编解码器功能。
 */
typedef struct luat_audio_data_codec_opts {
    /**
     * @brief 初始化编解码器实例
     * @param codec 编解码器上下文指针
     * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
     */
    int (*init)(struct luat_audio_data_codec *codec, uint8_t is_encode);
    
    /**
     * @brief 释放编解码器实例
     * @param codec 编解码器上下文指针
     */
    void (*deinit)(struct luat_audio_data_codec *codec);

    /**
     * @brief 获取播放信息，如果信息不够，需要跳过偏移量和需要长度来获取完整信息
     * @param codec 编解码器上下文指针
     * @param input_buffer 输入缓冲区指针
     * @param now_file_pos 当前文件位置，单位字节
     * @param jump_offset_bytes 跳过偏移量指针，单位字节，当获取播放信息完整时，这里偏移指针需要指向真正数据的开头位置
     * @param need_bytes 需要再次输入的长度，当获取播放信息完整时，这里需要输入的长度为0
     * @param info 指向存储播放信息的结构，如果信息不够，返回的sample_rate为0
     * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
     */
    int (*get_play_info)(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info);

    /**
     * @brief 预解码音频数据，获取解码后的帧大小（字节），只有decode_min_input_len为0时才需要调用此函数，说明数据帧长度是需要解析出来的，目前只有amr需要
     * @param codec 编解码器上下文指针
     * @param input 输入编码数据缓冲区
     * @param input_size 输入数据大小（字节）,不大于decode_min_input_len
     * @param frame_size_bytes 指向存储解码后的帧大小的指针，单位字节
     */
    void (*pre_decode)(struct luat_audio_data_codec* codec, const uint8_t *input, uint32_t input_size, uint32_t *frame_size_bytes);
    /**
     * @brief 解码音频数据
     * @param codec 编解码器上下文指针
     * @param info 播放信息结构指针
     * @param input 输入编码数据缓冲区
     * @param input_size 输入数据大小（字节）,不大于decode_min_input_len
     * @param output 输出解码数据缓冲区
     * @param decoded_output_size 实际解码产生的输出数据大小（字节）,不大于decode_max_output_len
     * @param decoded_used_size 实际解码消耗的输入数据大小（字节）,不大于decode_min_input_len
     * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
     */
    int (*decode)(struct luat_audio_data_codec* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, 
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size);
    
    /**
     * @brief 合成编码文件头信息
     * @param codec 编解码器上下文指针
     * @param info 播放信息结构指针
     * @param total_len 总编码数据大小（字节）
     * @param out_buffer 输出缓冲区，会动态修改大小
     * @return 成功返回 0，失败返回负值错误码
     */
    int (*make_head)(struct luat_audio_data_codec* codec, luat_audio_common_param_t *info, uint32_t total_len, luat_buffer_t *out_buffer);

    /**
     * @brief 编码音频数据
     * @param codec 编解码器上下文指针
     * @param info 播放信息结构指针
     * @param input 输入原始音频数据缓冲区
     * @param input_size 输入数据大小（字节）
     * @param output 输出编码数据缓冲区
     * @param encoded_used_size 实际编码消耗的输入数据大小（字节）
     * @param encoded_output_size 实际编码输出数据大小（字节）
     * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
     */
    int (*encode)(struct luat_audio_data_codec* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size);
    /**
     * @brief TTS解码音频数据
     * @param codec 编解码器上下文指针
     * @param text 输入文本指针
     * @param len 输入文本长度（字节）
     * @param user_data 用户自定义数据指针，用于传递额外信息
     * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
     */
    int (*tts_decode)(struct luat_audio_data_codec* codec, const char *text, uint32_t len, void *user_data);

    /**
     * @brief 设置TTS参数
     * @param codec 编解码器上下文指针
     * @param param TTS参数类型
     * @param value TTS参数值
     * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
     */
    int (*tts_set_param)(struct luat_audio_data_codec* codec, uint32_t param, uint32_t value);

    uint32_t encode_min_input_len;              /**< 编码1帧需要的输入长度 (字节) */
    uint32_t encode_max_output_len;             /**< 编码1帧输出的最大长度 (字节) */
    uint32_t decode_min_input_len;              /**< 解码最小输入长度 (字节) */
    uint32_t decode_max_output_len;             /**< 解码最大输出长度 (字节) */
    uint8_t type;                             /**< 编解码器类型 */
    uint8_t is_reentrant:1;                       /**< 是否可重入 */
    uint8_t is_hardware:1;                       /**< 是否硬件编解码器 */
    uint8_t support_detect:1;                       /**< 是否支持检测文件头 */
} luat_audio_data_codec_opts_t;

/**
 * @brief 音频编解码器上下文结构
 */
struct luat_audio_data_codec {
    const luat_audio_data_codec_opts_t *opts;   /**< 编解码器操作函数集指针 */
    void *encode_ctx;                            /**< 编码器私有上下文 */ 
    void *decode_ctx;                            /**< 解码器私有上下文 */
    void *user_data;                            /**< 用户自定义数据 */
    luat_audio_common_param_t common_param;           /**< 播放信息结构 */
    luat_audio_data_codec_param_u param;        /**< 编解码器参数联合体 */
    uint8_t *input_buffer;                      /**< 输入数据缓冲区 */
};


typedef struct luat_audio_data_codec luat_audio_data_codec_t;

/**
 * @brief 绑定音频编解码控制器到一个具体的编解码器
 * @param codec 编解码控制器上下文指针
 * @param opts 编解码器选项指针
 * @param user_data 用户自定义数据指针
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
 */
int luat_audio_data_codec_bind(luat_audio_data_codec_t *codec, const luat_audio_data_codec_opts_t *opts, void *user_data);

/**
 * @brief 去初始化音频编解码控制器，但是不解绑编解码器
 * @param codec 编解码控制器上下文指针
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
 */
void luat_audio_data_codec_deinit(luat_audio_data_codec_t *codec);

/**
 * @brief 解绑音频编解码控制器，如果是软件编解码器，可以跳过这个步骤
 * @param codec 编解码控制器上下文指针
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
 */
void luat_audio_data_codec_unbind(luat_audio_data_codec_t *codec);

/**
 * @brief 获取音频编解码器的播放信息
 * @param codec 编解码控制器上下文指针
 * @param input_buffer 输入数据缓冲区指针
 * @param now_file_pos 当前文件位置（字节）,输入参数
 * @param jump_offset_bytes 跳转偏移量指针，用于存储跳转偏移量（字节），输出参数，如果成功获取到采样率，则这里是解码开始的位置
 * @param need_bytes 需要的字节数指针，用于存储需要的字节数（字节），输出参数
 * @return int 无错误返回 LUAT_ERROR_NONE，失败返回负值错误码，codec->common_param 会更新播放信息结构，得到sample_rate则完全成功
 * @note 该函数在解码前调用，用于获取音频的播放信息，如采样率、声道数、采样宽度、采样深度等
 */
int luat_audio_data_codec_get_play_info(luat_audio_data_codec_t *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes);
/**
 * @brief 解码音频数据一次
 * @param codec 编解码控制器上下文指针
 * @param input_data_fifo 输入数据fifo指针
 * @param output_data_buffer 输出数据缓冲区指针
 * @param is_end 是否为最后一帧数据
 * @note 1=last frame, 0=not last frame
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
 */
int luat_audio_data_codec_decode_once(luat_audio_data_codec_t *codec, luat_fifo_t *input_data_fifo, luat_buffer_t *output_data_buffer, uint8_t is_end);

/**
 * @brief 编码音频数据一次
 * @param codec 编解码控制器上下文指针
 * @param input_data_fifo 输入数据fifo指针
 * @param output_data_buffer 输出数据缓冲区指针
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
 */
int luat_audio_data_codec_encode_once(luat_audio_data_codec_t *codec, luat_fifo_t *input_data_fifo, luat_buffer_t *output_data_buffer);

/**
 * @brief 注册音频编解码器，必须在BSP里，并且在luavm初始化前调用
 * @param opts 编解码器选项指针
 * @return int 成功返回 LUAT_ERROR_NONE，失败返回负值错误码
 */
int luat_audio_data_codec_register(const luat_audio_data_codec_opts_t *opts);

/**
 * @brief 查找音频编解码器
 * @param type 编解码器类型
 * @return const luat_audio_data_codec_opts_t* 编解码器选项指针，失败返回 NULL
 */
const luat_audio_data_codec_opts_t* luat_audio_data_codec_find(uint8_t type);

int luat_audio_amr_nb_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info);
int luat_audio_amr_wb_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info);
int luat_audio_mp3_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info);
int luat_audio_wav_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info);

extern const luat_audio_data_codec_opts_t luat_audio_data_codec_amr_nb_opts;
extern const luat_audio_data_codec_opts_t luat_audio_data_codec_amr_wb_opts;
extern const luat_audio_data_codec_opts_t luat_audio_data_codec_mp3_opts;       
extern const luat_audio_data_codec_opts_t luat_audio_data_codec_wav_opts;
extern const luat_audio_data_codec_opts_t luat_audio_data_codec_raw_opts;
#endif

/** @} */
