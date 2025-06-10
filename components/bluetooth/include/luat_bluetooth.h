#ifndef __LUAT_BLUETOOTH__
#define __LUAT_BLUETOOTH__

#include "luat_ble.h"
#include "luat_bt.h"

#define LUAT_BLUETOOTH_TYPE "BLUETOOTH*"
#define LUAT_BLE_TYPE "BLE*"

#define LUAT_BLUETOOTH_MAC_LEN    6

typedef struct luat_bluetooth{
    luat_ble_t* luat_ble;
    luat_bt_t* luat_bt;
    int bluetooth_ref;
}luat_bluetooth_t;

// bluetooth

int luat_bluetooth_init(luat_bluetooth_t* luat_bluetooth);
int luat_bluetooth_deinit(luat_bluetooth_t* luat_bluetooth);

int luat_bluetooth_get_mac(luat_bluetooth_t* luat_bluetooth, uint8_t *addr);
int luat_bluetooth_set_mac(luat_bluetooth_t* luat_bluetooth, uint8_t *addr, uint8_t len);

void luat_bluetooth_mac_swap(uint8_t* mac);

#endif
