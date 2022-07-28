
#ifndef LUAT_AIRUI_H
#define LUAT_AIRUI_H

#include "luat_base.h"
#include "lvgl.h"

#define JSMN_STATIC
#include "jsmn.h"

typedef struct luat_airui_obj
{
    lv_obj_t *lvobj;
}luat_airui_obj_t;


typedef struct luat_airui_ctx
{
    const char* screen_name;
    int airui_backend_type;
    lv_obj_t *scr;
    lv_obj_t *objs;
    size_t obj_count;
    const char* data;
}luat_airui_ctx_t;

typedef int (*airui_parse_cb)(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos);

typedef struct airui_parser
{
    const char* name;
    airui_parse_cb cb;
}airui_parser_t;


int luat_airui_load_buff(luat_airui_ctx_t** ctx, int backend, const char* screen_name, const char* buff, size_t len);
int luat_airui_load_file(luat_airui_ctx_t** ctx, int backend, const char* screen_name, const char* path);
int luat_airui_get(luat_airui_ctx_t* ctx, const char* key);

int luat_airui_load_components(luat_airui_ctx_t* ctx, void *tok, size_t tok_count);

// jsmn 的帮助函数

typedef struct c_str
{
    size_t len;
    char* ptr;
}c_str_t;

typedef struct air_block_info
{
    int x;
    int y;
    int width;
    int height;
    c_str_t name;
    c_str_t body;
}air_block_info_t;


int jsmn_skip_object(jsmntok_t *tok, size_t *cur);
int jsmn_skip_array(jsmntok_t *tok, size_t *cur);
int jsmn_skip_entry(jsmntok_t *tok, size_t *cur);
int jsmn_find_by_key(const char* data, const char* key, jsmntok_t *tok, size_t pos);
int jsmn_toint(const char* data, jsmntok_t *tok);
void jsmn_get_string(const char* data, jsmntok_t *tok, int pos, c_str_t *str);

typedef struct airui_block
{
    luat_airui_ctx_t* ctx;
    jsmntok_t *tok;
    air_block_info_t* info;
    int schema_pos;
    void* parent;
    void* self;
}airui_block_t;


typedef int (*airui_block_cb)(airui_block_t *bl);

#endif
