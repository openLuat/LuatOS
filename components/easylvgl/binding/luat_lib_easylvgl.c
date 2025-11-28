/*
@module  easylvgl
@summary EasyLVGL图像库 (LVGL 9.4)
@version 0.0.3
@date    2025.11.26
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "rotable2.h"
#include "../inc/easylvgl.h"
#include "luat_lcd.h"
#include "../inc/easylvgl_component.h"
#include "../lvgl9/src/widgets/button/lv_button.h"
#include "../lvgl9/src/widgets/label/lv_label.h"
#include "../lvgl9/src/widgets/image/lv_image.h"
#include "../lvgl9/src/widgets/win/lv_win.h"
#include <string.h>

#define LUAT_LOG_TAG "easylvgl"
#include "luat_log.h"

static int l_easylvgl_init(lua_State *L);
static int l_easylvgl_button(lua_State *L);
static int l_easylvgl_label(lua_State *L);
static int l_easylvgl_image(lua_State *L);
static int l_easylvgl_win(lua_State *L);
static int l_easylvgl_handler(lua_State *L);

static void register_button_meta(lua_State *L);
static void register_label_meta(lua_State *L);
static void register_image_meta(lua_State *L);
static void register_win_meta(lua_State *L);

static void push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt);
static lv_obj_t *check_component(lua_State *L, int index, const char *mt);

static int l_button_set_text(lua_State *L);
static int l_button_set_on_click(lua_State *L);
static int l_button_gc(lua_State *L);

static int l_label_set_text(lua_State *L);
static int l_label_get_text(lua_State *L);
static int l_label_gc(lua_State *L);

static int l_image_set_on_click(lua_State *L);
static int l_image_gc(lua_State *L);

static int l_win_set_title(lua_State *L);
static int l_win_set_content(lua_State *L);
static int l_win_set_close_cb(lua_State *L);
static int l_win_set_style(lua_State *L);
static int l_win_close(lua_State *L);
static int l_win_on_close(lua_State *L);
static int l_win_gc(lua_State *L);

static const rotable_Reg_t reg_easylvgl[] = {
    {"init", ROREG_FUNC(l_easylvgl_init)},
    {"handler", ROREG_FUNC(l_easylvgl_handler)},
    {"button", ROREG_FUNC(l_easylvgl_button)},
    {"label", ROREG_FUNC(l_easylvgl_label)},
    {"image", ROREG_FUNC(l_easylvgl_image)},
    {"win", ROREG_FUNC(l_easylvgl_win)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_easylvgl(lua_State *L) {
    register_button_meta(L);
    register_label_meta(L);
    register_image_meta(L);
    register_win_meta(L);
    luat_newlib2(L, reg_easylvgl);
    return 1;
}

static int l_easylvgl_init(lua_State *L) {
    easylvgl_set_lua_state(L);
    int w = luaL_optinteger(L, 1, 480);
    int h = luaL_optinteger(L, 2, 320);
    size_t buf_size = 0;
    uint8_t buff_mode = 0x06;
    if (lua_isinteger(L, 3)) {
        buf_size = luaL_checkinteger(L, 3);
    }
    if (lua_isinteger(L, 4)) {
        buff_mode = luaL_checkinteger(L, 4);
    }
    luat_lcd_conf_t *lcd_conf = NULL;
    if (lua_isuserdata(L, 5)) {
        lcd_conf = (luat_lcd_conf_t *)lua_touserdata(L, 5);
    }
    int ret = easylvgl_init_internal(w, h, buf_size, buff_mode, lcd_conf);
    lua_pushboolean(L, ret == 0);
    return 1;
}

static int l_easylvgl_button(lua_State *L) {
    lv_obj_t *btn = easylvgl_button_create_from_config(L, 1);
    if (btn == NULL) {
        lua_pushnil(L);
        return 1;
    }
    push_component_userdata(L, btn, EASYLVGL_BUTTON_MT);
    return 1;
}

static int l_easylvgl_label(lua_State *L) {
    lv_obj_t *label = easylvgl_label_create_from_config(L, 1);
    if (label == NULL) {
        lua_pushnil(L);
        return 1;
    }
    push_component_userdata(L, label, EASYLVGL_LABEL_MT);
    return 1;
}

static int l_easylvgl_image(lua_State *L) {
    lv_obj_t *img = easylvgl_image_create_from_config(L, 1);
    if (img == NULL) {
        lua_pushnil(L);
        return 1;
    }
    push_component_userdata(L, img, EASYLVGL_IMAGE_MT);
    return 1;
}

static int l_easylvgl_win(lua_State *L) {
    lv_obj_t *win = easylvgl_win_create_from_config(L, 1);
    if (win == NULL) {
        lua_pushnil(L);
        return 1;
    }
    push_component_userdata(L, win, EASYLVGL_WIN_MT);
    return 1;
}

static int l_easylvgl_handler(lua_State *L) {
    uint32_t time_till_next = lv_timer_handler();
    lua_pushinteger(L, time_till_next);
    return 1;
}

static void push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)lua_newuserdata(L, sizeof(easylvgl_component_ud_t));
    ud->obj = obj;
    luaL_getmetatable(L, mt);
    lua_setmetatable(L, -2);
}

static lv_obj_t *check_component(lua_State *L, int index, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, index, mt);
    if (ud == NULL || ud->obj == NULL) {
        luaL_error(L, "invalid %s object", mt);
    }
    return ud->obj;
}

static int l_button_set_text(lua_State *L) {
    lv_obj_t *btn = check_component(L, 1, EASYLVGL_BUTTON_MT);
    const char *text = luaL_checkstring(L, 2);
    easylvgl_button_set_text(btn, text);
    return 0;
}

static int l_button_set_on_click(lua_State *L) {
    lv_obj_t *btn = check_component(L, 1, EASYLVGL_BUTTON_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_component_set_callback_ref(btn, ref);
    easylvgl_component_attach_click_event(btn);
    return 0;
}

static int l_button_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_BUTTON_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_component_release_meta(ud->obj);
        lv_obj_del(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

static int l_label_set_text(lua_State *L) {
    lv_obj_t *label = check_component(L, 1, EASYLVGL_LABEL_MT);
    const char *text = luaL_checkstring(L, 2);
    easylvgl_label_set_text(label, text);
    return 0;
}

static int l_label_get_text(lua_State *L) {
    lv_obj_t *label = check_component(L, 1, EASYLVGL_LABEL_MT);
    const char *text = easylvgl_label_get_text(label);
    if (text == NULL) {
        lua_pushnil(L);
    } else {
        lua_pushstring(L, text);
    }
    return 1;
}

static int l_label_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_LABEL_MT);
    if (ud != NULL && ud->obj != NULL) {
        lv_obj_del(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

static int l_image_set_on_click(lua_State *L) {
    lv_obj_t *img = check_component(L, 1, EASYLVGL_IMAGE_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_component_set_callback_ref(img, ref);
    easylvgl_component_attach_click_event(img);
    return 0;
}

static int l_image_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_IMAGE_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_component_release_meta(ud->obj);
        lv_obj_del(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

static int l_win_set_title(lua_State *L) {
    lv_obj_t *win = check_component(L, 1, EASYLVGL_WIN_MT);
    const char *text = luaL_checkstring(L, 2);
    lv_obj_t *title = easylvgl_component_get_title(win);
    if (title == NULL) {
        title = lv_win_add_title(win, text);
        easylvgl_component_set_title(win, title);
    } else {
        lv_label_set_text(title, text);
    }
    return 0;
}

static int l_win_set_content(lua_State *L) {
    lv_obj_t *win = check_component(L, 1, EASYLVGL_WIN_MT);
    lv_obj_t *content = easylvgl_component_get_content(win);
    if (content == NULL) {
        luaL_error(L, "win content container missing");
        return 0;
    }
    lv_obj_t *child = easylvgl_component_get_lv_obj_from_value(L, 2);
    if (child == NULL) {
        luaL_error(L, "expect object for content");
        return 0;
    }
    lv_obj_set_parent(child, content);
    return 0;
}

static int l_win_set_close_cb(lua_State *L) {
    lv_obj_t *win = check_component(L, 1, EASYLVGL_WIN_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_component_set_callback_ref(win, ref);
    return 0;
}

static int l_win_set_style(lua_State *L) {
    lv_obj_t *win = check_component(L, 1, EASYLVGL_WIN_MT);
    const char *field = luaL_checkstring(L, 2);
    int value = luaL_checkinteger(L, 3);
    if (strcmp(field, "radius") == 0) {
        lv_obj_set_style_radius(win, value, 0);
    } else if (strcmp(field, "pad") == 0) {
        lv_obj_set_style_pad_all(win, value, 0);
    } else if (strcmp(field, "border_width") == 0) {
        lv_obj_set_style_border_width(win, value, 0);
    } else if (strcmp(field, "shadow") == 0) {
        lv_obj_set_style_shadow_width(win, value, 0);
    }
    return 0;
}

static int l_win_close(lua_State *L) {
    lv_obj_t *win = check_component(L, 1, EASYLVGL_WIN_MT);
    easylvgl_component_call_callback(win);
    lv_obj_del(win);
    return 0;
}

static int l_win_on_close(lua_State *L) {
    return l_win_set_close_cb(L);
}

static int l_win_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_WIN_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_component_release_meta(ud->obj);
        lv_obj_del(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

static void register_button_meta(lua_State *L) {
    if (luaL_newmetatable(L, EASYLVGL_BUTTON_MT)) {
        luaL_Reg methods[] = {
            {"set_text", l_button_set_text},
            {"set_on_click", l_button_set_on_click},
            {NULL, NULL}
        };
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        luaL_setfuncs(L, methods, 0);
        lua_pushcfunction(L, l_button_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}

static void register_label_meta(lua_State *L) {
    if (luaL_newmetatable(L, EASYLVGL_LABEL_MT)) {
        luaL_Reg methods[] = {
            {"set_text", l_label_set_text},
            {"get_text", l_label_get_text},
            {NULL, NULL}
        };
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        luaL_setfuncs(L, methods, 0);
        lua_pushcfunction(L, l_label_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}

static void register_image_meta(lua_State *L) {
    if (luaL_newmetatable(L, EASYLVGL_IMAGE_MT)) {
        luaL_Reg methods[] = {
            {"set_on_click", l_image_set_on_click},
            {NULL, NULL}
        };
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        luaL_setfuncs(L, methods, 0);
        lua_pushcfunction(L, l_image_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}

static void register_win_meta(lua_State *L) {
    if (luaL_newmetatable(L, EASYLVGL_WIN_MT)) {
        luaL_Reg methods[] = {
            {"set_title", l_win_set_title},
            {"set_content", l_win_set_content},
            {"set_close_cb", l_win_set_close_cb},
            {"set_style", l_win_set_style},
            {"close", l_win_close},
            {"on_close", l_win_on_close},
            {NULL, NULL}
        };
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        luaL_setfuncs(L, methods, 0);
        lua_pushcfunction(L, l_win_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}

