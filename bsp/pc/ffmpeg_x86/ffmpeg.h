#ifndef __FFMPEG_H
#define __FFMPEG_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#endif

// 先包含头文件获取类型定义
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>

#ifdef LUAT_USE_GUI
#define SDL_MAIN_HANDLED
#include <SDL2/SDL.h>
#endif

#ifdef _WIN32
// FFmpeg DLL句柄（声明为extern，在ffmpeg.c中定义）
extern HMODULE h_avutil;
extern HMODULE h_avcodec;
extern HMODULE h_avformat;
extern HMODULE h_swresample;

// 定义函数指针类型
typedef int (*av_find_best_stream_t)(AVFormatContext*, enum AVMediaType, int, int, const AVCodec**, int);
typedef int (*avformat_open_input_t)(AVFormatContext**, const char*, const AVInputFormat*, AVDictionary**);
typedef int (*avformat_find_stream_info_t)(AVFormatContext*, AVDictionary**);
typedef void (*avformat_close_input_t)(AVFormatContext**);
typedef int (*av_read_frame_t)(AVFormatContext*, AVPacket*);
typedef const AVCodec* (*avcodec_find_decoder_t)(enum AVCodecID);
typedef AVCodecContext* (*avcodec_alloc_context3_t)(const AVCodec*);
typedef void (*avcodec_free_context_t)(AVCodecContext**);
typedef int (*avcodec_parameters_to_context_t)(AVCodecContext*, const AVCodecParameters*);
typedef int (*avcodec_open2_t)(AVCodecContext*, const AVCodec*, AVDictionary**);
typedef int (*avcodec_send_packet_t)(AVCodecContext*, const AVPacket*);
typedef int (*avcodec_receive_frame_t)(AVCodecContext*, AVFrame*);
typedef const char* (*av_get_media_type_string_t)(enum AVMediaType);
typedef uint64_t (*av_get_default_channel_layout_t)(int);
typedef AVFrame* (*av_frame_alloc_t)(void);
typedef void (*av_frame_free_t)(AVFrame**);
typedef AVPacket* (*av_packet_alloc_t)(void);
typedef void (*av_packet_free_t)(AVPacket**);
typedef void (*av_packet_unref_t)(AVPacket*);
typedef int (*av_samples_alloc_t)(uint8_t**, int*, int, int, enum AVSampleFormat, int);
typedef void (*av_freep_t)(void*);
typedef int64_t (*av_rescale_rnd_t)(int64_t, int64_t, int64_t, enum AVRounding);
typedef int (*av_get_bytes_per_sample_t)(enum AVSampleFormat);
typedef void (*av_log_set_level_t)(int);
typedef struct SwrContext* (*swr_alloc_set_opts_t)(struct SwrContext*, int64_t, enum AVSampleFormat, int, int64_t, enum AVSampleFormat, int, int, void*);
typedef int (*swr_init_t)(struct SwrContext*);
typedef void (*swr_free_t)(struct SwrContext**);
typedef int (*swr_convert_t)(struct SwrContext*, uint8_t**, int, const uint8_t**, int);
typedef int64_t (*swr_get_delay_t)(struct SwrContext*, int64_t);

// 函数指针变量（声明为extern，在ffmpeg.c中定义）
extern av_find_best_stream_t p_av_find_best_stream;
extern avformat_open_input_t p_avformat_open_input;
extern avformat_find_stream_info_t p_avformat_find_stream_info;
extern avformat_close_input_t p_avformat_close_input;
extern av_read_frame_t p_av_read_frame;
extern avcodec_find_decoder_t p_avcodec_find_decoder;
extern avcodec_alloc_context3_t p_avcodec_alloc_context3;
extern avcodec_free_context_t p_avcodec_free_context;
extern avcodec_parameters_to_context_t p_avcodec_parameters_to_context;
extern avcodec_open2_t p_avcodec_open2;
extern avcodec_send_packet_t p_avcodec_send_packet;
extern avcodec_receive_frame_t p_avcodec_receive_frame;
extern av_get_media_type_string_t p_av_get_media_type_string;
extern av_get_default_channel_layout_t p_av_get_default_channel_layout;
extern av_frame_alloc_t p_av_frame_alloc;
extern av_frame_free_t p_av_frame_free;
extern av_packet_alloc_t p_av_packet_alloc;
extern av_packet_free_t p_av_packet_free;
extern av_packet_unref_t p_av_packet_unref;
extern av_samples_alloc_t p_av_samples_alloc;
extern av_freep_t p_av_freep;
extern av_rescale_rnd_t p_av_rescale_rnd;
extern av_get_bytes_per_sample_t p_av_get_bytes_per_sample;
extern av_log_set_level_t p_av_log_set_level;
extern swr_alloc_set_opts_t p_swr_alloc_set_opts;
extern swr_init_t p_swr_init;
extern swr_free_t p_swr_free;
extern swr_convert_t p_swr_convert;
extern swr_get_delay_t p_swr_get_delay;

// 宏定义名字，便于调用函数
#define av_find_best_stream p_av_find_best_stream
#define avformat_open_input p_avformat_open_input
#define avformat_find_stream_info p_avformat_find_stream_info
#define avformat_close_input p_avformat_close_input
#define av_read_frame p_av_read_frame
#define avcodec_find_decoder p_avcodec_find_decoder
#define avcodec_alloc_context3 p_avcodec_alloc_context3
#define avcodec_free_context p_avcodec_free_context
#define avcodec_parameters_to_context p_avcodec_parameters_to_context
#define avcodec_open2 p_avcodec_open2
#define avcodec_send_packet p_avcodec_send_packet
#define avcodec_receive_frame p_avcodec_receive_frame
#define av_get_media_type_string p_av_get_media_type_string
#define av_get_default_channel_layout p_av_get_default_channel_layout
#define av_frame_alloc p_av_frame_alloc
#define av_frame_free p_av_frame_free
#define av_packet_alloc p_av_packet_alloc
#define av_packet_free p_av_packet_free
#define av_packet_unref p_av_packet_unref
#define av_samples_alloc p_av_samples_alloc
#define av_freep p_av_freep
#define av_rescale_rnd p_av_rescale_rnd
#define av_get_bytes_per_sample p_av_get_bytes_per_sample
#define av_log_set_level p_av_log_set_level
#define swr_alloc_set_opts p_swr_alloc_set_opts
#define swr_init p_swr_init
#define swr_free p_swr_free
#define swr_convert p_swr_convert
#define swr_get_delay p_swr_get_delay
#endif

// 显式加载FFmpeg DLL
int luat_load_ffmpeg_dlls(void);
// 卸载FFmpeg DLL
void luat_unload_ffmpeg_dlls(void);
// 播放文件
int luat_ffmpeg_play_file(const char *path);
// 日志是否输出
void luat_ffmpeg_set_debug(int level);
#endif
