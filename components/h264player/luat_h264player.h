#ifndef LUAT_H264PLAYER_H
#define LUAT_H264PLAYER_H

#include <stddef.h>
#include <stdint.h>
#include "luat_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef LUAT_H264PLAYER_FRAME_WIDTH
#define LUAT_H264PLAYER_FRAME_WIDTH 640
#endif

#ifndef LUAT_H264PLAYER_FRAME_HEIGHT
#define LUAT_H264PLAYER_FRAME_HEIGHT 480
#endif

#ifndef LUAT_H264PLAYER_MAX_PIXELS
#define LUAT_H264PLAYER_MAX_PIXELS (640U*480U)
#endif

#if defined(LUAT_H264PLAYER_OUTPUT_RGB565) && defined(LUAT_H264PLAYER_OUTPUT_RGB8888)
#error "Only one of LUAT_H264PLAYER_OUTPUT_RGB565 or LUAT_H264PLAYER_OUTPUT_RGB8888 can be defined."
#endif

#if defined(LUAT_H264PLAYER_OUTPUT_RGB8888)
#define LUAT_H264PLAYER_OUTPUT_FORMAT 1
#define LUAT_H264PLAYER_PIXEL_BYTES 4
#else
#ifndef LUAT_H264PLAYER_OUTPUT_RGB565
#define LUAT_H264PLAYER_OUTPUT_RGB565 1
#endif
#define LUAT_H264PLAYER_OUTPUT_FORMAT 0
#define LUAT_H264PLAYER_PIXEL_BYTES 2
#endif

typedef struct luat_h264player_ctx luat_h264player_t;

typedef void (*luat_h264player_frame_cb_t)(void *userdata, const uint8_t *frame, size_t len,
										   uint16_t width, uint16_t height, uint8_t format);

/**
 * @brief 创建解码器实例（SPS/PPS 在 feed 数据中提供）
 * @param cb 解码帧回调，可为 NULL
 * @param userdata 回调用户参数
 * @return 解码器句柄，失败返回 NULL
 */
luat_h264player_t* luat_h264player_create(luat_h264player_frame_cb_t cb, void *userdata);

/**
 * @brief 设置解码帧回调
 * @param cb 解码帧回调，可为 NULL
 * @param userdata 回调用户参数
 */
void luat_h264player_set_callback(luat_h264player_t* ctx, luat_h264player_frame_cb_t cb, void *userdata);

/**
 * @brief 销毁解码器实例
 */
void luat_h264player_destroy(luat_h264player_t* ctx);

/**
 * @brief 输入 H264 bytestream (Annex-B, 含起始码)
 * @return LUAT_ERR_OK 或 LUAT_ERR_FAIL
 */
LUAT_RET luat_h264player_feed(luat_h264player_t* ctx, const uint8_t* data, size_t len);

/**
 * @brief 获取输出帧
 * @return 1 有新帧，0 无新帧
 */
int luat_h264player_get_frame(luat_h264player_t* ctx, const uint8_t** out, size_t* out_len);

uint16_t luat_h264player_get_width(luat_h264player_t* ctx);
uint16_t luat_h264player_get_height(luat_h264player_t* ctx);
uint8_t luat_h264player_get_format(luat_h264player_t* ctx);

#ifdef __cplusplus
}
#endif

#endif
