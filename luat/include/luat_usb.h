#ifndef LUAT_USB_H
#define LUAT_USB_H

#include "luat_base.h"

#define MAX_USB_DEVICE_COUNT 2
enum
{
	LUAT_USB_MODE_DEVICE,
	LUAT_USB_MODE_HOST,
	LUAT_USB_MODE_OTG,
	LUAT_USB_CLASS_CDC_ACM = 0,
	LUAT_USB_CLASS_AUDIO,
	LUAT_USB_CLASS_CAMERA,
	LUAT_USB_CLASS_HID_CUSTOMER,
	LUAT_USB_CLASS_HID_KEYBOARD,
	LUAT_USB_CLASS_MSC,
	LUAT_USB_CLASS_WINUSB,
	LUAT_USB_CLASS_QTY,
	LUAT_USB_EVENT_NEW_RX	= 0,
	LUAT_USB_EVENT_TX_DONE,
	LUAT_USB_EVENT_CONNECT,
	LUAT_USB_EVENT_DISCONNECT,
	LUAT_USB_EVENT_SUSPEND,
	LUAT_USB_EVENT_RESUME,
};

typedef void (*usb_callback_t)(int id, int event, uint8_t *data, uint32_t len);

int luat_usb_set_vid(int id, uint16_t vid);
int luat_usb_get_vid(int id, uint16_t *vid);

int luat_usb_set_pid(int id, uint16_t pid);
int luat_usb_get_pid(int id, uint16_t *pid);

int luat_usb_set_mode(int id, uint8_t mode);

int luat_usb_add_class(int id, uint8_t class, uint8_t num);
int luat_usb_get_free_ep_num(int id);
int luat_usb_clear_class(int id);

int luat_usb_set_callback(int id, usb_callback_t callback);

int luat_usb_tx(int id, uint8_t class, const void *data, uint32_t len);
int luat_usb_hid_tx(int id, const char *string, uint32_t len, uint8_t is_keyboard);
int luat_usb_rx(int id, uint8_t class, void *data, uint32_t len);

int luat_usb_power_on_off(int id, uint8_t on_off);
#endif
