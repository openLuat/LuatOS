#include "luat_base.h"
#include "luat_airui.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

int airui_block_lvgl_slider_cb(airui_block_t *bl) {
    lv_obj_t *parent = (lv_obj_t*)bl->parent;
    lv_obj_t *obj = lv_slider_create(parent, NULL);
    bl->self = obj;



    return 0;
}

