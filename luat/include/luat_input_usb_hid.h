/** @file luat_input_usb_hid.h Optional raw USB HID -> input application adapter. */
#ifndef LUAT_INPUT_USB_HID_H
#define LUAT_INPUT_USB_HID_H
#include "luat_usb_hid.h"
#ifdef __cplusplus
extern "C" {
#endif
/** Same lifetime/context contract as luat_usb_hid_host_callback. A custom
 * application callback can delegate selected devices here, forwarding their
 * complete lifecycle. The adapter owns device->userdata for those devices.
 * Includes raw report buffering, task dispatch, decoder, log and optional
 * service registration. Consumers own their bindings; the adapter does not
 * depend on AirUI. No platform USB types or functions are required.
 */
void luat_input_usb_hid_callback(luat_usb_hid_host_t *device,
    luat_usb_hid_event_t event, const uint8_t *data, uint32_t length);
#ifdef __cplusplus
}
#endif
#endif
