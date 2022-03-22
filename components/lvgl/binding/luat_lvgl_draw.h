
#ifndef LUAT_LVGL_DRAW
#define LUAT_LVGL_DRAW

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_draw_mask_radius_param_t(lua_State *L);
int luat_lv_draw_mask_radius_param_t_free(lua_State *L);
int luat_lv_draw_mask_line_param_t(lua_State *L);
int luat_lv_draw_mask_line_param_t_free(lua_State *L);
int luat_lv_draw_mask_fade_param_t(lua_State *L);
int luat_lv_draw_mask_fade_param_t_free(lua_State *L);

#define LUAT_LV_DRAW_EX_RLT {"draw_mask_radius_param_t", ROREG_FUNC(luat_lv_draw_mask_radius_param_t)},\
{"draw_mask_radius_param_t_free", ROREG_FUNC(luat_lv_draw_mask_radius_param_t_free)},\
{"draw_mask_line_param_t", ROREG_FUNC(luat_lv_draw_mask_line_param_t)},\
{"draw_mask_line_param_t_free", ROREG_FUNC(luat_lv_draw_mask_line_param_t_free)},\
{"draw_mask_fade_param_t", ROREG_FUNC(luat_lv_draw_mask_fade_param_t)},\
{"draw_mask_fade_param_t_free", ROREG_FUNC(luat_lv_draw_mask_fade_param_t_free)},\

#endif
