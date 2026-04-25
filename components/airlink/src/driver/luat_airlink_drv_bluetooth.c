/*
 * AirLink BLE raw byte 驱动（raw-only 路径）
 *
 * RPC client 路径已迁移至 drv_rpc/luat_airlink_drv_rpc_bluetooth.c
 * 本文件仅保留 raw byte 路径（发送 luat_drv_ble_msg_t via cmd 0x500）
 */

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_mem.h"

#include "luat_ble.h"
#include "luat_bt.h"
#include "luat_drv_ble.h"

#define LUAT_LOG_TAG "airlink.drv.bt"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...)

#ifndef ENOMEM
#define ENOMEM 12
#endif

/* ---------- raw byte path helper ---------- */

static int ble_raw_send(uint16_t cmd_id, const void* data, uint16_t data_len) {
    size_t payload = sizeof(luat_drv_ble_msg_t) + data_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, payload);
    if (cmd == NULL) return -101;
    luat_drv_ble_msg_t* msg = (luat_drv_ble_msg_t*)cmd->data;
    memset(msg, 0, sizeof(luat_drv_ble_msg_t));
    msg->id     = luat_airlink_get_next_cmd_id();
    msg->cmd_id = cmd_id;
    msg->len    = data_len;
    if (data && data_len > 0) memcpy(msg->data, data, data_len);
    airlink_queue_item_t item = {
        .len = (uint32_t)(sizeof(luat_airlink_cmd_t) + payload),
        .cmd = cmd,
    };
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

/* ---------- API: uuid swap (local utility, no RPC) ---------- */

int luat_airlink_drv_ble_uuid_swap(uint8_t* uuid_data, luat_ble_uuid_type uuid_type) {
    if (uuid_data == NULL) return -1;
    uint8_t len = 0;
    switch (uuid_type) {
    case LUAT_BLE_UUID_TYPE_16:  len = 2;  break;
    case LUAT_BLE_UUID_TYPE_32:  len = 4;  break;
    case LUAT_BLE_UUID_TYPE_128: len = 16; break;
    default: return -1;
    }
    for (uint8_t i = 0; i < len / 2; i++) {
        uint8_t tmp = uuid_data[i];
        uuid_data[i] = uuid_data[len - 1 - i];
        uuid_data[len - 1 - i] = tmp;
    }
    return 0;
}

/* ---------- API: classic bluetooth init (raw path only) ---------- */

int luat_airlink_drv_bluetooth_init(luat_bluetooth_t* luat_bluetooth) {
    (void)luat_bluetooth;
    return ble_raw_send(LUAT_DRV_BT_CMD_BT_INIT, NULL, 0);
}

/* ---------- API: BLE operations ---------- */

int luat_airlink_drv_ble_init(luat_ble_t* luat_ble, luat_ble_cb_t luat_ble_cb) {
    (void)luat_ble;
    (void)luat_ble_cb;
    // luat_drv_bt_task_start();
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_INIT, NULL, 0);
}

int luat_airlink_drv_ble_deinit(luat_ble_t* luat_ble) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_DEINIT, NULL, 0);
}

int luat_airlink_drv_ble_set_name(luat_ble_t* luat_ble, char* name, uint8_t len) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_SET_NAME, name, len);
}

int luat_airlink_drv_ble_set_max_mtu(luat_ble_t* luat_ble, uint16_t max_mtu) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_SET_NAME, &max_mtu, 2);
}

int luat_airlink_drv_ble_create_advertising(luat_ble_t* luat_ble, luat_ble_adv_cfg_t* adv_cfg) {
    (void)luat_ble;
    size_t cfg_len = adv_cfg ? sizeof(luat_ble_adv_cfg_t) : 0;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_ADV_CREATE, adv_cfg, (uint16_t)cfg_len);
}

int luat_airlink_drv_ble_set_adv_data(luat_ble_t* luat_ble, uint8_t* adv_buff, uint8_t adv_len) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_ADV_SET_DATA, adv_buff, adv_len);
}

int luat_airlink_drv_ble_set_scan_rsp_data(luat_ble_t* luat_ble, uint8_t* rsp_data, uint8_t rsp_len) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_ADV_SET_SCAN_RSP_DATA, rsp_data, rsp_len);
}

int luat_airlink_drv_ble_start_advertising(luat_ble_t* luat_ble) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_ADV_START, NULL, 0);
}

int luat_airlink_drv_ble_stop_advertising(luat_ble_t* luat_ble) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_ADV_STOP, NULL, 0);
}

int luat_airlink_drv_ble_delete_advertising(luat_ble_t* luat_ble) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_ADV_DELETE, NULL, 0);
}

int luat_airlink_drv_ble_create_gatt(luat_ble_t* luat_ble, luat_ble_gatt_service_t* luat_ble_gatt_service) {
    (void)luat_ble;
    /* raw path: pack gatt into msg data */
    size_t gatt_len = 0;
    luat_ble_gatt_pack(luat_ble_gatt_service, NULL, &gatt_len);
    size_t total_len = sizeof(luat_drv_ble_msg_t) + gatt_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, total_len);
    if (cmd == NULL) return -101;
    luat_drv_ble_msg_t* msg = (luat_drv_ble_msg_t*)cmd->data;
    memset(msg, 0, sizeof(luat_drv_ble_msg_t));
    msg->id     = luat_airlink_get_next_cmd_id();
    msg->cmd_id = LUAT_DRV_BT_CMD_BLE_GATT_CREATE;
    msg->len    = (uint16_t)gatt_len;
    luat_ble_gatt_pack(luat_ble_gatt_service, msg->data, &gatt_len);
    airlink_queue_item_t item = {
        .len = (uint32_t)(sizeof(luat_airlink_cmd_t) + total_len),
        .cmd = cmd,
    };
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_read_response_value(luat_ble_t* luat_ble, uint8_t conn_idx,
                                              uint16_t service_id, uint16_t att_handle,
                                              uint8_t* data, uint32_t len) {
    (void)luat_ble;
    size_t total = 1 + 2 + 2 + len;
    uint8_t* buf = (uint8_t*)luat_heap_malloc(total);
    if (!buf) return -ENOMEM;
    buf[0] = conn_idx;
    memcpy(buf + 1, &service_id, 2);
    memcpy(buf + 3, &att_handle, 2);
    if (data && len > 0) memcpy(buf + 5, data, len);
    int ret = ble_raw_send(LUAT_DRV_BT_CMD_BLE_SEND_READ_RESP, buf, (uint16_t)total);
    luat_heap_free(buf);
    return ret;
}

int luat_airlink_drv_ble_write_notify_value(luat_ble_t* luat_ble, uint8_t conn_idx,
                                             uint16_t service_id, uint16_t att_handle,
                                             uint8_t* data, uint16_t len) {
    (void)luat_ble;
    size_t total = 1 + 2 + 2 + len;
    uint8_t* buf = (uint8_t*)luat_heap_malloc(total);
    if (!buf) return -ENOMEM;
    buf[0] = conn_idx;
    memcpy(buf + 1, &service_id, 2);
    memcpy(buf + 3, &att_handle, 2);
    if (data && len > 0) memcpy(buf + 5, data, len);
    int ret = ble_raw_send(LUAT_DRV_BT_CMD_BLE_WRITE_NOTIFY, buf, (uint16_t)total);
    luat_heap_free(buf);
    return ret;
}

int luat_airlink_drv_ble_create_scanning(luat_ble_t* luat_ble, luat_ble_scan_cfg_t* scan_cfg) {
    (void)luat_ble;
    size_t cfg_len = scan_cfg ? sizeof(luat_ble_scan_cfg_t) : 0;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_SCAN_CREATE, scan_cfg, (uint16_t)cfg_len);
}

int luat_airlink_drv_ble_start_scanning(luat_ble_t* luat_ble) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_SCAN_START, NULL, 0);
}

int luat_airlink_drv_ble_stop_scanning(luat_ble_t* luat_ble) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_SCAN_STOP, NULL, 0);
}

int luat_airlink_drv_ble_delete_scanning(luat_ble_t* luat_ble) {
    (void)luat_ble;
    return ble_raw_send(LUAT_DRV_BT_CMD_BLE_SCAN_DELETE, NULL, 0);
}
