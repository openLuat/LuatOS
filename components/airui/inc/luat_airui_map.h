/**
 * @file luat_airui_map.h
 * @summary Offline XYZ tile map widget.
 */
#ifndef LUAT_AIRUI_MAP_H
#define LUAT_AIRUI_MAP_H

#include "luat_airui_component.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AIRUI_MAP_TILE_SIZE 256
#define AIRUI_MAP_ZOOM_MIN 0
#define AIRUI_MAP_ZOOM_MAX 22
#define AIRUI_MAP_MAX_LATITUDE 85.0511287798066

typedef enum {
    AIRUI_MAP_CRS_WGS84 = 0,
    AIRUI_MAP_CRS_GCJ02 = 1
} airui_map_crs_t;

/**
 * Project longitude/latitude in degrees to Web Mercator world pixels.
 * Longitude wraps to [-180, 180); latitude clamps to the Mercator limit.
 * World width is 256 * 2^zoom. No CRS conversion is performed here.
 * @return 1 on success; 0 for non-finite input, invalid zoom or NULL output.
 * On failure neither output is modified. The two outputs must be distinct.
 */
int airui_map_geo_to_world(double lon, double lat, int zoom, double *x, double *y);

/**
 * Inverse Web Mercator projection. World x wraps; y clamps to [0, world size].
 * @return 1 on success; 0 on invalid input without modifying outputs.
 */
int airui_map_world_to_geo(double x, double y, int zoom, double *lon, double *lat);

/**
 * Convert WGS84/GCJ02 degrees. Longitude wraps; latitude clamps to [-90, 90].
 * Conversion is skipped outside the conventional GCJ02 applicability rectangle
 * (72.004..137.8347 E, 0.8293..55.8271 N); this is not a political boundary.
 * GCJ02 inverse uses iterative refinement of the forward transform.
 * @return 1 on success; 0 on invalid input or failure to converge. Outputs are
 * unchanged on failure and must be distinct, non-NULL pointers.
 */
int airui_map_convert_crs(double lon, double lat, int from_crs, int to_crs,
                          double *out_lon, double *out_lat);

typedef struct {
    uint32_t generation;
    uint32_t loaded_total;
    uint32_t decode_failures;
    uint32_t bytes_used;
    uint32_t cache_bytes;
    uint16_t capacity;
    uint16_t visible;
    uint16_t visible_ready;
    uint16_t ready;
    uint16_t pending;
    uint16_t missing;
    uint16_t failed;
} airui_map_stats_t;

lv_obj_t *airui_map_create_from_config(void *L, int idx);
int airui_map_set_center(lv_obj_t *obj, double lon, double lat);
int airui_map_get_center(lv_obj_t *obj, double *lon, double *lat);
int airui_map_set_zoom(lv_obj_t *obj, int zoom);
int airui_map_get_zoom(lv_obj_t *obj);
int airui_map_set_position(lv_obj_t *obj, double lon, double lat, double heading, bool valid);
int airui_map_set_follow(lv_obj_t *obj, bool follow);
bool airui_map_get_follow(lv_obj_t *obj);
int airui_map_set_draggable(lv_obj_t *obj, bool draggable);
int airui_map_set_size(lv_obj_t *obj, int w, int h);
int airui_map_pan(lv_obj_t *obj, double dx, double dy);
int airui_map_geo_to_screen(lv_obj_t *obj, double lon, double lat, double *x, double *y);
int airui_map_screen_to_geo(lv_obj_t *obj, double x, double y, double *lon, double *lat);
int airui_map_refresh(lv_obj_t *obj);
int airui_map_get_stats(lv_obj_t *obj, airui_map_stats_t *stats);
int airui_map_set_callback(lv_obj_t *obj, void *L, int idx, const char *name);

#ifdef __cplusplus
}
#endif
#endif
