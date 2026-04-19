#include "luat_airui_component.h"
#include "luat_hzfont.h"

#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/core/lv_obj_pos.h"
#include "lvgl9/src/themes/lv_theme.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.font"
#include "luat_log.h"

// 判断文本对象是否使用hzfont
static bool airui_text_font_is_using_hzfont(lv_obj_t *text_obj, airui_text_font_state_t *state)
{
    const lv_font_t *current_font;
    lv_font_t *hzfont;

    if (text_obj == NULL || state == NULL) {
        if (state != NULL) {
            state->use_hzfont = false;
        }
        return false;
    }

    hzfont = airui_font_hzfont_get_size(state->hzfont_size);
    if (hzfont == NULL) {
        state->use_hzfont = false;
        return false;
    }

    current_font = lv_obj_get_style_text_font(text_obj, LV_PART_MAIN);
    state->use_hzfont = (current_font == hzfont);
    return state->use_hzfont;
}

// 刷新文本对象的布局
static void airui_text_font_refresh_layout(lv_obj_t *text_obj, airui_text_font_state_t *state)
{
    lv_obj_t *parent;

    if (text_obj == NULL || state == NULL || !airui_text_font_is_using_hzfont(text_obj, state)) {
        return;
    }

    lv_obj_refresh_self_size(text_obj);
    lv_obj_mark_layout_as_dirty(text_obj);
    lv_obj_update_layout(text_obj);

    parent = lv_obj_get_parent(text_obj);
    if (parent != NULL) {
        lv_obj_mark_layout_as_dirty(parent);
        lv_obj_update_layout(parent);
    }
}

// 初始化文本字体状态
void airui_text_font_state_init(airui_text_font_state_t *state, uint16_t font_size)
{
    if (state == NULL) {
        return;
    }

    state->hzfont_size = font_size;
    state->prefer_hzfont = false;
    state->use_hzfont = false;
}

// 读取文本字体配置
void airui_text_font_read_config(airui_text_font_state_t *state, void *L, int idx)
{
    const char *font_name;
    int font_size;

    if (state == NULL || L == NULL) {
        return;
    }

    font_name = airui_marshal_string(L, idx, "font", NULL);
    font_size = airui_marshal_integer(L, idx, "font_size", 0);

    if (font_size > 0) {
        state->hzfont_size = (uint16_t)font_size;
    }
    state->prefer_hzfont = ((font_name != NULL && strcmp(font_name, "hzfont") == 0) || state->hzfont_size > 0);
}

// 应用文本字体到对象
void airui_text_font_apply_to_obj(lv_obj_t *text_obj, airui_text_font_state_t *state)
{
    lv_font_t *hzfont;
    const lv_font_t *theme_font;

    if (text_obj == NULL || state == NULL) {
        return;
    }

    hzfont = airui_font_hzfont_get_size(state->hzfont_size);
    if (state->prefer_hzfont) {
        if (hzfont != NULL) {
            state->use_hzfont = true;
            lv_obj_set_style_text_font(text_obj, hzfont, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        else {
            state->use_hzfont = false;
            LLOGW("font=hzfont but hzfont is not loaded, fallback to theme font");
        }
    }

    if (!state->prefer_hzfont) {
        theme_font = lv_theme_get_font_normal(text_obj);
        if (theme_font != NULL) {
            lv_obj_set_style_text_font(text_obj, theme_font, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
            state->use_hzfont = (hzfont != NULL && theme_font == hzfont);
        }
        else {
            state->use_hzfont = false;
        }
    }

    if (state->hzfont_size > 0 && state->use_hzfont) {
        state->prefer_hzfont = true;
        state->use_hzfont = true;
        (void)airui_text_font_apply_hzfont(text_obj, state->hzfont_size,
            ((lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT));
        airui_text_font_refresh_layout(text_obj, state);
    }
}

// 附加文本字体到对象
void airui_text_font_attach(lv_obj_t *text_obj, airui_text_font_state_t *state)
{
    (void)text_obj;
    (void)state;
}

int airui_text_font_apply_hzfont(lv_obj_t *obj, int font_size, lv_style_selector_t selector)
{
    lv_font_t *hzfont;

    if (obj == NULL || font_size <= 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

#ifdef LUAT_USE_HZFONT
    if (luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY) {
        LLOGW("hzfont 未注册，无法设置字号");
        return AIRUI_ERR_NOT_SUPPORTED;
    }

    hzfont = airui_font_hzfont_get_size((uint16_t)font_size);
    if (hzfont == NULL) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }

    lv_obj_set_style_text_font(obj, hzfont, selector);
    lv_obj_mark_layout_as_dirty(obj);
    lv_obj_update_layout(obj);
    lv_obj_invalidate(obj);
    return AIRUI_OK;
#else
    LLOGW("hzfont 未启用，无法设置字号");
    (void)selector;
    return AIRUI_ERR_NOT_SUPPORTED;
#endif
}
