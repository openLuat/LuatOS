
#ifndef LUAT_FONTS_H
#define LUAT_FONTS_H
#include "luat_base.h"

typedef struct luat_font_data {
    // uint8_t version;
    // uint8_t gray;
    uint8_t w;
    uint8_t len;
    uint8_t *buff;
}luat_font_data_t;

typedef int (*luat_font_loader_get)(const uint32_t chr, luat_font_data_t* data, size_t font_size, void* ptr);

int luat_font_get(int font_id, const uint32_t chr, luat_font_data_t* data);

int luat_font_register(luat_font_loader_get loader, void* ptr);

unsigned short luat_font_unicode_gb2312 ( unsigned short	chr);

int const_gb2312_font_loader(const uint32_t chr, luat_font_data_t* data, size_t font_size, void* ptr);

int file_gb2312_font_loader(const uint32_t chr, luat_font_data_t* data, size_t font_size, void* ptr);

typedef struct luat_fonts
{
    luat_font_loader_get loader;
    size_t font_size;
    void* userdata;
}luat_fonts_t;

#endif
