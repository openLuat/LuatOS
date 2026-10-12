#ifndef LUAT_VIDEOPLAYER_SINK_H
#define LUAT_VIDEOPLAYER_SINK_H

#include "luat_videoplayer.h"
#include <stdint.h>

/**
 * 是否编译了 display 或 lcd 绘制后端。
 * 用于决定是否向 Lua 导出 videoplayer.draw_frame。
 */
int luat_videoplayer_sink_available(void);

/**
 * 将一帧 RGB565 画到默认屏幕。优先 display，失败再 lcd。
 * @param consumed 非 NULL 时：1 表示 sink 接管了 frame->data（调用方不要 free）
 * @return LUAT_VP_OK / LUAT_VP_ERR_NOIMPL / 其他负错误码
 */
int luat_videoplayer_sink_draw(luat_vp_frame_t *frame, int16_t x, int16_t y, uint8_t *consumed);

int luat_videoplayer_sink_display_present(void);
int luat_videoplayer_sink_lcd_present(void);
int luat_videoplayer_sink_display_draw(luat_vp_frame_t *frame, int16_t x, int16_t y, uint8_t *consumed);
int luat_videoplayer_sink_lcd_draw(luat_vp_frame_t *frame, int16_t x, int16_t y, uint8_t *consumed);

#endif
