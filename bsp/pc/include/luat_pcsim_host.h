#ifndef LUAT_PCSIM_HOST_H
#define LUAT_PCSIM_HOST_H

#include "luat_base.h"
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void luat_pcsim_host_set_pixel_perfect(int enable);
int luat_pcsim_host_pixel_perfect(void);

void luat_pcsim_host_set_parent_hwnd(uint64_t hwnd);
uint64_t luat_pcsim_host_parent_hwnd(void);
void luat_pcsim_host_set_parent_offset(int x, int y);

void luat_pcsim_host_set_headless(int enable);
int luat_pcsim_host_headless(void);

int luat_pcsim_host_parse_agent_ctl(const char *addr);
int luat_pcsim_host_agent_ctl_port(void);

uint32_t luat_pcsim_host_window_flags(uint32_t base_flags);
int luat_pcsim_host_force_native_size(void);
int luat_pcsim_host_apply_window(void *sdl_window);
int luat_pcsim_host_parent_ok(void);

int luat_pcsim_host_bind(void *sdl_window, void *sdl_renderer, void *sdl_texture, int native_w, int native_h);
void luat_pcsim_host_unbind(void);
int luat_pcsim_host_ready(void);
int luat_pcsim_host_native_width(void);
int luat_pcsim_host_native_height(void);

void luat_pcsim_host_poll(void);

int luat_pcsim_host_inject_pointer(const char *type, int x, int y, const char *button, int from_x, int from_y, int dx, int dy);
int luat_pcsim_host_inject_key(const char *type, const char **keys, int key_count, const char *text);
int luat_pcsim_host_screenshot_png(uint8_t **out_png, size_t *out_len, int *out_w, int *out_h);
int luat_pcsim_host_copy_frame(uint32_t min_seq, uint8_t *out, size_t cap, uint32_t *seq, int *w, int *h, uint8_t *format, uint16_t *stride);

int luat_agent_ctl_start(void);
void luat_agent_ctl_stop(void);

#ifdef __cplusplus
}
#endif

#endif
