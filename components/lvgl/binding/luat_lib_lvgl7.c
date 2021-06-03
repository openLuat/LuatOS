
#include "luat_base.h"
#include "luat_lvgl.h"
#include "luat_malloc.h"
#include "luat_zbuff.h"

static lv_disp_t* my_disp = NULL;
static lv_disp_buf_t disp_buff = {0};

static void disp_flush(struct _disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p) {
    //-----
    int32_t x;
    int32_t y;
    for(y = area->y1; y <= area->y2; y++) {
        for(x = area->x1; x <= area->x2; x++) {
            /* Put a pixel to the display. For example: */
            /* put_px(x, y, *color_p)*/
            color_p++;
        }
    }
    //----
    lv_disp_flush_ready(disp_drv);
}


int luat_lv_init(lua_State *L) {
    if (my_disp != NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lv_color_t *fbuffer = NULL; 
    size_t fbuff_size = LV_HOR_RES_MAX * 10;
    if (lua_isuserdata(L, 1)) {
        luat_zbuff *zbuff = tozbuff(L);
        fbuffer = (lv_color_t *)zbuff->addr;
        fbuff_size = zbuff->len / sizeof(lv_color_t);
    }
    else {
        fbuffer = luat_heap_malloc(fbuff_size * sizeof(lv_color_t));
    }
    lv_disp_buf_init(&disp_buff, fbuffer, NULL, fbuff_size);

    lv_disp_drv_t disp_drv;
    lv_disp_drv_init(&disp_drv);

    disp_drv.flush_cb = disp_flush;

    disp_drv.hor_res = 480;
    disp_drv.ver_res = 320;
    disp_drv.buffer = &disp_buff;
    //LLOGD(">>%s %d", __func__, __LINE__);
    my_disp = lv_disp_drv_register(&disp_drv);
    //LLOGD(">>%s %d", __func__, __LINE__);
    lua_pushboolean(L, my_disp != NULL ? 1 : 0);
    //LLOGD(">>%s %d", __func__, __LINE__);
    return 1;
}
