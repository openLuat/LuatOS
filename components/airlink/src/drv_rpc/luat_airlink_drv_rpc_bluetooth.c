#include "luat_base.h"

#if defined(LUAT_USE_AIRLINK_RPC) && defined(LUAT_USE_DRV_BLUETOOTH)
#include "luat_airlink_rpc.h"
#include "luat_airlink_drv_rpc_bluetooth.h"
#include "luat_airlink_ble_wire.h"
#include "drv_bluetooth.pb.h"
#include "luat_drv_ble.h"
#include "luat_rtos.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.drv.bt"
#include "luat_log.h"

/* A teardown can contain several BK command waits. Transport timeout is
 * deliberately longer; a timeout is still an error, never implied success. */
#define BLE_RPC_TIMEOUT_MS 30000
#define BLE_RPC_ID 0x0600

/* Generated init_zero initializes only the first (empty) oneof member. Clear
 * the whole union explicitly before selecting a larger request member. */
#define BLE_RPC_REQUEST \
    drv_bluetooth_BleRpcRequest req; \
    memset(&req, 0, sizeof(req))

static luat_ble_cb_t s_ble_rpc_cb;
static luat_ble_cb_t ble_rpc_callback_swap(luat_ble_cb_t cb) {
    uint32_t critical = luat_rtos_entry_critical();
    luat_ble_cb_t old = s_ble_rpc_cb;
    s_ble_rpc_cb = cb;
    luat_rtos_exit_critical(critical);
    return old;
}
typedef void (*ble_rpc_notify_fn_t)(uint16_t, const void*, void*);
extern void luat_airlink_rpc_ble_set_notify_fn(ble_rpc_notify_fn_t fn);

static void ble_rpc_notify_dispatch(uint16_t rpc_id, const void* raw, void* userdata) {
    (void)rpc_id;
    (void)userdata;
    const drv_bluetooth_BleEventNotify* ev = raw;
    uint32_t critical = luat_rtos_entry_critical();
    luat_ble_cb_t cb = s_ble_rpc_cb;
    luat_rtos_exit_critical(critical);
    if (!cb || !ev->has_packed_data || ev->event_type >= LUAT_BLE_EVENT_MAX) return;
    luat_ble_event_t event = (luat_ble_event_t)ev->event_type;
    luat_ble_param_t param;
    if (luat_airlink_ble_event_decode(event, ev->packed_data.bytes, ev->packed_data.size, &param)) {
        LLOGW("invalid BLE event %u", (unsigned)ev->event_type);
        return;
    }
    /* The callback borrows everything, including the full GATT tree. */
    cb(NULL, event, event >= LUAT_BLE_EVENT_SCAN_REPORT ? &param : NULL);
    luat_airlink_ble_event_cleanup(event, &param);
}

static int ble_rpc_call(drv_bluetooth_BleRpcRequest* req) {
    int mode = luat_airlink_current_mode_get();
    if (mode < 0 || !luat_airlink_peer_rpc_supported()) return -1;
    drv_bluetooth_BleRpcResponse resp = drv_bluetooth_BleRpcResponse_init_zero;
    req->req_id = req->which_payload;
    int rc = luat_airlink_rpc_nb_call((uint8_t)mode, BLE_RPC_ID,
                                    drv_bluetooth_BleRpcRequest_fields, req,
                                    drv_bluetooth_BleRpcResponse_fields, &resp,
                                    BLE_RPC_TIMEOUT_MS);
    if (rc) return rc;
    if (!resp.has_req_id || resp.req_id != req->req_id || !resp.has_status ||
        !resp.has_operation || resp.operation != req->which_payload) return -1;
    return resp.status;
}

static int ble_rpc_empty(pb_size_t tag) {
    BLE_RPC_REQUEST;
    req.which_payload = tag;
    return ble_rpc_call(&req);
}

int luat_airlink_drv_rpc_bluetooth_init(void* args) {
    (void)args;
    return ble_rpc_empty(drv_bluetooth_BleRpcRequest_bluetooth_init_tag);
}

int luat_airlink_drv_rpc_bluetooth_deinit(void* args) {
    (void)args;
    int rc = ble_rpc_empty(drv_bluetooth_BleRpcRequest_bluetooth_deinit_tag);
    if (!rc) ble_rpc_callback_swap(NULL);
    return rc;
}

int luat_airlink_drv_rpc_ble_init(luat_ble_t* ble, luat_ble_cb_t cb) {
    (void)ble;
    if (!cb) return -1;
    luat_ble_cb_t previous = ble_rpc_callback_swap(cb);
    luat_airlink_rpc_ble_set_notify_fn(ble_rpc_notify_dispatch);
    int rc = ble_rpc_empty(drv_bluetooth_BleRpcRequest_init_tag);
    if (rc) ble_rpc_callback_swap(previous);
    return rc;
}

int luat_airlink_drv_rpc_ble_deinit(luat_ble_t* ble) {
    (void)ble;
    int rc = ble_rpc_empty(drv_bluetooth_BleRpcRequest_deinit_tag);
    if (!rc) ble_rpc_callback_swap(NULL);
    return rc;
}

int luat_airlink_drv_rpc_ble_set_name(luat_ble_t* ble, char* name, uint8_t len) {
    (void)ble;
    BLE_RPC_REQUEST;
    if (len > sizeof(req.payload.set_name.name.bytes) || (len && !name)) return -1;
    req.which_payload = drv_bluetooth_BleRpcRequest_set_name_tag;
    req.payload.set_name.name.size = len;
    if (len) memcpy(req.payload.set_name.name.bytes, name, len);
    return ble_rpc_call(&req);
}

int luat_airlink_drv_rpc_ble_set_max_mtu(luat_ble_t* ble, uint16_t mtu) {
    (void)ble;
    BLE_RPC_REQUEST;
    req.which_payload = drv_bluetooth_BleRpcRequest_set_max_mtu_tag;
    req.payload.set_max_mtu.max_mtu = mtu;
    return ble_rpc_call(&req);
}

int luat_airlink_drv_rpc_ble_create_advertising(luat_ble_t* ble, luat_ble_adv_cfg_t* cfg) {
    (void)ble;
    BLE_RPC_REQUEST;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_create_tag;
    if (cfg) {
        drv_bluetooth_BleAdvCfg* c = &req.payload.adv_create.cfg;
        req.payload.adv_create.has_cfg = true;
        c->has_channel_map = c->has_addr_mode = c->has_intv_min = true;
        c->has_intv_max = c->has_adv_prop = c->has_adv_type = true;
        c->channel_map = cfg->channel_map;
        c->addr_mode = cfg->addr_mode;
        c->intv_min = cfg->intv_min;
        c->intv_max = cfg->intv_max;
        c->adv_prop = cfg->adv_prop;
        c->adv_type = cfg->adv_type;
    }
    return ble_rpc_call(&req);
}

int luat_airlink_drv_rpc_ble_set_adv_data(luat_ble_t* ble, uint8_t* data, uint8_t len) {
    (void)ble;
    BLE_RPC_REQUEST;
    if (len > sizeof(req.payload.adv_set_data.data.bytes) || (len && !data)) return -1;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_set_data_tag;
    req.payload.adv_set_data.data.size = len;
    if (len) memcpy(req.payload.adv_set_data.data.bytes, data, len);
    return ble_rpc_call(&req);
}

int luat_airlink_drv_rpc_ble_set_scan_rsp_data(luat_ble_t* ble, uint8_t* data, uint8_t len) {
    (void)ble;
    BLE_RPC_REQUEST;
    if (len > sizeof(req.payload.adv_set_scan_rsp.data.bytes) || (len && !data)) return -1;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_set_scan_rsp_tag;
    req.payload.adv_set_scan_rsp.data.size = len;
    if (len) memcpy(req.payload.adv_set_scan_rsp.data.bytes, data, len);
    return ble_rpc_call(&req);
}

#define BLE_EMPTY_API(name, tag) \
    int luat_airlink_drv_rpc_ble_##name(luat_ble_t* ble) { \
        (void)ble; return ble_rpc_empty(drv_bluetooth_BleRpcRequest_##tag##_tag); \
    }
BLE_EMPTY_API(start_advertising, adv_start)
BLE_EMPTY_API(stop_advertising, adv_stop)
BLE_EMPTY_API(delete_advertising, adv_delete)
BLE_EMPTY_API(start_scanning, scan_start)
BLE_EMPTY_API(stop_scanning, scan_stop)
BLE_EMPTY_API(delete_scanning, scan_delete)
#undef BLE_EMPTY_API

int luat_airlink_drv_rpc_ble_create_gatt(luat_ble_t* ble, luat_ble_gatt_service_t* gatt) {
    (void)ble;
    BLE_RPC_REQUEST;
    req.which_payload = drv_bluetooth_BleRpcRequest_gatt_create_tag;
    size_t len = 0;
    if (luat_airlink_ble_gatt_encode(gatt, req.payload.gatt_create.packed_gatt.bytes,
                                   sizeof(req.payload.gatt_create.packed_gatt.bytes), &len)) return -1;
    req.payload.gatt_create.packed_gatt.size = (pb_size_t)len;
    return ble_rpc_call(&req);
}

int luat_airlink_drv_rpc_ble_create_scanning(luat_ble_t* ble, luat_ble_scan_cfg_t* cfg) {
    (void)ble;
    BLE_RPC_REQUEST;
    req.which_payload = drv_bluetooth_BleRpcRequest_scan_create_tag;
    if (cfg) {
        drv_bluetooth_BleScanCfg* c = &req.payload.scan_create.cfg;
        req.payload.scan_create.has_cfg = true;
        c->has_scan_type = c->has_addr_mode = c->has_scan_interval = c->has_scan_window = true;
        c->scan_type = cfg->scan_type;
        c->addr_mode = cfg->addr_mode;
        c->scan_interval = cfg->scan_interval;
        c->scan_window = cfg->scan_window;
    }
    return ble_rpc_call(&req);
}

int luat_airlink_drv_rpc_ble_connect(void* args, luat_ble_connect_req_t* conn) {
    (void)args;
    if (!conn) return -1;
    BLE_RPC_REQUEST;
    req.which_payload = drv_bluetooth_BleRpcRequest_connect_tag;
    req.payload.connect.address.size = 6;
    memcpy(req.payload.connect.address.bytes, conn->adv_addr, 6);
    req.payload.connect.address_type = conn->adv_addr_type;
    req.payload.connect.interval = conn->conn_interval;
    req.payload.connect.latency = conn->conn_latency;
    req.payload.connect.timeout = conn->sup_to;
    return ble_rpc_call(&req);
}

int luat_airlink_drv_rpc_ble_disconnect(void* args) {
    (void)args;
    return ble_rpc_empty(drv_bluetooth_BleRpcRequest_disconnect_tag);
}

int luat_airlink_drv_rpc_ble_value(uint16_t operation, luat_ble_uuid_t* svc,
                                  luat_ble_uuid_t* chr, luat_ble_uuid_t* desc,
                                  uint8_t* data, uint16_t len, uint8_t enable) {
    BLE_RPC_REQUEST;
    drv_bluetooth_BleValueRequest* r = &req.payload.value;
    if (!svc || !chr || !luat_airlink_ble_uuid_valid(svc->uuid_type, 0) ||
        !luat_airlink_ble_uuid_valid(chr->uuid_type, 0) ||
        (desc && !luat_airlink_ble_uuid_valid(desc->uuid_type, 1)) ||
        len > sizeof(r->data.bytes) || (len && !data) || enable > 1) return -1;
    switch (operation) {
    case LUAT_DRV_BT_CMD_BLE_WRITE_VALUE:
    case LUAT_DRV_BT_CMD_BLE_WRITE_NOTIFY:
    case LUAT_DRV_BT_CMD_BLE_WRITE_INDICATION: break;
    case LUAT_DRV_BT_CMD_BLE_READ_VALUE:
    case LUAT_DRV_BT_CMD_BLE_NOTIFY_ENABLE:
    case LUAT_DRV_BT_CMD_BLE_INDICATE_ENABLE:
        if (len) return -1;
        break;
    default: return -1;
    }
    req.which_payload = drv_bluetooth_BleRpcRequest_value_tag;
    r->operation = operation;
    r->service.size = (pb_size_t)svc->uuid_type;
    memcpy(r->service.bytes, svc->uuid, r->service.size);
    r->characteristic.size = (pb_size_t)chr->uuid_type;
    memcpy(r->characteristic.bytes, chr->uuid, r->characteristic.size);
    if (desc) {
        r->descriptor.size = (pb_size_t)desc->uuid_type;
        memcpy(r->descriptor.bytes, desc->uuid, r->descriptor.size);
    }
    r->enable = enable != 0;
    r->data.size = len;
    if (len) memcpy(r->data.bytes, data, len);
    return ble_rpc_call(&req);
}

/* Compatibility entry points for the older handle-based drv API. */
int luat_airlink_drv_rpc_ble_read_response_value(luat_ble_t* ble, uint8_t conn_idx,
                                                uint16_t service_id, uint16_t handle,
                                                uint8_t* data, uint32_t len) {
    (void)ble; (void)conn_idx; (void)service_id; (void)handle; (void)data; (void)len;
    /* No backend API exists: never acknowledge an unimplemented operation. */
    return -1;
}

int luat_airlink_drv_rpc_ble_write_notify_value(luat_ble_t* ble, uint8_t conn_idx,
                                               uint16_t service_id, uint16_t handle,
                                               uint8_t* data, uint16_t len) {
    (void)ble;
    BLE_RPC_REQUEST;
    if (len > sizeof(req.payload.write_notify.data.bytes) || (len && !data)) return -1;
    req.which_payload = drv_bluetooth_BleRpcRequest_write_notify_tag;
    req.payload.write_notify.conn_idx = conn_idx;
    req.payload.write_notify.service_id = service_id;
    req.payload.write_notify.att_handle = handle;
    req.payload.write_notify.data.size = len;
    if (len) memcpy(req.payload.write_notify.data.bytes, data, len);
    return ble_rpc_call(&req);
}
#endif
