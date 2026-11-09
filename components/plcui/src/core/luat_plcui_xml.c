/** @file luat_plcui_xml.c SAX parser for the deliberately small plcui schema. */
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_plcui_component.h"
#include "luat_plcui_font.h"
#include "lvgl9/src/libs/expat/expat.h"
#include "lvgl9/src/draw/lv_image_decoder_private.h"
#include "lvgl9/src/misc/cache/instance/lv_image_header_cache.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <limits.h>
#include <ctype.h>

typedef enum { TAG_NONE, TAG_UI, TAG_RESOURCES, TAG_PAGES, TAG_PAGE, TAG_IMAGE, TAG_FONT, TAG_WIDGET, TAG_CELL, TAG_SERIES } tag_t;
typedef struct {
    XML_Parser parser;
    plcui_document_t *doc;
    plcui_error_t *error;
    tag_t stack[PLCUI_MAX_XML_DEPTH];
    unsigned widget_stack[PLCUI_MAX_XML_DEPTH];
    int depth;
    bool failed, root_seen, resources_seen, pages_seen;
} parser_t;

void luat_plcui_error(plcui_error_t *error, const char *code, const char *format, ...)
{
    va_list args;
    memset(error, 0, sizeof(*error));
    error->code = code;
    va_start(args, format);
    vsnprintf(error->message, sizeof(error->message), format, args);
    va_end(args);
}

static void fail(parser_t *p, const char *code, const char *message)
{
    if (p->failed) return;
    p->failed = true;
    luat_plcui_error(p->error, code, "%s", message);
    snprintf(p->error->file, sizeof(p->error->file), "%s", p->doc->path);
    p->error->line = (unsigned long)XML_GetCurrentLineNumber(p->parser);
    p->error->column = (unsigned long)XML_GetCurrentColumnNumber(p->parser) + 1UL;
    XML_StopParser(p->parser, XML_FALSE);
}

static const char *attribute(const char **attrs, const char *name)
{
    for (unsigned i = 0; attrs[i]; i += 2) if (!strcmp(attrs[i], name)) return attrs[i + 1];
    return NULL;
}

static bool allowed(parser_t *p, const char **attrs, const char *names)
{
    char token[96];
    for (unsigned i = 0; attrs[i]; i += 2) {
        int n = snprintf(token, sizeof(token), "|%s|", attrs[i]);
        if (n < 0 || (size_t)n >= sizeof(token) || !strstr(names, token)) {
            char message[192];
            snprintf(message, sizeof(message), "Unknown attribute: %s", attrs[i]);
            fail(p, "E_SCHEMA", message);
            snprintf(p->error->attribute, sizeof(p->error->attribute), "%s", attrs[i]);
            return false;
        }
    }
    return true;
}

static bool copy_attr(parser_t *p, const char **attrs, const char *name, char *dest, size_t capacity, bool required)
{
    const char *value = attribute(attrs, name);
    if (!value) {
        if (required) { fail(p, "E_SCHEMA", "A required attribute is missing"); snprintf(p->error->attribute, sizeof(p->error->attribute), "%s", name); }
        return !required;
    }
    if (strlen(value) >= capacity || (required && !value[0])) {
        fail(p, "E_SCHEMA", "Attribute is empty or exceeds its length limit");
        snprintf(p->error->attribute, sizeof(p->error->attribute), "%s", name);
        return false;
    }
    memcpy(dest, value, strlen(value) + 1);
    return true;
}

static bool integer_attr(parser_t *p, const char **attrs, const char *name, int32_t *dest, long minimum, long maximum, bool required)
{
    const char *text = attribute(attrs, name);
    char *end;
    long value;
    if (!text) {
        if (required) { fail(p, "E_SCHEMA", "A required integer attribute is missing"); snprintf(p->error->attribute, sizeof(p->error->attribute), "%s", name); }
        return !required;
    }
    errno = 0;
    value = strtol(text, &end, 10);
    if (!text[0] || *end || errno || value < minimum || value > maximum) {
        fail(p, "E_SCHEMA", "Integer attribute is invalid or out of range");
        snprintf(p->error->attribute, sizeof(p->error->attribute), "%s", name);
        return false;
    }
    *dest = (int32_t)value;
    return true;
}

static bool bool_attr(parser_t *p, const char **attrs, const char *name, bool *dest)
{
    const char *text = attribute(attrs, name);
    if (!text) return true;
    if (!strcmp(text, "true")) *dest = true;
    else if (!strcmp(text, "false")) *dest = false;
    else { fail(p, "E_SCHEMA", "Boolean attribute must be true or false"); return false; }
    return true;
}

static bool color_attr(parser_t *p, const char **attrs, const char *name, uint32_t *dest)
{
    const char *text = attribute(attrs, name);
    if (!text) return true;
    if (strlen(text) != 7 || text[0] != '#') { fail(p, "E_SCHEMA", "Color must use #RRGGBB notation"); return false; }
    for (unsigned i = 1; i < 7; i++) if (!isxdigit((unsigned char)text[i])) { fail(p, "E_SCHEMA", "Invalid color"); return false; }
    *dest = (uint32_t)strtoul(text + 1, NULL, 16);
    return true;
}

static bool relative_path(const char *path)
{
    if (!path[0] || path[0] == '/' || strchr(path, '\\') || strchr(path, ':')) return false;
    const char *segment = path;
    for (const char *c = path;; c++) {
        if (*c == '/' || *c == '\0') {
            size_t length = (size_t)(c - segment);
            if (!length || (length == 1 && segment[0] == '.') || (length == 2 && segment[0] == '.' && segment[1] == '.')) return false;
            if (!*c) break;
            segment = c + 1;
        }
    }
    return true;
}

static bool chart_number_attr(parser_t *p, const char **attrs, const char *name, int32_t *dest)
{
    const char *text = attribute(attrs, name);
    if (!text) return true;
    char *end;
    errno = 0;
    double value = strtod(text, &end);
    if (!text[0] || *end || errno || !luat_plcui_chart_number(value, dest)) {
        fail(p, "E_SCHEMA", "Chart numbers must be finite and between -1000 and 1000");
        snprintf(p->error->attribute, sizeof(p->error->attribute), "%s", name);
        return false;
    }
    return true;
}

static bool alignment_value(const char *text, size_t length, lv_text_align_t *align)
{
    if (length == 4 && !strncmp(text, "left", 4)) *align = LV_TEXT_ALIGN_LEFT;
    else if (length == 6 && !strncmp(text, "center", 6)) *align = LV_TEXT_ALIGN_CENTER;
    else if (length == 5 && !strncmp(text, "right", 5)) *align = LV_TEXT_ALIGN_RIGHT;
    else return false;
    return true;
}

static void parse_table_alignments(parser_t *p, const char **attrs, plcui_widget_t *widget)
{
    plcui_table_t *table = widget->table;
    const char *text = attribute(attrs, "align");
    if (text && !alignment_value(text, strlen(text), &widget->align)) { fail(p, "E_SCHEMA", "Invalid table alignment"); return; }
    table->header_align = widget->align;
    text = attribute(attrs, "header-align");
    if (text && !alignment_value(text, strlen(text), &table->header_align)) { fail(p, "E_SCHEMA", "Invalid table header alignment"); return; }
    for (unsigned i = 0; i < table->columns; ++i) table->column_aligns[i] = widget->align;
    text = attribute(attrs, "col-aligns");
    if (!text) return;
    for (unsigned i = 0; i < table->columns; ++i) {
        while (isspace((unsigned char)*text)) ++text;
        const char *end = strchr(text, ',');
        if (!end) end = text + strlen(text);
        const char *trim = end;
        while (trim > text && isspace((unsigned char)trim[-1])) --trim;
        if (!alignment_value(text, (size_t)(trim - text), &table->column_aligns[i])
            || (i + 1 == table->columns ? *end != '\0' : *end != ',')) {
            fail(p, "E_SCHEMA", "col-aligns requires one left, center or right value per column"); return;
        }
        text = *end ? end + 1 : end;
    }
}

static void parse_column_widths(parser_t *p, const char *text, plcui_table_t *table)
{
    if (!text) return;
    for (unsigned i = 0; i < table->columns; ++i) {
        char *end;
        errno = 0;
        long width = strtol(text, &end, 10);
        if (end == text || errno || width < 1 || width > 4096) { fail(p, "E_SCHEMA", "Invalid table column width"); return; }
        while (isspace((unsigned char)*end)) ++end;
        table->widths[i] = (uint16_t)width;
        if (i + 1 == table->columns) {
            if (*end) fail(p, "E_SCHEMA", "col-widths must contain exactly columns values");
        } else {
            if (*end != ',') { fail(p, "E_SCHEMA", "col-widths must contain exactly columns values"); return; }
            text = end + 1;
        }
    }
}

static void parse_series_values(parser_t *p, const char *text, plcui_chart_t *chart, plcui_chart_series_t *series)
{
    for (unsigned i = 0; i < chart->points; ++i) series->values[i] = chart->minimum;
    if (!text) return;
    for (unsigned i = 0; i < chart->points; ++i) {
        char *end;
        errno = 0;
        double value = strtod(text, &end);
        if (end == text || errno || !luat_plcui_chart_number(value, &series->values[i])) { fail(p, "E_SCHEMA", "Invalid chart series value"); return; }
        while (isspace((unsigned char)*end)) ++end;
        if (i + 1 == chart->points) {
            if (*end) fail(p, "E_SCHEMA", "Series values count must equal point-count");
        } else {
            if (*end != ',') { fail(p, "E_SCHEMA", "Series values count must equal point-count"); return; }
            text = end + 1;
        }
    }
}

static void XMLCALL start_element(void *data, const char *name, const char **attrs)
{
    parser_t *p = data;
    plcui_document_t *doc = p->doc;
    tag_t parent = p->depth ? p->stack[p->depth - 1] : TAG_NONE;
    tag_t tag = TAG_NONE;
    if (p->failed) return;
    if (p->depth >= PLCUI_MAX_XML_DEPTH) { fail(p, "E_SCHEMA", "XML nesting depth exceeds its limit"); return; }
    if (parent == TAG_NONE && !strcmp(name, "ui") && !p->root_seen) {
        tag = TAG_UI;
        p->root_seen = true;
        if (!allowed(p, attrs, "|version||width||height||entry|")) return;
        const char *version = attribute(attrs, "version");
        if (!version || strcmp(version, "0.1")) { fail(p, "E_VERSION", "Only plcui XML version 0.1 is supported"); return; }
        int32_t width = 0, height = 0;
        integer_attr(p, attrs, "width", &width, 1, 4096, true);
        integer_attr(p, attrs, "height", &height, 1, 4096, true);
        doc->width = (int)width; doc->height = (int)height;
        copy_attr(p, attrs, "entry", doc->entry, sizeof(doc->entry), true);
    } else if (parent == TAG_UI && !strcmp(name, "resources") && !p->resources_seen) {
        tag = TAG_RESOURCES; p->resources_seen = true;
        allowed(p, attrs, "");
    } else if (parent == TAG_UI && !strcmp(name, "pages") && !p->pages_seen) {
        tag = TAG_PAGES; p->pages_seen = true;
        allowed(p, attrs, "");
    } else if (parent == TAG_RESOURCES && (!strcmp(name, "image") || !strcmp(name, "font"))) {
        bool image = !strcmp(name, "image");
        tag = image ? TAG_IMAGE : TAG_FONT;
        if (!allowed(p, attrs, image ? "|id||src|" : "|id||builtin|")) return;
        if (doc->resource_count >= PLCUI_MAX_RESOURCES) { fail(p, "E_SCHEMA", "Resource count limit exceeded"); return; }
        plcui_resource_t *items = realloc(doc->resources, (doc->resource_count + 1U) * sizeof(*items));
        if (!items) { fail(p, "E_MEMORY", "Cannot allocate resource description"); return; }
        doc->resources = items;
        plcui_resource_t *resource = &items[doc->resource_count++];
        memset(resource, 0, sizeof(*resource));
        resource->type = image ? PLCUI_RES_IMAGE : PLCUI_RES_FONT;
        copy_attr(p, attrs, "id", resource->id, sizeof(resource->id), true);
        if (image) {
            const char *src = attribute(attrs, "src");
            if (!src || !relative_path(src)) { fail(p, "E_RESOURCE", "Image paths must stay relative to the XML package directory"); return; }
            int count = snprintf(resource->path, sizeof(resource->path), "%s%s", doc->directory, src);
            if (count < 0 || (size_t)count >= sizeof(resource->path)) { fail(p, "E_RESOURCE", "Image path is too long"); return; }
        } else copy_attr(p, attrs, "builtin", resource->builtin, sizeof(resource->builtin), true);
    } else if (parent == TAG_PAGES && !strcmp(name, "page")) {
        tag = TAG_PAGE;
        if (!allowed(p, attrs, "|id||background|")) return;
        if (doc->page_count >= PLCUI_MAX_PAGES) { fail(p, "E_SCHEMA", "Page count limit exceeded"); return; }
        plcui_page_t *pages = realloc(doc->pages, (doc->page_count + 1U) * sizeof(*pages));
        if (!pages) { fail(p, "E_MEMORY", "Cannot allocate page description"); return; }
        doc->pages = pages;
        plcui_page_t *page = &pages[doc->page_count++];
        memset(page, 0, sizeof(*page));
        copy_attr(p, attrs, "id", page->id, sizeof(page->id), true);
        color_attr(p, attrs, "background", &page->background);
    } else if (parent == TAG_WIDGET && (!strcmp(name, "cell") || !strcmp(name, "series"))) {
        plcui_page_t *page = &doc->pages[doc->page_count - 1U];
        plcui_widget_t *owner = &page->widgets[p->widget_stack[p->depth - 1]];
        if (!strcmp(name, "cell") && owner->table) {
            tag = TAG_CELL;
            if (!allowed(p, attrs, "|row||column||text|")) return;
            int32_t row = 0, column = 0;
            integer_attr(p, attrs, "row", &row, 1, owner->table->rows, true);
            integer_attr(p, attrs, "column", &column, 1, owner->table->columns, true);
            char text[PLCUI_TEXT_MAX] = {0};
            copy_attr(p, attrs, "text", text, sizeof(text), false);
            if (p->failed) return;
            unsigned index = (unsigned)(row - 1) * owner->table->columns + (unsigned)(column - 1);
            if (owner->table->cells[index]) { fail(p, "E_SCHEMA", "Duplicate table cell"); return; }
            owner->table->cells[index] = malloc(strlen(text) + 1);
            if (!owner->table->cells[index]) { fail(p, "E_MEMORY", "Cannot allocate table text"); return; }
            memcpy(owner->table->cells[index], text, strlen(text) + 1);
        } else if (!strcmp(name, "series") && owner->chart) {
            tag = TAG_SERIES;
            if (!allowed(p, attrs, "|id||color||values||hidden|")) return;
            if (owner->chart->count >= PLCUI_CHART_MAX_SERIES) { fail(p, "E_SCHEMA", "Too many chart series"); return; }
            plcui_chart_series_t *series = &owner->chart->series[owner->chart->count++];
            series->color = 0x38d6ce;
            copy_attr(p, attrs, "id", series->id, sizeof(series->id), true);
            color_attr(p, attrs, "color", &series->color);
            bool_attr(p, attrs, "hidden", &series->hidden);
            for (unsigned i = 0; i + 1 < owner->chart->count; ++i) {
                if (!strcmp(series->id, owner->chart->series[i].id)) { fail(p, "E_DUPLICATE_ID", "Duplicate chart series ID"); return; }
            }
            if (p->failed) return;
            series->values = malloc(owner->chart->points * sizeof(*series->values));
            if (!series->values) { fail(p, "E_MEMORY", "Cannot allocate chart values"); return; }
            parse_series_values(p, attribute(attrs, "values"), owner->chart, series);
        } else { fail(p, "E_SCHEMA", "cell requires a table and series requires a chart"); return; }
    } else if ((parent == TAG_PAGE || parent == TAG_WIDGET) && (!strcmp(name, "image") || !strcmp(name, "label") || !strcmp(name, "textarea") || !strcmp(name, "keyboard") || !strcmp(name, "container") || !strcmp(name, "table") || !strcmp(name, "chart"))) {
        tag = TAG_WIDGET;
        plcui_page_t *page = &doc->pages[doc->page_count - 1U];
        int32_t parent_index = -1;
        if (parent == TAG_WIDGET) {
            unsigned index = p->widget_stack[p->depth - 1];
            if (index >= page->count || page->widgets[index].type != PLCUI_CONTAINER) { fail(p, "E_SCHEMA", "Only container components can contain child components"); return; }
            parent_index = (int32_t)index;
        }
        plcui_widget_type_t type = !strcmp(name, "image") ? PLCUI_IMAGE : !strcmp(name, "label") ? PLCUI_LABEL : !strcmp(name, "textarea") ? PLCUI_TEXTAREA : !strcmp(name, "keyboard") ? PLCUI_KEYBOARD : !strcmp(name, "table") ? PLCUI_TABLE : !strcmp(name, "chart") ? PLCUI_CHART : PLCUI_CONTAINER;
        const char *specific = type == PLCUI_IMAGE ? "|src||src-pressed||src-checked||src-disabled||clickable||on-click||hit-x||hit-y||hit-w||hit-h|" :
                               type == PLCUI_LABEL ? "|text||font||font_size||color||align|" :
                               type == PLCUI_TEXTAREA ? "|text||font||font_size||color||align||max-length||accepted-chars||keyboard||one-line||on-change||on-submit||on-cancel|" :
                               type == PLCUI_KEYBOARD ? "|layout||font||font_size|" :
                               type == PLCUI_TABLE ? "|rows||columns||col-widths||col-aligns||align||header-align||grid||row-height||header||cell-padding||header-color||alternate-color||font||font_size||color||background||border-color||border-width|" :
                               type == PLCUI_CHART ? "|type||point-count||y-min||y-max||hdiv||vdiv||line-width||grid-color||background||bg-opacity||border-color||border-width|" : "|background||bg-opacity||border-color||border-width||radius||padding|";
        char accepted[512];
        snprintf(accepted, sizeof(accepted), "|id||x||y||w||h||hidden||disabled|%s", specific);
        if (!allowed(p, attrs, accepted)) return;
        if (doc->widget_count >= PLCUI_MAX_WIDGETS) { fail(p, "E_SCHEMA", "Component count limit exceeded"); return; }
        plcui_widget_t *items = realloc(page->widgets, (page->count + 1U) * sizeof(*items));
        if (!items) { fail(p, "E_MEMORY", "Cannot allocate component description"); return; }
        page->widgets = items;
        plcui_widget_t *w = &items[page->count];
        memset(w, 0, sizeof(*w));
        w->type = type; w->document = doc; w->page_index = doc->page_count - 1U; w->widget_index = page->count++;
        w->parent_index = parent_index;
        p->widget_stack[p->depth] = w->widget_index;
        doc->widget_count++;
        w->color = 0xffffff; w->max_length = PLCUI_TEXT_MAX - 1; w->align = LV_TEXT_ALIGN_LEFT;
        w->one_line = true;
        copy_attr(p, attrs, "id", w->id, sizeof(w->id), true);
        integer_attr(p, attrs, "x", &w->x, -4096, 4096, false);
        integer_attr(p, attrs, "y", &w->y, -4096, 4096, false);
        integer_attr(p, attrs, "w", &w->w, 1, 4096, true);
        integer_attr(p, attrs, "h", &w->h, 1, 4096, true);
        bool_attr(p, attrs, "hidden", &w->hidden);
        bool_attr(p, attrs, "disabled", &w->disabled);
        if (type == PLCUI_LABEL || type == PLCUI_TEXTAREA || type == PLCUI_KEYBOARD || type == PLCUI_TABLE) {
            int32_t font_size = 0;
            if (type == PLCUI_TABLE) snprintf(w->font_id, sizeof(w->font_id), "hzfont");
            copy_attr(p, attrs, "font", w->font_id, sizeof(w->font_id), false);
            integer_attr(p, attrs, "font_size", &font_size, 1, 255, false);
            w->font_size = (uint16_t)font_size;
        }
        if (type == PLCUI_IMAGE) {
            const char *sources[] = {"src", "src-pressed", "src-checked", "src-disabled"};
            for (unsigned i = 0; i < 4; i++) copy_attr(p, attrs, sources[i], w->source[i], sizeof(w->source[i]), i == 0);
            bool_attr(p, attrs, "clickable", &w->clickable);
            copy_attr(p, attrs, "on-click", w->handler[PLCUI_CLICK], PLCUI_ID_MAX, false);
            w->has_hit_rect = attribute(attrs, "hit-x") || attribute(attrs, "hit-y") || attribute(attrs, "hit-w") || attribute(attrs, "hit-h");
            w->hit_w = w->w; w->hit_h = w->h;
            integer_attr(p, attrs, "hit-x", &w->hit_x, 0, 4096, false);
            integer_attr(p, attrs, "hit-y", &w->hit_y, 0, 4096, false);
            integer_attr(p, attrs, "hit-w", &w->hit_w, 1, 4096, false);
            integer_attr(p, attrs, "hit-h", &w->hit_h, 1, 4096, false);
            if ((int64_t)w->hit_x + w->hit_w > w->w || (int64_t)w->hit_y + w->hit_h > w->h) fail(p, "E_SCHEMA", "Hit rectangle must remain inside the component bounds");
            if (w->handler[PLCUI_CLICK][0] && !w->clickable) fail(p, "E_SCHEMA", "on-click requires clickable=true");
        } else if (type == PLCUI_LABEL || type == PLCUI_TEXTAREA) {
            copy_attr(p, attrs, "text", w->text, sizeof(w->text), false);
            color_attr(p, attrs, "color", &w->color);
            const char *align = attribute(attrs, "align");
            if (align) {
                if (!strcmp(align, "left")) w->align = LV_TEXT_ALIGN_LEFT;
                else if (!strcmp(align, "center")) w->align = LV_TEXT_ALIGN_CENTER;
                else if (!strcmp(align, "right")) w->align = LV_TEXT_ALIGN_RIGHT;
                else fail(p, "E_SCHEMA", "align must be left, center or right");
            }
            if (type == PLCUI_TEXTAREA) {
                bool_attr(p, attrs, "one-line", &w->one_line);
                int32_t maximum = w->max_length;
                integer_attr(p, attrs, "max-length", &maximum, 1, PLCUI_TEXT_MAX - 1, false);
                w->max_length = (uint16_t)maximum;
                copy_attr(p, attrs, "keyboard", w->keyboard_id, sizeof(w->keyboard_id), false);
                copy_attr(p, attrs, "accepted-chars", w->accepted_chars, sizeof(w->accepted_chars), false);
                copy_attr(p, attrs, "on-change", w->handler[PLCUI_CHANGE], PLCUI_ID_MAX, false);
                copy_attr(p, attrs, "on-submit", w->handler[PLCUI_SUBMIT], PLCUI_ID_MAX, false);
                copy_attr(p, attrs, "on-cancel", w->handler[PLCUI_CANCEL], PLCUI_ID_MAX, false);
            }
        } else if (type == PLCUI_KEYBOARD) {
            const char *layout = attribute(attrs, "layout");
            w->numeric_keyboard = true;
            if (layout && !strcmp(layout, "text")) w->numeric_keyboard = false;
            else if (layout && strcmp(layout, "number")) fail(p, "E_SCHEMA", "Keyboard layout must be number or text");
        } else if (type == PLCUI_TABLE) {
            w->table = calloc(1, sizeof(*w->table));
            if (!w->table) { fail(p, "E_MEMORY", "Cannot allocate table description"); return; }
            plcui_table_t *table = w->table;
            int32_t rows = 0, columns = 0, padding = 8, border = 1, row_height = 0;
            table->header = true;
            table->header_color = 0x153c56;
            table->alternate_color = 0x10283b;
            w->background = 0x0c2133;
            w->border_color = 0x24465c;
            integer_attr(p, attrs, "rows", &rows, 1, PLCUI_TABLE_MAX_ROWS, true);
            integer_attr(p, attrs, "columns", &columns, 1, PLCUI_TABLE_MAX_COLS, true);
            integer_attr(p, attrs, "cell-padding", &padding, 0, 64, false);
            integer_attr(p, attrs, "border-width", &border, 0, 16, false);
            integer_attr(p, attrs, "row-height", &row_height, 1, 4096, false);
            bool_attr(p, attrs, "header", &table->header);
            bool_attr(p, attrs, "grid", &table->grid);
            color_attr(p, attrs, "color", &w->color);
            color_attr(p, attrs, "background", &w->background);
            color_attr(p, attrs, "border-color", &w->border_color);
            color_attr(p, attrs, "header-color", &table->header_color);
            color_attr(p, attrs, "alternate-color", &table->alternate_color);
            if (p->failed) return;
            if ((unsigned)rows * (unsigned)columns > PLCUI_TABLE_MAX_CELLS) { fail(p, "E_SCHEMA", "Table exceeds 1024 cells"); return; }
            table->rows = (uint16_t)rows;
            table->columns = (uint16_t)columns;
            table->cell_padding = (uint16_t)padding;
            table->row_height = (uint16_t)row_height;
            w->border_width = (uint16_t)border;
            table->cells = calloc((size_t)rows * columns, sizeof(*table->cells));
            if (!table->cells) { fail(p, "E_MEMORY", "Cannot allocate table cells"); return; }
            int32_t available = w->w - border * 2;
            if (available < columns) available = columns;
            for (int32_t i = 0; i < columns; ++i) table->widths[i] = (uint16_t)(available / columns + (i == columns - 1 ? available % columns : 0));
            parse_column_widths(p, attribute(attrs, "col-widths"), table);
            parse_table_alignments(p, attrs, w);
        } else if (type == PLCUI_CHART) {
            w->chart = calloc(1, sizeof(*w->chart));
            if (!w->chart) { fail(p, "E_MEMORY", "Cannot allocate chart description"); return; }
            plcui_chart_t *chart = w->chart;
            chart->maximum = 100 * PLCUI_CHART_SCALE;
            chart->grid_color = 0x34566b;
            int32_t points = 60, hdiv = 5, vdiv = 6, line = 2, border = 0, opacity = 0;
            integer_attr(p, attrs, "point-count", &points, 2, PLCUI_CHART_MAX_POINTS, false);
            integer_attr(p, attrs, "hdiv", &hdiv, 0, 32, false);
            integer_attr(p, attrs, "vdiv", &vdiv, 0, 32, false);
            integer_attr(p, attrs, "line-width", &line, 1, 16, false);
            integer_attr(p, attrs, "border-width", &border, 0, 16, false);
            integer_attr(p, attrs, "bg-opacity", &opacity, 0, 255, false);
            chart_number_attr(p, attrs, "y-min", &chart->minimum);
            chart_number_attr(p, attrs, "y-max", &chart->maximum);
            color_attr(p, attrs, "grid-color", &chart->grid_color);
            color_attr(p, attrs, "background", &w->background);
            color_attr(p, attrs, "border-color", &w->border_color);
            const char *kind = attribute(attrs, "type");
            if (kind && strcmp(kind, "line") && strcmp(kind, "bar")) fail(p, "E_SCHEMA", "Chart type must be line or bar");
            chart->bar = kind && !strcmp(kind, "bar");
            if (chart->minimum >= chart->maximum) fail(p, "E_SCHEMA", "Chart y-min must be less than y-max");
            if (p->failed) return;
            chart->points = (uint16_t)points;
            chart->hdiv = (uint16_t)hdiv;
            chart->vdiv = (uint16_t)vdiv;
            chart->line_width = (uint16_t)line;
            w->border_width = (uint16_t)border;
            w->bg_opa = (uint8_t)opacity;
        } else if (type == PLCUI_CONTAINER) {
            if (attribute(attrs, "background")) w->bg_opa = 255;
            color_attr(p, attrs, "background", &w->background);
            color_attr(p, attrs, "border-color", &w->border_color);
            int32_t opacity = w->bg_opa, border = 0, radius = 0, padding = 0;
            integer_attr(p, attrs, "bg-opacity", &opacity, 0, 255, false);
            integer_attr(p, attrs, "border-width", &border, 0, 4096, false);
            integer_attr(p, attrs, "radius", &radius, 0, 4096, false);
            integer_attr(p, attrs, "padding", &padding, 0, 4096, false);
            w->bg_opa = (uint8_t)opacity;
            w->border_width = (uint16_t)border;
            w->radius = (uint16_t)radius;
            w->padding = (uint16_t)padding;
        }
        if (p->failed) snprintf(p->error->id, sizeof(p->error->id), "%s", w->id);
    } else {
        char message[192];
        snprintf(message, sizeof(message), "Unsupported element or invalid nesting: %s", name);
        fail(p, "E_SCHEMA", message);
        return;
    }
    if (!p->failed) p->stack[p->depth++] = tag;
}

static void XMLCALL end_element(void *data, const char *name)
{
    parser_t *p = data;
    (void)name;
    if (!p->failed && p->depth > 0) p->depth--;
}

static void XMLCALL character_data(void *data, const char *text, int length)
{
    parser_t *p = data;
    for (int i = 0; i < length; i++) if (!isspace((unsigned char)text[i])) { fail(p, "E_SCHEMA", "Text content belongs in a text attribute"); break; }
}

static void XMLCALL doctype(void *data, const char *name, const char *system_id, const char *public_id, int internal)
{
    (void)name; (void)system_id; (void)public_id; (void)internal;
    fail(data, "E_SCHEMA", "DTD and external entities are not supported");
}

static void XMLCALL processing_instruction(void *data, const char *target, const char *instruction)
{
    (void)target; (void)instruction;
    fail(data, "E_SCHEMA", "XML processing instructions are not supported");
}

static int XMLCALL external_entity(XML_Parser parser, const char *context, const char *base, const char *system_id, const char *public_id)
{
    (void)context; (void)base; (void)system_id; (void)public_id;
    parser_t *p = XML_GetUserData(parser);
    fail(p, "E_SCHEMA", "External entities are not supported");
    return XML_STATUS_ERROR;
}

plcui_resource_t *luat_plcui_resource(plcui_document_t *doc, const char *id, plcui_resource_type_t type)
{
    for (unsigned i = 0; i < doc->resource_count; i++) if (doc->resources[i].type == type && !strcmp(doc->resources[i].id, id)) return &doc->resources[i];
    return NULL;
}

static const lv_font_t *builtin_font(const char *name)
{
#if LV_FONT_MONTSERRAT_14
    if (!strcmp(name, "montserrat_14")) return &lv_font_montserrat_14;
#endif
#if LV_FONT_MONTSERRAT_16
    if (!strcmp(name, "montserrat_16")) return &lv_font_montserrat_16;
#endif
#if LV_FONT_MONTSERRAT_20
    if (!strcmp(name, "montserrat_20")) return &lv_font_montserrat_20;
#endif
#if LV_FONT_MONTSERRAT_24
    if (!strcmp(name, "montserrat_24")) return &lv_font_montserrat_24;
#endif
#if LV_FONT_MONTSERRAT_32
    if (!strcmp(name, "montserrat_32")) return &lv_font_montserrat_32;
#endif
    return NULL;
}

const lv_font_t *luat_plcui_font(plcui_document_t *doc, const char *id)
{
    if (!id[0]) return LV_FONT_DEFAULT;
    plcui_resource_t *resource = luat_plcui_resource(doc, id, PLCUI_RES_FONT);
    return resource ? resource->font : NULL;
}

int luat_plcui_page_index(plcui_document_t *doc, const char *id)
{
    for (unsigned i = 0; i < doc->page_count; i++) if (!strcmp(doc->pages[i].id, id)) return (int)i;
    return -1;
}

static bool validate_image(plcui_resource_t *resource, plcui_error_t *error)
{
    lv_image_header_t header;
    memset(&header, 0, sizeof(header));
    /* Package files may have changed since an earlier page visit. */
    lv_image_header_cache_drop(resource->path);
    size_t file_bytes = luat_fs_fsize(resource->path);
    if (!file_bytes || file_bytes > PLCUI_MAX_IMAGE_BYTES || lv_image_decoder_get_info(resource->path, &header) != LV_RESULT_OK || !header.w || !header.h || (uint64_t)header.w * header.h * 4U > PLCUI_MAX_IMAGE_BYTES || (uint64_t)header.w * header.h * 4U > LV_CACHE_DEF_SIZE) {
        luat_plcui_error(error, "E_RESOURCE", "Image is missing, unsupported or exceeds its file/pixel/cache limit: %s", resource->path);
        return false;
    }
    lv_image_decoder_dsc_t probe;
    lv_image_decoder_args_t args;
    memset(&probe, 0, sizeof(probe));
    memset(&args, 0, sizeof(args));
    args.no_cache = true;
    /* A PNG header alone does not prove that IDAT is decodable. Decode the file
       before a transaction can replace a working page, without disturbing its cache. */
    if (lv_image_decoder_open(&probe, resource->path, &args) != LV_RESULT_OK) {
        luat_plcui_error(error, "E_RESOURCE", "Image cannot be fully decoded: %s", resource->path);
        return false;
    }
    bool decoded = probe.decoded != NULL;
    lv_image_decoder_close(&probe);
    if (!decoded) {
        luat_plcui_error(error, "E_RESOURCE", "This image requires an unsupported incremental decoder: %s", resource->path);
        return false;
    }
    resource->decoded_bytes = (uint32_t)((uint64_t)header.w * header.h * 4U);
    return true;
}

bool luat_plcui_validate_page_images(plcui_document_t *doc, int index, plcui_error_t *error)
{
    bool checked[PLCUI_MAX_RESOURCES];
    memset(checked, 0, sizeof(checked));
    plcui_page_t *page = &doc->pages[index];
    for (unsigned i = 0; i < page->count; i++) {
        plcui_widget_t *widget = &page->widgets[i];
        if (widget->type != PLCUI_IMAGE) continue;
        for (unsigned state = 0; state < 4; state++) {
            if (!widget->source[state][0]) continue;
            plcui_resource_t *resource = luat_plcui_resource(doc, widget->source[state], PLCUI_RES_IMAGE);
            if (!resource) { luat_plcui_error(error, "E_RESOURCE", "Image reference no longer exists"); return false; }
            unsigned resource_index = (unsigned)(resource - doc->resources);
            if (!checked[resource_index] && !validate_image(resource, error)) return false;
            checked[resource_index] = true;
        }
    }
    return true;
}

bool luat_plcui_validate(plcui_document_t *doc, plcui_error_t *error)
{
    if (doc->width != luat_plcui_runtime()->width || doc->height != luat_plcui_runtime()->height) { luat_plcui_error(error, "E_SCHEMA", "XML size must match the initialized display size"); return false; }
    if (!doc->page_count || luat_plcui_page_index(doc, doc->entry) < 0) { luat_plcui_error(error, "E_SCHEMA", "The entry page does not exist"); return false; }
    for (unsigned i = 0; i < doc->resource_count; i++) {
        plcui_resource_t *r = &doc->resources[i];
        for (unsigned j = 0; j < i; j++) if (!strcmp(r->id, doc->resources[j].id)) { luat_plcui_error(error, "E_DUPLICATE_ID", "Duplicate resource ID: %s", r->id); return false; }
        if (r->type == PLCUI_RES_FONT) {
            if (!strcmp(r->builtin, "hzfont")) {
#if !defined(LUAT_USE_HZFONT)
                luat_plcui_error(error, "E_RESOURCE", "HZFont is not enabled in this build");
                return false;
#endif
            } else {
                if (!strcmp(r->id, "hzfont")) {
                    luat_plcui_error(error, "E_SCHEMA", "The font ID hzfont is reserved for HZFont");
                    return false;
                }
                r->font = builtin_font(r->builtin);
                if (!r->font) { luat_plcui_error(error, "E_RESOURCE", "Builtin font is not available: %s", r->builtin); return false; }
            }
        } else if (!validate_image(r, error)) return false;
    }
    lua_State *L = doc->L;
    for (unsigned p = 0; p < doc->page_count; p++) {
        plcui_page_t *page = &doc->pages[p];
        for (unsigned q = 0; q < p; q++) if (!strcmp(page->id, doc->pages[q].id)) { luat_plcui_error(error, "E_DUPLICATE_ID", "Duplicate page ID: %s", page->id); return false; }
        for (unsigned i = 0; i < page->count; i++) {
            plcui_widget_t *w = &page->widgets[i];
            if (w->parent_index < -1 || (w->parent_index >= 0 && ((unsigned)w->parent_index >= i || page->widgets[w->parent_index].type != PLCUI_CONTAINER))) { luat_plcui_error(error, "E_SCHEMA", "Component parent must be a preceding container on the same page"); return false; }
            for (unsigned j = 0; j < i; j++) if (!strcmp(w->id, page->widgets[j].id)) { luat_plcui_error(error, "E_DUPLICATE_ID", "Duplicate component ID: %s", w->id); return false; }
            if (w->type == PLCUI_IMAGE) {
                for (unsigned k = 0; k < 4; k++) if (w->source[k][0] && !luat_plcui_resource(doc, w->source[k], PLCUI_RES_IMAGE)) { luat_plcui_error(error, "E_RESOURCE", "Unknown image reference: %s", w->source[k]); return false; }
            }
            if ((w->type == PLCUI_LABEL || w->type == PLCUI_TEXTAREA || w->type == PLCUI_KEYBOARD || w->type == PLCUI_TABLE) && !luat_plcui_resolve_widget_font(w, error)) return false;
            if (w->chart && !w->chart->count) { luat_plcui_error(error, "E_SCHEMA", "A chart requires at least one series"); return false; }
            if ((w->type == PLCUI_LABEL || w->type == PLCUI_TEXTAREA) && !luat_plcui_check_text(w, w->text, strlen(w->text), error)) return false;
            if (w->type == PLCUI_TEXTAREA && w->keyboard_id[0]) {
                bool found = false;
                for (unsigned j = 0; j < page->count; j++) if (!strcmp(w->keyboard_id, page->widgets[j].id) && page->widgets[j].type == PLCUI_KEYBOARD) found = true;
                if (!found) { luat_plcui_error(error, "E_SCHEMA", "Input keyboard must refer to a keyboard on the same page: %s", w->id); return false; }
            }
            for (unsigned k = 0; k < 4; k++) if (w->handler[k][0]) {
                lua_rawgeti(L, LUA_REGISTRYINDEX, doc->handlers_ref);
                lua_getfield(L, -1, w->handler[k]);
                bool valid = lua_isfunction(L, -1);
                lua_pop(L, 2);
                if (!valid) { luat_plcui_error(error, "E_HANDLER", "Missing event handler: %s", w->handler[k]); return false; }
            }
        }
    }
    return true;
}

bool luat_plcui_parse(plcui_document_t *doc, const char *path, plcui_error_t *error)
{
    if (!path || path[0] != '/' || strlen(path) >= sizeof(doc->path) || strchr(path, '\\') || strchr(path, ':')) { luat_plcui_error(error, "E_RESOURCE", "XML path must be an absolute LuatOS VFS path"); return false; }
    snprintf(doc->path, sizeof(doc->path), "%s", path);
    const char *slash = strrchr(path, '/');
    size_t directory_length = (size_t)(slash - path) + 1U;
    memcpy(doc->directory, path, directory_length);
    doc->directory[directory_length] = '\0';
    FILE *file = luat_fs_fopen(path, "rb");
    if (!file) { luat_plcui_error(error, "E_RESOURCE", "Cannot open XML file: %s", path); return false; }
    parser_t p;
    memset(&p, 0, sizeof(p));
    p.doc = doc; p.error = error;
    p.parser = XML_ParserCreate("UTF-8");
    if (!p.parser) { luat_fs_fclose(file); luat_plcui_error(error, "E_MEMORY", "Cannot allocate XML parser"); return false; }
    XML_SetUserData(p.parser, &p);
    XML_SetElementHandler(p.parser, start_element, end_element);
    XML_SetCharacterDataHandler(p.parser, character_data);
    XML_SetStartDoctypeDeclHandler(p.parser, doctype);
    XML_SetProcessingInstructionHandler(p.parser, processing_instruction);
    XML_SetExternalEntityRefHandler(p.parser, external_entity);
    XML_SetParamEntityParsing(p.parser, XML_PARAM_ENTITY_PARSING_NEVER);
    char buffer[4096];
    size_t total = 0;
    while (!p.failed) {
        size_t count = luat_fs_fread(buffer, 1, sizeof(buffer), file);
        total += count;
        if (total > PLCUI_MAX_XML_BYTES) { fail(&p, "E_SCHEMA", "XML file size limit exceeded"); break; }
        if (luat_fs_ferror(file)) { fail(&p, "E_RESOURCE", "Failed reading XML file"); break; }
        bool final = count < sizeof(buffer);
        if (XML_Parse(p.parser, buffer, (int)count, final ? XML_TRUE : XML_FALSE) == XML_STATUS_ERROR) {
            if (!p.failed) fail(&p, "E_XML_SYNTAX", XML_ErrorString(XML_GetErrorCode(p.parser)));
            break;
        }
        if (final) break;
    }
    if (!p.failed && (!p.root_seen || !p.resources_seen || !p.pages_seen)) fail(&p, "E_SCHEMA", "ui must contain resources and pages sections");
    XML_ParserFree(p.parser);
    luat_fs_fclose(file);
    if (p.failed) return false;
    bool valid = luat_plcui_validate(doc, error);
    if (!valid && !error->file[0]) snprintf(error->file, sizeof(error->file), "%s", path);
    return valid;
}

void luat_plcui_free_description(plcui_document_t *doc)
{
    for (unsigned i = 0; i < doc->page_count; i++) {
        plcui_page_t *page = &doc->pages[i];
        for (unsigned j = 0; j < page->count; ++j) {
            plcui_widget_t *widget = &page->widgets[j];
            if (widget->table) {
                if (widget->table->cells) {
                    unsigned count = (unsigned)widget->table->rows * widget->table->columns;
                    for (unsigned k = 0; k < count; ++k) free(widget->table->cells[k]);
                }
                free(widget->table->cells);
                free(widget->table);
            }
            if (widget->chart) {
                for (unsigned k = 0; k < widget->chart->count; ++k) free(widget->chart->series[k].values);
                free(widget->chart);
            }
        }
        free(page->widgets);
    }
    free(doc->pages);
    for (unsigned i = 0; i < doc->resource_count; i++) if (doc->resources[i].type == PLCUI_RES_IMAGE) lv_image_cache_drop(doc->resources[i].path);
    free(doc->resources);
    luat_plcui_free_fonts(doc);
    doc->pages = NULL; doc->resources = NULL;
    doc->page_count = doc->resource_count = doc->widget_count = 0;
}
