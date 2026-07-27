#ifndef LUAT_USB_H
#define LUAT_USB_H

#include "luat_base.h"

#define MAX_USB_BUS_COUNT 2
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
//	LUAT_USB_CLASS_WINUSB,
	LUAT_USB_CLASS_QTY,
	LUAT_USB_EVENT_NEW_RX	= 0,
	LUAT_USB_EVENT_TX_DONE,
	LUAT_USB_EVENT_CONNECT,
	LUAT_USB_EVENT_DISCONNECT,
	LUAT_USB_EVENT_RX_ERROR,
	LUAT_USB_EVENT_TX_ERROR,
	LUAT_USB_EVENT_SUSPEND,
	LUAT_USB_EVENT_RESUME,
	LUAT_USB_EVENT_ERROR_STOP,
};

typedef union
{
	struct
	{
		uint8_t usb_id;
		uint8_t class;
		uint8_t app_id;
		uint8_t event;
	};
	uint32_t u32;
}usb_event_u;

typedef union
{
	struct
	{
		uint8_t hub_address;
		uint8_t hub_port;
		uint8_t device_address;
		uint8_t unuse;
	};
	uint32_t u32;
}usb_info_u;

typedef void (*usb_app_callback_t)(uint8_t usb_id, uint8_t class_type, uint8_t app_id, uint8_t event, uint8_t *data, uint32_t len);

int luat_usb_set_vid(int id, uint16_t vid);
int luat_usb_get_vid(int id, uint16_t *vid);

int luat_usb_set_pid(int id, uint16_t pid);
int luat_usb_get_pid(int id, uint16_t *pid);

int luat_usb_set_dev_id(int id, uint16_t dev_id);
int luat_usb_get_dev_id(int id, uint16_t *dev_id);

int luat_usb_set_mode(int id, uint8_t mode);

int luat_usb_add_class(int id, uint8_t class, uint8_t num);
int luat_usb_get_free_ep_num(int id);
int luat_usb_clear_class(int id);

int luat_usb_set_callback(int id, usb_app_callback_t callback);

int luat_usb_tx(int id, uint8_t app_id, const void *data, uint32_t len);
int luat_usb_hid_tx(int id, const char *string, uint32_t len, uint8_t is_keyboard);
int luat_usb_rx(int id, uint8_t app_id, void *data, uint32_t len);

int luat_usb_power_on_off(int id, uint8_t on_off);

int luat_usb_debug(int id, uint8_t on_off);

int luat_usb_host_reset_device(int id, uint8_t app_id);

/********************** c层内部调用接口 ***********************/
enum
{
	LUAT_USB_ETH_ID_0 = 0,

	LUAT_USB_ETH_EVENT_TX_DONE = 0,
	LUAT_USB_ETH_EVENT_NEW_RX,
	LUAT_USB_ETH_EVENT_LINK_STATE,
	LUAT_USB_ETH_EVENT_DOWNSTREAM_BPS,
	LUAT_USB_ETH_EVENT_UPSTREAM_BPS,
	LUAT_USB_ETH_EVENT_MSS,
	LUAT_USB_ETH_EVENT_MAC,
	LUAT_USB_ETH_EVENT_CONNECT,
	LUAT_USB_ETH_EVENT_DISCONNECT,
};

typedef void(*luat_usb_event_callback_fun_t)(uint32_t event, void *data_or_p_param, uint32_t size_or_u32_param, void *user_param);
void *luat_usb_bind_eth(int id, luat_usb_event_callback_fun_t callback, void *user_param);
int luat_usb_eth_start_tx(int id, const uint32_t *data, uint32_t len);
int luat_usb_eth_continue_tx(int id, const uint32_t *data, uint32_t len);
#endif
