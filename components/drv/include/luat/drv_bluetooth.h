
#ifndef LUAT_DRV_BLUETOOTH_H
#define LUAT_DRV_BLUETOOTH_H

#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_bt.h"

int luat_drv_bluetooth_init(luat_bluetooth_t* luat_bluetooth);

int luat_airlink_drv_ble_uuid_swap(uint8_t* uuid_data, luat_ble_uuid_type uuid_type);

int luat_airlink_drv_ble_init(luat_ble_t* luat_ble, luat_ble_cb_t luat_ble_cb);

int luat_airlink_drv_ble_deinit(luat_ble_t* luat_ble);

int luat_airlink_drv_ble_set_name(luat_ble_t* luat_ble, char* name, uint8_t len);

int luat_airlink_drv_ble_set_max_mtu(luat_ble_t* luat_ble, uint16_t max_mtu);

// advertise
int luat_airlink_drv_ble_create_advertising(luat_ble_t* luat_ble, luat_ble_adv_cfg_t* adv_cfg);

int luat_airlink_drv_ble_set_adv_data(luat_ble_t* luat_ble, uint8_t* adv_buff, uint8_t adv_len);

int luat_airlink_drv_ble_set_scan_rsp_data(luat_ble_t* luat_ble, uint8_t* rsp_data, uint8_t rsp_len);

int luat_airlink_drv_ble_start_advertising(luat_ble_t* luat_ble);

int luat_airlink_drv_ble_stop_advertising(luat_ble_t* luat_ble);

int luat_airlink_drv_ble_delete_advertising(luat_ble_t* luat_ble);

// gatt
int luat_airlink_drv_ble_create_gatt(luat_ble_t* luat_ble, luat_ble_gatt_service_t* luat_ble_gatt_service);

// slaver
int luat_airlink_drv_ble_read_response_value(luat_ble_t* luat_ble, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint32_t len);

int luat_airlink_drv_ble_write_notify_value(luat_ble_t* luat_ble, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint16_t len);

// scanning
int luat_airlink_drv_ble_create_scanning(luat_ble_t* luat_ble, luat_ble_scan_cfg_t* scan_cfg);

int luat_airlink_drv_ble_start_scanning(luat_ble_t* luat_ble);

int luat_airlink_drv_ble_stop_scanning(luat_ble_t* luat_ble);

int luat_airlink_drv_ble_delete_scanning(luat_ble_t* luat_ble);

#endif
