/** @file luat_plcui_keyboard.c Native keyboard layout, styling and session events. */
#include "luat_plcui_component.h"
#include "luat_plcui_keyboard.h"
#include "luat_plcui_debug.h"
#include "luat_conf_bsp.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#ifdef LUAT_USE_PINYIN
#include "luat_pinyin.h"
#endif

#ifdef LUAT_USE_PINYIN
static int32_t pinyin_text_width(const lv_font_t *font, const char *text)
{
    lv_point_t size;
    lv_text_get_size(&size, text, font, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
    return size.x;
}

static int32_t pinyin_minimum_width(const lv_font_t *font, int32_t line)
{
    if (!font) return (line + 8) * 21 + 38;
    /* The candidate row uses 21 width units: 2/3/1/2/2/2/2/2/2/2/1.
       The pinyin field is 3 units so the adjacent candidate row can hold
       seven cells. Reserve real glyph advances for seven letters and the
       mode button. Ten 2px gaps and 18px outer geometry are extra. */
    int32_t mode = LV_MAX(pinyin_text_width(font, "中文"), pinyin_text_width(font, "EN"));
    int32_t prompt = LV_MAX(pinyin_text_width(font, "wwwwwww"), pinyin_text_width(font, "mmmmmmm"));
    prompt = LV_MAX(prompt, pinyin_text_width(font, "超出限制"));
    prompt = LV_MAX(prompt, pinyin_text_width(font, "请先选字"));
    int32_t arrow = LV_MAX(pinyin_text_width(font, LV_SYMBOL_LEFT), pinyin_text_width(font, LV_SYMBOL_RIGHT));
    int32_t unit = LV_MAX((mode + 8 + 1) / 2, (prompt + 8 + 2) / 3);
    unit = LV_MAX(unit, arrow + 8);
    unit = LV_MAX(unit, (line + 8 + 1) / 2);
    return unit * 21 + 38;
}
#endif

bool luat_plcui_keyboard_validate(const plcui_widget_t *widget, plcui_error_t *error)
{
    if (!widget->pinyin_keyboard) return true;
#ifndef LUAT_USE_PINYIN
    luat_plcui_error(error, "E_NOT_SUPPORTED", "Pinyin requires LUAT_USE_PINYIN");
    return false;
#else
    if (widget->numeric_keyboard) {
        luat_plcui_error(error, "E_SCHEMA", "Pinyin requires layout=text");
        return false;
    }
    int32_t line = widget->font ? lv_font_get_line_height(widget->font) : widget->font_size;
    if (line < 1) line = 16;
    int32_t minimum_width = pinyin_minimum_width(widget->font, line);
    int32_t minimum_height = (line + 12) * 5 + 16;
    if (widget->h < minimum_height || widget->w < minimum_width) {
        luat_plcui_error(error, "E_SCHEMA", "Pinyin keyboard requires at least %dx%d for its font and candidate row",
                         (int)minimum_width, (int)minimum_height);
        return false;
    }
    return true;
#endif
}

#ifdef LUAT_USE_PINYIN
#define PINYIN_CANDIDATES 7U
#define PINYIN_ROW_BUTTONS 11U
#define PINYIN_RIGHT_BUTTON (PINYIN_ROW_BUTTONS - 1U)

typedef struct {
    plcui_widget_t *widget;
    lv_obj_t *row;
    bool chinese;
    char composing[8];
    char prompt[32];
    char candidates[PINYIN_CANDIDATES][5];
    const char *map[PINYIN_ROW_BUTTONS + 1U];
    lv_buttonmatrix_ctrl_t controls[PINYIN_ROW_BUTTONS];
    const uint32_t *codepoints;
    uint16_t count;
    uint16_t offset;
} plcui_pinyin_t;

static void pinyin_event(lv_event_t *event);

static plcui_pinyin_t *pinyin_data(plcui_widget_t *widget)
{
    if (!widget || !widget->pinyin_keyboard || !widget->obj) return NULL;
    uint32_t count = lv_obj_get_event_count(widget->obj);
    for (uint32_t i = 0; i < count; i++) {
        lv_event_dsc_t *descriptor = lv_obj_get_event_dsc(widget->obj, i);
        if (lv_event_dsc_get_cb(descriptor) == pinyin_event)
            return lv_event_dsc_get_user_data(descriptor);
    }
    return NULL;
}

static bool pinyin_active(plcui_pinyin_t *data)
{
    plcui_widget_t *keyboard = data->widget;
    plcui_document_t *document = keyboard->document;
    return !document->closed && !document->silent && document->keyboard == keyboard
        && document->editing && document->editing->obj
        && lv_keyboard_get_textarea(keyboard->obj) == document->editing->obj
        && luat_plcui_component_interactive(document->editing)
        && luat_plcui_component_interactive(keyboard);
}

static void pinyin_update_row(plcui_pinyin_t *data, const char *hint)
{
    data->map[0] = data->chinese ? "中文" : "EN";
    snprintf(data->prompt, sizeof(data->prompt), "%s", hint ? hint :
        (data->composing[0] ? data->composing : (data->chinese ? "拼音" : "英文")));
    for (unsigned i = 0; i < PINYIN_CANDIDATES; i++) {
        data->candidates[i][0] = ' ';
        data->candidates[i][1] = 0;
        bool available = data->codepoints && data->offset + i < data->count;
        if (available) luat_pinyin_codepoint_to_utf8(data->codepoints[data->offset + i], data->candidates[i]);
        if (available) lv_buttonmatrix_clear_button_ctrl(data->row, i + 3U, LV_BUTTONMATRIX_CTRL_DISABLED);
        else lv_buttonmatrix_set_button_ctrl(data->row, i + 3U, LV_BUTTONMATRIX_CTRL_DISABLED);
    }
    if (data->offset) lv_buttonmatrix_clear_button_ctrl(data->row, 2, LV_BUTTONMATRIX_CTRL_DISABLED);
    else lv_buttonmatrix_set_button_ctrl(data->row, 2, LV_BUTTONMATRIX_CTRL_DISABLED);
    if (data->offset + PINYIN_CANDIDATES < data->count)
        lv_buttonmatrix_clear_button_ctrl(data->row, PINYIN_RIGHT_BUTTON, LV_BUTTONMATRIX_CTRL_DISABLED);
    else lv_buttonmatrix_set_button_ctrl(data->row, PINYIN_RIGHT_BUTTON, LV_BUTTONMATRIX_CTRL_DISABLED);
    /* map contains persistent pointers; refresh cached button widths/text after changing them. */
    lv_buttonmatrix_set_map(data->row, data->map);
    lv_obj_invalidate(data->row);
}

static void pinyin_clear(plcui_pinyin_t *data)
{
    data->composing[0] = 0;
    data->codepoints = NULL;
    data->count = 0;
    data->offset = 0;
    pinyin_update_row(data, NULL);
}

static void pinyin_query(plcui_pinyin_t *data)
{
    uint32_t started = plcui_debug_now();
    data->offset = 0;
    data->count = 0;
    data->codepoints = NULL;
    if (data->composing[0]) luat_pinyin_query(data->composing, &data->codepoints, &data->count);
    pinyin_update_row(data, NULL);
    plcui_widget_t *widget = data->widget;
    plcui_debug_record(PLCUI_KEYBOARD, "update", "pinyin_query",
        widget->document->pages[widget->page_index].id, widget->id, plcui_debug_now() - started, true);
}

/* Convert a validated UTF-8 character offset to a byte offset without accessing LVGL private data. */
static size_t text_offset(const char *text, uint32_t character)
{
    size_t offset = 0;
    while (text[offset] && character) {
        offset++;
        while (((unsigned char)text[offset] & 0xc0U) == 0x80U) offset++;
        character--;
    }
    return offset;
}

static uint32_t text_characters(const char *text)
{
    uint32_t count = 0;
    for (size_t i = 0; text[i]; i++) if (((unsigned char)text[i] & 0xc0U) != 0x80U) count++;
    return count;
}

static bool pinyin_insert(plcui_pinyin_t *data, const char *insert)
{
    if (!pinyin_active(data)) return false;
    uint32_t started = plcui_debug_now();
    plcui_widget_t *textarea = data->widget->document->editing;
    const char *old = lv_textarea_get_text(textarea->obj);
    uint32_t first = lv_textarea_get_cursor_pos(textarea->obj), last = first;
#if LV_LABEL_TEXT_SELECTION
    lv_obj_t *label = lv_textarea_get_label(textarea->obj);
    uint32_t selected_first = lv_label_get_text_selection_start(label);
    uint32_t selected_last = lv_label_get_text_selection_end(label);
    if (selected_first != LV_LABEL_TEXT_SELECTION_OFF && selected_last != LV_LABEL_TEXT_SELECTION_OFF
        && selected_first != selected_last) {
        first = LV_MIN(selected_first, selected_last);
        last = LV_MAX(selected_first, selected_last);
    }
#endif
    size_t at = text_offset(old, first), end = text_offset(old, last);
    size_t suffix = strlen(old + end), added = strlen(insert);
    char result[PLCUI_TEXT_MAX];
    plcui_error_t error;
    bool success = at + added + suffix < sizeof(result);
    if (success) {
        memcpy(result, old, at);
        memcpy(result + at, insert, added);
        memcpy(result + at + added, old + end, suffix + 1U);
        success = luat_plcui_check_text(textarea, result, at + added + suffix, &error);
    }
    if (success) {
        plcui_document_t *document = textarea->document;
        bool silent = document->silent;
        document->silent = true;
        luat_plcui_textarea_write(textarea->obj, result);
        lv_textarea_set_cursor_pos(textarea->obj, (int32_t)(first + text_characters(insert)));
        document->silent = silent;
        snprintf(textarea->text, sizeof(textarea->text), "%s", result);
        luat_plcui_emit(textarea, PLCUI_CHANGE);
        pinyin_clear(data);
    } else pinyin_update_row(data, "超出限制");
    plcui_widget_t *keyboard = data->widget;
    plcui_debug_record(PLCUI_KEYBOARD, "update", "pinyin_commit",
        keyboard->document->pages[keyboard->page_index].id, keyboard->id, plcui_debug_now() - started, success);
    return success;
}

static bool pinyin_choose(plcui_pinyin_t *data, unsigned index)
{
    if (!data->codepoints || data->offset + index >= data->count) {
        pinyin_update_row(data, "无候选");
        return false;
    }
    char text[5];
    if (!luat_pinyin_codepoint_to_utf8(data->codepoints[data->offset + index], text)) return false;
    return pinyin_insert(data, text);
}

static void candidate_event(lv_event_t *event)
{
    plcui_pinyin_t *data = lv_event_get_user_data(event);
    if (!pinyin_active(data)) return;
    uint32_t button = lv_buttonmatrix_get_selected_button(data->row);
    if (button == 0) {
        if (data->composing[0] && !pinyin_insert(data, data->composing)) return;
        data->chinese = !data->chinese;
        pinyin_update_row(data, NULL);
    } else if (button == 2 && data->offset) {
        data->offset = (uint16_t)(data->offset - PINYIN_CANDIDATES);
        pinyin_update_row(data, NULL);
    } else if (button == PINYIN_RIGHT_BUTTON && data->offset + PINYIN_CANDIDATES < data->count) {
        data->offset = (uint16_t)(data->offset + PINYIN_CANDIDATES);
        pinyin_update_row(data, NULL);
    } else if (button >= 3 && button < PINYIN_RIGHT_BUTTON) pinyin_choose(data, button - 3U);
}

static void pinyin_event(lv_event_t *event)
{
    plcui_pinyin_t *data = lv_event_get_user_data(event);
    if (lv_event_get_target(event) != data->widget->obj || !pinyin_active(data)) return;
    uint32_t button = lv_keyboard_get_selected_button(data->widget->obj);
    const char *key = lv_keyboard_get_button_text(data->widget->obj, button);
    if (!key) return;
    if (!data->chinese) { lv_keyboard_def_event_cb(event); return; }
    if (key[0] && !key[1] && ((key[0] >= 'a' && key[0] <= 'z') || (key[0] >= 'A' && key[0] <= 'Z'))) {
        size_t length = strlen(data->composing);
        if (length < sizeof(data->composing) - 1U) {
            data->composing[length] = key[0] >= 'A' && key[0] <= 'Z' ? (char)(key[0] + 'a' - 'A') : key[0];
            data->composing[length + 1U] = 0;
            pinyin_query(data);
        }
    } else if (!strcmp(key, LV_SYMBOL_CLOSE) || !strcmp(key, LV_SYMBOL_KEYBOARD)) {
        lv_keyboard_def_event_cb(event);
    } else if (!strcmp(key, "ABC") || !strcmp(key, "abc") || !strcmp(key, "1#")) {
        /* Key-plane changes preserve the composition. English mode is the explicit commit-ASCII action. */
        lv_keyboard_def_event_cb(event);
    } else if (data->composing[0]) {
        if (!strcmp(key, LV_SYMBOL_BACKSPACE)) {
            data->composing[strlen(data->composing) - 1U] = 0;
            pinyin_query(data);
        } else if (!strcmp(key, " ") || !strcmp(key, LV_SYMBOL_OK)
            || !strcmp(key, "Enter") || !strcmp(key, LV_SYMBOL_NEW_LINE)) pinyin_choose(data, 0);
        else pinyin_update_row(data, "请先选字");
    } else lv_keyboard_def_event_cb(event);
}

static void pinyin_delete(lv_event_t *event)
{
    if (lv_event_get_target(event) != lv_event_get_current_target(event)) return;
    plcui_pinyin_t *data = lv_event_get_user_data(event);
    /* LVGL sends the parent's DELETE before deleting its children. Detach both
       composition callbacks before releasing their shared private state. */
    lv_obj_remove_event_cb(data->row, candidate_event);
    lv_obj_remove_event_cb(lv_event_get_current_target(event), pinyin_event);
    free(data);
}

static bool pinyin_create(plcui_widget_t *widget, lv_obj_t *object)
{
    plcui_pinyin_t *data = calloc(1, sizeof(*data));
    if (!data) return false;
    data->widget = widget;
    data->chinese = true;
    data->map[0] = "中文";
    snprintf(data->prompt, sizeof(data->prompt), "%s", "拼音");
    for (unsigned i = 0; i < PINYIN_CANDIDATES; i++) strcpy(data->candidates[i], " ");
    data->map[1] = data->prompt;
    data->map[2] = LV_SYMBOL_LEFT;
    for (unsigned i = 0; i < PINYIN_CANDIDATES; i++) data->map[i + 3U] = data->candidates[i];
    data->map[PINYIN_RIGHT_BUTTON] = LV_SYMBOL_RIGHT;
    data->map[PINYIN_ROW_BUTTONS] = "";
    for (unsigned i = 0; i < PINYIN_ROW_BUTTONS; i++)
        data->controls[i] = LV_BUTTONMATRIX_CTRL_CLICK_TRIG | LV_BUTTONMATRIX_CTRL_NO_REPEAT | 2;
    data->controls[1] = LV_BUTTONMATRIX_CTRL_DISABLED | 3;
    data->controls[2] = data->controls[PINYIN_RIGHT_BUTTON] = LV_BUTTONMATRIX_CTRL_CLICK_TRIG | LV_BUTTONMATRIX_CTRL_NO_REPEAT | 1;
    data->row = lv_buttonmatrix_create(object);
    if (!data->row) { free(data); return false; }
    lv_obj_remove_style_all(data->row);
    lv_obj_remove_flag(data->row, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICK_FOCUSABLE | LV_OBJ_FLAG_EVENT_BUBBLE);
    lv_obj_set_style_bg_color(data->row, lv_color_hex(0x243746), LV_PART_ITEMS);
    lv_obj_set_style_bg_opa(data->row, LV_OPA_COVER, LV_PART_ITEMS);
    lv_obj_set_style_text_color(data->row, lv_color_hex(0xedf7fb), LV_PART_ITEMS);
    lv_obj_set_style_bg_color(data->row, lv_color_hex(0x1caa8d), (lv_style_selector_t)LV_PART_ITEMS | (lv_style_selector_t)LV_STATE_PRESSED);
    lv_obj_set_style_text_letter_space(data->row, 0, LV_PART_ITEMS);
    lv_obj_set_style_pad_column(data->row, 2, LV_PART_MAIN);
    lv_buttonmatrix_set_map(data->row, data->map);
    lv_buttonmatrix_set_ctrl_map(data->row, data->controls);
    lv_obj_add_event_cb(data->row, candidate_event, LV_EVENT_VALUE_CHANGED, data);
    lv_obj_remove_event_cb(object, lv_keyboard_def_event_cb);
    lv_obj_add_event_cb(object, pinyin_event, LV_EVENT_VALUE_CHANGED, data);
    lv_obj_add_event_cb(object, pinyin_delete, LV_EVENT_DELETE, data);
    int32_t row_height = lv_font_get_line_height(widget->font) + 12;
    /* 2px above the pinyin row and 2px between the row and the keys. */
    lv_obj_set_style_pad_top(object, row_height + 4, LV_PART_MAIN);
    lv_obj_set_pos(data->row, 0, -row_height - 2);
    lv_obj_set_size(data->row, widget->w - 18, row_height);
    lv_obj_set_style_text_font(data->row, widget->font, LV_PART_ITEMS);
    pinyin_clear(data);
    return true;
}
#endif

void luat_plcui_keyboard_reset(plcui_widget_t *widget)
{
#ifdef LUAT_USE_PINYIN
    plcui_pinyin_t *data = pinyin_data(widget);
    if (data) pinyin_clear(data);
#else
    (void)widget;
#endif
}

void luat_plcui_keyboard_font_changed(plcui_widget_t *widget)
{
#ifdef LUAT_USE_PINYIN
    plcui_pinyin_t *data = pinyin_data(widget);
    if (!data) return;
    int32_t row_height = lv_font_get_line_height(widget->font) + 12;
    lv_obj_set_style_pad_top(widget->obj, row_height + 4, LV_PART_MAIN);
    lv_obj_set_pos(data->row, 0, -row_height - 2);
    lv_obj_set_size(data->row, widget->w - 18, row_height);
    lv_obj_set_style_text_font(data->row, widget->font, LV_PART_ITEMS);
#else
    (void)widget;
#endif
}

static void keyboard_event(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    if (widget->document->closed || !widget->obj || widget->document->keyboard != widget
        || lv_event_get_target(event) != widget->obj) return;
    lv_event_code_t code = lv_event_get_code(event);
    if (code == LV_EVENT_READY) luat_plcui_input_finish(widget->document, true, true);
    else if (code == LV_EVENT_CANCEL) luat_plcui_input_finish(widget->document, false, true);
}

lv_obj_t *luat_plcui_keyboard_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_keyboard_create(parent);
    if (!object) return NULL;
    luat_plcui_component_init(widget, object);
    lv_keyboard_set_mode(object, widget->numeric_keyboard ? LV_KEYBOARD_MODE_NUMBER : LV_KEYBOARD_MODE_TEXT_LOWER);
    lv_keyboard_set_popovers(object, false);
    lv_obj_set_style_bg_color(object, lv_color_hex(0x111e28), LV_PART_MAIN);
    lv_obj_set_style_border_width(object, 1, LV_PART_MAIN);
    lv_obj_set_style_border_color(object, lv_color_hex(0x3c596b), LV_PART_MAIN);
    lv_obj_set_style_pad_all(object, 8, LV_PART_MAIN);
    lv_obj_set_style_bg_color(object, lv_color_hex(0x243746), LV_PART_ITEMS);
    lv_obj_set_style_bg_color(object, lv_color_hex(0x1caa8d), (lv_style_selector_t)LV_PART_ITEMS | (lv_style_selector_t)LV_STATE_PRESSED);
    lv_obj_set_style_text_color(object, lv_color_hex(0xedf7fb), LV_PART_ITEMS);
    lv_obj_set_style_text_font(object, widget->font, LV_PART_ITEMS);
    lv_obj_add_flag(object, LV_OBJ_FLAG_HIDDEN);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICK_FOCUSABLE);
    lv_obj_add_event_cb(object, keyboard_event, LV_EVENT_ALL, widget);
#ifdef LUAT_USE_PINYIN
    if (widget->pinyin_keyboard && !pinyin_create(widget, object)) {
        lv_obj_delete(object);
        widget->obj = NULL;
        return NULL;
    }
#endif
    return object;
}
