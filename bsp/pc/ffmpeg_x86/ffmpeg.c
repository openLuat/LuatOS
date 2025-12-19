#include "ffmpeg.h"
#include <libavutil/opt.h>

#ifdef _WIN32
// FFmpeg DLL句柄定义 (仅Windows)
HMODULE h_avutil = NULL;
HMODULE h_avcodec = NULL;
HMODULE h_avformat = NULL;
HMODULE h_swresample = NULL;

// 函数指针变量定义
av_find_best_stream_t p_av_find_best_stream = NULL;
avformat_open_input_t p_avformat_open_input = NULL;
avformat_find_stream_info_t p_avformat_find_stream_info = NULL;
avformat_close_input_t p_avformat_close_input = NULL;
av_read_frame_t p_av_read_frame = NULL;
avcodec_find_decoder_t p_avcodec_find_decoder = NULL;
avcodec_alloc_context3_t p_avcodec_alloc_context3 = NULL;
avcodec_free_context_t p_avcodec_free_context = NULL;
avcodec_parameters_to_context_t p_avcodec_parameters_to_context = NULL;
avcodec_open2_t p_avcodec_open2 = NULL;
avcodec_send_packet_t p_avcodec_send_packet = NULL;
avcodec_receive_frame_t p_avcodec_receive_frame = NULL;
av_get_media_type_string_t p_av_get_media_type_string = NULL;
av_get_default_channel_layout_t p_av_get_default_channel_layout = NULL;
av_frame_alloc_t p_av_frame_alloc = NULL;
av_frame_free_t p_av_frame_free = NULL;
av_packet_alloc_t p_av_packet_alloc = NULL;
av_packet_free_t p_av_packet_free = NULL;
av_packet_unref_t p_av_packet_unref = NULL;
av_samples_alloc_t p_av_samples_alloc = NULL;
av_freep_t p_av_freep = NULL;
av_rescale_rnd_t p_av_rescale_rnd = NULL;
av_get_bytes_per_sample_t p_av_get_bytes_per_sample = NULL;
av_log_set_level_t p_av_log_set_level = NULL;
swr_alloc_set_opts_t p_swr_alloc_set_opts = NULL;
swr_init_t p_swr_init = NULL;
swr_free_t p_swr_free = NULL;
swr_convert_t p_swr_convert = NULL;
swr_get_delay_t p_swr_get_delay = NULL;
#endif  // _WIN32

static int luat_ffmpeg_debug = 0;

#ifdef _WIN32
// 显式加载FFmpeg DLL (仅Windows)
int luat_load_ffmpeg_dlls(void) {
    char exe_path[MAX_PATH];
    char dll_dir[MAX_PATH];
    char dll_path[MAX_PATH];

    // 获取exe路径和目录
    if (GetModuleFileNameA(NULL, exe_path, MAX_PATH) == 0) {
        return -1;
    }
    char* last_slash = strrchr(exe_path, '\\');
    if (last_slash) *last_slash = '\0';

    // plan1: 从..\..\release加载
    snprintf(dll_dir, sizeof(dll_dir), "%s\\..\\..\\release", exe_path);
    snprintf(dll_path, sizeof(dll_path), "%s\\avutil-56.dll", dll_dir);
    h_avutil = LoadLibraryA(dll_path);

    // plan2: 从exe同目录加载
    if (!h_avutil) {
        strcpy(dll_dir, exe_path);
        snprintf(dll_path, sizeof(dll_path), "%s\\avutil-56.dll", dll_dir);
        h_avutil = LoadLibraryA(dll_path);
    }

    if (!h_avutil) {
        return -1;  // 两个位置都没找到
    }

    snprintf(dll_path, sizeof(dll_path), "%s\\swresample-3.dll", dll_dir);
    h_swresample = LoadLibraryA(dll_path);
    if (!h_swresample) {
        return -1;
    }

    snprintf(dll_path, sizeof(dll_path), "%s\\avcodec-58.dll", dll_dir);
    h_avcodec = LoadLibraryA(dll_path);
    if (!h_avcodec) {
        return -1;
    }

    snprintf(dll_path, sizeof(dll_path), "%s\\avformat-58.dll", dll_dir);
    h_avformat = LoadLibraryA(dll_path);
    if (!h_avformat) {
        return -1;
    }

    #define LOAD_FUNC(module, name) \
        p_##name = (name##_t)GetProcAddress(module, #name); \
        if (!p_##name) return -1;

    LOAD_FUNC(h_avformat, av_find_best_stream);
    LOAD_FUNC(h_avformat, avformat_open_input);
    LOAD_FUNC(h_avformat, avformat_find_stream_info);
    LOAD_FUNC(h_avformat, avformat_close_input);
    LOAD_FUNC(h_avformat, av_read_frame);
    LOAD_FUNC(h_avcodec, avcodec_find_decoder);
    LOAD_FUNC(h_avcodec, avcodec_alloc_context3);
    LOAD_FUNC(h_avcodec, avcodec_free_context);
    LOAD_FUNC(h_avcodec, avcodec_parameters_to_context);
    LOAD_FUNC(h_avcodec, avcodec_open2);
    LOAD_FUNC(h_avcodec, avcodec_send_packet);
    LOAD_FUNC(h_avcodec, avcodec_receive_frame);
    LOAD_FUNC(h_avutil, av_get_media_type_string);
    LOAD_FUNC(h_avutil, av_get_default_channel_layout);
    LOAD_FUNC(h_avutil, av_frame_alloc);
    LOAD_FUNC(h_avutil, av_frame_free);
    LOAD_FUNC(h_avcodec, av_packet_alloc);
    LOAD_FUNC(h_avcodec, av_packet_free);
    LOAD_FUNC(h_avcodec, av_packet_unref);
    LOAD_FUNC(h_avutil, av_samples_alloc);
    LOAD_FUNC(h_avutil, av_freep);
    LOAD_FUNC(h_avutil, av_rescale_rnd);
    LOAD_FUNC(h_avutil, av_get_bytes_per_sample);
    LOAD_FUNC(h_avutil, av_log_set_level);
    LOAD_FUNC(h_swresample, swr_alloc_set_opts);
    LOAD_FUNC(h_swresample, swr_init);
    LOAD_FUNC(h_swresample, swr_free);
    LOAD_FUNC(h_swresample, swr_convert);
    LOAD_FUNC(h_swresample, swr_get_delay);

    av_log_set_level(16);  // AV_LOG_ERROR 只显示错误

    return 0;
}

void luat_unload_ffmpeg_dlls(void) {
    if (h_avformat) FreeLibrary(h_avformat);
    if (h_avcodec) FreeLibrary(h_avcodec);
    if (h_swresample) FreeLibrary(h_swresample);
    if (h_avutil) FreeLibrary(h_avutil);
    luat_ffmpeg_debug = 0;
}
#else
int luat_load_ffmpeg_dlls(void) {
    av_log_set_level(16);
    return 0;
}

void luat_unload_ffmpeg_dlls(void) {
    // Linux下无需卸载
}
#endif  // _WIN32

int luat_ffmpeg_play_file(const char *path) {
    AVFormatContext *fmt_ctx = NULL;
    // 打开输入文件
    if (avformat_open_input(&fmt_ctx, path, NULL, NULL) < 0) {
        return -1;
    }

    // 获取流信息
    if (avformat_find_stream_info(fmt_ctx, NULL) < 0) {
        avformat_close_input(&fmt_ctx);
        return -1;
    }

    // 打印流信息
    for (unsigned int i = 0; i < fmt_ctx->nb_streams; i++) {
        AVStream *stream = fmt_ctx->streams[i];
        AVCodecParameters *codecpar = stream->codecpar;
        if(luat_ffmpeg_debug) {
            printf("Stream %u: type=%s, codec_id=%d\n",
                i,
                av_get_media_type_string(codecpar->codec_type),
                codecpar->codec_id);
        }
    }

    // 查找最佳音频流
    int audio_stream_idx = av_find_best_stream(fmt_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (audio_stream_idx < 0) {
        avformat_close_input(&fmt_ctx);
        return -1;
    }

    // 获取编码参数和解码器
    AVCodecParameters *codec_par = fmt_ctx->streams[audio_stream_idx]->codecpar;
    const AVCodec *codec = avcodec_find_decoder(codec_par->codec_id);
    if (!codec) {
        avformat_close_input(&fmt_ctx);
        return -1;
    }

    // 分配解码器上下文
    AVCodecContext *codec_ctx = avcodec_alloc_context3(codec);
    if (!codec_ctx) {
        avformat_close_input(&fmt_ctx);
        return -1;
    }

    // 复制编码参数到解码器上下文
    if (avcodec_parameters_to_context(codec_ctx, codec_par) < 0) {
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&fmt_ctx);
        return -1;
    }

    // 确保 channel_layout 已设置
    if (!codec_ctx->channel_layout) {
#ifdef _WIN32
        codec_ctx->channel_layout = av_get_default_channel_layout(codec_ctx->channels);
#else
        if (codec_ctx->channels == 1) codec_ctx->channel_layout = AV_CH_LAYOUT_MONO;
        else codec_ctx->channel_layout = AV_CH_LAYOUT_STEREO;
#endif
    }

    // 打开解码器
    if (avcodec_open2(codec_ctx, codec, NULL) < 0) {
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&fmt_ctx);
        return -1;
    }

    SwrContext *swr_ctx = NULL;
    uint64_t out_ch_layout = AV_CH_LAYOUT_STEREO;
    enum AVSampleFormat out_sample_fmt = AV_SAMPLE_FMT_S16;
    int out_sample_rate = 44100;

    swr_ctx = swr_alloc();
    if (!swr_ctx) {
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&fmt_ctx);
        return -1;
    }
    
    av_opt_set_int(swr_ctx, "in_channel_layout",    codec_ctx->channel_layout, 0);
    av_opt_set_int(swr_ctx, "in_sample_rate",       codec_ctx->sample_rate, 0);
    av_opt_set_sample_fmt(swr_ctx, "in_sample_fmt", codec_ctx->sample_fmt, 0);
    av_opt_set_int(swr_ctx, "out_channel_layout",   out_ch_layout, 0);
    av_opt_set_int(swr_ctx, "out_sample_rate",      out_sample_rate, 0);
    av_opt_set_sample_fmt(swr_ctx, "out_sample_fmt", out_sample_fmt, 0);

    // 初始化重采样器
    if (swr_init(swr_ctx) < 0) {
        swr_free(&swr_ctx);
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&fmt_ctx);
        return -1;
    }

    // 分配帧和包
    AVPacket *pkt = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    if (!pkt || !frame) {
        av_frame_free(&frame);
        av_packet_free(&pkt);
        swr_free(&swr_ctx);
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&fmt_ctx);
        return -1;
    }

#ifdef LUAT_USE_GUI
    // 初始化SDL音频子系统
    if (SDL_Init(SDL_INIT_AUDIO) < 0) {
        av_frame_free(&frame);
        av_packet_free(&pkt);
        swr_free(&swr_ctx);
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&fmt_ctx);
        return -1;
    }
    // 设置SDL音频规格
    SDL_AudioSpec desired_spec, obtained_spec;
    desired_spec.freq = out_sample_rate;
    desired_spec.format = AUDIO_S16SYS;  // 16位有符号整数，系统字节序
    desired_spec.channels = 2;  // 立体声
    desired_spec.samples = 1024;  // 缓冲区大小
    desired_spec.callback = NULL;  // 使用队列方式
    desired_spec.userdata = NULL;

    // 打开音频设备
    SDL_AudioDeviceID audio_device = SDL_OpenAudioDevice(NULL, 0, &desired_spec, &obtained_spec, 0);
    if (audio_device == 0) {
        SDL_Quit();
        av_frame_free(&frame);
        av_packet_free(&pkt);
        swr_free(&swr_ctx);
        avcodec_free_context(&codec_ctx);
        avformat_close_input(&fmt_ctx);
        return -1;
    }
    // 开始播放音频
    SDL_PauseAudioDevice(audio_device, 0);

#endif
    // 读取并处理帧
    while (av_read_frame(fmt_ctx, pkt) >= 0) {
        if (pkt->stream_index == audio_stream_idx) {
            // 发送包到解码器
            if (avcodec_send_packet(codec_ctx, pkt) < 0) {
                break;
            }

            // 接收解码后的帧
            while (avcodec_receive_frame(codec_ctx, frame) == 0) {
                // 分配重采样缓冲区
                uint8_t *resampled_data[AV_NUM_DATA_POINTERS];
                int resampled_linesize;
                int resampled_nb_samples = av_rescale_rnd(
                    swr_get_delay(swr_ctx, frame->sample_rate) + frame->nb_samples,
                    out_sample_rate,
                    frame->sample_rate,
                    AV_ROUND_UP
                );

                if (av_samples_alloc(
                         resampled_data, &resampled_linesize,
                         2,  // 立体声通道数
                         resampled_nb_samples,
                         out_sample_fmt,
                         0
                     ) < 0) {
                    break;
                }

                // 执行重采样
                int out_nb_samples = swr_convert(
                    swr_ctx,
                    resampled_data, resampled_nb_samples,
                    (const uint8_t **)frame->data, frame->nb_samples
                );
                if (out_nb_samples < 0) {
                    av_freep(&resampled_data[0]);
                    break;
                }

                // 计算PCM数据大小（字节数）
                int pcm_size = out_nb_samples * 2 * av_get_bytes_per_sample(out_sample_fmt);  // 2 = 立体声通道数

                #ifdef LUAT_USE_GUI
                // 将PCM数据加入SDL音频队列进行播放
                if (SDL_QueueAudio(audio_device, resampled_data[0], pcm_size) < 0) {
                    fprintf(stderr, "Failed to queue audio: %s\n", SDL_GetError());
                }
                if(luat_ffmpeg_debug) {
                    printf("Queued %d bytes of audio data\n", pcm_size);
                }
                #endif

                // 释放重采样缓冲区
                av_freep(&resampled_data[0]);
            }
        }
        av_packet_unref(pkt);
    }

#ifdef LUAT_USE_GUI
    // 等待音频播放完成
    Uint32 queued = SDL_GetQueuedAudioSize(audio_device);
    while (queued > 0) {
        SDL_Delay(100);  // 等待100毫秒
        queued = SDL_GetQueuedAudioSize(audio_device);
    }
    // 清理资源
    SDL_CloseAudioDevice(audio_device);
    SDL_Quit();
#endif
    av_frame_free(&frame);
    av_packet_free(&pkt);
    swr_free(&swr_ctx);
    avcodec_free_context(&codec_ctx);
    avformat_close_input(&fmt_ctx);

    return 0;
}

void luat_ffmpeg_set_debug(int level) {
    /**
     * ffmepg 日志等级设置
     *  AV_LOG_QUIET	-8	关闭所有日志输出（最 “安静”）
     *  AV_LOG_PANIC	0	仅输出导致程序崩溃的致命错误（如内存分配失败）
     *  AV_LOG_FATAL	8	输出严重错误（如无法打开文件），程序可能无法继续运行
     *  AV_LOG_ERROR	16	输出普通错误（如处理帧失败），程序可能仍能部分运行
     *  AV_LOG_WARNING	24	输出警告信息（如不推荐的用法、格式不兼容），不影响核心功能
     *  AV_LOG_INFO	32	输出信息性消息（如处理进度、参数信息），用于说明程序正常运行状态
     *  AV_LOG_VERBOSE	40	输出详细信息（比INFO更细致），通常用于跟踪程序流程
     *  AV_LOG_DEBUG	48	输出调试信息（如函数调用细节、中间变量值），用于开发调试
     *  AV_LOG_TRACE	56	输出最详细的跟踪信息（如每一步操作的细节），仅用于深度调试
     */
    // av_log_set_level(AV_LOG_QUIET);

    if (level) {
        luat_ffmpeg_debug = 1;
    } else {
        luat_ffmpeg_debug = 0;
    }
}
