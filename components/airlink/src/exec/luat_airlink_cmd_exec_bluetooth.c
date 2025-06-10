#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_bt.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_netdrv.h"
#include "luat_mem.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "airlink.ble"
#include "luat_log.h"

extern void luat_ble_cb(luat_ble_t* luat_ble, luat_ble_event_t ble_event, luat_ble_param_t* ble_param);

int luat_airlink_cmd_exec_bluetooth_init(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_bluetooth_t *luat_bluetooth = (luat_bluetooth_t *)(cmd->data + 8);
    int ret = luat_bluetooth_init(luat_bluetooth);
    LLOGE("luat_airlink_cmd_exec_bluetooth_init ret=%d", ret);
    return ret;
}

int luat_airlink_cmd_exec_ble_uuid_swap(luat_airlink_cmd_t *cmd, void *userdata)
{
    uint8_t* uuid_data = cmd->data[8];
    uint8_t uuid_len = cmd->data[9];

    LLOGD("luat_airlink_cmd_exec_ble_uuid_swap");
    return 0;
}

int luat_airlink_cmd_exec_ble_init(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    luat_ble_cb_t luat_ble_cb = cmd->func[0];
    luat_ble_init(luat_ble, luat_ble_cb);
    return 0;
}

int luat_airlink_cmd_exec_ble_deinit(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    int ret = luat_ble_deinit(luat_ble);
    return ret;
}

int luat_airlink_cmd_exec_ble_set_name(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t* luat_ble = (luat_ble_t *)(cmd->data + 8);
    char* name = (char*)(cmd->data + 8);
    uint8_t len = cmd->len - 8;
    int ret = luat_ble_set_name(luat_ble, name, len);
    return ret;
}

int luat_airlink_cmd_exec_ble_set_max_mtu(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t* luat_ble = (luat_ble_t *)(cmd->data + 8);
    uint16_t max_mtu = cmd->data + 8 + sizeof(luat_ble_t);
    int ret = luat_ble_set_max_mtu(luat_ble, max_mtu);
    return ret;
}

// advertise
int luat_airlink_cmd_exec_ble_create_advertising(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    luat_ble_adv_cfg_t *adv_cfg = (luat_ble_adv_cfg_t *)(cmd->data + 8 + sizeof(luat_ble_t));
    int ret = luat_ble_create_advertising(luat_ble, adv_cfg);
    return ret;
}

int luat_airlink_cmd_exec_ble_set_adv_data(luat_airlink_cmd_t *cmd, void *userdata)
{
    return 0;
}

int luat_airlink_cmd_exec_ble_set_scan_rsp_data(luat_airlink_cmd_t *cmd, void *userdata)
{
    return 0;
}

int luat_airlink_cmd_exec_ble_start_advertising(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    int ret = luat_ble_start_advertising(luat_ble);
    return ret;
}

int luat_airlink_cmd_exec_ble_stop_advertising(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    int ret = luat_ble_stop_advertising(luat_ble);
    return ret;
}

int luat_airlink_cmd_exec_ble_delete_advertising(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    int ret = luat_ble_delete_advertising(luat_ble);
    return ret;
}

// gatt
int luat_airlink_cmd_exec_ble_create_gatt(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    luat_ble_gatt_service_t *luat_ble_gatt_service = (cmd->data + 8 + sizeof(luat_ble_t));
    luat_ble_gatt_service->characteristics = (luat_ble_gatt_chara_t*)luat_heap_malloc(sizeof(luat_ble_gatt_chara_t) * luat_ble_gatt_service->characteristics_num);
    memset(luat_ble_gatt_service->characteristics, 0, sizeof(luat_ble_gatt_chara_t) * luat_ble_gatt_service->characteristics_num);
    luat_ble_gatt_service->characteristics = (luat_ble_gatt_chara_t*)(cmd->data + 8 + sizeof(luat_ble_t) + sizeof(luat_ble_gatt_service_t));
    int ret = luat_ble_create_gatt(luat_ble, luat_ble_gatt_service);
    return ret;
}

// slaver
int luat_airlink_cmd_exec_ble_read_response_value(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    uint8_t data[5];
    memcpy(data, cmd->data + 8 + sizeof(luat_ble_t), 5);
    int ret = luat_ble_read_response_value(luat_ble, data[0], data[1],data[2], &(data[3]), data[4]);
    return 0;
}

int luat_airlink_cmd_exec_ble_write_notify_value(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    uint8_t data[5];
    memcpy(data, cmd->data + 8 + sizeof(luat_ble_t), 5);
    int ret = luat_ble_write_notify_value(luat_ble, data[0], data[1],data[2], &(data[3]), data[4]);
    return 0;
}

// scanning
int luat_airlink_cmd_exec_ble_create_scanning(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    luat_ble_scan_cfg_t *scan_cfg = (luat_ble_scan_cfg_t *)(cmd->data + 8 + sizeof(luat_ble_t));
    int ret = luat_ble_create_scanning(luat_ble, scan_cfg);
    return ret;
}

int luat_airlink_cmd_exec_ble_start_scanning(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    int ret = luat_ble_start_scanning(luat_ble);
    return ret;
}

int luat_airlink_cmd_exec_ble_stop_scanning(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    int ret = luat_ble_stop_scanning(luat_ble);
    return ret;
}

int luat_airlink_cmd_exec_ble_delete_scanning(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_ble_t *luat_ble = (luat_ble_t *)(cmd->data + 8);
    int ret = luat_ble_delete_scanning(luat_ble);
    return ret;
}