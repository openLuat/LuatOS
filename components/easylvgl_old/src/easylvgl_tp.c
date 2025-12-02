#include "easylvgl.h"
#include "luat_tp.h"
#include "luat_log.h"
#include "../lvgl9/lvgl.h"
#include <stdbool.h>

#define LUAT_LOG_TAG "easylvgl_tp"

static luat_tp_data_t *g_tp_data = NULL;
static lv_indev_t *g_tp_indev = NULL;

static bool easylvgl_tp_pressed(void) {
    if (g_tp_data == NULL) {
        return false;
    }
    return g_tp_data[0].event == TP_EVENT_TYPE_DOWN || g_tp_data[0].event == TP_EVENT_TYPE_MOVE;
}

static inline void easylvgl_tp_get_xy(lv_coord_t *x, lv_coord_t *y) {
    if (g_tp_data == NULL || x == NULL || y == NULL) {
        return;
    }
    *x = (lv_coord_t)g_tp_data[0].x_coordinate;
    *y = (lv_coord_t)g_tp_data[0].y_coordinate;
}

static void easylvgl_touch_read_cb(lv_indev_t *indev, lv_indev_data_t *data) {
    static lv_point_t last_point = {0, 0};

    if (easylvgl_tp_pressed()) {
        easylvgl_tp_get_xy(&last_point.x, &last_point.y);
        data->state = LV_INDEV_STATE_PRESSED;
    }
    else {
        data->state = LV_INDEV_STATE_RELEASED;
    }
    data->point = last_point;
}

int easylvgl_indev_tp_register(struct luat_tp_config* luat_tp_config) {
    if (luat_tp_config == NULL) {
        LLOGE("luat_tp_config is NULL");
        return -1;
    }

    g_tp_data = luat_tp_config->tp_data;

    if (g_tp_indev == NULL) {
        g_tp_indev = lv_indev_create();
        if (g_tp_indev == NULL) {
            LLOGE("lv_indev_create failed");
            return -1;
        }
        lv_indev_set_type(g_tp_indev, LV_INDEV_TYPE_POINTER);
        lv_indev_set_read_cb(g_tp_indev, easylvgl_touch_read_cb);
        lv_indev_set_user_data(g_tp_indev, luat_tp_config);
        lv_indev_set_driver_data(g_tp_indev, luat_tp_config);
        lv_indev_set_group(g_tp_indev, NULL);
        lv_display_t *disp = lv_display_get_default();
        if (disp != NULL) {
            lv_indev_set_display(g_tp_indev, disp);
        }
        LLOGD("registered indev %p", g_tp_indev);
    }

    lv_indev_set_user_data(g_tp_indev, luat_tp_config);
    return 0;
}

