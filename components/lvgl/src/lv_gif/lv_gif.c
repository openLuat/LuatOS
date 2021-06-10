/**
 * @file lv_gifenc.c
 *
 */

/*********************
 *      INCLUDES
 *********************/
#include "gifdec.h"

/*********************
 *      DEFINES
 *********************/
#define LV_OBJX_NAME "lv_gif"

/**********************
 *      TYPEDEFS
 **********************/
typedef struct {
    lv_img_ext_t img_ext;
    gd_GIF *gif;
    lv_task_t * task;
    lv_img_dsc_t imgdsc;
    uint32_t last_call;
}lv_gif_ext_t;

/**********************
 *  STATIC PROTOTYPES
 **********************/
static void next_frame_task_cb(lv_task_t * t);
static lv_res_t lv_gif_signal(lv_obj_t * img, lv_signal_t sign, void * param);

/**********************
 *  STATIC VARIABLES
 **********************/
static lv_signal_cb_t ancestor_signal;

/**********************
 *      MACROS
 **********************/

/**********************
 *   GLOBAL FUNCTIONS
 **********************/

lv_obj_t * lv_gif_create_from_file(lv_obj_t * parent, const char * path)
{
    lv_obj_t * img = lv_img_create(parent, NULL);
    lv_gif_ext_t * ext = lv_obj_allocate_ext_attr(img, sizeof(lv_gif_ext_t));
    LV_ASSERT_MEM(ext);

    if(ancestor_signal == NULL) ancestor_signal = lv_obj_get_signal_cb(img);
    lv_obj_set_signal_cb(img, lv_gif_signal);

    ext->gif = gd_open_gif_file(path);
    if(ext->gif == NULL) return img;

    ext->imgdsc.data = ext->gif->canvas;
    ext->imgdsc.header.always_zero = 0;
    ext->imgdsc.header.cf = LV_IMG_CF_TRUE_COLOR_ALPHA;
    ext->imgdsc.header.h = ext->gif->height;
    ext->imgdsc.header.w = ext->gif->width;
    ext->last_call = lv_tick_get();

    lv_img_set_src(img, &ext->imgdsc);

    ext->task = lv_task_create(next_frame_task_cb, 10, LV_TASK_PRIO_HIGH, img);
    next_frame_task_cb(ext->task);    /*Immediately process the first frame*/
    return img;
}

lv_obj_t * lv_gif_create_from_data(lv_obj_t * parent, const void * data)
{

    lv_obj_t * img = lv_img_create(parent, NULL);
    lv_gif_ext_t * ext = lv_obj_allocate_ext_attr(img, sizeof(lv_gif_ext_t));
    LV_ASSERT_MEM(ext);

    if(ancestor_signal == NULL) ancestor_signal = lv_obj_get_signal_cb(img);
    lv_obj_set_signal_cb(img, lv_gif_signal);

    ext->gif = gd_open_gif_data(data);
    if(ext->gif == NULL) return img;

    ext->imgdsc.data = ext->gif->canvas;
    ext->imgdsc.header.always_zero = 0;
    ext->imgdsc.header.cf = LV_IMG_CF_TRUE_COLOR_ALPHA;
    ext->imgdsc.header.h = ext->gif->height;
    ext->imgdsc.header.w = ext->gif->width;
    ext->last_call = lv_tick_get();

    lv_img_set_src(img, &ext->imgdsc);

    ext->task = lv_task_create(next_frame_task_cb, 10, LV_TASK_PRIO_HIGH, img);
    next_frame_task_cb(ext->task);    /*Immediately process the first frame*/
    return img;
}

void lv_gif_restart(lv_obj_t * gif)
{
    lv_gif_ext_t * ext = lv_obj_get_ext_attr(gif);
    lv_task_set_prio(ext->task, LV_TASK_PRIO_HIGH);
    gd_rewind(ext->gif);
}

/**********************
 *   STATIC FUNCTIONS
 **********************/

static void next_frame_task_cb(lv_task_t * t)
{
    lv_obj_t * img = t->user_data;
    lv_gif_ext_t * ext = lv_obj_get_ext_attr(img);
    uint32_t elaps = lv_tick_elaps(ext->last_call);
    if(elaps < ext->gif->gce.delay * 10) return;

    ext->last_call = lv_tick_get();

    int has_next = gd_get_frame(ext->gif);
    if(has_next == 0) {
        /*It was the last repeat*/
        if(ext->gif->loop_count == 1) {
            lv_res_t res = lv_signal_send(img, LV_SIGNAL_LEAVE, NULL);
            if(res != LV_RES_OK) return;

            res = lv_event_send(img, LV_EVENT_LEAVE, NULL);
            if(res != LV_RES_OK) return;
        } else {
            if(ext->gif->loop_count > 1)  ext->gif->loop_count--;
            gd_rewind(ext->gif);
        }
    }

    gd_render_frame(ext->gif, ext->imgdsc.data);

    lv_img_cache_invalidate_src(lv_img_get_src(img));
    lv_obj_invalidate(img);
}

/**
 * Signal function of the image
 * @param img pointer to a image object
 * @param sign a signal type from lv_signal_t enum
 * @param param pointer to a signal specific variable
 * @return LV_RES_OK: the object is not deleted in the function; LV_RES_INV: the object is deleted
 */
static lv_res_t lv_gif_signal(lv_obj_t * img, lv_signal_t sign, void * param)
{
    lv_res_t res;

    /* Include the ancient signal function */
    res = ancestor_signal(img, sign, param);
    if(res != LV_RES_OK) return res;
    if(sign == LV_SIGNAL_GET_TYPE) return lv_obj_handle_get_type_signal(param, LV_OBJX_NAME);

    lv_gif_ext_t * ext = lv_obj_get_ext_attr(img);

    if(sign == LV_SIGNAL_CLEANUP) {
        lv_img_cache_invalidate_src(&ext->imgdsc);
        gd_close_gif(ext->gif);
        lv_task_del(ext->task);
    } else if (sign == LV_SIGNAL_LEAVE) {
        lv_task_set_prio(ext->task, LV_TASK_PRIO_OFF);
    }

    return LV_RES_OK;
}
