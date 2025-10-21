#ifndef TTF_RASTERIZER_H
#define TTF_RASTERIZER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration - full definition is in ttf_rasterizer.c
struct TTF_Font;

typedef enum TTF_Result {
    TTF_OK = 0,
    TTF_ERR_FILE_IO,
    TTF_ERR_FORMAT,
    TTF_ERR_MEMORY,
    TTF_ERR_NOT_FOUND,
    TTF_ERR_UNSUPPORTED
} TTF_Result;

typedef struct TTF_Bitmap {
    int width;
    int height;
    int left;
    int top;
    float advance;
    uint8_t *pixels;
} TTF_Bitmap;

// Original API - load from file path
TTF_Result ttf_load_glyph_bitmap(const char *path,
                                 uint32_t codepoint,
                                 float pixel_size,
                                 TTF_Bitmap *out_bitmap);

// New API - load from cached font data
TTF_Result ttf_load_glyph_bitmap_cached(struct TTF_Font *font,
                                       uint32_t codepoint,
                                       float pixel_size,
                                       TTF_Bitmap *out_bitmap);

// Font management API
TTF_Result ttf_load_font_from_memory(const uint8_t *data, 
                                    size_t size, 
                                    struct TTF_Font **out_font);
void ttf_unload_font(struct TTF_Font *font);

// Bitmap management
void ttf_free_bitmap(TTF_Bitmap *bitmap);

void ttf_print_bitmap_ascii(const TTF_Bitmap *bitmap,
                            char on_char,
                            char off_char);

#ifdef __cplusplus
}
#endif

#endif
