#ifndef _LUAT_HZFONT_H_
#define _LUAT_HZFONT_H_

#include "luat_base.h"
#include <stdint.h>
#include "ttf_parser.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LUAT_HZFONT_STATE_UNINIT = 0,
    LUAT_HZFONT_STATE_READY  = 1,
    LUAT_HZFONT_STATE_ERROR  = 2,
} luat_hzfont_state_t;

int luat_hzfont_init(const char *ttf_path, uint32_t cache_size, int load_to_psram);
void luat_hzfont_deinit(void);
luat_hzfont_state_t luat_hzfont_get_state(void);
uint32_t luat_hzfont_get_str_width(const char *utf8, unsigned char font_size);
/* antialias = -1(自动), 1(无AA), 2(2x2), 4(4x4) */
int luat_hzfont_draw_utf8(int x, int y, const char *utf8, unsigned char font_size, uint32_t color, int antialias);
// 用于easylvgl的hzfont兼容接口
TtfFont * luat_hzfont_get_ttf(void);
const TtfBitmap * luat_hzfont_get_bitmap(uint16_t glyph_index, uint8_t font_size, uint8_t supersample);
#ifdef __cplusplus
}
#endif

#endif /* _LUAT_HZFONT_H_ */
