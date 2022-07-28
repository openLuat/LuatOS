#include "luat_base.h"
#include "luat_airui.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

int airui_block_lvgl_bar_cb(airui_block_t *bl) {
    lv_obj_t *parent = (lv_obj_t*)bl->parent;
    lv_obj_t *bar = lv_bar_create(parent, NULL);
    bl->self = bar;

    return 0;
}

