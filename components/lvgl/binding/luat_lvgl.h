
#ifndef LUAT_LVGL
#define LUAT_LVGL

#include "luat_base.h"

#include "lvgl.h"
#include "luat_lv_enum.h"
#include "luat_lv_gen.h"

#include "rotable.h"
#define LUAT_LOG_TAG "lvgl"
#include "luat_log.h"

#define LUAT_LV_DEBUG 1

#if (LUAT_LV_DEBUG == 1)
#define LV_DEBUG LLOGD
#else
#define LV_DEBUG
#endif

int luat_lv_init(lua_State *L);
void luat_lv_fs_init(void);


#include "luat_lvgl_anim.h"
#include "luat_lvgl_qrcode.h"
#include "luat_lvgl_gif.h"
#include "luat_lvgl_cb.h"
#include "luat_lvgl_style.h"
#include "luat_lv_style_dec.h"
#include "luat_lvgl_img_ext.h"
#include "luat_lvgl_imgbtn.h"
#include "luat_lvgl_map.h"
#include "luat_lvgl_gauge_ex.h"
#include "luat_lvgl_btnmatrix_ex.h"
#include "luat_lvgl_calendar_ex.h"
#include "luat_lvgl_ex.h"
#include "luat_lvgl_line_ex.h"

#include "luat_lvgl_fonts.h"
#include "luat_lvgl_font.h"

#endif
