/** @file luat_plcui_table.c XML-defined data table and row styles. */
#include "luat_plcui_component.h"

static void table_draw(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    lv_draw_task_t *task = lv_event_get_draw_task(event);
    lv_draw_dsc_base_t *base = lv_draw_task_get_draw_dsc(task);
    if (!base || base->part != LV_PART_ITEMS) return;
    lv_draw_fill_dsc_t *fill = lv_draw_task_get_fill_dsc(task);
    if (fill) {
        uint32_t color = widget->background;
        if (widget->table->header && base->id1 == 0) color = widget->table->header_color;
        else if (base->id1 & 1U) color = widget->table->alternate_color;
        fill->color = lv_color_hex(color);
    }
    lv_draw_label_dsc_t *label = lv_draw_task_get_label_dsc(task);
    if (label && base->id2 < widget->table->columns) {
        label->align = widget->table->header && base->id1 == 0
                     ? widget->table->header_align : widget->table->column_aligns[base->id2];
    }
}

lv_obj_t *luat_plcui_table_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    plcui_table_t *data = widget->table;
    lv_obj_t *object = lv_table_create(parent);
    if (!object) return NULL;
    lv_obj_remove_style_all(object);
    luat_plcui_component_init(widget, object);
    lv_obj_set_style_bg_color(object, lv_color_hex(widget->background), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(object, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_border_width(object, widget->border_width, LV_PART_MAIN);
    lv_obj_set_style_border_color(object, lv_color_hex(widget->border_color), LV_PART_MAIN);
    lv_obj_set_style_text_font(object, widget->font, LV_PART_ITEMS);
    lv_obj_set_style_text_color(object, lv_color_hex(widget->color), LV_PART_ITEMS);
    lv_obj_set_style_bg_opa(object, LV_OPA_COVER, LV_PART_ITEMS);
    lv_obj_set_style_border_color(object, lv_color_hex(widget->border_color), LV_PART_ITEMS);
    lv_obj_set_style_border_width(object, 1, LV_PART_ITEMS);
    lv_obj_set_style_border_side(object, data->grid ? LV_BORDER_SIDE_FULL : LV_BORDER_SIDE_BOTTOM, LV_PART_ITEMS);
    lv_obj_set_style_min_height(object, data->row_height, LV_PART_ITEMS);
    lv_obj_set_style_pad_ver(object, data->cell_padding, LV_PART_ITEMS);
    lv_obj_set_style_pad_hor(object, 12, LV_PART_ITEMS);
    lv_table_set_row_count(object, data->rows);
    lv_table_set_column_count(object, data->columns);
    for (unsigned col = 0; col < data->columns; ++col) {
        lv_table_set_column_width(object, col, data->widths[col]);
    }
    for (unsigned row = 0; row < data->rows; ++row) {
        for (unsigned col = 0; col < data->columns; ++col) {
            const char *text = data->cells[row * data->columns + col];
            lv_table_set_cell_value(object, row, col, text ? text : "");
        }
    }
    lv_obj_add_flag(object, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_SEND_DRAW_TASK_EVENTS);
    lv_obj_set_scroll_dir(object, LV_DIR_ALL);
    lv_obj_add_event_cb(object, table_draw, LV_EVENT_DRAW_TASK_ADDED, widget);
    return object;
}
