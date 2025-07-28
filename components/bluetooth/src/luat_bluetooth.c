#include "luat_base.h"
#include "luat_mem.h"
#include "luat_bluetooth.h"

#include "luat_log.h"
#define LUAT_LOG_TAG "bluetooth"

void luat_bluetooth_mac_swap(uint8_t* mac){
    uint8_t tmp_mac[LUAT_BLUETOOTH_MAC_LEN] = {0};
    memcpy(tmp_mac, mac, LUAT_BLUETOOTH_MAC_LEN);
    for(int i=0;i<LUAT_BLUETOOTH_MAC_LEN;i++){
        mac[i] = tmp_mac[LUAT_BLUETOOTH_MAC_LEN-1-i];
    }
}



