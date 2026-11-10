#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC
#include "luat_airlink_ble_wire.h"
#include "luat_mem.h"
#include <string.h>

typedef struct {
    uint8_t* out;
    const uint8_t* in;
    size_t size;
    size_t pos;
    int error;
} ble_wire_t;

int luat_airlink_ble_uuid_valid(unsigned type, int optional) {
    return type == 2 || type == 4 || type == 16 || (optional && type == 0);
}

static void put_bytes(ble_wire_t* w, const void* data, size_t len) {
    if (w->error || len > w->size - w->pos || (len && !data)) {
        w->error = 1;
        return;
    }
    if (len) memcpy(w->out + w->pos, data, len);
    w->pos += len;
}

static const uint8_t* get_bytes(ble_wire_t* w, size_t len) {
    if (w->error || len > w->size - w->pos) {
        w->error = 1;
        return NULL;
    }
    const uint8_t* data = w->in + w->pos;
    w->pos += len;
    return data;
}

static void put8(ble_wire_t* w, unsigned value) {
    uint8_t v = (uint8_t)value;
    put_bytes(w, &v, 1);
}

static void put16(ble_wire_t* w, unsigned value) {
    put8(w, value);
    put8(w, value >> 8);
}

static unsigned get8(ble_wire_t* w) {
    const uint8_t* p = get_bytes(w, 1);
    return p ? p[0] : 0;
}

static unsigned get16(ble_wire_t* w) {
    unsigned lo = get8(w);
    return lo | (get8(w) << 8);
}

static void get_copy(ble_wire_t* w, void* dst, size_t len) {
    const uint8_t* p = get_bytes(w, len);
    if (p && len) memcpy(dst, p, len);
}

static void put_uuid(ble_wire_t* w, unsigned type, const uint8_t* uuid, int optional) {
    if (!luat_airlink_ble_uuid_valid(type, optional)) { w->error = 1; return; }
    put8(w, type);
    put_bytes(w, uuid, type);
}

static luat_ble_uuid_type get_uuid(ble_wire_t* w, uint8_t* uuid, int optional) {
    unsigned type = get8(w);
    if (!luat_airlink_ble_uuid_valid(type, optional)) { w->error = 1; return 0; }
    get_copy(w, uuid, type);
    return (luat_ble_uuid_type)type;
}

static void put_attribute(ble_wire_t* w, unsigned type, const uint8_t* uuid,
                          uint16_t handle, uint16_t perm, uint16_t max_size,
                          const uint8_t* value, uint16_t value_len) {
    put_uuid(w, type, uuid, 0);
    put16(w, handle);
    put16(w, perm);
    put16(w, max_size);
    put16(w, value_len);
    put_bytes(w, value, value_len);
}

static void get_attribute(ble_wire_t* w, luat_ble_uuid_type* type, uint8_t* uuid,
                          uint16_t* handle, uint16_t* perm, uint16_t* max_size,
                          uint8_t** value, uint16_t* value_len) {
    *type = get_uuid(w, uuid, 0);
    *handle = (uint16_t)get16(w);
    *perm = (uint16_t)get16(w);
    *max_size = (uint16_t)get16(w);
    *value_len = (uint16_t)get16(w);
    const uint8_t* p = get_bytes(w, *value_len);
    if (!p || !*value_len) return;
    *value = luat_heap_malloc(*value_len);
    if (!*value) { w->error = 1; return; }
    memcpy(*value, p, *value_len);
}

static void put_gatt(ble_wire_t* w, const luat_ble_gatt_service_t* gatt) {
    if (!gatt || (gatt->characteristics_num && !gatt->characteristics)) {
        w->error = 1;
        return;
    }
    put8(w, 1);
    put_uuid(w, gatt->uuid_type, gatt->uuid, 0);
    put8(w, gatt->characteristics_num);
    for (size_t i = 0; !w->error && i < gatt->characteristics_num; i++) {
        const luat_ble_gatt_chara_t* ch = &gatt->characteristics[i];
        put_attribute(w, ch->uuid_type, ch->uuid, ch->handle, ch->perm,
                      ch->max_size, ch->value, ch->value_len);
        put8(w, ch->descriptors_num);
        if (ch->descriptors_num && !ch->descriptor) { w->error = 1; break; }
        for (size_t j = 0; !w->error && j < ch->descriptors_num; j++) {
            const luat_ble_gatt_descriptor_t* d = &ch->descriptor[j];
            put_attribute(w, d->uuid_type, d->uuid, d->handle, d->perm,
                          d->max_size, d->value, d->value_len);
        }
    }
}

void luat_airlink_ble_gatt_free(luat_ble_gatt_service_t* gatt) {
    if (!gatt) return;
    if (gatt->characteristics) {
        for (size_t i = 0; i < gatt->characteristics_num; i++) {
            luat_ble_gatt_chara_t* ch = &gatt->characteristics[i];
            if (ch->descriptor) {
                for (size_t j = 0; j < ch->descriptors_num; j++)
                    luat_heap_free(ch->descriptor[j].value);
                luat_heap_free(ch->descriptor);
            }
            luat_heap_free(ch->value);
        }
        luat_heap_free(gatt->characteristics);
    }
    luat_heap_free(gatt);
}

static luat_ble_gatt_service_t* get_gatt(ble_wire_t* w) {
    if (get8(w) != 1) { w->error = 1; return NULL; }
    luat_ble_gatt_service_t* g = luat_heap_calloc(1, sizeof(*g));
    if (!g) { w->error = 1; return NULL; }
    g->uuid_type = get_uuid(w, g->uuid, 0);
    g->characteristics_num = (uint8_t)get8(w);
    /* Even the smallest characteristic occupies 12 bytes. Check before
     * allocation, so a truncated frame cannot amplify allocation counts. */
    if (g->characteristics_num > (w->size - w->pos) / 12) w->error = 1;
    if (!w->error && g->characteristics_num) {
        g->characteristics = luat_heap_calloc(g->characteristics_num, sizeof(*g->characteristics));
        if (!g->characteristics) w->error = 1;
    }
    for (size_t i = 0; !w->error && i < g->characteristics_num; i++) {
        luat_ble_gatt_chara_t* ch = &g->characteristics[i];
        get_attribute(w, &ch->uuid_type, ch->uuid, &ch->handle, &ch->perm,
                      &ch->max_size, &ch->value, &ch->value_len);
        ch->descriptors_num = (uint8_t)get8(w);
        if (ch->descriptors_num > (w->size - w->pos) / 11) w->error = 1;
        if (!w->error && ch->descriptors_num) {
            ch->descriptor = luat_heap_calloc(ch->descriptors_num, sizeof(*ch->descriptor));
            if (!ch->descriptor) w->error = 1;
        }
        for (size_t j = 0; !w->error && j < ch->descriptors_num; j++) {
            luat_ble_gatt_descriptor_t* d = &ch->descriptor[j];
            get_attribute(w, &d->uuid_type, d->uuid, &d->handle, &d->perm,
                          &d->max_size, &d->value, &d->value_len);
        }
    }
    if (w->error) { luat_airlink_ble_gatt_free(g); return NULL; }
    return g;
}

int luat_airlink_ble_gatt_encode(const luat_ble_gatt_service_t* gatt,
                                uint8_t* data, size_t capacity, size_t* length) {
    if (!data || !length) return -1;
    *length = 0;
    ble_wire_t w = {.out = data, .size = capacity};
    put_gatt(&w, gatt);
    if (w.error) return -1;
    *length = w.pos;
    return 0;
}

int luat_airlink_ble_gatt_decode(const uint8_t* data, size_t length,
                                luat_ble_gatt_service_t** gatt) {
    if (!gatt) return -1;
    *gatt = NULL;
    if (!data || !length) return -1;
    ble_wire_t w = {.in = data, .size = length};
    luat_ble_gatt_service_t* g = get_gatt(&w);
    if (w.error || w.pos != length) { luat_airlink_ble_gatt_free(g); return -1; }
    *gatt = g;
    return 0;
}

static int event_has_param(luat_ble_event_t event) {
    return event >= LUAT_BLE_EVENT_SCAN_REPORT && event < LUAT_BLE_EVENT_MAX;
}

int luat_airlink_ble_event_encode(luat_ble_event_t event, const luat_ble_param_t* p,
                                 uint8_t* data, size_t capacity, size_t* length) {
    if (!data || !length || event <= LUAT_BLE_EVENT_NONE || event >= LUAT_BLE_EVENT_MAX ||
        (event_has_param(event) && !p)) return -1;
    *length = 0;
    ble_wire_t w = {.out = data, .size = capacity};
    put8(&w, 1);
    switch (event) {
    case LUAT_BLE_EVENT_CONN:
        put8(&w, p->conn_ind.peer_addr_type);
        put_bytes(&w, p->conn_ind.peer_addr, 6);
        put8(&w, p->conn_ind.clk_accuracy);
        put16(&w, p->conn_ind.con_interval);
        put16(&w, p->conn_ind.con_latency);
        put16(&w, p->conn_ind.sup_to);
        break;
    case LUAT_BLE_EVENT_DISCONN: put8(&w, p->disconn_ind.reason); break;
    case LUAT_BLE_EVENT_GATT_DONE: put8(&w, p->gatt_done_ind.gatt_service_num); break;
    case LUAT_BLE_EVENT_WRITE:
    case LUAT_BLE_EVENT_READ:
    case LUAT_BLE_EVENT_READ_VALUE: {
        /* Read and write structs have matching fields, but are distinct types. */
        luat_ble_read_req_t r;
        if (event == LUAT_BLE_EVENT_WRITE) {
            r.handle = p->write_req.handle;
            r.uuid_service = p->write_req.uuid_service;
            r.uuid_characteristic = p->write_req.uuid_characteristic;
            r.uuid_descriptor = p->write_req.uuid_descriptor;
            r.value = p->write_req.value;
            r.value_len = p->write_req.value_len;
            r.size = p->write_req.size;
        } else r = p->read_req;
        put16(&w, r.handle);
        put_uuid(&w, r.uuid_service.uuid_type, r.uuid_service.uuid, 1);
        put_uuid(&w, r.uuid_characteristic.uuid_type, r.uuid_characteristic.uuid, 1);
        put_uuid(&w, r.uuid_descriptor.uuid_type, r.uuid_descriptor.uuid, 1);
        put16(&w, r.size);
        put16(&w, r.value_len);
        put_bytes(&w, r.value, r.value_len);
        break;
    }
    case LUAT_BLE_EVENT_SCAN_REPORT:
        put8(&w, p->adv_req.actv_idx);
        put8(&w, p->adv_req.evt_type);
        put8(&w, p->adv_req.adv_addr_type);
        put8(&w, (uint8_t)p->adv_req.rssi);
        put_bytes(&w, p->adv_req.adv_addr, 6);
        put8(&w, p->adv_req.data_len);
        put_bytes(&w, p->adv_req.data, p->adv_req.data_len);
        break;
    case LUAT_BLE_EVENT_GATT_ITEM:
        if (!p->gatt_item_ind.gatt_service_total_num ||
            p->gatt_item_ind.gatt_service_index >= p->gatt_item_ind.gatt_service_total_num)
            return -1;
        put8(&w, p->gatt_item_ind.gatt_service_index);
        put8(&w, p->gatt_item_ind.gatt_service_total_num);
        put_gatt(&w, p->gatt_item_ind.gatt_service);
        break;
    default: break;
    }
    if (w.error) return -1;
    *length = w.pos;
    return 0;
}

void luat_airlink_ble_event_cleanup(luat_ble_event_t event, luat_ble_param_t* p) {
    if (p && event == LUAT_BLE_EVENT_GATT_ITEM) {
        luat_airlink_ble_gatt_free(p->gatt_item_ind.gatt_service);
        p->gatt_item_ind.gatt_service = NULL;
    }
}

int luat_airlink_ble_event_decode(luat_ble_event_t event, const uint8_t* data,
                                 size_t length, luat_ble_param_t* p) {
    if (!p || !data || !length || event <= LUAT_BLE_EVENT_NONE || event >= LUAT_BLE_EVENT_MAX)
        return -1;
    memset(p, 0, sizeof(*p));
    ble_wire_t w = {.in = data, .size = length};
    if (get8(&w) != 1) return -1;
    switch (event) {
    case LUAT_BLE_EVENT_CONN:
        p->conn_ind.peer_addr_type = (uint8_t)get8(&w);
        get_copy(&w, p->conn_ind.peer_addr, 6);
        p->conn_ind.clk_accuracy = (uint8_t)get8(&w);
        p->conn_ind.con_interval = (uint16_t)get16(&w);
        p->conn_ind.con_latency = (uint16_t)get16(&w);
        p->conn_ind.sup_to = (uint16_t)get16(&w);
        break;
    case LUAT_BLE_EVENT_DISCONN: p->disconn_ind.reason = (uint8_t)get8(&w); break;
    case LUAT_BLE_EVENT_GATT_DONE: p->gatt_done_ind.gatt_service_num = (uint8_t)get8(&w); break;
    case LUAT_BLE_EVENT_WRITE:
    case LUAT_BLE_EVENT_READ:
    case LUAT_BLE_EVENT_READ_VALUE: {
        luat_ble_read_req_t r = {0};
        r.handle = (uint16_t)get16(&w);
        r.uuid_service.uuid_type = get_uuid(&w, r.uuid_service.uuid, 1);
        r.uuid_characteristic.uuid_type = get_uuid(&w, r.uuid_characteristic.uuid, 1);
        r.uuid_descriptor.uuid_type = get_uuid(&w, r.uuid_descriptor.uuid, 1);
        r.size = (uint16_t)get16(&w);
        r.value_len = (uint16_t)get16(&w);
        r.value = (uint8_t*)get_bytes(&w, r.value_len);
        if (!r.value_len) r.value = NULL;
        if (event == LUAT_BLE_EVENT_WRITE) {
            p->write_req.handle = r.handle;
            p->write_req.uuid_service = r.uuid_service;
            p->write_req.uuid_characteristic = r.uuid_characteristic;
            p->write_req.uuid_descriptor = r.uuid_descriptor;
            p->write_req.value = r.value;
            p->write_req.value_len = r.value_len;
            p->write_req.size = r.size;
        } else p->read_req = r;
        break;
    }
    case LUAT_BLE_EVENT_SCAN_REPORT:
        p->adv_req.actv_idx = (uint8_t)get8(&w);
        p->adv_req.evt_type = (uint8_t)get8(&w);
        p->adv_req.adv_addr_type = (uint8_t)get8(&w);
        p->adv_req.rssi = (int8_t)get8(&w);
        get_copy(&w, p->adv_req.adv_addr, 6);
        p->adv_req.data_len = (uint8_t)get8(&w);
        p->adv_req.data = (uint8_t*)get_bytes(&w, p->adv_req.data_len);
        if (!p->adv_req.data_len) p->adv_req.data = NULL;
        break;
    case LUAT_BLE_EVENT_GATT_ITEM:
        p->gatt_item_ind.gatt_service_index = (uint8_t)get8(&w);
        p->gatt_item_ind.gatt_service_total_num = (uint8_t)get8(&w);
        if (!p->gatt_item_ind.gatt_service_total_num ||
            p->gatt_item_ind.gatt_service_index >= p->gatt_item_ind.gatt_service_total_num)
            w.error = 1;
        if (!w.error) p->gatt_item_ind.gatt_service = get_gatt(&w);
        break;
    default: break;
    }
    if (w.error || w.pos != length) {
        luat_airlink_ble_event_cleanup(event, p);
        return -1;
    }
    return 0;
}
#endif
