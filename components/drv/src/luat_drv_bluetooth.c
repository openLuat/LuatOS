#include "luat_base.h"
#include "luat_mem.h"
#include "luat/drv_bluetooth.h"
#include "luat_airlink.h"
#include "luat_bluetooth.h"
#include "luat_airlink_drv_bluetooth.h"

#define LUAT_LOG_TAG "drv.ble"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

int luat_drv_bluetooth_init(luat_bluetooth_t* luat_bluetooth) {
    if (luat_airlink_sversion() < 10) {
        LLOGE("wifi fw version too low, need >= 10");
        return -1;
    }
    return luat_airlink_drv_bluetooth_init(luat_bluetooth);
}

int luat_drv_ble_uuid_swap(uint8_t* uuid_data, luat_ble_uuid_type uuid_type)
{
    return luat_airlink_drv_ble_uuid_swap(uuid_data, uuid_type);
}

int luat_drv_ble_init(luat_ble_t* luat_ble, luat_ble_cb_t luat_ble_cb){
    return luat_airlink_drv_ble_init(luat_ble, luat_ble_cb);
}

int luat_drv_ble_deinit(luat_ble_t* luat_ble)
{
    return luat_airlink_drv_ble_deinit(luat_ble);
}

int luat_drv_ble_set_name(luat_ble_t* luat_ble, char* name, uint8_t len)
{
    return luat_airlink_drv_ble_set_name(luat_ble, name, len);
}

int luat_drv_ble_set_max_mtu(luat_ble_t* luat_ble, uint16_t max_mtu)
{
    return luat_airlink_drv_ble_set_max_mtu(luat_ble, max_mtu);
}

// advertise
int luat_drv_ble_create_advertising(luat_ble_t* luat_ble, luat_ble_adv_cfg_t* adv_cfg)
{
    return luat_airlink_drv_ble_create_advertising(luat_ble, adv_cfg);
}

int luat_drv_ble_set_adv_data(luat_ble_t* luat_ble, uint8_t* adv_buff, uint8_t adv_len)
{
    return luat_airlink_drv_ble_set_adv_data(luat_ble, adv_buff, adv_len);
}

int luat_drv_ble_set_scan_rsp_data(luat_ble_t* luat_ble, uint8_t* rsp_data, uint8_t rsp_len)
{
    return luat_airlink_drv_ble_set_scan_rsp_data(luat_ble, rsp_data, rsp_len);
}

int luat_drv_ble_start_advertising(luat_ble_t* luat_ble)
{
    return luat_airlink_drv_ble_start_advertising(luat_ble);
}

int luat_drv_ble_stop_advertising(luat_ble_t* luat_ble)
{
    return luat_airlink_drv_ble_stop_advertising(luat_ble);
}

int luat_drv_ble_delete_advertising(luat_ble_t* luat_ble)
{
    return luat_airlink_drv_ble_delete_advertising(luat_ble);
}

// gatt
int luat_drv_ble_create_gatt(luat_ble_t* luat_ble, luat_ble_gatt_service_t* luat_ble_gatt_service)
{
    return luat_airlink_drv_ble_create_gatt(luat_ble, luat_ble_gatt_service);
}

// slaver
int luat_drv_ble_read_response_value(luat_ble_t* luat_ble, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint32_t len)
{
    return luat_airlink_drv_ble_read_response_value(luat_ble, conn_idx, service_id, att_handle, data, len);
}

int luat_drv_ble_write_notify_value(luat_ble_t* luat_ble, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint16_t len)
{
    return luat_airlink_drv_ble_write_notify_value(luat_ble, conn_idx, service_id, att_handle, data, len);
}

// scanning
int luat_drv_ble_create_scanning(luat_ble_t* luat_ble, luat_ble_scan_cfg_t* scan_cfg)
{
    return luat_airlink_drv_ble_create_scanning(luat_ble, scan_cfg);
}


int luat_drv_ble_start_scanning(luat_ble_t* luat_ble)
{
    return luat_airlink_drv_ble_start_scanning(luat_ble);
}

int luat_drv_ble_stop_scanning(luat_ble_t* luat_ble)
{
    return luat_airlink_drv_ble_stop_scanning(luat_ble);
}

int luat_drv_ble_delete_scanning(luat_ble_t* luat_ble)
{
    return luat_airlink_drv_ble_delete_scanning(luat_ble);
}