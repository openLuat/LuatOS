#include "luat_base.h"
#if defined(LUAT_USE_DRV_BLUETOOTH)
#include "luat/drv_bluetooth.h"
#include "luat_airlink.h"
#include "luat_airlink_drv_bluetooth.h"
#include "luat_airlink_drv_rpc_bluetooth.h"

/* In RPC builds all BLE operations use the same synchronous protocol. A
 * missing peer capability is an error, not a silent raw-command fallback. */
#ifdef LUAT_USE_AIRLINK_RPC
#define BLE_ROUTE(name, arguments) \
    return luat_airlink_peer_rpc_supported() && luat_airlink_current_mode_get() >= 0 \
        ? luat_airlink_drv_rpc_##name arguments : -1
#else
#define BLE_ROUTE(name, arguments) return luat_airlink_drv_##name arguments
#endif

int luat_drv_bluetooth_init(luat_bluetooth_t* bt) {
#ifndef LUAT_USE_AIRLINK_RPC
    if (luat_airlink_sversion() < 10) return -1;
#endif
    BLE_ROUTE(bluetooth_init, (bt));
}

int luat_drv_bluetooth_deinit(luat_bluetooth_t* bt) {
#ifdef LUAT_USE_AIRLINK_RPC
    BLE_ROUTE(bluetooth_deinit, (bt));
#else
    (void)bt;
    return -1;
#endif
}

int luat_drv_ble_uuid_swap(uint8_t* uuid, luat_ble_uuid_type type) {
    return luat_airlink_drv_ble_uuid_swap(uuid, type);
}

int luat_drv_ble_init(luat_ble_t* ble, luat_ble_cb_t cb) { BLE_ROUTE(ble_init, (ble, cb)); }
int luat_drv_ble_deinit(luat_ble_t* ble) { BLE_ROUTE(ble_deinit, (ble)); }
int luat_drv_ble_set_name(luat_ble_t* ble, char* name, uint8_t len) { BLE_ROUTE(ble_set_name, (ble, name, len)); }
int luat_drv_ble_set_max_mtu(luat_ble_t* ble, uint16_t mtu) { BLE_ROUTE(ble_set_max_mtu, (ble, mtu)); }
int luat_drv_ble_create_advertising(luat_ble_t* ble, luat_ble_adv_cfg_t* cfg) { BLE_ROUTE(ble_create_advertising, (ble, cfg)); }
int luat_drv_ble_set_adv_data(luat_ble_t* ble, uint8_t* data, uint8_t len) { BLE_ROUTE(ble_set_adv_data, (ble, data, len)); }
int luat_drv_ble_set_scan_rsp_data(luat_ble_t* ble, uint8_t* data, uint8_t len) { BLE_ROUTE(ble_set_scan_rsp_data, (ble, data, len)); }
int luat_drv_ble_start_advertising(luat_ble_t* ble) { BLE_ROUTE(ble_start_advertising, (ble)); }
int luat_drv_ble_stop_advertising(luat_ble_t* ble) { BLE_ROUTE(ble_stop_advertising, (ble)); }
int luat_drv_ble_delete_advertising(luat_ble_t* ble) { BLE_ROUTE(ble_delete_advertising, (ble)); }
int luat_drv_ble_create_gatt(luat_ble_t* ble, luat_ble_gatt_service_t* gatt) { BLE_ROUTE(ble_create_gatt, (ble, gatt)); }
int luat_drv_ble_create_scanning(luat_ble_t* ble, luat_ble_scan_cfg_t* cfg) { BLE_ROUTE(ble_create_scanning, (ble, cfg)); }
int luat_drv_ble_start_scanning(luat_ble_t* ble) { BLE_ROUTE(ble_start_scanning, (ble)); }
int luat_drv_ble_stop_scanning(luat_ble_t* ble) { BLE_ROUTE(ble_stop_scanning, (ble)); }
int luat_drv_ble_delete_scanning(luat_ble_t* ble) { BLE_ROUTE(ble_delete_scanning, (ble)); }

int luat_drv_ble_read_response_value(luat_ble_t* ble, uint8_t conn, uint16_t svc,
                                    uint16_t handle, uint8_t* data, uint32_t len) {
    BLE_ROUTE(ble_read_response_value, (ble, conn, svc, handle, data, len));
}

int luat_drv_ble_write_notify_value(luat_ble_t* ble, uint8_t conn, uint16_t svc,
                                   uint16_t handle, uint8_t* data, uint16_t len) {
    BLE_ROUTE(ble_write_notify_value, (ble, conn, svc, handle, data, len));
}

int luat_drv_ble_connect(void* args, luat_ble_connect_req_t* conn) {
#ifdef LUAT_USE_AIRLINK_RPC
    BLE_ROUTE(ble_connect, (args, conn));
#else
    (void)args; (void)conn;
    return -1;
#endif
}

int luat_drv_ble_disconnect(void* args) {
#ifdef LUAT_USE_AIRLINK_RPC
    BLE_ROUTE(ble_disconnect, (args));
#else
    (void)args;
    return -1;
#endif
}

int luat_drv_ble_value(uint16_t operation, luat_ble_uuid_t* service,
                       luat_ble_uuid_t* characteristic, luat_ble_uuid_t* descriptor,
                       uint8_t* data, uint16_t len, uint8_t enable) {
#ifdef LUAT_USE_AIRLINK_RPC
    BLE_ROUTE(ble_value, (operation, service, characteristic, descriptor, data, len, enable));
#else
    (void)operation; (void)service; (void)characteristic; (void)descriptor;
    (void)data; (void)len; (void)enable;
    return -1;
#endif
}
#undef BLE_ROUTE
#endif
