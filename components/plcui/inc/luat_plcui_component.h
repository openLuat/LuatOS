/** @file luat_plcui_component.h
 * Native component factories and shared tree behavior for XML page assembly.
 */
#ifndef LUAT_PLCUI_COMPONENT_H
#define LUAT_PLCUI_COMPONENT_H

#include "luat_plcui.h"

lv_obj_t *luat_plcui_image_create(plcui_widget_t *widget, lv_obj_t *parent);
lv_obj_t *luat_plcui_label_create(plcui_widget_t *widget, lv_obj_t *parent);
lv_obj_t *luat_plcui_textarea_create(plcui_widget_t *widget, lv_obj_t *parent);
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
void luat_plcui_component_sync_disabled(plcui_widget_t *root);

#endif
