/*
处理输入设备的remotem命令
*/
#include "luat_base.h"
#include "luat_remotem.h"
#include "luat_malloc.h"

#include "lvgl.h"

static lv_indev_data_t point_emulator_data = {0};

extern void luat_str_fromhex(char* str, size_t len, char* buff);

static bool point_input_read(lv_indev_drv_t * drv, lv_indev_data_t*data) {
    memcpy(data, drv->user_data, sizeof(lv_indev_data_t));
    // if (((lv_indev_data_t*)drv->user_data)->state == LV_INDEV_STATE_PR){
    //     ((lv_indev_data_t*)drv->user_data)->state == LV_INDEV_STATE_REL;
    // }
    return false;
}

// 输入设备, 模拟鼠标点击/触摸屏点击
void luat_remotem_typeopt_indev(cJSON* top, cJSON* data) {
    cJSON* opt = cJSON_GetObjectItem(data, "opt");
    if (opt == NULL || opt->type != cJSON_String) {
        return;
    }
    if (!strcmp("pointer", opt->valuestring)) {
        cJSON* pointer = cJSON_GetObjectItem(data, "pointer");
        if (pointer) {
            cJSON* x = cJSON_GetObjectItem(pointer, "x");
            cJSON* y = cJSON_GetObjectItem(pointer, "y");
            cJSON* state = cJSON_GetObjectItem(pointer, "state");
            if (x != NULL && y != NULL && state != NULL) {
                point_emulator_data.point.x = x->valueint;
                point_emulator_data.point.y = y->valueint;
                point_emulator_data.state = state->valueint;
            }
        }
    }
}

void luat_remotem_indev_init(void) {
    lv_indev_drv_t indev_drv;
    lv_indev_drv_init(&indev_drv);
    indev_drv.user_data = &point_emulator_data;
    memset(indev_drv.user_data, 0, sizeof(lv_indev_data_t));
    indev_drv.read_cb = point_input_read;
    lv_indev_drv_register(&indev_drv);
}
