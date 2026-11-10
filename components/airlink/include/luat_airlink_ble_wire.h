#ifndef LUAT_AIRLINK_BLE_WIRE_H
#define LUAT_AIRLINK_BLE_WIRE_H

#include "luat_base.h"
#include "luat_ble.h"

/* Wire version 1: integers are little endian, UUIDs are length(u8) + bytes
 * in API order (0 only for absent event/request UUIDs). No native structs,
 * padding or pointers cross the link.
 * Tree: version, service UUID, characteristic count(u8), characteristics.
 * Attribute: UUID, handle(u16), permissions(u16), max size(u16), value
 * length(u16), value bytes. Each characteristic then has a descriptor count
 * (u8) followed by descriptor attributes. Decode allocates each value using
 * luat_heap; the backend may replace these pointers. Free CURRENT pointers
 * only after successful backend teardown, including after failed creation.
 * Events: version followed by fields in API declaration order (UUIDs before
 * the value length/data for read/write; scan length/data follows address).
 * GATT_ITEM contains index(u8), total(u8), then the complete versioned tree.
 */
int luat_airlink_ble_uuid_valid(unsigned type, int optional);
int luat_airlink_ble_gatt_encode(const luat_ble_gatt_service_t* gatt,
                                uint8_t* data, size_t capacity, size_t* length);
int luat_airlink_ble_gatt_decode(const uint8_t* data, size_t length,
                                luat_ble_gatt_service_t** gatt);
void luat_airlink_ble_gatt_free(luat_ble_gatt_service_t* gatt);

/* Encode is a deep snapshot, suitable for borrowed BK callback parameters.
 * Decode borrows value/scan bytes until the callback returns; only GATT_ITEM
 * allocates a tree, which must be freed with event_cleanup afterwards. */
int luat_airlink_ble_event_encode(luat_ble_event_t event, const luat_ble_param_t* param,
                                 uint8_t* data, size_t capacity, size_t* length);
int luat_airlink_ble_event_decode(luat_ble_event_t event, const uint8_t* data,
                                 size_t length, luat_ble_param_t* param);
void luat_airlink_ble_event_cleanup(luat_ble_event_t event, luat_ble_param_t* param);

#endif
