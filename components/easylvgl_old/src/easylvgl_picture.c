#define LUAT_LOG_TAG "easylvgl_picture"
#include "easylvgl_component.h"
#include "luat_log.h"
#include "../lvgl9/lvgl.h"
#include "../lvgl9/src/widgets/image/lv_image.h"

static void easylvgl_image_apply_props(lua_State *L, int table_index, lv_obj_t *img) {
    const char *src = easylvgl_component_get_string_field(L, table_index, "src");
    if (src != NULL) {
        lv_img_set_src(img, src);
    }
    lv_point_t pivot;
    if (easylvgl_component_get_pivot(L, table_index, &pivot)) {
        lv_img_set_pivot(img, pivot.x, pivot.y);
    }
    int zoom = 0;
    if (easylvgl_component_get_integer_field(L, table_index, "zoom", &zoom)) {
        lv_img_set_zoom(img, zoom);
    }
    int opacity = 0;
    if (easylvgl_component_get_integer_field(L, table_index, "opacity", &opacity)) {
        lv_obj_set_style_opa(img, opacity, 0);
    }
}

lv_obj_t *easylvgl_image_create_from_config(lua_State *L, int table_index) {
    lv_obj_t *parent = easylvgl_component_get_parent_from_table(L, table_index);
    if (parent == NULL) {
        parent = lv_screen_active();
        if (parent == NULL) {
            parent = lv_obj_get_screen(lv_disp_get_default());
        }
    }
    lv_obj_t *img = lv_img_create(parent);
    if (img == NULL) {
        return NULL;
    }
    easylvgl_component_apply_geometry(L, table_index, img);
    easylvgl_image_apply_props(L, table_index, img);
    int callback_ref = easylvgl_component_capture_callback(L, table_index, "on_click");
    if (callback_ref != LUA_NOREF) {
        easylvgl_component_set_callback_ref(img, callback_ref);
        easylvgl_component_attach_click_event(img);
    }
    return img;
}

