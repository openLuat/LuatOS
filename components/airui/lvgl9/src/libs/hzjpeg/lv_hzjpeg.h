/**
 * @file lv_hzjpeg.h
 *
 */

#ifndef LV_HZJPEG_H
#define LV_HZJPEG_H

#ifdef __cplusplus
extern "C" {
#endif

/*********************
 *      INCLUDES
 *********************/
#include "../../lv_conf_internal.h"

#if LV_USE_HZJPEG

/**********************
 * GLOBAL PROTOTYPES
 **********************/

void lv_hzjpeg_init(void);

void lv_hzjpeg_deinit(void);

#endif /*LV_USE_HZJPEG*/

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /*LV_HZJPEG_H*/
