/** @file luat_usb_hid.h Raw USB Host HID callback contract, independent of input. */
#ifndef LUAT_USB_HID_H
#define LUAT_USB_HID_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LUAT_USB_HID_OPEN,
    LUAT_USB_HID_CLOSE,
    LUAT_USB_HID_REPORT,
    LUAT_USB_HID_RX_ERROR
} luat_usb_hid_event_t;

typedef struct {
    const uint8_t *report_descriptor;
    uint16_t report_descriptor_len;
    uint16_t packet_size;
    uint16_t vendor, product;
    uint8_t bus, address, interface_number, subclass, protocol;
    void *userdata; /**< Owned by the callback, initially NULL. */
} luat_usb_hid_host_t;

typedef void (*luat_usb_hid_callback_t)(luat_usb_hid_host_t *device,
    luat_usb_hid_event_t event, const uint8_t *data, uint32_t length);

/** Select application handling before enabling USB Host, or after all devices
 * are closed and callbacks stopped. NULL restores the default input handler.
 * Do not change handlers while a device is open (userdata belongs to its owner).
 */
void luat_usb_hid_set_callback(luat_usb_hid_callback_t callback);

/** BSP calls OPEN in task context before starting RX, CLOSE after stopping RX
 * and joining in-flight report callbacks, before freeing descriptor/device.
 * CLOSE may occur without OPEN on partial activation failure; it is idempotent.
 * OPEN/CLOSE must be serialized by the transport. REPORT/RX_ERROR may run in
 * an ISR concurrently with task processing: do not block, allocate or decode.
 * Device storage lives through CLOSE; descriptor is borrowed through CLOSE;
 * report data is borrowed only until REPORT returns (one interrupt packet).
 *
 * Applications may register a callback to consume raw HID themselves.
 * The default delegates to luat_input_usb_hid_callback when INPUT_HID is built,
 * otherwise it is a no-op. BSP must never depend on callback-owned userdata.
 */
void luat_usb_hid_host_callback(luat_usb_hid_host_t *device,
    luat_usb_hid_event_t event, const uint8_t *data, uint32_t length);

#ifdef __cplusplus
}
#endif
#endif
