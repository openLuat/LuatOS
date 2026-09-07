/** @file luat_input_touch.h
 * Allocation-free single/multi-touch adapter for the LuatOS input core.
 */
#ifndef LUAT_INPUT_TOUCH_H
#define LUAT_INPUT_TOUCH_H

#include "luat_input.h"

#ifdef __cplusplus
extern "C" {
#endif

enum {
    LUAT_INPUT_TOUCH_DOWN = 1,
    LUAT_INPUT_TOUCH_MOVE = 2,
    LUAT_INPUT_TOUCH_UP = 3
};

typedef struct {
    const char *name;
    int32_t maximum_x;
    int32_t maximum_y;
    int32_t maximum_pressure;    /* Zero omits ABS/MT pressure. */
    int32_t maximum_touch_major; /* Zero omits MT touch-major. */
    uint16_t slots;
    uint16_t bus;
    uint16_t vendor;
    uint16_t product;
    uint16_t version;
} luat_input_touch_config_t;

typedef struct {
    uint16_t slot;
    uint8_t event;
    uint8_t reserved;
    int32_t tracking_id;
    int32_t x;
    int32_t y;
    int32_t pressure;
    int32_t touch_major;
} luat_input_touch_point_t;

typedef struct luat_input_touch luat_input_touch_t;

/** Required caller-owned bytes. SIZE_MAX means an invalid slot count. */
size_t luat_input_touch_size(uint16_t slots);
/** Register a direct touch device. storage must be suitably aligned and persist
 * through deinit. receive may be NULL when consumers will bind later by ID.
 */
int luat_input_touch_init(luat_input_touch_t *touch, size_t bytes,
    luat_input_core_t *core, const luat_input_touch_config_t *config,
    luat_input_receive_t receive, void *userdata);
/** Submit one atomic batch of slot updates. Slots may occur at most once. */
int luat_input_touch_feed(luat_input_touch_t *touch, uint32_t timestamp_ms,
    const luat_input_touch_point_t *points, uint16_t count);
int luat_input_touch_reset(luat_input_touch_t *touch, uint32_t timestamp_ms);
int luat_input_touch_deinit(luat_input_touch_t *touch, uint32_t timestamp_ms);
luat_input_handle_t luat_input_touch_handle(luat_input_touch_t *touch);

#ifdef __cplusplus
}
#endif
#endif
