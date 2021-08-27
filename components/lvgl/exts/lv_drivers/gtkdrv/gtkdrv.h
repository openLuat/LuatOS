/**
 * @file gtkdrv
 *
 */

#ifndef GTKDRV_H
#define GTKDRV_H

#ifdef __cplusplus
extern "C" {
#endif

/*********************
 *      INCLUDES
 *********************/
#include "src/lv_drv_conf.h"

#if USE_GTK

#include "lvgl.h"


/*********************
 *      DEFINES
 *********************/

/**********************
 *      TYPEDEFS
 **********************/

/**********************
 * GLOBAL PROTOTYPES
 **********************/
void gtkdrv_init(void);
uint32_t gtkdrv_tick_get(void);
void gtkdrv_flush_cb(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p);
void gtkdrv_mouse_read_cb(lv_indev_drv_t * drv, lv_indev_data_t * data);
void gtkdrv_keyboard_read_cb(lv_indev_drv_t * drv, lv_indev_data_t * data);
/**********************
 *      MACROS
 **********************/

#endif /*USE_GTK*/

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* GTKDRV_H */
