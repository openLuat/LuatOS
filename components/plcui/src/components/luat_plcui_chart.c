/** @file luat_plcui_chart.c Two-decimal data charts with safe native projection. */
#include "luat_plcui_component.h"
#include <float.h>
#include <math.h>
#include <string.h>

bool luat_plcui_chart_number(double value, double *rounded)
{
    if (!isfinite(value)) return false;
#if LUA_FLOAT_TYPE == LUA_FLOAT_FLOAT
    /* XML uses strtod even when Lua numbers are single precision. Keep
       accepted values representable by get_values() and state(). */
    if (value < -FLT_MAX || value > FLT_MAX) return false;
#endif
    if (fabs(value) < 1.0 / (DBL_EPSILON * PLCUI_CHART_SCALE)) {
        /* Preserve the existing rounding of ordinary decimal values. */
        double number = value * PLCUI_CHART_SCALE;
        *rounded = trunc(number + (number < 0 ? -0.5 : 0.5)) / PLCUI_CHART_SCALE;
    } else {
        /* Multiplying a large integer by 100 can change it or overflow.
           Round only its fractional part at these magnitudes. */
        double whole;
        double fraction = modf(value, &whole);
        *rounded = whole + round(fraction * PLCUI_CHART_SCALE) / PLCUI_CHART_SCALE;
    }
    if (*rounded == 0) *rounded = 0.0;
    return true;
}

plcui_chart_series_t *luat_plcui_chart_series(plcui_widget_t *widget, const char *id)
{
    for (unsigned i = 0; i < widget->chart->count; ++i) {
        if (!strcmp(widget->chart->series[i].id, id)) return &widget->chart->series[i];
    }
    return NULL;
}

int32_t luat_plcui_chart_display_value(const plcui_widget_t *widget, double value)
{
    double minimum = widget->chart->minimum;
    double maximum = widget->chart->maximum;
    if (value <= minimum) return 0;
    if (value >= maximum) return PLCUI_CHART_NATIVE_MAX;
    double span = maximum - minimum;
    double position;
    if (isfinite(span)) {
        position = (value - minimum) / span;
    } else {
        /* Opposite extreme endpoints can overflow their difference. */
        position = (value * 0.5 - minimum * 0.5) / (maximum * 0.5 - minimum * 0.5);
    }
    if (position <= 0) return 0;
    if (position >= 1) return PLCUI_CHART_NATIVE_MAX;
    return (int32_t)(position * PLCUI_CHART_NATIVE_MAX + 0.5);
}

void luat_plcui_chart_sync_series(plcui_widget_t *widget, plcui_chart_series_t *series)
{
    /* LVGL multiplies native values by pixel height in signed 32-bit math.
       Only projected values enter LVGL; original values survive range changes. */
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
    lv_chart_set_axis_range(object, LV_CHART_AXIS_PRIMARY_Y, 0, PLCUI_CHART_NATIVE_MAX);
    lv_chart_set_div_line_count(object, data->hdiv, data->vdiv);
    lv_chart_set_update_mode(object, LV_CHART_UPDATE_MODE_SHIFT);
    for (unsigned i = 0; i < data->count; ++i) {
        plcui_chart_series_t *series = &data->series[i];
        series->native = lv_chart_add_series(object, lv_color_hex(series->color), LV_CHART_AXIS_PRIMARY_Y);
        if (!series->native) return NULL;
        /* Keep LVGL's buffers owned by LVGL; XML owns a separate persistent copy. */
        lv_chart_set_all_values(object, series->native, 0);
        luat_plcui_chart_sync_series(widget, series);
        lv_chart_hide_series(object, series->native, series->hidden);
    }
    lv_chart_refresh(object);
    return object;
}
