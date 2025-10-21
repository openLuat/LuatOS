#ifndef _LUAT_FREETYPEFONT_H_
#define _LUAT_FREETYPEFONT_H_

#include "luat_base.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LUAT_FREETYPEFONT_STATE_UNINIT = 0,
    LUAT_FREETYPEFONT_STATE_READY  = 1,
    LUAT_FREETYPEFONT_STATE_ERROR  = 2,
} luat_freetypefont_state_t;

int luat_freetypefont_init(const char *ttf_path);
void luat_freetypefont_deinit(void);
luat_freetypefont_state_t luat_freetypefont_get_state(void);
uint32_t luat_freetypefont_get_str_width(const char *utf8, unsigned char font_size);
int luat_freetypefont_draw_utf8(int x, int y, const char *utf8, unsigned char font_size, uint32_t color);

#ifdef __cplusplus
}
#endif

#endif /* _LUAT_FREETYPEFONT_H_ */
