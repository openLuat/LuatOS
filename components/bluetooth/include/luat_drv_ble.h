#ifndef LUAT_DRV_BLE_H
#define LUAT_DRV_BLE_H

typedef struct luat_drv_ble_msg
{
    uint32_t cmd_id;
    uint32_t len;
    uint8_t data[0];
}luat_drv_ble_msg_t;

// 定义蓝牙cmd id

enum {
    LUAT_DRV_BT_CMD_BT_INIT = 0,
    LUAT_DRV_BT_CMD_BT_DEINIT,
    LUAT_DRV_BT_CMD_BLE_INIT,
    LUAT_DRV_BT_CMD_BLE_DEINIT,
    LUAT_DRV_BT_CMD_BLE_GATT_CREATE,


    LUAT_DRV_BT_CMD_MAX
};

#endif
