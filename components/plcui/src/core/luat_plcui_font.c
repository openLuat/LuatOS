/** @file luat_plcui_font.c
 * XML 字体解析和独立的 HZFont 到 LVGL 适配。
 */
#include "luat_plcui_font.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(LUAT_USE_HZFONT)
#include "luat_hzfont.h"
#endif

/* 字体描述按 XML 实例持有，同一字号共享一个描述。
   描述只保存字号，不拥有底层 TTF 和 HZFont 的全局字形缓存。 */
struct plcui_hzfont_face {
    lv_font_t font;
    uint16_t size;
    plcui_hzfont_face_t *next;
};

static bool text_component(plcui_widget_type_t type)
{
    return type == PLCUI_LABEL || type == PLCUI_TEXTAREA || type == PLCUI_KEYBOARD
        || type == PLCUI_TABLE;
}

static void font_error_context(plcui_widget_t *widget, plcui_error_t *error, const char *attribute)
{
    if (!widget) return;
    snprintf(error->id, sizeof(error->id), "%s", widget->id);
    snprintf(error->attribute, sizeof(error->attribute), "%s", attribute);
    if (widget->document) {
        snprintf(error->file, sizeof(error->file), "%s", widget->document->path);
    }
}

static bool requested_hzfont(plcui_widget_t *widget)
{
    if (!strcmp(widget->font_id, "hzfont")) return true;
    if (!widget->font_id[0]) return false;
    plcui_resource_t *resource = luat_plcui_resource(widget->document, widget->font_id, PLCUI_RES_FONT);
    return resource && !strcmp(resource->builtin, "hzfont");
}

#if defined(LUAT_USE_HZFONT)

static uint8_t current_supersample(void)
{
    int value = ttf_get_supersample_rate();
    return value > 0 && value <= UINT8_MAX ? (uint8_t)value : 1;
}

static bool hzfont_glyph_description(const lv_font_t *font, lv_font_glyph_dsc_t *glyph,
                                    uint32_t letter, uint32_t letter_next)
{
    (void)letter_next;
    /* LVGL 的 entry 等内部字段也必须清零，不能只设置宽高。 */
    memset(glyph, 0, sizeof(*glyph));
    const plcui_hzfont_face_t *face = font->dsc;
    if (!face) return false;

    glyph->resolved_font = font;
    if (letter == ' ' || letter == '\t' || letter == '\n' || letter == '\r') {
        unsigned space = face->size / 2U;
        if (!space) space = 1;
        glyph->adv_w = letter == '\t' ? (uint16_t)(space * 4U) : letter == ' ' ? (uint16_t)space : 0;
        glyph->format = LV_FONT_GLYPH_FORMAT_NONE;
        return true;
    }

    uint16_t index = 0;
    if (luat_hzfont_lookup_glyph_index(letter, &index) != TTF_OK || !index) return false;
    const TtfBitmap *bitmap = luat_hzfont_get_bitmap(index, (uint8_t)face->size, current_supersample());
    if (!bitmap || bitmap->width > UINT16_MAX || bitmap->height > UINT16_MAX) return false;
    if (bitmap->width && bitmap->height && !bitmap->pixels) return false;
    int64_t offset_y = (int64_t)bitmap->originY - (int64_t)bitmap->height;
    if (offset_y < INT16_MIN || offset_y > INT16_MAX) return false;

    glyph->adv_w = (uint16_t)bitmap->width;
    glyph->box_w = (uint16_t)bitmap->width;
    glyph->box_h = (uint16_t)bitmap->height;
    glyph->stride = (uint16_t)bitmap->width;
    glyph->ofs_y = (int16_t)offset_y;
    glyph->gid.index = index;
    glyph->format = bitmap->width && bitmap->height ? LV_FONT_GLYPH_FORMAT_A8 : LV_FONT_GLYPH_FORMAT_NONE;
    return true;
}

static const void *hzfont_glyph_bitmap(lv_font_glyph_dsc_t *glyph, lv_draw_buf_t *draw_buffer)
{
    if (!glyph->resolved_font || glyph->format == LV_FONT_GLYPH_FORMAT_NONE) return NULL;
    const plcui_hzfont_face_t *face = glyph->resolved_font->dsc;
    if (!face || glyph->gid.index > UINT16_MAX) return NULL;
    const TtfBitmap *bitmap = luat_hzfont_get_bitmap((uint16_t)glyph->gid.index,
                                                   (uint8_t)face->size, current_supersample());
    if (!bitmap || !bitmap->pixels || !bitmap->width || !bitmap->height) return NULL;
    if (!draw_buffer) return bitmap->pixels;

    /* 字形缓存可能在其他字形请求时更新。复制进 LVGL 提供的缓冲，
       同时校验宽、高、步幅和容量，绝不扩大原缓冲的可写范围。 */
    uint32_t stride = draw_buffer->header.stride;
    if (!stride) stride = bitmap->width;
    if (!draw_buffer->data || stride < bitmap->width || stride > UINT16_MAX
        || draw_buffer->header.w < bitmap->width || draw_buffer->header.h < bitmap->height
        || (uint64_t)stride * draw_buffer->header.h > draw_buffer->data_size) {
        return NULL;
    }
    size_t used_bytes = (size_t)stride * draw_buffer->header.h;
    memset(draw_buffer->data, 0, used_bytes);
    for (uint32_t row = 0; row < bitmap->height; ++row) {
        memcpy(draw_buffer->data + (size_t)row * stride,
               bitmap->pixels + (size_t)row * bitmap->width, bitmap->width);
    }
    draw_buffer->header.magic = LV_IMAGE_HEADER_MAGIC;
    draw_buffer->header.cf = LV_COLOR_FORMAT_A8;
    draw_buffer->header.w = bitmap->width;
    draw_buffer->header.h = bitmap->height;
    draw_buffer->header.stride = stride;
    return draw_buffer;
}

#endif

static const lv_font_t *get_hzfont_face(plcui_document_t *xml, uint16_t size, plcui_error_t *error)
{
#if defined(LUAT_USE_HZFONT)
    if (luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY && !luat_hzfont_init(NULL, 0, 0)) {
        luat_plcui_error(error, "E_RESOURCE", "Cannot initialize hzfont; load a TTF with hzfont.init or enable the builtin TTF");
        return NULL;
    }
    for (plcui_hzfont_face_t *face = xml->hzfont_faces; face; face = face->next) {
        if (face->size == size) return &face->font;
    }
    plcui_hzfont_face_t *face = calloc(1, sizeof(*face));
    if (!face) {
        luat_plcui_error(error, "E_MEMORY", "Cannot allocate a hzfont size descriptor");
        return NULL;
    }
    face->size = size;
    face->font.get_glyph_dsc = hzfont_glyph_description;
    face->font.get_glyph_bitmap = hzfont_glyph_bitmap;
    face->font.dsc = face;
    face->font.line_height = (int32_t)size + 3;
    uint16_t ascent = (uint16_t)(((uint32_t)size * 4U + 4U) / 5U);
    face->font.base_line = face->font.line_height - ascent;
    face->font.kerning = LV_FONT_KERNING_NONE;
    face->font.underline_position = -2;
    face->font.underline_thickness = 1;
    face->font.fallback = lv_font_get_default();
    face->next = xml->hzfont_faces;
    xml->hzfont_faces = face;
    return &face->font;
#else
    (void)xml;
    (void)size;
    luat_plcui_error(error, "E_RESOURCE", "This firmware does not enable LUAT_USE_HZFONT");
    return NULL;
#endif
}

bool luat_plcui_resolve_widget_font(plcui_widget_t *widget, plcui_error_t *error)
{
    if (!widget || !widget->document) {
        luat_plcui_error(error, "E_SCHEMA", "Font requires an XML component");
        return false;
    }
    if (!text_component(widget->type)) return true;
    bool hzfont = requested_hzfont(widget);
    if (hzfont) {
        uint16_t size = widget->font_size ? widget->font_size : PLCUI_HZFONT_DEFAULT_SIZE;
        if (!size || size > UINT8_MAX) {
            luat_plcui_error(error, "E_SCHEMA", "hzfont font_size must be between 1 and 255");
            font_error_context(widget, error, "font_size");
            return false;
        }
        const lv_font_t *font = get_hzfont_face(widget->document, size, error);
        if (!font) {
            font_error_context(widget, error, "font");
            return false;
        }
        widget->font = font;
        widget->font_size = size;
        widget->use_hzfont = true;
        return true;
    }

    if (widget->font_size) {
        luat_plcui_error(error, "E_SCHEMA", "font_size is available only for hzfont");
        font_error_context(widget, error, "font_size");
        return false;
    }
    const lv_font_t *font;
#if LV_FONT_MONTSERRAT_20
    if (widget->type == PLCUI_KEYBOARD && !widget->font_id[0]) {
        font = &lv_font_montserrat_20;
    } else
#endif
    {
        font = luat_plcui_font(widget->document, widget->font_id);
    }
    if (!font) {
        luat_plcui_error(error, "E_RESOURCE", "Unknown font reference: %s", widget->font_id);
        font_error_context(widget, error, "font");
        return false;
    }
    widget->font = font;
    widget->use_hzfont = false;
    return true;
}

bool luat_plcui_set_font_size(plcui_widget_t *widget, uint16_t size, plcui_error_t *error)
{
    if (!widget || !text_component(widget->type)) {
        luat_plcui_error(error, "E_TYPE", "set_font_size requires a text component");
        font_error_context(widget, error, "font_size");
        return false;
    }
    if (!widget->use_hzfont) {
        luat_plcui_error(error, "E_SCHEMA", "font_size is available only for hzfont");
        font_error_context(widget, error, "font_size");
        return false;
    }
    if (!size || size > UINT8_MAX) {
        luat_plcui_error(error, "E_SCHEMA", "hzfont font_size must be between 1 and 255");
        font_error_context(widget, error, "font_size");
        return false;
    }
    if (!widget->obj || !widget->document || widget->document->closed) {
        luat_plcui_error(error, "E_OBJECT_CLOSED", "Text component is closed");
        font_error_context(widget, error, "font_size");
        return false;
    }
    const lv_font_t *font = get_hzfont_face(widget->document, size, error);
    if (!font) {
        font_error_context(widget, error, "font");
        return false;
    }
    widget->font = font;
    widget->font_size = size;
    lv_style_selector_t selector = widget->type == PLCUI_KEYBOARD || widget->type == PLCUI_TABLE ? LV_PART_ITEMS : LV_PART_MAIN;
    lv_obj_set_style_text_font(widget->obj, font, selector);
    /* textarea 的单行原生逻辑可能随字体调整高度，XML 的尺寸仍是布局依据。 */
    if (widget->type == PLCUI_TEXTAREA) {
        lv_obj_set_size(widget->obj, widget->w, widget->h);
    }
    lv_obj_mark_layout_as_dirty(widget->obj);
    lv_obj_invalidate(widget->obj);
    return true;
}

void luat_plcui_free_fonts(plcui_document_t *xml)
{
    /* 调用前须先删除该 XML 的页面对象；全局 HZFont 缓存由 hzfont 库管理。 */
    plcui_hzfont_face_t *face = xml->hzfont_faces;
    while (face) {
        plcui_hzfont_face_t *next = face->next;
        free(face);
        face = next;
    }
    xml->hzfont_faces = NULL;
}
