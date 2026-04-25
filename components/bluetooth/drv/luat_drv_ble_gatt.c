#include "luat_base.h"
#include "luat_mem.h"
#include "luat_ble.h"
#include "luat_drv_ble.h"
#include <string.h>

#define LUAT_LOG_TAG "drv.ble.gatt"
#include "luat_log.h"

int luat_ble_gatt_pack(luat_ble_gatt_service_t* gatt, uint8_t* ptr, size_t* _len) {
    uint16_t descriptor_totalNum = 0;
    for (size_t i = 0; i < gatt->characteristics_num; i++) {
        descriptor_totalNum += gatt->characteristics[i].descriptors_num;
    }

    size_t total_len = 8
                     + sizeof(luat_ble_gatt_service_t)
                     + gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t)
                     + descriptor_totalNum * sizeof(luat_ble_gatt_descriptor_t);
    if (_len) {
        *_len = total_len;
    }

    if (ptr == NULL) {
        return 0;
    }

    uint16_t tmp = 0;
    uint16_t offset = 0;
    uint8_t descriptor_num;

    tmp = sizeof(luat_ble_gatt_service_t);
    memcpy(ptr, &tmp, 2);
    tmp = sizeof(luat_ble_gatt_chara_t);
    memcpy(ptr + 2, &tmp, 2);
    tmp = gatt->characteristics_num;
    memcpy(ptr + 2 + 2, &tmp, 2);
    tmp = sizeof(luat_ble_gatt_descriptor_t);
    memcpy(ptr + 2 + 2 + 2, &tmp, 2);

    memcpy(ptr + 8, gatt, sizeof(luat_ble_gatt_service_t));
    memcpy(ptr + 8 + sizeof(luat_ble_gatt_service_t),
        gatt->characteristics, gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t));

    offset = 8 + sizeof(luat_ble_gatt_service_t) + gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t);
    for (size_t i = 0; i < gatt->characteristics_num; i++) {
        descriptor_num = gatt->characteristics[i].descriptors_num;
        if (descriptor_num == 0) {
            continue;
        }
        memcpy(ptr + offset, gatt->characteristics[i].descriptor, descriptor_num * sizeof(luat_ble_gatt_descriptor_t));
        offset += descriptor_num * sizeof(luat_ble_gatt_descriptor_t);
    }

    return 0;
}

int luat_ble_gatt_unpack(luat_ble_gatt_service_t* gatt, uint8_t* data, size_t* len) {
    size_t offset = 0;
    uint16_t sizeof_gatt = 0;
    uint16_t sizeof_gatt_chara = 0;
    uint16_t num_of_gatt_srv = 0;
    uint16_t sizeof_gatt_desc = 0;
    memcpy(&sizeof_gatt, data, 2);
    memcpy(&sizeof_gatt_chara, data + 2, 2);
    memcpy(&num_of_gatt_srv, data + 4, 2);
    memcpy(&sizeof_gatt_desc, data + 6, 2);
    offset = 8;

    memcpy(gatt, data + offset, sizeof(luat_ble_gatt_service_t));
    offset += sizeof(luat_ble_gatt_service_t);

    gatt->characteristics = luat_heap_malloc(sizeof(luat_ble_gatt_chara_t) * gatt->characteristics_num);
    if (gatt->characteristics == NULL) {
        LLOGE("gatt_unpack: characteristics malloc fail %d", gatt->characteristics_num);
        if (len) *len = 0;
        return -1;
    }
    for (size_t i = 0; i < gatt->characteristics_num; i++) {
        memcpy(&gatt->characteristics[i], data + 8 + sizeof(luat_ble_gatt_service_t) + sizeof_gatt_chara * i, sizeof(luat_ble_gatt_chara_t));
        if (gatt->characteristics[i].descriptors_num) {
            gatt->characteristics[i].descriptor = luat_heap_malloc(gatt->characteristics[i].descriptors_num * sizeof(luat_ble_gatt_descriptor_t));
        }
        offset += sizeof(luat_ble_gatt_chara_t);
    }
    for (size_t i = 0; i < gatt->characteristics_num; i++) {
        if (gatt->characteristics[i].descriptors_num) {
            memcpy(gatt->characteristics[i].descriptor, data + offset, gatt->characteristics[i].descriptors_num * sizeof(luat_ble_gatt_descriptor_t));
        }
        offset += gatt->characteristics[i].descriptors_num * sizeof(luat_ble_gatt_descriptor_t);
    }
    if (len) {
        *len = offset;
    }
    return 0;
}
