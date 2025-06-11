#include "luat_base.h"
#include "luat_mem.h"
#include "luat_bluetooth.h"

#include "luat_log.h"
#define LUAT_LOG_TAG "ble"

int luat_ble_uuid_swap(uint8_t* uuid_data, luat_ble_uuid_type uuid_type){
    uint8_t len = 0;
    if(uuid_type == LUAT_BLE_UUID_TYPE_16){
        len = 2;
    }else if(uuid_type == LUAT_BLE_UUID_TYPE_32){
        len = 4;
    }else if(uuid_type == LUAT_BLE_UUID_TYPE_128){
        len = 16;
    }else{
        return -1;
    }
    for(int i=0;i<len/2;i++){
        uint8_t tmp = uuid_data[i];
        uuid_data[i] = uuid_data[len-1-i];
        uuid_data[len-1-i] = tmp;
    }
    return 0;
}


