/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"
#include "luat_malloc.h"
#include "luat_zbuff.h"

static void _canvas_gc(lv_event_t *e) {
    void *buf = lv_event_get_user_data(e);
    if (buf)
        luat_heap_free(buf);
    return LV_RES_OK;
}

int luat_lv_canvas_set_buffer(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_set_buffer");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    void *buf = NULL;
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 4);
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 5);
    buf = luat_heap_malloc((lv_img_cf_get_px_size(cf) * w * h) / 8);
    if (buf == NULL)
        return 0;
    lv_canvas_set_buffer(canvas ,buf ,w ,h ,cf);
    lv_obj_add_event_cb(canvas, _canvas_gc, LV_EVENT_DELETE, buf);
    return 0;
}
