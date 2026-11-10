/** @file luat_plcui.h Bounded, XML-first PLC user interface runtime. */
#ifndef LUAT_PLCUI_H
#define LUAT_PLCUI_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "lua.h"
#include "lauxlib.h"
#include "lvgl.h"
#include "luat_plcui_conf.h"
#include "luat_plcui_platform.h"

#define PLCUI_ID_MAX 64
#define PLCUI_PATH_MAX 384
#define PLCUI_TEXT_MAX 512
#define PLCUI_MAX_PAGES 16
#define PLCUI_MAX_WIDGETS 512
#define PLCUI_MAX_XML_DEPTH 16
#define PLCUI_MAX_RESOURCES 256
#define PLCUI_EVENT_CAPACITY 64
#define PLCUI_MAX_XML_BYTES (256U * 1024U)
#define PLCUI_MAX_IMAGE_BYTES (16U * 1024U * 1024U)
#define PLCUI_XML_MT "plcui.xml"

typedef enum { PLCUI_IMAGE, PLCUI_LABEL, PLCUI_TEXTAREA, PLCUI_KEYBOARD, PLCUI_CONTAINER, PLCUI_TABLE, PLCUI_CHART } plcui_widget_type_t;
#define PLCUI_TABLE_MAX_ROWS 128U
#define PLCUI_TABLE_MAX_COLS 16U
#define PLCUI_TABLE_MAX_CELLS 1024U
#define PLCUI_CHART_MAX_POINTS 1024U
#define PLCUI_CHART_MAX_SERIES 8U
#define PLCUI_CHART_SCALE 100

typedef struct {
    uint16_t rows, columns;
    uint16_t widths[PLCUI_TABLE_MAX_COLS];
    uint16_t cell_padding;
    uint16_t row_height;
    lv_text_align_t column_aligns[PLCUI_TABLE_MAX_COLS];
    lv_text_align_t header_align;
    uint32_t header_color, alternate_color;
    bool header;
    bool grid;
    char **cells;
} plcui_table_t;

typedef struct {
    char id[PLCUI_ID_MAX];
    uint32_t color;
    int32_t *values;
    uint32_t start;
    bool hidden;
    lv_chart_series_t *native;
} plcui_chart_series_t;

typedef struct {
    uint16_t points, count, hdiv, vdiv, line_width;
    int32_t minimum, maximum;
    uint32_t grid_color;
    bool bar;
    plcui_chart_series_t series[PLCUI_CHART_MAX_SERIES];
} plcui_chart_t;
typedef enum { PLCUI_RES_IMAGE, PLCUI_RES_FONT } plcui_resource_type_t;
typedef enum { PLCUI_CLICK, PLCUI_CHANGE, PLCUI_SUBMIT, PLCUI_CANCEL } plcui_event_type_t;

typedef struct {
    const char *code;
    char message[256];
    char file[PLCUI_PATH_MAX];
    char id[PLCUI_ID_MAX];
    char attribute[PLCUI_ID_MAX];
    unsigned long line;
    unsigned long column;
} plcui_error_t;

typedef struct {
    plcui_resource_type_t type;
    char id[PLCUI_ID_MAX];
    char path[PLCUI_PATH_MAX];
    char builtin[PLCUI_ID_MAX];
    const lv_font_t *font;
    uint32_t decoded_bytes;
    bool image_validated; /* Immutable resource for this XML instance; reload to update. */
} plcui_resource_t;

typedef struct plcui_document plcui_document_t;
typedef struct plcui_hzfont_face plcui_hzfont_face_t;
typedef struct {
    plcui_widget_type_t type;
    char id[PLCUI_ID_MAX];
    int32_t x, y, w, h;
    int32_t parent_index; /* -1 for page children; otherwise a preceding container. */
    int32_t hit_x, hit_y, hit_w, hit_h;
    bool has_hit_rect;
    bool hidden, disabled, clickable, checked, pressed;
    char source[4][PLCUI_ID_MAX]; /* default, pressed, checked, disabled */
    char text[PLCUI_TEXT_MAX];
    char font_id[PLCUI_ID_MAX];
    const lv_font_t *font;
    uint16_t font_size;
    bool use_hzfont;
    char keyboard_id[PLCUI_ID_MAX];
    char accepted_chars[128];
    char handler[4][PLCUI_ID_MAX];
    uint32_t color;
    uint32_t background;
    uint32_t border_color;
    uint16_t border_width, radius, padding;
    uint8_t bg_opa;
    uint16_t max_length;
    lv_text_align_t align;
    bool numeric_keyboard;
    bool one_line;
    plcui_table_t *table;
    plcui_chart_t *chart;
    lv_obj_t *obj;
    plcui_document_t *document;
    unsigned page_index;
    unsigned widget_index;
} plcui_widget_t;

typedef struct {
    char id[PLCUI_ID_MAX];
    uint32_t background;
    plcui_widget_t *widgets;
    unsigned count;
    lv_obj_t *screen;
} plcui_page_t;

typedef struct {
    unsigned generation;
    unsigned page_index;
    unsigned widget_index;
    plcui_event_type_t type;
    char text[PLCUI_TEXT_MAX];
} plcui_event_t;

struct plcui_document {
    lua_State *L;
    int self_ref;
    int handlers_ref;
    bool closed;
    bool switching;
    bool dispatching;
    bool silent;
    bool pending_close;
    int pending_page;
    char path[PLCUI_PATH_MAX];
    char directory[PLCUI_PATH_MAX];
    char entry[PLCUI_ID_MAX];
    int width, height;
    unsigned generation;
    unsigned widget_count;
    plcui_resource_t *resources;
    plcui_hzfont_face_t *hzfont_faces;
    unsigned resource_count;
    plcui_page_t *pages;
    unsigned page_count;
    int current_page;
    plcui_widget_t *editing;
    plcui_widget_t *keyboard;
    char edit_original[PLCUI_TEXT_MAX];
    plcui_event_t events[PLCUI_EVENT_CAPACITY];
    unsigned event_head, event_count;
    unsigned events_dropped;
};

typedef struct {
    plcui_document_t *document;
    int document_ref;
    unsigned generation;
    unsigned page_index;
    unsigned widget_index;
} plcui_object_ref_t;

typedef struct {
    lua_State *L;
    bool initialized;
    bool refreshing;
    bool pending_deinit;
    bool auto_refresh;
    uint32_t auto_refresh_count;
    int width, height;
    lv_obj_t *idle_screen;
    plcui_document_t *document;
} plcui_runtime_t;

plcui_runtime_t *luat_plcui_runtime(void);
void luat_plcui_error(plcui_error_t *error, const char *code, const char *format, ...);
int luat_plcui_push_error(lua_State *L, const plcui_error_t *error);
bool luat_plcui_parse(plcui_document_t *document, const char *path, plcui_error_t *error);
bool luat_plcui_validate(plcui_document_t *document, plcui_error_t *error);
bool luat_plcui_validate_page_images(plcui_document_t *document, int page_index, plcui_error_t *error);
void luat_plcui_free_description(plcui_document_t *document);
plcui_resource_t *luat_plcui_resource(plcui_document_t *document, const char *id, plcui_resource_type_t type);
const lv_font_t *luat_plcui_font(plcui_document_t *document, const char *id);
int luat_plcui_page_index(plcui_document_t *document, const char *id);
void luat_plcui_apply_image(plcui_widget_t *widget);
void luat_plcui_emit(plcui_widget_t *widget, plcui_event_type_t type);
void luat_plcui_input_finish(plcui_document_t *document, bool submit, bool notify);
void luat_plcui_input_begin(plcui_widget_t *widget);
bool luat_plcui_show(plcui_document_t *document, int page_index, plcui_error_t *error);
void luat_plcui_close(plcui_document_t *document);
void luat_plcui_refresh(void);
bool luat_plcui_start_refresh(void);
void luat_plcui_stop_refresh(void);
void luat_plcui_deinit(void);
void luat_plcui_dispatch(plcui_document_t *document);
bool luat_plcui_check_text(plcui_widget_t *widget, const char *text, size_t length, plcui_error_t *error);
bool luat_plcui_create_page(plcui_document_t *document, int page_index, plcui_error_t *error);
void luat_plcui_destroy_page(plcui_document_t *document, int page_index);

#endif
