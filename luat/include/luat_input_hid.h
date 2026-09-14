/** @file luat_input_hid.h HID Report-protocol adapter, independent of USB/RTOS. */
#ifndef LUAT_INPUT_HID_H
#define LUAT_INPUT_HID_H
#include "luat_input.h"
#ifdef __cplusplus
extern "C" {
#endif

typedef struct luat_input_hid luat_input_hid_t;
#define LUAT_INPUT_HID_ROLLOVER (-20)
#define LUAT_INPUT_HID_REPORT_BYTES 512U

/** Allocate this many bytes (normal pointer alignment) once per HID interface. */
size_t luat_input_hid_size(void);
/** Largest complete Input report, including Report ID. Query after init. */
size_t luat_input_hid_report_size(const luat_input_hid_t *hid);
/** Compile a bounded report layout, register a device, then bind the consumer.
 * Caller owns storage, core and consumer; all calls use core serialization.
 * On failure no registered device remains. Descriptor can be freed after init.
 * Supports keyboard arrays/bitmaps, mouse, consumer keys and single-contact ABS.
 * Multi-contact digitizers and unsupported layouts return ENOTSUP, never guess.
 */
int luat_input_hid_init(luat_input_hid_t *hid, luat_input_core_t *core,
    const uint8_t *descriptor, size_t length, uint16_t vendor, uint16_t product,
    luat_input_receive_t receive, void *userdata);
/** Decode a complete report into one input frame. No allocation. Unknown Report
 * IDs return ENOTSUP; malformed/short reports leave all previous state intact.
 * ROLLOVER leaves previous keyboard state intact until the next valid report.
 */
int luat_input_hid_feed(luat_input_hid_t *hid, const uint8_t *report,
    size_t length, uint32_t timestamp_ms);
/** Cancel device state and clear per-report caches after transport loss. */
int luat_input_hid_reset(luat_input_hid_t *hid, uint32_t timestamp_ms);
/** Unregister before releasing adapter storage. */
int luat_input_hid_deinit(luat_input_hid_t *hid, uint32_t timestamp_ms);
/** Read-only registered instance and capabilities for configuration/diagnostics. */
luat_input_handle_t luat_input_hid_handle(const luat_input_hid_t *hid);

#ifdef __cplusplus
}
#endif
#endif
