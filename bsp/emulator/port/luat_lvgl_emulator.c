#include "luat_base.h"
#include "luat_malloc.h"

#include "lv_conf.h"
#include "lvgl.h"

#define LUAT_LOG_TAG "win32"
#include "luat_log.h"

#include "luat_remotem.h"
#include "windows.h"
#include "luat_msgbus.h"

uint32_t WINDOW_HOR_RES = LV_HOR_RES_MAX;
uint32_t WINDOW_VER_RES = LV_VER_RES_MAX;

typedef struct luat_lv {
    lv_disp_t* disp;
    lv_disp_buf_t disp_buf;
    int buff_ref;
    int buff2_ref;
}luat_lv_t;

static luat_lv_t LV = {0};

static char* rbuff;

#ifdef LUAT_USE_LVGL

#include "lvgl.h"
static int luat_lvg_handler(lua_State* L, void* ptr) {
    lv_tick_inc(25);
    lv_task_handler();
    return 0;
}

static void CALLBACK _lvgl_handler(HWND hwnd,       
    UINT message,     
    UINT idTimer,     
    DWORD dwTime) {
    rtos_msg_t msg = {0};
    msg.handler = luat_lvg_handler;
    luat_msgbus_put(&msg, 0);
}
#endif

void luat_lv_disp_flush(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p) {
    //-----
    //LLOGD("disp_flush (%d, %d, %d, %d)", area->x1, area->y1, area->x2, area->y2);
    if (luat_remotem_ready()) {
        cJSON* top = cJSON_CreateObject();
        cJSON* data = luat_remotem_json_init(top);
        //luat_heap_malloc(sizeof(lv_color16_t) * (area->x2 - area->x1) * (area->y2 - area->y1) * 2);
        cJSON_AddStringToObject(top, "type", "display");
        cJSON_AddStringToObject(data, "opt", "zone_update");
        cJSON_AddStringToObject(data, "type", "hex");
        //char* buff = luat_heap_malloc(l * 2 + 1);
        size_t len = (area->x2 - area->x1) * (area->y2 - area->y1);
        luat_str_tohex((char*)color_p, len, rbuff);
        rbuff[len * 2] = 0x00;

        cJSON* _rbuff = cJSON_AddObjectToObject(data, "rbuff");
        cJSON_AddStringToObject(_rbuff, "type", "hex");
        cJSON_AddStringToObject(_rbuff, "value", rbuff);

        cJSON* _area = cJSON_AddObjectToObject(data, "area");
        cJSON_AddNumberToObject(_area, "x1", area->x1);
        cJSON_AddNumberToObject(_area, "x2", area->x2);
        cJSON_AddNumberToObject(_area, "y1", area->y1);
        cJSON_AddNumberToObject(_area, "y2", area->y2);

        luat_remotem_up(top);
        cJSON_Delete(top);
    }

    lv_disp_flush_ready(disp_drv);
}

void emulator_lvgl_init(int w, int h) {
    if (rbuff != NULL) {
        LLOGE("lvgl was init completed!!");
        return;
    }
    size_t fbuff_size = w * 10;
    LLOGD("w %d h %d buff %d", w, h, fbuff_size);
    lv_color_t* fbuffer = luat_heap_malloc(fbuff_size * sizeof(lv_color_t));

    lv_disp_buf_init(&LV.disp_buf, fbuffer, NULL, fbuff_size);

    lv_disp_drv_t my_disp_drv;
    lv_disp_drv_init(&my_disp_drv);

    my_disp_drv.flush_cb = luat_lv_disp_flush;

    my_disp_drv.hor_res = w;
    my_disp_drv.ver_res = h;
    my_disp_drv.buffer = &LV.disp_buf;
    //LLOGD(">>%s %d", __func__, __LINE__);
    LV.disp = lv_disp_drv_register(&my_disp_drv);

    rbuff = luat_heap_malloc(sizeof(lv_color_t) * w * h *2 + 4);

    // send message to mqtt
    {
        cJSON* top = cJSON_CreateObject();
        cJSON* data = luat_remotem_json_init(top);
        cJSON_AddStringToObject(top, "type", "display");
        cJSON_AddStringToObject(data, "opt", "init");
        cJSON_AddNumberToObject(data, "w", w);
        cJSON_AddNumberToObject(data, "h", h);
        cJSON_AddStringToObject(data, "colorspace", "rgb565");
        cJSON_AddBoolToObject(data, "colorswap", true);

        luat_remotem_up(top);
        cJSON_Delete(top);
    }
    
    SetTimer(NULL, 0, 25, _lvgl_handler);
}
