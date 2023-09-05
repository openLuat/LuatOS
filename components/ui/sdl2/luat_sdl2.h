
#ifndef LUAT_SDL2_H
#define LUAT_SDL2_H
#include "luat_base.h"

typedef struct luat_sdl2_conf
{
    size_t width;
    size_t height;
    const char* title;
    // uint32_t color_space;
}luat_sdl2_conf_t;

int luat_sdl2_init(luat_sdl2_conf_t *conf);
int luat_sdl2_deinit(luat_sdl2_conf_t *conf);

void luat_sdl2_draw(int16_t x1, int16_t y1, int16_t x2, int16_t y2, uint32_t* data);
void luat_sdl2_flush(void);

#endif

