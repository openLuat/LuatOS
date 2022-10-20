
#ifndef LUAT_NUMBLE_H
#define LUAT_NUMBLE_H
#include "luat_base.h"
#include "luat_msgbus.h"


/** Bluetooth Adapter State */
typedef enum
{
    BT_STATE_OFF,
    BT_STATE_ON,
    BT_STATE_CONNECTED,
    BT_STATE_DISCONNECT,
} bt_state_t;


typedef enum
{
    BT_MODE_BLE_SERVER,
    BT_MODE_BLE_CLIENT,
    BT_MODE_BLE_BEACON,
    BT_MODE_BLE_MESH,
} bt_mode_t;

int luat_nimble_trace_level(int level);

int luat_nimble_init(uint8_t uart_idx, char* name, int mode);
int luat_nimble_deinit();

int luat_nimble_server_send(int id, char* data, size_t len);

#endif

