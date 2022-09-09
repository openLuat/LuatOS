#include "luat_base.h"
#include "luat_lvgl.h"
#include "luat_zbuff.h"
#include "lvgl.h"

#define META_LV_ANIM "LV_ANIM*"
#define META_LV_AREA "LV_AREA*"
#define META_LV_CALENDAR_DATE_T "LV_CALENDAR_DATE_T*"
#define META_LV_DRAW_RECT_DSC_T "LV_DRAW_RECT_DSC_T*"
#define META_LV_DRAW_LABEL_DSC_T "LV_DRAW_LABEL_DSC_T*"
#define META_LV_DRAW_IMG_DSC_T "LV_DRAW_IMG_DSC_T*"
#define META_LV_IMG_DSC_T "LV_IMG_DSC_T*"
#define META_LV_LINE_DSC_T "LV_LINE_DSC_T*"
//---------------------------------------------
#if LV_USE_ANIMATION
/*
创建一个anim
@api lvgl.anim_t()
@return userdata anim指针
@usage
local anim = lvgl.anim_t()
*/
int luat_lv_struct_anim_t(lua_State *L) {
    lua_newuserdata(L, sizeof(lv_anim_t));
    luaL_setmetatable(L, META_LV_ANIM);
    return 1;
}


int _lvgl_struct_anim_t_newindex(lua_State *L) {
    lv_anim_t* anim = (lv_anim_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("start", key)) {
        anim->start = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("end", key)) {
        anim->end = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("current", key)) {
        anim->current = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("time", key)) {
        anim->time = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("act_time", key)) {
        anim->act_time = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("playback_delay", key)) {
        anim->playback_delay = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("playback_time", key)) {
        anim->playback_time = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("repeat_delay", key)) {
        anim->repeat_delay = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("repeat_cnt", key)) {
        anim->repeat_cnt = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("early_apply", key)) {
        anim->early_apply = luaL_optinteger(L, 3, 0);
    }
    return 0;
}
#endif

//---------------------------------------------
/*
创建一个area
@api lvgl.area_t()
@return userdata area指针
@usage
local area = lvgl.area_t()
*/
int luat_lv_struct_area_t(lua_State *L) {
    lua_newuserdata(L, sizeof(lv_area_t));
    luaL_setmetatable(L, META_LV_AREA);
    return 1;
}


int _lvgl_struct_area_t_newindex(lua_State *L) {
    lv_area_t* area = (lv_area_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("x1", key)) {
        area->x1 = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("x2", key)) {
        area->x2 = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("y1", key)) {
        area->y1 = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("y2", key)) {
        area->y2 = luaL_optinteger(L, 3, 0);
    }
    return 0;
}

//---------------------------------------------
/*
创建一个calendar_date_t
@api lvgl.calendar_date_t()
@return userdata calendar_date_t指针
@usage
local today = lvgl.calendar_date_t()
*/
int luat_lv_calendar_date_t(lua_State *L){
    lua_newuserdata(L, sizeof(lv_calendar_date_t));
    luaL_setmetatable(L, META_LV_CALENDAR_DATE_T);
    return 1;
}

int _lvgl_struct_calendar_date_t_newindex(lua_State *L) {
    lv_calendar_date_t* date_t = (lv_calendar_date_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("year", key)) {
        date_t->year = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("month", key)) {
        date_t->month = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("day", key)) {
        date_t->day = luaL_optinteger(L, 3, 0);
    }
    return 0;
}

//---------------------------------------------
/*
创建一个lv_draw_rect_dsc_t
@api lvgl.draw_rect_dsc_t()
@return userdata lv_draw_rect_dsc_t指针
@usage
local rect_dsc = lvgl.draw_rect_dsc_t()
*/
int luat_lv_draw_rect_dsc_t(lua_State *L){
    lua_newuserdata(L, sizeof(lv_draw_rect_dsc_t));
    luaL_setmetatable(L, META_LV_DRAW_RECT_DSC_T);
    return 1;
}

int _lvgl_struct_draw_rect_dsc_t_newindex(lua_State *L) {
    lv_draw_rect_dsc_t* rect_dsc = (lv_draw_rect_dsc_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("radius", key)) {
        rect_dsc->radius = luaL_optinteger(L, 3, 0);
    }
    /*Background*/
    else if (!strcmp("bg_color", key)) {
        rect_dsc->bg_color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("bg_grad_color", key)) {
        rect_dsc->bg_grad_color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("bg_grad_dir", key)) {
        rect_dsc->bg_grad_dir = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("bg_main_color_stop", key)) {
        rect_dsc->bg_main_color_stop = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("bg_grad_color_stop", key)) {
        rect_dsc->bg_grad_color_stop = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("bg_opa", key)) {
        rect_dsc->bg_opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("bg_blend_mode", key)) {
        rect_dsc->bg_blend_mode = luaL_optinteger(L, 3, 0);
    }
    /*Border*/
    else if (!strcmp("border_color", key)) {
        rect_dsc->border_color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("border_width", key)) {
        rect_dsc->border_width = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("border_side", key)) {
        rect_dsc->border_side = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("border_opa", key)) {
        rect_dsc->border_opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("border_blend_mode", key)) {
        rect_dsc->border_blend_mode = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("border_post", key)) {
        rect_dsc->border_post = luaL_optinteger(L, 3, 1);
    }
    /*Outline*/
    else if (!strcmp("outline_color", key)) {
        rect_dsc->outline_color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("outline_width", key)) {
        rect_dsc->outline_width = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("outline_pad", key)) {
        rect_dsc->outline_pad = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("outline_opa", key)) {
        rect_dsc->outline_opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("outline_blend_mode", key)) {
        rect_dsc->outline_blend_mode = luaL_optinteger(L, 3, 0);
    }
    /*Shadow*/
    else if (!strcmp("shadow_color", key)) {
        rect_dsc->shadow_color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("shadow_width", key)) {
        rect_dsc->shadow_width = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("shadow_ofs_x", key)) {
        rect_dsc->shadow_ofs_x = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("shadow_ofs_y", key)) {
        rect_dsc->shadow_ofs_y = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("shadow_spread", key)) {
        rect_dsc->shadow_spread = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("shadow_opa", key)) {
        rect_dsc->shadow_opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("shadow_blend_mode", key)) {
        rect_dsc->shadow_blend_mode = luaL_optinteger(L, 3, 0);
    }
    /*Pattern*/
    else if (!strcmp("pattern_image", key)) {
        rect_dsc->pattern_image = luaL_optstring(L, 3, NULL);
    }
    else if (!strcmp("pattern_font", key)) {
        rect_dsc->pattern_font = luaL_optstring(L, 3, NULL);
    }
    else if (!strcmp("pattern_recolor", key)) {
        rect_dsc->pattern_recolor.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("pattern_opa", key)) {
        rect_dsc->pattern_opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("pattern_recolor_opa", key)) {
        rect_dsc->pattern_recolor_opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("pattern_repeat", key)) {
        rect_dsc->pattern_repeat = luaL_optinteger(L, 3, 1);
    }
    else if (!strcmp("pattern_blend_mode", key)) {
        rect_dsc->pattern_blend_mode = luaL_optinteger(L, 3, 0);
    }
    /*Value*/
    else if (!strcmp("value_str", key)) {
        rect_dsc->value_str = luaL_optstring(L, 3, NULL);
    }
    else if (!strcmp("value_font", key)) {
        rect_dsc->value_font = luaL_optstring(L, 3, NULL);
    }
    else if (!strcmp("value_opa", key)) {
        rect_dsc->value_opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("value_color", key)) {
        rect_dsc->value_color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("value_ofs_x", key)) {
        rect_dsc->value_ofs_x = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("value_ofs_y", key)) {
        rect_dsc->value_ofs_y = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("value_letter_space", key)) {
        rect_dsc->value_letter_space = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("value_line_space", key)) {
        rect_dsc->value_line_space = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("value_align", key)) {
        rect_dsc->value_align = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("value_blend_mode", key)) {
        rect_dsc->value_blend_mode = luaL_optinteger(L, 3, 0);
    }
    return 0;
}

//---------------------------------------------
/*
创建一个lv_draw_line_dsc_t
@api lvgl.draw_line_dsc_t()
@return userdata lv_draw_line_dsc_t指针
@usage
local rect_dsc = lvgl.draw_line_dsc_t()
*/
int luat_lv_draw_line_dsc_t(lua_State *L){
    lua_newuserdata(L, sizeof(lv_draw_line_dsc_t));
    luaL_setmetatable(L, META_LV_LINE_DSC_T);
    return 1;
}

int _lvgl_struct_draw_line_dsc_t_newindex(lua_State *L) {
    lv_draw_line_dsc_t* line_dsc = (lv_draw_line_dsc_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("color", key)) {
        line_dsc->color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("width", key)) {
        line_dsc->width = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("dash_width", key)) {
        line_dsc->dash_width = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("dash_gap", key)) {
        line_dsc->dash_gap = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("opa", key)) {
        line_dsc->opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("blend_mode", key)) {
        line_dsc->blend_mode = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("round_start", key)) {
        line_dsc->round_start = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("round_end", key)) {
        line_dsc->round_end = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("raw_end", key)) {
        line_dsc->raw_end = luaL_optinteger(L, 3, 0);
    }
    return 0;
}


//---------------------------------------------
/*
创建一个lv_draw_label_dsc_t
@api lvgl.draw_label_dsc_t()
@return userdata lv_draw_label_dsc_t指针
@usage
local rect_dsc = lvgl.draw_label_dsc_t()
*/
int luat_lv_draw_label_dsc_t(lua_State *L){
    lua_newuserdata(L, sizeof(lv_draw_label_dsc_t));
    luaL_setmetatable(L, META_LV_DRAW_LABEL_DSC_T);
    return 1;
}

int _lvgl_struct_draw_label_dsc_t_newindex(lua_State *L) {
    lv_draw_label_dsc_t* label_dsc = (lv_draw_label_dsc_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("color", key)) {
        label_dsc->color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("sel_color", key)) {
        label_dsc->sel_color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("sel_bg_color", key)) {
        label_dsc->sel_bg_color.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("font", key)) {
        label_dsc->font = luaL_optstring(L, 3, NULL);
    }
    else if (!strcmp("opa", key)) {
        label_dsc->opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("line_space", key)) {
        label_dsc->line_space = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("letter_space", key)) {
        label_dsc->letter_space = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("sel_start", key)) {
        label_dsc->sel_start = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("sel_end", key)) {
        label_dsc->sel_end = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("ofs_x", key)) {
        label_dsc->ofs_x = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("ofs_y", key)) {
        label_dsc->ofs_y = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("bidi_dir", key)) {
        label_dsc->bidi_dir = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("flag", key)) {
        label_dsc->flag = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("decor", key)) {
        label_dsc->decor = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("blend_mode", key)) {
        label_dsc->blend_mode = luaL_optinteger(L, 3, 0);
    }
    return 0;
}

//---------------------------------------------
/*
创建一个lv_draw_img_dsc_t
@api lvgl.draw_img_dsc_t()
@return userdata lv_draw_img_dsc_t指针
@usage
local draw_img_dsc_t = lvgl.draw_img_dsc_t()
*/
int luat_lv_draw_img_dsc_t(lua_State *L){
    lua_newuserdata(L, sizeof(lv_draw_img_dsc_t));
    luaL_setmetatable(L, META_LV_DRAW_IMG_DSC_T);
    return 1;
}

int _lvgl_struct_draw_img_dsc_t_newindex(lua_State *L) {
    lv_draw_img_dsc_t* draw_img_dsc_t = (lv_draw_img_dsc_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("opa", key)) {
        draw_img_dsc_t->opa = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("angle", key)) {
        draw_img_dsc_t->angle = luaL_optinteger(L, 3, 0);
    }
    // else if (!strcmp("pivot", key)) {
    //     img_dsc_t->pivot = (lv_point_t)luaL_optinteger(L, 3, 0);
    // }
    else if (!strcmp("zoom", key)) {
        draw_img_dsc_t->zoom = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("recolor", key)) {
        draw_img_dsc_t->recolor.full = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("blend_mode", key)) {
        draw_img_dsc_t->blend_mode = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("antialias", key)) {
        draw_img_dsc_t->antialias = luaL_optinteger(L, 3, 1);
    }
    return 0;
}

//---------------------------------------------
/*
创建一个lv_img_dsc_t
@api lvgl.draw_img_dsc_t()
@return userdata lv_img_dsc_t指针
@usage
local img_dsc_t = lvgl.img_dsc_t()
*/
int luat_lv_img_dsc_t(lua_State *L){
    lua_newuserdata(L, sizeof(lv_img_dsc_t));
    luaL_setmetatable(L, META_LV_IMG_DSC_T);
    return 1;
}

int _lvgl_struct_img_dsc_t_newindex(lua_State *L) {
    lv_img_dsc_t* img_dsc_t = (lv_img_dsc_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("header", key)) {
        // img_dsc_t->header = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("data_size", key)) {
        img_dsc_t->data_size = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("data", key)) {
        luat_zbuff_t* cbuff = (luat_zbuff_t *)luaL_checkudata(L, 3, "ZBUFF*");
        img_dsc_t->data = cbuff->addr;
    }
    else if (!strcmp("header_cf", key)) {
        img_dsc_t->header.cf = luaL_optinteger(L, 3, 5);
    }
    else if (!strcmp("header_w", key)) {
        img_dsc_t->header.w = luaL_optinteger(L, 3, 11);
    }
    else if (!strcmp("header_h", key)) {
        img_dsc_t->header.h = luaL_optinteger(L, 3, 11);
    }
    return 0;
}

//--------------------------------------------


void luat_lvgl_struct_init(lua_State *L) {

    // lv_anim*
#if LV_USE_ANIMATION
    luaL_newmetatable(L, META_LV_ANIM);
    lua_pushcfunction(L, _lvgl_struct_anim_t_newindex);
    lua_setfield( L, -2, "__newindex" );
    lua_pop(L, 1);
#endif

    // lv_area
    luaL_newmetatable(L, META_LV_AREA);
    lua_pushcfunction(L, _lvgl_struct_area_t_newindex);
    lua_setfield( L, -2, "__newindex" );
    lua_pop(L, 1);

    // lv_calendar_date_t
    luaL_newmetatable(L, META_LV_CALENDAR_DATE_T);
    lua_pushcfunction(L, _lvgl_struct_calendar_date_t_newindex);
    lua_setfield( L, -2, "__newindex" );
    lua_pop(L, 1);

    // lv_draw_rect_dsc_t
    luaL_newmetatable(L, META_LV_DRAW_RECT_DSC_T);
    lua_pushcfunction(L, _lvgl_struct_draw_rect_dsc_t_newindex);
    lua_setfield( L, -2, "__newindex" );
    lua_pop(L, 1);

    // draw_label_dsc_t
    luaL_newmetatable(L, META_LV_DRAW_LABEL_DSC_T);
    lua_pushcfunction(L, _lvgl_struct_draw_label_dsc_t_newindex);
    lua_setfield( L, -2, "__newindex" );
    lua_pop(L, 1);

    // lv_draw_img_dsc_t
    luaL_newmetatable(L, META_LV_DRAW_IMG_DSC_T);
    lua_pushcfunction(L, _lvgl_struct_draw_img_dsc_t_newindex);
    lua_setfield( L, -2, "__newindex" );
    lua_pop(L, 1);

    // lv_img_dsc_t
    luaL_newmetatable(L, META_LV_IMG_DSC_T);
    lua_pushcfunction(L, _lvgl_struct_img_dsc_t_newindex);
    lua_setfield( L, -2, "__newindex" );
    lua_pop(L, 1);

    luaL_newmetatable(L, META_LV_LINE_DSC_T);
    lua_pushcfunction(L, _lvgl_struct_draw_line_dsc_t_newindex);
    lua_setfield( L, -2, "__newindex" );
    lua_pop(L, 1);
}
