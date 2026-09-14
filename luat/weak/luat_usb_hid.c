#include "luat_base.h"
#include "luat_usb_hid.h"
#ifdef LUAT_USE_INPUT_HID
#include "luat_input_usb_hid.h"
#endif

static luat_usb_hid_callback_t application_callback;

void luat_usb_hid_set_callback(luat_usb_hid_callback_t callback)
{
    application_callback = callback;
}

LUAT_WEAK void luat_usb_hid_host_callback(luat_usb_hid_host_t *device,
    luat_usb_hid_event_t event, const uint8_t *data, uint32_t length)
{
    if (application_callback) {
        application_callback(device, event, data, length);
        return;
    }
#ifdef LUAT_USE_INPUT_HID
    luat_input_usb_hid_callback(device, event, data, length);
#else
    (void)device;
    (void)event;
    (void)data;
    (void)length;
#endif
}
