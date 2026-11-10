/** @file luat_plcui_chart.c Bounded two-decimal line/bar data charts. */
#include "luat_plcui_component.h"
#include <math.h>
#include <string.h>

bool luat_plcui_chart_number(double value, int32_t *scaled)
{
    /* Limit the native values to +/-100000. LVGL uses signed 32-bit products
       while drawing; with the XML height limit of 4096 this stays in range. */
    if (!isfinite(value) || value < -1000.0 || value > 1000.0) return false;
    double number = value * PLCUI_CHART_SCALE;
    *scaled = (int32_t)(number + (number < 0 ? -0.5 : 0.5));
    return true;
}

plcui_chart_series_t *luat_plcui_chart_series(plcui_widget_t *widget, const char *id)
{
    for (unsigned i = 0; i < widget->chart->count; ++i) {
        if (!strcmp(widget->chart->series[i].id, id)) return &widget->chart->series[i];
    }
    return NULL;
}

int32_t luat_plcui_chart_display_value(const plcui_widget_t *widget, int32_t value)
{
    if (value < widget->chart->minimum) return widget->chart->minimum;
    if (value > widget->chart->maximum) return widget->chart->maximum;
    return value;
}

void luat_plcui_chart_sync_series(plcui_widget_t *widget, plcui_chart_series_t *series)
{
    /* Keep projection inside the chart rectangle even for a very narrow axis.
       The document retains the real values so changing range can restore them. */
    int32_t *native = lv_chart_get_series_y_array(widget->obj, series->native);
    for (unsigned i = 0; i < widget->chart->points; ++i) {
        native[i] = luat_plcui_chart_display_value(widget, series->values[i]);
    }
    lv_chart_set_x_start_point(widget->obj, series->native, series->start);
}

lv_obj_t *luat_plcui_chart_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    plcui_chart_t *data = widget->chart;
    lv_obj_t *object = lv_chart_create(parent);
    if (!object) return NULL;
    lv_obj_remove_style_all(object);
    luat_plcui_component_init(widget, object);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_bg_color(object, lv_color_hex(widget->background), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(object, widget->bg_opa, LV_PART_MAIN);
    lv_obj_set_style_border_color(object, lv_color_hex(widget->border_color), LV_PART_MAIN);
    lv_obj_set_style_border_width(object, widget->border_width, LV_PART_MAIN);
    lv_obj_set_style_pad_all(object, 0, LV_PART_MAIN);
    lv_obj_set_style_line_color(object, lv_color_hex(data->grid_color), LV_PART_MAIN);
    lv_obj_set_style_line_width(object, 1, LV_PART_MAIN);
    lv_obj_set_style_line_opa(object, LV_OPA_50, LV_PART_MAIN);
    lv_obj_set_style_line_width(object, data->line_width, LV_PART_ITEMS);
    lv_obj_set_style_size(object, 0, 0, LV_PART_INDICATOR);
    lv_chart_set_type(object, data->bar ? LV_CHART_TYPE_BAR : LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(object, data->points);
    lv_chart_set_axis_range(object, LV_CHART_AXIS_PRIMARY_Y, data->minimum, data->maximum);
    lv_chart_set_div_line_count(object, data->hdiv, data->vdiv);
    lv_chart_set_update_mode(object, LV_CHART_UPDATE_MODE_SHIFT);
    for (unsigned i = 0; i < data->count; ++i) {
        plcui_chart_series_t *series = &data->series[i];
        series->native = lv_chart_add_series(object, lv_color_hex(series->color), LV_CHART_AXIS_PRIMARY_Y);
        if (!series->native) return NULL;
        /* Keep LVGL's buffers owned by LVGL; XML owns a separate persistent copy. */
        lv_chart_set_all_values(object, series->native, data->minimum);
        luat_plcui_chart_sync_series(widget, series);
        lv_chart_hide_series(object, series->native, series->hidden);
    }
    lv_chart_refresh(object);
    return object;
}
