#include "ttf_rasterizer.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TTF_TAG(a, b, c, d) ((uint32_t)(uint8_t)(a) << 24 | (uint32_t)(uint8_t)(b) << 16 | (uint32_t)(uint8_t)(c) << 8 | (uint32_t)(uint8_t)(d))

#define GLYF_FLAG_ON_CURVE 0x01
#define GLYF_FLAG_X_SHORT 0x02
#define GLYF_FLAG_Y_SHORT 0x04
#define GLYF_FLAG_REPEAT 0x08
#define GLYF_FLAG_X_SAME 0x10
#define GLYF_FLAG_Y_SAME 0x20

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef struct {
    const uint8_t *data;
    uint32_t length;
} TTF_Table;

struct TTF_Font {
    uint8_t *buffer;
    size_t size;
    TTF_Table cmap;
    TTF_Table head;
    TTF_Table hhea;
    TTF_Table hmtx;
    TTF_Table loca;
    TTF_Table glyf;
    TTF_Table maxp;
    uint16_t units_per_em;
    int16_t index_to_loc_format;
    uint16_t num_glyphs;
    uint16_t num_hmetrics;
};

typedef struct {
    float x;
    float y;
    uint8_t on_curve;
} GlyphPoint;

typedef struct {
    GlyphPoint *points;
    uint16_t *end_points;
    int contour_count;
    int point_count;
    int16_t x_min;
    int16_t y_min;
    int16_t x_max;
    int16_t y_max;
} GlyphOutline;

typedef struct {
    float x0;
    float y0;
    float x1;
    float y1;
} LineSegment;

typedef struct {
    LineSegment *items;
    size_t count;
    size_t capacity;
} SegmentList;

// Helpers for SFNT reads ---------------------------------------------------

static uint16_t read_u16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}

static int16_t read_s16(const uint8_t *p) {
    return (int16_t)read_u16(p);
}

static uint32_t read_u32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static int ensure_capacity(void **data, size_t element_size, size_t *capacity, size_t needed) {
    if (needed <= *capacity) {
        return 1;
    }
    size_t new_capacity = (*capacity == 0) ? 16 : *capacity;
    while (new_capacity < needed) {
        new_capacity *= 2;
    }
    void *new_data = realloc(*data, new_capacity * element_size);
    if (!new_data) {
        return 0;
    }
    *data = new_data;
    *capacity = new_capacity;
    return 1;
}

static int segment_list_add(SegmentList *list, float x0, float y0, float x1, float y1) {
    const float dx = x1 - x0;
    const float dy = y1 - y0;
    if (fabsf(dx) < 1e-6f && fabsf(dy) < 1e-6f) {
        return 1;
    }
    if (!ensure_capacity((void **)&list->items, sizeof(LineSegment), &list->capacity, list->count + 1)) {
        return 0;
    }
    LineSegment *seg = &list->items[list->count++];
    seg->x0 = x0;
    seg->y0 = y0;
    seg->x1 = x1;
    seg->y1 = y1;
    return 1;
}

static void segment_list_free(SegmentList *list) {
    free(list->items);
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
}

static int point_in_polygon(const SegmentList *segments, float x, float y) {
    int crossings = 0;
    for (size_t i = 0; i < segments->count; ++i) {
        const LineSegment *seg = &segments->items[i];
        const float y0 = seg->y0;
        const float y1 = seg->y1;
        if ((y0 > y) == (y1 > y)) {
            continue;
        }
        const float x0 = seg->x0;
        const float x1 = seg->x1;
        const float t = (y - y0) / (y1 - y0);
        const float xi = x0 + t * (x1 - x0);
        if (xi > x) {
            crossings ^= 1;
        }
    }
    return crossings;
}

static GlyphPoint midpoint(const GlyphPoint *a, const GlyphPoint *b) {
    GlyphPoint p;
    p.x = (a->x + b->x) * 0.5f;
    p.y = (a->y + b->y) * 0.5f;
    p.on_curve = 1;
    return p;
}

// Recursively split a quadratic curve until it is within the flatness threshold
// and emit the result as a straight segment.
static int flatten_quadratic(const GlyphPoint *p0,
                             const GlyphPoint *p1,
                             const GlyphPoint *p2,
                             float tolerance,
                             SegmentList *segments) {
    const float mid_x = (p0->x + p2->x) * 0.5f;
    const float mid_y = (p0->y + p2->y) * 0.5f;
    const float dx = p1->x - mid_x;
    const float dy = p1->y - mid_y;
    const float error = dx * dx + dy * dy;
    if (error <= tolerance * tolerance) {
        return segment_list_add(segments, p0->x, p0->y, p2->x, p2->y);
    }
    GlyphPoint q0 = { (p0->x + p1->x) * 0.5f, (p0->y + p1->y) * 0.5f, 1 };
    GlyphPoint q1 = { (p1->x + p2->x) * 0.5f, (p1->y + p2->y) * 0.5f, 1 };
    GlyphPoint r = { (q0.x + q1.x) * 0.5f, (q0.y + q1.y) * 0.5f, 1 };
    if (!flatten_quadratic(p0, &q0, &r, tolerance, segments)) {
        return 0;
    }
    if (!flatten_quadratic(&r, &q1, p2, tolerance, segments)) {
        return 0;
    }
    return 1;
}

// Convert one contour (potentially containing control points) into line segments.
static int emit_contour_segments(const GlyphOutline *outline,
                                 int start,
                                 int end,
                                 float tolerance,
                                 SegmentList *segments) {
    int index = start;
    GlyphPoint prev = outline->points[end];
    if (!prev.on_curve && !outline->points[start].on_curve) {
        prev = midpoint(&prev, &outline->points[start]);
    }
    GlyphPoint curr = outline->points[index];
    do {
        int next_index = (index == end) ? start : index + 1;
        GlyphPoint next = outline->points[next_index];
        if (curr.on_curve && next.on_curve) {
            if (!segment_list_add(segments, curr.x, curr.y, next.x, next.y)) {
                return 0;
            }
        } else if (curr.on_curve && !next.on_curve) {
            int after_index = (next_index == end) ? start : next_index + 1;
            GlyphPoint after = outline->points[after_index];
            if (!after.on_curve) {
                GlyphPoint implied = midpoint(&next, &after);
                if (!flatten_quadratic(&curr, &next, &implied, tolerance, segments)) {
                    return 0;
                }
            } else {
                if (!flatten_quadratic(&curr, &next, &after, tolerance, segments)) {
                    return 0;
                }
            }
        } else if (!curr.on_curve && next.on_curve) {
            if (!prev.on_curve) {
                GlyphPoint implied_prev = midpoint(&prev, &curr);
                if (!flatten_quadratic(&implied_prev, &curr, &next, tolerance, segments)) {
                    return 0;
                }
            } else {
                if (!flatten_quadratic(&prev, &curr, &next, tolerance, segments)) {
                    return 0;
                }
            }
        } else {
            GlyphPoint implied_next = midpoint(&curr, &next);
            if (!prev.on_curve) {
                GlyphPoint implied_prev = midpoint(&prev, &curr);
                if (!flatten_quadratic(&implied_prev, &curr, &implied_next, tolerance, segments)) {
                    return 0;
                }
            } else {
                if (!flatten_quadratic(&prev, &curr, &implied_next, tolerance, segments)) {
                    return 0;
                }
            }
        }
        prev = curr;
        curr = next;
        index = next_index;
    } while (index != start);
    return 1;
}

static void free_outline(GlyphOutline *outline) {
    free(outline->points);
    free(outline->end_points);
    memset(outline, 0, sizeof(*outline));
}

// Look up a table in the SFNT directory and return its pointer/length.
static int find_table(const uint8_t *font,
                      size_t size,
                      uint32_t tag,
                      TTF_Table *out_table) {
    if (size < 12) {
        return 0;
    }
    uint16_t num_tables = read_u16(font + 4);
    const uint8_t *record = font + 12;
    if (size < 12 + (size_t)num_tables * 16) {
        return 0;
    }
    for (uint16_t i = 0; i < num_tables; ++i) {
        uint32_t record_tag = read_u32(record);
        uint32_t offset = read_u32(record + 8);
        uint32_t length = read_u32(record + 12);
        if (record_tag == tag) {
            if ((size_t)offset + length > size) {
                return 0;
            }
            out_table->data = font + offset;
            out_table->length = length;
            return 1;
        }
        record += 16;
    }
    return 0;
}

// Read the entire font file into memory and locate the tables we need.
static TTF_Result load_font(const char *path, struct TTF_Font *font) {
    memset(font, 0, sizeof(*font));
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return TTF_ERR_FILE_IO;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return TTF_ERR_FILE_IO;
    }
    long file_size = ftell(fp);
    if (file_size < 0) {
        fclose(fp);
        return TTF_ERR_FILE_IO;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return TTF_ERR_FILE_IO;
    }
    font->buffer = (uint8_t *)malloc((size_t)file_size);
    if (!font->buffer) {
        fclose(fp);
        return TTF_ERR_MEMORY;
    }
    if (fread(font->buffer, 1, (size_t)file_size, fp) != (size_t)file_size) {
        free(font->buffer);
        fclose(fp);
        return TTF_ERR_FILE_IO;
    }
    fclose(fp);
    font->size = (size_t)file_size;
    if (!find_table(font->buffer, font->size, TTF_TAG('c', 'm', 'a', 'p'), &font->cmap) ||
        !find_table(font->buffer, font->size, TTF_TAG('h', 'e', 'a', 'd'), &font->head) ||
        !find_table(font->buffer, font->size, TTF_TAG('h', 'h', 'e', 'a'), &font->hhea) ||
        !find_table(font->buffer, font->size, TTF_TAG('h', 'm', 't', 'x'), &font->hmtx) ||
        !find_table(font->buffer, font->size, TTF_TAG('l', 'o', 'c', 'a'), &font->loca) ||
        !find_table(font->buffer, font->size, TTF_TAG('g', 'l', 'y', 'f'), &font->glyf) ||
        !find_table(font->buffer, font->size, TTF_TAG('m', 'a', 'x', 'p'), &font->maxp)) {
        free(font->buffer);
        memset(font, 0, sizeof(*font));
        return TTF_ERR_FORMAT;
    }
    if (font->head.length < 54 || font->maxp.length < 6 || font->hhea.length < 36) {
        free(font->buffer);
        memset(font, 0, sizeof(*font));
        return TTF_ERR_FORMAT;
    }
    font->units_per_em = read_u16(font->head.data + 18);
    font->index_to_loc_format = read_s16(font->head.data + 50);
    font->num_glyphs = read_u16(font->maxp.data + 4);
    font->num_hmetrics = read_u16(font->hhea.data + 34);
    return TTF_OK;
}

static void unload_font(struct TTF_Font *font) {
    free(font->buffer);
    memset(font, 0, sizeof(*font));
}

// Resolve glyph byte range using the loca table (short or long format).
static int glyph_offset(const struct TTF_Font *font, uint16_t glyph_index, uint32_t *offset, uint32_t *length) {
    if (glyph_index >= font->num_glyphs) {
        return 0;
    }
    if (font->index_to_loc_format == 0) {
        if ((glyph_index + 1) * 2 > font->loca.length) {
            return 0;
        }
        uint16_t off0 = read_u16(font->loca.data + glyph_index * 2);
        uint16_t off1 = read_u16(font->loca.data + (glyph_index + 1) * 2);
        *offset = (uint32_t)off0 * 2;
        *length = (uint32_t)(off1 - off0) * 2;
    } else {
        if ((glyph_index + 1) * 4 > font->loca.length) {
            return 0;
        }
        uint32_t off0 = read_u32(font->loca.data + glyph_index * 4);
        uint32_t off1 = read_u32(font->loca.data + (glyph_index + 1) * 4);
        *offset = off0;
        *length = off1 - off0;
    }
    if (*offset + *length > font->glyf.length) {
        return 0;
    }
    return 1;
}

// Decode a simple glyph outline into point arrays (composite glyphs are rejected).
static TTF_Result parse_simple_glyph(const uint8_t *glyph_data,
                                     uint32_t length,
                                     GlyphOutline *outline) {
    if (length < 10) {
        return TTF_ERR_FORMAT;
    }
    int16_t num_contours = read_s16(glyph_data);
    if (num_contours <= 0) {
        return TTF_ERR_UNSUPPORTED;
    }
    outline->contour_count = num_contours;
    outline->x_min = read_s16(glyph_data + 2);
    outline->y_min = read_s16(glyph_data + 4);
    outline->x_max = read_s16(glyph_data + 6);
    outline->y_max = read_s16(glyph_data + 8);
    const uint8_t *p = glyph_data + 10;
    const size_t end_pts_size = (size_t)num_contours * 2;
    if (end_pts_size > length - 10) {
        return TTF_ERR_FORMAT;
    }
    outline->end_points = (uint16_t *)malloc(end_pts_size);
    if (!outline->end_points) {
        return TTF_ERR_MEMORY;
    }
    for (int i = 0; i < num_contours; ++i) {
        outline->end_points[i] = read_u16(p + i * 2);
    }
    p += end_pts_size;
    if ((size_t)(p - glyph_data) + 2 > length) {
        free(outline->end_points);
        memset(outline, 0, sizeof(*outline));
        return TTF_ERR_FORMAT;
    }
    uint16_t instruction_length = read_u16(p);
    p += 2;
    if ((size_t)(p - glyph_data) + instruction_length > length) {
        free(outline->end_points);
        memset(outline, 0, sizeof(*outline));
        return TTF_ERR_FORMAT;
    }
    p += instruction_length;
    outline->point_count = outline->end_points[num_contours - 1] + 1;
    if (outline->point_count <= 0) {
        free(outline->end_points);
        memset(outline, 0, sizeof(*outline));
        return TTF_ERR_FORMAT;
    }
    uint8_t *flags = (uint8_t *)malloc((size_t)outline->point_count);
    if (!flags) {
        free(outline->end_points);
        memset(outline, 0, sizeof(*outline));
        return TTF_ERR_MEMORY;
    }
    int flag_index = 0;
    while (flag_index < outline->point_count) {
        if ((size_t)(p - glyph_data) >= length) {
            free(flags);
            free(outline->end_points);
            memset(outline, 0, sizeof(*outline));
            return TTF_ERR_FORMAT;
        }
        uint8_t flag = *p++;
        flags[flag_index++] = flag;
        if (flag & GLYF_FLAG_REPEAT) {
            if ((size_t)(p - glyph_data) >= length) {
                free(flags);
                free(outline->end_points);
                memset(outline, 0, sizeof(*outline));
                return TTF_ERR_FORMAT;
            }
            uint8_t repeat = *p++;
            for (uint8_t r = 0; r < repeat && flag_index < outline->point_count; ++r) {
                flags[flag_index++] = flag;
            }
        }
    }
    outline->points = (GlyphPoint *)calloc((size_t)outline->point_count, sizeof(GlyphPoint));
    if (!outline->points) {
        free(flags);
        free(outline->end_points);
        memset(outline, 0, sizeof(*outline));
        return TTF_ERR_MEMORY;
    }
    int16_t x = 0;
    for (int i = 0; i < outline->point_count; ++i) {
        uint8_t flag = flags[i];
        if (flag & GLYF_FLAG_X_SHORT) {
            if ((size_t)(p - glyph_data) >= length) {
                free(flags);
                free_outline(outline);
                return TTF_ERR_FORMAT;
            }
            uint8_t dx = *p++;
            if (flag & GLYF_FLAG_X_SAME) {
                x += dx;
            } else {
                x -= dx;
            }
        } else {
            if (!(flag & GLYF_FLAG_X_SAME)) {
                if ((size_t)(p - glyph_data) + 2 > length) {
                    free(flags);
                    free_outline(outline);
                    return TTF_ERR_FORMAT;
                }
                x += read_s16(p);
                p += 2;
            }
        }
        outline->points[i].x = (float)x;
    }
    int16_t y = 0;
    for (int i = 0; i < outline->point_count; ++i) {
        uint8_t flag = flags[i];
        if (flag & GLYF_FLAG_Y_SHORT) {
            if ((size_t)(p - glyph_data) >= length) {
                free(flags);
                free_outline(outline);
                return TTF_ERR_FORMAT;
            }
            uint8_t dy = *p++;
            if (flag & GLYF_FLAG_Y_SAME) {
                y += dy;
            } else {
                y -= dy;
            }
        } else {
            if (!(flag & GLYF_FLAG_Y_SAME)) {
                if ((size_t)(p - glyph_data) + 2 > length) {
                    free(flags);
                    free_outline(outline);
                    return TTF_ERR_FORMAT;
                }
                y += read_s16(p);
                p += 2;
            }
        }
        outline->points[i].y = (float)y;
        outline->points[i].on_curve = (flags[i] & GLYF_FLAG_ON_CURVE) ? 1 : 0;
    }
    free(flags);
    return TTF_OK;
}

static TTF_Result load_glyph_outline(const struct TTF_Font *font,
                                     uint16_t glyph_index,
                                     GlyphOutline *outline) {
    memset(outline, 0, sizeof(*outline));
    uint32_t offset = 0;
    uint32_t length = 0;
    if (!glyph_offset(font, glyph_index, &offset, &length)) {
        return TTF_ERR_NOT_FOUND;
    }
    if (length == 0) {
        memset(outline, 0, sizeof(*outline));
        return TTF_OK;
    }
    const uint8_t *glyph_data = font->glyf.data + offset;
    int16_t contour_count = read_s16(glyph_data);
    if (contour_count < 0) {
        return TTF_ERR_UNSUPPORTED;
    }
    return parse_simple_glyph(glyph_data, length, outline);
}

// Fetch advance width and (optionally) left side bearing from hmtx.
static TTF_Result glyph_metrics(const struct TTF_Font *font,
                                uint16_t glyph_index,
                                uint16_t *advance_width,
                                int16_t *left_side_bearing) {
    if (font->hmtx.length < font->num_hmetrics * 4) {
        return TTF_ERR_FORMAT;
    }
    if (glyph_index < font->num_hmetrics) {
        const uint8_t *entry = font->hmtx.data + glyph_index * 4;
        *advance_width = read_u16(entry);
        if (left_side_bearing) {
            *left_side_bearing = read_s16(entry + 2);
        }
    } else {
        const uint8_t *aw_entry = font->hmtx.data + (font->num_hmetrics - 1) * 4;
        *advance_width = read_u16(aw_entry);
        size_t lsb_index = font->num_hmetrics * 4 + (glyph_index - font->num_hmetrics) * 2;
        if (lsb_index + 2 > font->hmtx.length) {
            return TTF_ERR_FORMAT;
        }
        if (left_side_bearing) {
            *left_side_bearing = read_s16(font->hmtx.data + lsb_index);
        }
    }
    return TTF_OK;
}

// Decode Unicode BMP characters via cmap format 4.
static uint16_t cmap_lookup_format4(const uint8_t *table, uint32_t length, uint32_t codepoint) {
    if (length < 16) {
        return 0;
    }
    uint16_t seg_count = read_u16(table + 6) / 2;
    uint32_t header_size = 16;
    uint32_t arrays_size = (uint32_t)seg_count * 2 * 4;
    if (header_size + arrays_size > length) {
        return 0;
    }
    const uint8_t *end_codes = table + 14;
    const uint8_t *start_codes = end_codes + seg_count * 2 + 2;
    const uint8_t *id_delta = start_codes + seg_count * 2;
    const uint8_t *id_range_offset = id_delta + seg_count * 2;
    for (uint16_t i = 0; i < seg_count; ++i) {
        uint16_t end_code = read_u16(end_codes + i * 2);
        if (codepoint > end_code) {
            continue;
        }
        uint16_t start_code = read_u16(start_codes + i * 2);
        if (codepoint < start_code) {
            break;
        }
        int16_t delta = (int16_t)read_u16(id_delta + i * 2);
        uint16_t range_offset = read_u16(id_range_offset + i * 2);
        if (range_offset == 0) {
            uint32_t glyph = (uint32_t)(codepoint + delta) & 0xFFFFu;
            return (uint16_t)glyph;
        }
        const uint8_t *range_ptr = id_range_offset + i * 2;
        uint32_t glyph_offset = (uint32_t)range_offset + (uint32_t)(codepoint - start_code) * 2;
        const uint8_t *ptr = range_ptr + glyph_offset;
        if ((uint32_t)(ptr - table) + 2 > length) {
            return 0;
        }
        uint16_t glyph_index = read_u16(ptr);
        if (glyph_index) {
            uint32_t glyph = (uint32_t)((int32_t)glyph_index + delta) & 0xFFFFu;
            return (uint16_t)glyph;
        }
        return 0;
    }
    return 0;
}

// Decode Unicode characters via cmap format 12 (32-bit space).
static uint16_t cmap_lookup_format12(const uint8_t *table, uint32_t length, uint32_t codepoint) {
    if (length < 16) {
        return 0;
    }
    uint32_t n_groups = read_u32(table + 12);
    if (16 + n_groups * 12 > length) {
        return 0;
    }
    const uint8_t *groups = table + 16;
    uint32_t lo = 0;
    uint32_t hi = n_groups;
    while (lo < hi) {
        uint32_t mid = (lo + hi) / 2;
        const uint8_t *group = groups + mid * 12;
        uint32_t start = read_u32(group);
        uint32_t end = read_u32(group + 4);
        if (codepoint < start) {
            hi = mid;
        } else if (codepoint > end) {
            lo = mid + 1;
        } else {
            uint32_t glyph = read_u32(group + 8);
            uint32_t result = glyph + (codepoint - start);
            return (uint16_t)(result & 0xFFFFu);
        }
    }
    return 0;
}

// Locate the glyph ID for a given codepoint by trying preferred cmap subtables first.
static uint16_t cmap_lookup(const struct TTF_Font *font, uint32_t codepoint) {
    const uint8_t *cmap = font->cmap.data;
    uint32_t length = font->cmap.length;
    if (length < 4) {
        return 0;
    }
    uint16_t num_tables = read_u16(cmap + 2);
    const uint8_t *record = cmap + 4;
    uint32_t best_offset = 0;
    uint16_t best_format = 0;
    for (uint16_t i = 0; i < num_tables; ++i) {
        if ((uint32_t)(record - cmap) + 8 > length) {
            break;
        }
        uint16_t platform = read_u16(record);
        uint16_t encoding = read_u16(record + 2);
        uint32_t offset = read_u32(record + 4);
        if (offset >= length) {
            record += 8;
            continue;
        }
        const uint8_t *subtable = cmap + offset;
        uint16_t format = read_u16(subtable);
        if ((platform == 3 && (encoding == 1 || encoding == 10)) || platform == 0) {
            if (format == 12 || format == 4) {
                best_format = format;
                best_offset = offset;
                if (format == 12) {
                    break;
                }
            }
        }
        record += 8;
    }
    if (!best_format) {
        record = cmap + 4;
        for (uint16_t i = 0; i < num_tables; ++i) {
            if ((uint32_t)(record - cmap) + 8 > length) {
                break;
            }
            uint32_t offset = read_u32(record + 4);
            if (offset >= length) {
                record += 8;
                continue;
            }
            const uint8_t *subtable = cmap + offset;
            uint16_t format = read_u16(subtable);
            if (format == 12 || format == 4) {
                best_format = format;
                best_offset = offset;
                if (format == 12) {
                    break;
                }
            }
            record += 8;
        }
    }
    if (!best_format) {
        return 0;
    }
    const uint8_t *subtable = cmap + best_offset;
    if (best_format == 4) {
        uint16_t length4 = read_u16(subtable + 2);
        if (best_offset + length4 > length) {
            return 0;
        }
        return cmap_lookup_format4(subtable, length4, codepoint);
    }
    if (best_format == 12) {
        uint32_t length12 = read_u32(subtable + 4);
        if (best_offset + length12 > length) {
            return 0;
        }
        return cmap_lookup_format12(subtable, length12, codepoint);
    }
    return 0;
}

// Expand every contour of the outline to straight segments.
static TTF_Result outline_to_segments(const GlyphOutline *outline,
                                      float tolerance,
                                      SegmentList *segments) {
    int start = 0;
    for (int c = 0; c < outline->contour_count; ++c) {
        int end = outline->end_points[c];
        if (!emit_contour_segments(outline, start, end, tolerance, segments)) {
            return TTF_ERR_MEMORY;
        }
        start = end + 1;
    }
    return TTF_OK;
}

// Sample the vector outline against a regular grid and write a monochrome bitmap.
static TTF_Result rasterize_outline(const GlyphOutline *outline,
                                    const SegmentList *segments,
                                    const struct TTF_Font *font,
                                    float pixel_size,
                                    uint16_t advance_width,
                                    TTF_Bitmap *bitmap) {
    if (font->units_per_em == 0) {
        return TTF_ERR_FORMAT;
    }
    const float scale = pixel_size / (float)font->units_per_em;
    float min_x = floorf((float)outline->x_min);
    float max_x = ceilf((float)outline->x_max);
    float min_y = floorf((float)outline->y_min);
    float max_y = ceilf((float)outline->y_max);
    int width = (int)ceilf((max_x - min_x) * scale);
    int height = (int)ceilf((max_y - min_y) * scale);
    if (width <= 0 || height <= 0) {
        width = height = 1;
        min_x = max_x = min_y = max_y = 0.0f;
    }
    bitmap->width = width;
    bitmap->height = height;
    bitmap->left = (int)floorf(min_x * scale);
    bitmap->top = (int)ceilf(max_y * scale);
    bitmap->advance = advance_width * scale;
    bitmap->pixels = (uint8_t *)calloc((size_t)width * (size_t)height, sizeof(uint8_t));
    if (!bitmap->pixels) {
        return TTF_ERR_MEMORY;
    }
    for (int y = 0; y < height; ++y) {
        float sample_y = max_y - ((float)y + 0.5f) / scale;
        for (int x = 0; x < width; ++x) {
            float sample_x = min_x + ((float)x + 0.5f) / scale;
            if (point_in_polygon(segments, sample_x, sample_y)) {
                bitmap->pixels[y * width + x] = 255;
            }
        }
    }
    return TTF_OK;
}

// Public entry point: load a glyph, triangulate its curves, and rasterize it.
TTF_Result ttf_load_glyph_bitmap(const char *path,
                                 uint32_t codepoint,
                                 float pixel_size,
                                 TTF_Bitmap *out_bitmap) {
    if (!path || !out_bitmap || pixel_size <= 0.0f) {
        return TTF_ERR_FORMAT;
    }
    memset(out_bitmap, 0, sizeof(*out_bitmap));
    struct TTF_Font font;
    TTF_Result res = load_font(path, &font);
    if (res != TTF_OK) {
        return res;
    }
    uint16_t glyph_index = cmap_lookup(&font, codepoint);
    if (!glyph_index) {
        unload_font(&font);
        return TTF_ERR_NOT_FOUND;
    }
    if (glyph_index >= font.num_glyphs) {
        unload_font(&font);
        return TTF_ERR_FORMAT;
    }
    uint16_t advance_width = 0;
    res = glyph_metrics(&font, glyph_index, &advance_width, NULL);
    if (res != TTF_OK) {
        unload_font(&font);
        return res;
    }
    GlyphOutline outline;
    res = load_glyph_outline(&font, glyph_index, &outline);
    if (res != TTF_OK) {
        unload_font(&font);
        return res;
    }
    SegmentList segments = {0};
    const float tolerance = 0.25f;
    res = outline_to_segments(&outline, tolerance, &segments);
    if (res == TTF_OK) {
        res = rasterize_outline(&outline, &segments, &font, pixel_size, advance_width, out_bitmap);
    }
    segment_list_free(&segments);
    free_outline(&outline);
    unload_font(&font);
    if (res != TTF_OK) {
        ttf_free_bitmap(out_bitmap);
    }
    return res;
}

void ttf_free_bitmap(TTF_Bitmap *bitmap) {
    if (!bitmap) {
        return;
    }
    free(bitmap->pixels);
    memset(bitmap, 0, sizeof(*bitmap));
}

void ttf_print_bitmap_ascii(const TTF_Bitmap *bitmap,
                            char on_char,
                            char off_char) {
    if (!bitmap || !bitmap->pixels) {
        return;
    }
    for (int y = 0; y < bitmap->height; ++y) {
        for (int x = 0; x < bitmap->width; ++x) {
            uint8_t v = bitmap->pixels[y * bitmap->width + x];
            putchar(v ? on_char : off_char);
        }
        putchar('\n');
    }
}

// New API implementations for cached font loading
TTF_Result ttf_load_font_from_memory(const uint8_t *data, 
                                    size_t size, 
                                    struct TTF_Font **out_font) {
    if (!data || !out_font || size < 12) {
        return TTF_ERR_FORMAT;
    }
    
    struct TTF_Font *font = (struct TTF_Font *)malloc(sizeof(struct TTF_Font));
    if (!font) {
        return TTF_ERR_MEMORY;
    }
    
    memset(font, 0, sizeof(*font));
    
    // Use provided data directly (don't copy)
    font->buffer = (uint8_t *)data;
    font->size = size;
    
    // Find required tables
    if (!find_table(font->buffer, font->size, TTF_TAG('c', 'm', 'a', 'p'), &font->cmap) ||
        !find_table(font->buffer, font->size, TTF_TAG('h', 'e', 'a', 'd'), &font->head) ||
        !find_table(font->buffer, font->size, TTF_TAG('h', 'h', 'e', 'a'), &font->hhea) ||
        !find_table(font->buffer, font->size, TTF_TAG('h', 'm', 't', 'x'), &font->hmtx) ||
        !find_table(font->buffer, font->size, TTF_TAG('l', 'o', 'c', 'a'), &font->loca) ||
        !find_table(font->buffer, font->size, TTF_TAG('g', 'l', 'y', 'f'), &font->glyf) ||
        !find_table(font->buffer, font->size, TTF_TAG('m', 'a', 'x', 'p'), &font->maxp)) {
        memset(font, 0, sizeof(*font));
        free(font);
        return TTF_ERR_FORMAT;
    }
    
    if (font->head.length < 54 || font->maxp.length < 6 || font->hhea.length < 36) {
        memset(font, 0, sizeof(*font));
        free(font);
        return TTF_ERR_FORMAT;
    }
    
    font->units_per_em = read_u16(font->head.data + 18);
    font->index_to_loc_format = read_s16(font->head.data + 50);
    font->num_glyphs = read_u16(font->maxp.data + 4);
    font->num_hmetrics = read_u16(font->hhea.data + 34);
    
    *out_font = font;
    return TTF_OK;
}

void ttf_unload_font(struct TTF_Font *font) {
    if (font) {
        // Note: Don't free buffer as it's managed externally
        memset(font, 0, sizeof(*font));
        free(font);
    }
}

TTF_Result ttf_load_glyph_bitmap_cached(struct TTF_Font *font,
                                       uint32_t codepoint,
                                       float pixel_size,
                                       TTF_Bitmap *out_bitmap) {
    if (!font || !out_bitmap || pixel_size <= 0.0f) {
        return TTF_ERR_FORMAT;
    }
    
    memset(out_bitmap, 0, sizeof(*out_bitmap));
    
    // Use cached font data directly
    uint16_t glyph_index = cmap_lookup(font, codepoint);
    if (!glyph_index) {
        return TTF_ERR_NOT_FOUND;
    }
    if (glyph_index >= font->num_glyphs) {
        return TTF_ERR_FORMAT;
    }
    
    uint16_t advance_width = 0;
    TTF_Result res = glyph_metrics(font, glyph_index, &advance_width, NULL);
    if (res != TTF_OK) {
        return res;
    }
    
    GlyphOutline outline;
    res = load_glyph_outline(font, glyph_index, &outline);
    if (res != TTF_OK) {
        return res;
    }
    
    SegmentList segments = {0};
    const float tolerance = 0.25f;
    res = outline_to_segments(&outline, tolerance, &segments);
    if (res == TTF_OK) {
        res = rasterize_outline(&outline, &segments, font, pixel_size, advance_width, out_bitmap);
    }
    
    segment_list_free(&segments);
    free_outline(&outline);
    
    if (res != TTF_OK) {
        ttf_free_bitmap(out_bitmap);
    }
    
    return res;
}
