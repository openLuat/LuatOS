#ifndef LUAT_USBAPP_H
#define LUAT_USBAPP_H

#include "luat_base.h"

extern void *luat_spi_get_sdhc_ctrl(void);

int32_t luat_usb_app_vhid_cb(void *pData, void *pParam);
void luat_usb_app_set_vid_pid(uint8_t usb_id, uint16_t vid, uint16_t pid);
void luat_usb_app_set_hid_mode(uint8_t usb_id, uint8_t hid_mode, uint8_t buff_size);
//打开luatos内置usb device config，实现虚拟MSC，HID和串口的复合设备功能，串口收发见luat_uart
void luat_usb_app_start(uint8_t usb_id);
void luat_usb_app_stop(uint8_t usb_id);
void luat_usb_app_vhid_tx(uint8_t usb_id, uint8_t *data, uint32_t len);
uint32_t luat_usb_app_vhid_rx(uint8_t usb_id, uint8_t *data, uint32_t len);
void luat_usb_app_vhid_upload(uint8_t usb_id, uint8_t *key_data, uint32_t len);
void luat_usb_app_vhid_cancel_upload(uint8_t usb_id);
void luat_usb_udisk_attach_sdhc(uint8_t usb_id);
void luat_usb_udisk_detach_sdhc(uint8_t usb_id);

#endif
