/** @file luat_plcui_component.h
 * Native component factories and shared tree behavior for XML page assembly.
 */
#ifndef LUAT_PLCUI_COMPONENT_H
#define LUAT_PLCUI_COMPONENT_H

#include "luat_plcui.h"

struct plcui_image {
    lv_image_align_t fit;
    uint16_t zoom, rotation;
    int32_t pivot_x, pivot_y, crop_x, crop_y;
    uint8_t opacity;
    bool pivot_explicit, antialias, crop;
    lv_area_t draw_clip;
    bool clip_saved;
};
struct plcui_label {
    lv_label_long_mode_t mode;
    uint32_t duration_ms, delay_ms;
    lv_anim_t animation;
    bool running, ready;
};
plcui_image_t *luat_plcui_image_config(plcui_widget_t *widget, plcui_error_t *error);
void luat_plcui_image_sync(plcui_widget_t *widget);
bool luat_plcui_image_validate_source(plcui_widget_t *widget, uint32_t width, uint32_t height, lv_color_format_t format, plcui_error_t *error);
plcui_label_t *luat_plcui_label_config(plcui_widget_t *widget, plcui_error_t *error);
void luat_plcui_label_sync(plcui_widget_t *widget);
void luat_plcui_label_restart(plcui_widget_t *widget);
lv_obj_t *luat_plcui_slider_create(plcui_widget_t *widget, lv_obj_t *parent);
void luat_plcui_slider_cancel(plcui_widget_t *widget, const char *reason);
int32_t luat_plcui_slider_snap(int32_t value, int32_t minimum, int32_t maximum, uint32_t step);
lv_obj_t *luat_plcui_animimg_create(plcui_widget_t *widget, lv_obj_t *parent);
bool luat_plcui_animimg_prepare(plcui_widget_t *widget, plcui_error_t *error);
bool luat_plcui_animimg_play(plcui_widget_t *widget, plcui_error_t *error);
void luat_plcui_animimg_pause(plcui_widget_t *widget);
bool luat_plcui_animimg_stop(plcui_widget_t *widget, plcui_error_t *error);
void luat_plcui_animimg_destroy(plcui_widget_t *widget);
void luat_plcui_components_tick(plcui_document_t *document);
void luat_plcui_components_sync(plcui_document_t *document);
void luat_plcui_components_presented(plcui_document_t *document);
void luat_plcui_components_retire(plcui_document_t *document);
void luat_plcui_component_cancel_pointer(plcui_widget_t *root, const char *reason);
bool luat_plcui_component_set_pos(plcui_widget_t *widget, int32_t x, int32_t y, plcui_error_t *error);

lv_obj_t *luat_plcui_image_create(plcui_widget_t *widget, lv_obj_t *parent);
lv_obj_t *luat_plcui_label_create(plcui_widget_t *widget, lv_obj_t *parent);
lv_obj_t *luat_plcui_textarea_create(plcui_widget_t *widget, lv_obj_t *parent);
/* Bulk-write previously validated text; caller owns document event suppression. */
void luat_plcui_textarea_write(lv_obj_t *object, const char *text);
lv_obj_t *luat_plcui_keyboard_create(plcui_widget_t *widget, lv_obj_t *parent);
lv_obj_t *luat_plcui_container_create(plcui_widget_t *widget, lv_obj_t *parent);
lv_obj_t *luat_plcui_table_create(plcui_widget_t *widget, lv_obj_t *parent);
lv_obj_t *luat_plcui_chart_create(plcui_widget_t *widget, lv_obj_t *parent);
bool luat_plcui_chart_number(double value, int32_t *scaled);
plcui_chart_series_t *luat_plcui_chart_series(plcui_widget_t *widget, const char *id);
int32_t luat_plcui_chart_display_value(const plcui_widget_t *widget, int32_t value);
void luat_plcui_chart_sync_series(plcui_widget_t *widget, plcui_chart_series_t *series);

void luat_plcui_component_init(plcui_widget_t *widget, lv_obj_t *object);
bool luat_plcui_component_is_within(const plcui_widget_t *widget, const plcui_widget_t *ancestor);
bool luat_plcui_component_interactive(const plcui_widget_t *widget);
bool luat_plcui_component_ancestors_interactive(const plcui_widget_t *widget);
bool luat_plcui_component_sync_disabled(plcui_widget_t *root, plcui_error_t *error);

#endif
