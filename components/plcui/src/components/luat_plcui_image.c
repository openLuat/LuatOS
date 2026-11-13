/** @file luat_plcui_image.c Image creation, transforms and pointer events. */
#include "luat_plcui_component.h"
#include "lvgl9/src/core/lv_obj_event_private.h"
#include "lvgl9/src/misc/lv_area_private.h"
#include "lvgl9/src/draw/lv_draw_image_private.h"
#include <stdlib.h>
#define LUAT_LOG_TAG "plcui.image"
#include "luat_log.h"

plcui_image_t *luat_plcui_image_config(plcui_widget_t *widget, plcui_error_t *error)
{
    if (widget->image) return widget->image;
    plcui_image_t *image = calloc(1, sizeof(*image));
    if (!image) {
        luat_plcui_error(error, "E_MEMORY", "Cannot allocate image configuration");
        return NULL;
    }
    image->fit = LV_IMAGE_ALIGN_STRETCH;
    image->zoom = 256;
    image->opacity = 255;
    image->antialias = true;
    widget->image = image;
    return image;
}

/* Reapply after source assignment, including default pivot for each state image. */
void luat_plcui_image_sync(plcui_widget_t *widget)
{
    if (!widget || !widget->obj || widget->type != PLCUI_IMAGE) return;
    lv_obj_t *object = widget->obj;
    const plcui_image_t *image = widget->image;
    lv_obj_invalidate(object);
    if (!image) {
        lv_image_set_inner_align(object, LV_IMAGE_ALIGN_STRETCH);
        return;
    }
    lv_obj_set_style_image_opa(object, image->opacity, LV_PART_MAIN);
    lv_image_set_antialias(object, image->antialias);
    if (image->crop) {
        lv_image_set_inner_align(object, LV_IMAGE_ALIGN_TOP_LEFT);
        lv_image_set_scale(object, 256);
        lv_image_set_rotation(object, 0);
        lv_image_set_pivot(object, 0, 0);
        lv_image_set_offset_x(object, -image->crop_x);
        lv_image_set_offset_y(object, -image->crop_y);
    } else {
        lv_image_set_offset_x(object, 0);
        lv_image_set_offset_y(object, 0);
        lv_image_set_inner_align(object, image->fit);
        if (image->fit == LV_IMAGE_ALIGN_CENTER) {
            lv_image_set_scale(object, image->zoom);
            lv_image_set_rotation(object, image->rotation);
            lv_image_set_pivot(object,
                image->pivot_explicit ? image->pivot_x : (int32_t)lv_image_get_src_width(object) / 2,
                image->pivot_explicit ? image->pivot_y : (int32_t)lv_image_get_src_height(object) / 2);
        }
    }
    lv_obj_refresh_ext_draw_size(object);
    lv_obj_invalidate(object);
}

bool luat_plcui_image_validate_source(plcui_widget_t *widget, uint32_t width,
                                     uint32_t height, lv_color_format_t format,
                                     plcui_error_t *error)
{
    const plcui_image_t *image = widget->image;
    if (!image) return true;
    if (image->crop && ((uint64_t)(uint32_t)image->crop_x + (uint32_t)widget->w > width
        || (uint64_t)(uint32_t)image->crop_y + (uint32_t)widget->h > height)) {
        luat_plcui_error(error, "E_RESOURCE", "Image source rectangle exceeds source dimensions");
        return false;
    }
    bool transformed = !image->crop && ((image->fit == LV_IMAGE_ALIGN_CENTER
        && (image->zoom != 256 || image->rotation != 0))
        || ((image->fit == LV_IMAGE_ALIGN_CONTAIN || image->fit == LV_IMAGE_ALIGN_COVER)
            && (width != (uint32_t)widget->w || height != (uint32_t)widget->h)));
    if (transformed && (LV_COLOR_FORMAT_IS_INDEXED(format)
        || LV_COLOR_FORMAT_IS_ALPHA_ONLY(format) || LV_COLOR_FORMAT_IS_YUV(format))) {
        luat_plcui_error(error, "E_NOT_SUPPORTED", "Image pixel format does not support transforms");
        return false;
    }
    return true;
}

void luat_plcui_apply_image(plcui_widget_t *widget)
{
    if (!widget->obj || widget->type != PLCUI_IMAGE) return;
    if (widget->document->preparing_page >= 0
        || widget->page_index != (unsigned)widget->document->current_page) return;
    plcui_error_t error;
    if (!luat_plcui_prepare_widget_image(widget, &error))
        LLOGW("state image preparation failed: %s", error.message);
}

static void image_event(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    if (widget->document->closed || !widget->obj) return;
    lv_event_code_t code = lv_event_get_code(event);
    plcui_image_t *image = widget->image;
    /* Clip the base atlas draw to the logical viewport. The source/cache key is
       unchanged, so multiple regions retain one decoded image. */
    if (code == LV_EVENT_COVER_CHECK && image && !image->crop
        && (image->fit == LV_IMAGE_ALIGN_CENTER || image->fit == LV_IMAGE_ALIGN_CONTAIN)) {
        /* A centered/contained source may leave uncovered space inside the
           logical box. Never let native full-box cover inference cull its backplate. */
        lv_cover_check_info_t *info = lv_event_get_param(event);
        if (info->res != LV_COVER_RES_MASKED) info->res = LV_COVER_RES_NOT_COVER;
    } else if (code == LV_EVENT_REFR_EXT_DRAW_SIZE && image && !image->crop
        && image->fit == LV_IMAGE_ALIGN_CENTER) {
        int32_t width = (int32_t)lv_image_get_src_width(widget->obj);
        int32_t height = (int32_t)lv_image_get_src_height(widget->obj);
        if (width > 0 && height > 0) {
            lv_point_t pivot = {image->pivot_explicit ? image->pivot_x : width / 2,
                                image->pivot_explicit ? image->pivot_y : height / 2};
            lv_area_t area;
            lv_image_buf_get_transformed_area(&area, width, height, image->rotation,
                                              image->zoom, image->zoom, &pivot);
            /* Native image ext_draw_size uses the logical object size. A center
               image instead draws source pixels centered inside that object. */
            int32_t dx = (widget->w - width) / 2, dy = (widget->h - height) / 2;
            int32_t extra = LV_MAX(LV_MAX(-(area.x1 + dx), -(area.y1 + dy)),
                LV_MAX(area.x2 + dx - widget->w + 1, area.y2 + dy - widget->h + 1));
            lv_event_set_ext_draw_size(event, extra > 0 ? extra : 0);
        }
    } else if (code == LV_EVENT_DRAW_MAIN_BEGIN && image && image->crop) {
        lv_layer_t *layer = lv_event_get_layer(event);
        lv_area_t bounds;
        lv_obj_get_coords(widget->obj, &bounds);
        image->draw_clip = layer->_clip_area;
        image->clip_saved = true;
        if (!lv_area_intersect(&layer->_clip_area, &image->draw_clip, &bounds)) {
            layer->_clip_area.x1 = 1; layer->_clip_area.x2 = 0;
            layer->_clip_area.y1 = 1; layer->_clip_area.y2 = 0;
        }
    } else if (code == LV_EVENT_DRAW_MAIN_END && image && image->clip_saved) {
        lv_event_get_layer(event)->_clip_area = image->draw_clip;
        image->clip_saved = false;
    } else if (code == LV_EVENT_HIT_TEST) {
        lv_hit_test_info_t *info = lv_event_get_hit_test_info(event);
        lv_area_t bounds;
        lv_obj_get_coords(widget->obj, &bounds);
        int32_t x = widget->has_hit_rect ? widget->hit_x : 0;
        int32_t y = widget->has_hit_rect ? widget->hit_y : 0;
        int32_t w = widget->has_hit_rect ? widget->hit_w : widget->w;
        int32_t h = widget->has_hit_rect ? widget->hit_h : widget->h;
        if (info) info->res = luat_plcui_component_interactive(widget)
            && info->point->x >= bounds.x1 + x && info->point->x < bounds.x1 + x + w
            && info->point->y >= bounds.y1 + y && info->point->y < bounds.y1 + y + h;
    } else if (code == LV_EVENT_PRESSED && luat_plcui_component_interactive(widget)) {
        widget->pressed = true;
        luat_plcui_apply_image(widget);
    } else if (code == LV_EVENT_RELEASED || code == LV_EVENT_PRESS_LOST || code == LV_EVENT_INDEV_RESET) {
        widget->pressed = false;
        luat_plcui_apply_image(widget);
    } else if (code == LV_EVENT_CLICKED && widget->clickable && luat_plcui_component_interactive(widget)) {
        luat_plcui_emit(widget, PLCUI_CLICK);
    }
}

lv_obj_t *luat_plcui_image_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_image_create(parent);
    if (!object) return NULL;
    luat_plcui_component_init(widget, object);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_CLICK_FOCUSABLE);
    if (widget->clickable) lv_obj_add_flag(object, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(object, image_event, LV_EVENT_ALL, widget);
    widget->pressed = false;
    luat_plcui_image_sync(widget);
    luat_plcui_apply_image(widget);
    return object;
}
