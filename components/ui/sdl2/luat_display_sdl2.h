#ifndef LUAT_DISPLAY_SDL2_H
#define LUAT_DISPLAY_SDL2_H

#include <stdint.h>
#include <stddef.h>

typedef struct luat_display_sdl2_ctx luat_display_sdl2_ctx_t;

luat_display_sdl2_ctx_t* luat_display_sdl2_create(const char *title, uint32_t width, uint32_t height);
void luat_display_sdl2_destroy(luat_display_sdl2_ctx_t *ctx);
void luat_display_sdl2_draw(luat_display_sdl2_ctx_t *ctx, int16_t x, int16_t y, uint16_t w, uint16_t h, const void *data, uint32_t pitch);
void luat_display_sdl2_flush(luat_display_sdl2_ctx_t *ctx);
void luat_display_sdl2_pump_events(luat_display_sdl2_ctx_t *ctx);
int  luat_display_sdl2_is_exit_requested(luat_display_sdl2_ctx_t *ctx);

#endif
