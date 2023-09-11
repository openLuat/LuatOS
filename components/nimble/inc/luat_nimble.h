
#ifndef LUAT_NUMBLE_H
#define LUAT_NUMBLE_H
#include "luat_base.h"
#include "luat_msgbus.h"

#include "host/ble_uuid.h"

#define LUAT_BLE_MAX_CHR (3)

#define MAX_PER_SERV (8)

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

int luat_nimble_server_send_notify(ble_uuid_any_t* srv, ble_uuid_any_t* chr, char* data, size_t len);

int luat_nimble_server_send_indicate(ble_uuid_any_t* srv, ble_uuid_any_t* chr, char* data, size_t len);



int luat_nimble_server_send2(ble_uuid_any_t* srv, ble_uuid_any_t* chr, char* data, size_t len, int type);

int luat_nimble_blecent_scan(int timeout);

int luat_nimble_blecent_connect(const char* addr);

// 直接设置标准的ibeacon数据
int luat_nimble_ibeacon_setup(void *uuid128, uint16_t major,
                         uint16_t minor, int8_t measured_power);

// 自由设置广播数据, 比ibeacon更自由
int luat_nimble_set_adv_data(char* buff, size_t len, int flags);


int luat_nimble_peripheral_set_chr(int index, ble_uuid_any_t* chr_uuid, int flags);

int luat_nimble_central_disc_char(struct ble_gatt_svc *service);

#endif

