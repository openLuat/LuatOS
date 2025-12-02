#define LUAT_LOG_TAG "easylvgl_win"
#include "easylvgl_component.h"
#include "luat_log.h"
#include "../lvgl9/lvgl.h"
#include "../lvgl9/src/widgets/win/lv_win.h"

static void easylvgl_win_close_event_cb(lv_event_t *e) {
    if (lv_event_get_code(e) != LV_EVENT_CLICKED) {
        return;
    }
    lv_obj_t *win = (lv_obj_t *)lv_event_get_user_data(e);
    if (win == NULL) {
        lv_obj_t *btn = lv_event_get_target_obj(e);
        win = btn == NULL ? NULL : lv_obj_get_parent(btn);
    }
    if (win != NULL) {
        easylvgl_component_call_callback(win);
        lv_obj_del(win);
    }
}

void easylvgl_component_attach_win_close_event(lv_obj_t *win, lv_obj_t *target) {
    if (win == NULL || target == NULL) {
        return;
    }
    easylvgl_component_meta_t *meta = easylvgl_component_ensure_meta(win);
    if (meta == NULL) {
        return;
    }
    if (meta->flags & EASYLVGL_COMPONENT_FLAG_CLOSE) {
        return;
    }
    lv_obj_add_event_cb(target, easylvgl_win_close_event_cb, LV_EVENT_CLICKED, win);
    meta->flags |= EASYLVGL_COMPONENT_FLAG_CLOSE;
}

static void easylvgl_apply_win_style(lua_State *L, int table_index, lv_obj_t *win) {
    const int abs_index = lua_absindex(L, table_index);
    lua_getfield(L, abs_index, "style");
    if (lua_istable(L, -1)) {
        int radius = 0;
        if (easylvgl_component_get_integer_field(L, lua_gettop(L), "radius", &radius)) {
            lv_obj_set_style_radius(win, radius, 0);
        }
        int pad = 0;
        if (easylvgl_component_get_integer_field(L, lua_gettop(L), "pad", &pad)) {
            lv_obj_set_style_pad_all(win, pad, 0);
        }
        int border = 0;
        if (easylvgl_component_get_integer_field(L, lua_gettop(L), "border_width", &border)) {
            lv_obj_set_style_border_width(win, border, 0);
        }
    }
    lua_pop(L, 1);
}

lv_obj_t *easylvgl_win_create_from_config(lua_State *L, int table_index) {
    lv_obj_t *parent = easylvgl_component_get_parent_from_table(L, table_index);
    if (parent == NULL) {
        parent = lv_screen_active();
        if (parent == NULL) {
            parent = lv_display_get_screen_active(lv_display_get_default());
        }
    }
    lv_obj_t *win = lv_win_create(parent);
    if (win == NULL) {
        return NULL;
    }
    easylvgl_component_apply_geometry(L, table_index, win);
    const char *title = easylvgl_component_get_string_field(L, table_index, "title");
    if (title != NULL) {
        lv_obj_t *title_label = lv_win_add_title(win, title);
        easylvgl_component_set_title(win, title_label);
    }
    bool close_btn = false;
    if (easylvgl_component_get_bool_field(L, table_index, "close_btn", &close_btn) && close_btn) {
        lv_obj_t *btn = lv_win_add_button(win, LV_SYMBOL_CLOSE, 40);
        easylvgl_component_attach_win_close_event(win, btn);
    }
    bool auto_center = false;
    if (easylvgl_component_get_bool_field(L, table_index, "auto_center", &auto_center) && auto_center) {
        lv_obj_center(win);
    }
    easylvgl_apply_win_style(L, table_index, win);
    lv_obj_t *cont = lv_win_get_content(win);
    easylvgl_component_set_content(win, cont);
    int callback_ref = easylvgl_component_capture_callback(L, table_index, "on_close");
    if (callback_ref != LUA_NOREF) {
        easylvgl_component_set_callback_ref(win, callback_ref);
        if (!close_btn) {
            lv_obj_add_event_cb(win, easylvgl_win_close_event_cb, LV_EVENT_DELETE, win);
        }
    }
    return win;
}

