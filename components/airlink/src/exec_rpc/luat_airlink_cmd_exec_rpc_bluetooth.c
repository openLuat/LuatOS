#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC
#include "luat_airlink_rpc.h"
#include "drv_bluetooth.pb.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "airlink.rpc.bt"
#include "luat_log.h"

#define AIRLINK_RPC_ID_BT 0x0600
#define AIRLINK_RPC_ID_BT_EVENT 0x0601

typedef void (*ble_rpc_notify_fn_t)(uint16_t, const void*, void*);
static ble_rpc_notify_fn_t s_client_notify_fn;

void luat_airlink_rpc_ble_set_notify_fn(ble_rpc_notify_fn_t fn) {
    uint32_t critical = luat_rtos_entry_critical();
    s_client_notify_fn = fn;
    luat_rtos_exit_critical(critical);
}

static void ble_rpc_event_recv_handler(uint16_t rpc_id, const void* msg, void* userdata) {
    uint32_t critical = luat_rtos_entry_critical();
    ble_rpc_notify_fn_t fn = s_client_notify_fn;
    luat_rtos_exit_critical(critical);
    if (fn) fn(rpc_id, msg, userdata);
}

static void ble_rpc_result(const drv_bluetooth_BleRpcRequest* req,
                            drv_bluetooth_BleRpcResponse* resp, int status) {
    resp->has_req_id = resp->has_status = resp->has_operation = true;
    resp->req_id = req->req_id;
    resp->operation = req->which_payload;
    resp->status = status;
}

#ifdef LUAT_USE_AIRLINK_EXEC_BLUETOOTH
#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_drv_ble.h"
#include "luat_airlink_ble_wire.h"

/* Only the worker calls BLE APIs. BK command callbacks must be able to run
 * while these APIs wait for completion. No callback sends RPC or waits. */
typedef struct {
    const drv_bluetooth_BleRpcRequest* req;
    drv_bluetooth_BleRpcResponse* resp;
    luat_rtos_semaphore_t done;
} ble_rpc_job_t;

typedef struct {
    uint16_t event_type;
    uint16_t length;
    uint8_t data[];
} ble_rpc_event_t;

typedef struct {
    ble_rpc_job_t* job;
    ble_rpc_event_t* event;
} ble_rpc_work_t;

static luat_rtos_queue_t s_ble_queue;
static luat_rtos_task_handle s_ble_worker;
static luat_ble_t s_ble_handle;
static luat_ble_gatt_service_t* s_owned_gatt[32];
static size_t s_owned_count;

/* Budget includes snapshot headers; no scan burst can consume all BK heap. */
#define BLE_EVENT_BUDGET (12 * 1024)
static volatile long s_event_bytes;
#ifdef _MSC_VER
#include <windows.h>
#define BLE_BYTES_CAS(old, value) InterlockedCompareExchange(&s_event_bytes, (value), (old))
#define BLE_BYTES_SUB(value) InterlockedExchangeAdd(&s_event_bytes, -(long)(value))
#else
#define BLE_BYTES_CAS(old, value) __sync_val_compare_and_swap(&s_event_bytes, (old), (value))
#define BLE_BYTES_SUB(value) __sync_fetch_and_sub(&s_event_bytes, (long)(value))
#endif

static int ble_rpc_event_reserve(size_t bytes) {
    long used;
    do {
        used = BLE_BYTES_CAS(0, 0);
        if (bytes > BLE_EVENT_BUDGET - (size_t)used) return -1;
    } while (BLE_BYTES_CAS(used, used + (long)bytes) != used);
    return 0;
}

static void ble_rpc_event_free(ble_rpc_event_t* event) {
    BLE_BYTES_SUB(sizeof(*event) + event->length);
    luat_heap_free(event);
}

static void ble_rpc_free_gatts(void) {
    for (size_t i = 0; i < s_owned_count; i++) {
        luat_airlink_ble_gatt_free(s_owned_gatt[i]);
        s_owned_gatt[i] = NULL;
    }
    s_owned_count = 0;
}

static int ble_rpc_queue_event(luat_ble_event_t event, const luat_ble_param_t* param) {
    if (!s_ble_queue) return -1;
    /* Encode off the BK callback stack, then retain only the used bytes. */
    size_t capacity = sizeof(((drv_bluetooth_BleEventNotify*)0)->packed_data.bytes);
    uint8_t* snapshot = luat_heap_malloc(capacity);
    if (!snapshot) return -1;
    size_t len = 0;
    if (luat_airlink_ble_event_encode(event, param, snapshot, capacity, &len) ||
        ble_rpc_event_reserve(sizeof(ble_rpc_event_t) + len)) {
        luat_heap_free(snapshot);
        return -1;
    }
    ble_rpc_event_t* ev = luat_heap_malloc(sizeof(*ev) + len);
    if (!ev) {
        BLE_BYTES_SUB(sizeof(*ev) + len);
        luat_heap_free(snapshot);
        return -1;
    }
    ev->event_type = event;
    ev->length = (uint16_t)len;
    memcpy(ev->data, snapshot, len);
    luat_heap_free(snapshot);
    ble_rpc_work_t work = {.event = ev};
    if (luat_rtos_queue_send(s_ble_queue, &work, sizeof(work), LUAT_NO_WAIT)) {
        ble_rpc_event_free(ev);
        return -1;
    }
    return 0;
}

static void ble_rpc_event_cb(luat_ble_t* ble, luat_ble_event_t event, luat_ble_param_t* param) {
    (void)ble;
    /* Copies every pointed-to byte (including GATT_ITEM's entire tree) before
     * returning to BK, whose stack/local objects are all borrowed. */
    if (ble_rpc_queue_event(event, param)) LLOGW("BLE event queue/encode failed: %d", event);
}

static int ble_rpc_value(const drv_bluetooth_BleValueRequest* r) {
    if (!luat_airlink_ble_uuid_valid(r->service.size, 0) ||
        !luat_airlink_ble_uuid_valid(r->characteristic.size, 0) ||
        !luat_airlink_ble_uuid_valid(r->descriptor.size, 1) ||
        r->data.size > sizeof(r->data.bytes)) return -1;
    luat_ble_uuid_t svc = {0}, chr = {0}, desc = {0};
    svc.uuid_type = (luat_ble_uuid_type)r->service.size;
    chr.uuid_type = (luat_ble_uuid_type)r->characteristic.size;
    desc.uuid_type = (luat_ble_uuid_type)r->descriptor.size;
    memcpy(svc.uuid, r->service.bytes, r->service.size);
    memcpy(chr.uuid, r->characteristic.bytes, r->characteristic.size);
    memcpy(desc.uuid, r->descriptor.bytes, r->descriptor.size);
    luat_ble_uuid_t* d = r->descriptor.size ? &desc : NULL;
    uint8_t* data = (uint8_t*)r->data.bytes;
    uint16_t len = (uint16_t)r->data.size;
    switch (r->operation) {
    case LUAT_DRV_BT_CMD_BLE_WRITE_VALUE:
        return luat_ble_write_value(&svc, &chr, d, data, len);
    case LUAT_DRV_BT_CMD_BLE_WRITE_NOTIFY:
        return luat_ble_write_notify_value(&svc, &chr, d, data, len);
    case LUAT_DRV_BT_CMD_BLE_WRITE_INDICATION:
        return luat_ble_write_indicate_value(&svc, &chr, d, data, len);
    case LUAT_DRV_BT_CMD_BLE_READ_VALUE: {
        if (len) return -1;
        uint8_t* value = NULL;
        uint16_t value_len = 0;
        int ret = luat_ble_read_value(&svc, &chr, d, &value, &value_len);
        /* Central reads arrive asynchronously. Local peripheral reads return
         * borrowed storage, including a valid empty value. Normalize to event. */
        if (!ret && luat_ble_get_mode(NULL) != LUAT_BLE_MODE_MASTER) {
            luat_ble_param_t p = {0};
            p.read_req.uuid_service = svc;
            p.read_req.uuid_characteristic = chr;
            p.read_req.uuid_descriptor = desc;
            p.read_req.value = value;
            p.read_req.value_len = value_len;
            p.read_req.size = value_len;
            ret = luat_ble_uuid2handle(&svc, &chr, d, &p.read_req.handle);
            if (!ret) ret = ble_rpc_queue_event(LUAT_BLE_EVENT_READ_VALUE, &p);
        }
        return ret;
    }
    case LUAT_DRV_BT_CMD_BLE_NOTIFY_ENABLE:
        if (len || d) return -1;
        return luat_ble_notify_enable(&svc, &chr, r->enable);
    case LUAT_DRV_BT_CMD_BLE_INDICATE_ENABLE:
        if (len || d) return -1;
        return luat_ble_indicate_enable(&svc, &chr, r->enable);
    default: return -1;
    }
}

static int ble_rpc_execute(const drv_bluetooth_BleRpcRequest* req) {
    switch (req->which_payload) {
    case drv_bluetooth_BleRpcRequest_bluetooth_init_tag:
        return luat_bluetooth_init(NULL);
    case drv_bluetooth_BleRpcRequest_bluetooth_deinit_tag: {
        int ret = luat_bluetooth_deinit(NULL);
        if (!ret) ble_rpc_free_gatts();
        return ret;
    }
    case drv_bluetooth_BleRpcRequest_init_tag:
        return luat_ble_init(&s_ble_handle, ble_rpc_event_cb);
    case drv_bluetooth_BleRpcRequest_deinit_tag: {
        int ret = luat_ble_deinit(&s_ble_handle);
        if (!ret) ble_rpc_free_gatts();
        return ret;
    }
    case drv_bluetooth_BleRpcRequest_set_name_tag: {
        const drv_bluetooth_BleSetNameRequest* r = &req->payload.set_name;
        char name[sizeof(r->name.bytes) + 1];
        if (r->name.size > sizeof(r->name.bytes)) return -1;
        memcpy(name, r->name.bytes, r->name.size);
        name[r->name.size] = 0;
        return luat_ble_set_name(&s_ble_handle, name, (uint8_t)r->name.size);
    }
    case drv_bluetooth_BleRpcRequest_set_max_mtu_tag:
        if (req->payload.set_max_mtu.max_mtu > UINT16_MAX) return -1;
        return luat_ble_set_max_mtu(&s_ble_handle, (uint16_t)req->payload.set_max_mtu.max_mtu);
    case drv_bluetooth_BleRpcRequest_adv_create_tag: {
        const drv_bluetooth_BleAdvCreateRequest* r = &req->payload.adv_create;
        luat_ble_adv_cfg_t cfg = {
            .channel_map = LUAT_BLE_ADV_CHNLS_ALL, .addr_mode = LUAT_BLE_ADDR_MODE_PUBLIC,
            .intv_min = 160, .intv_max = 160, .adv_prop = 0, .adv_type = LUAT_BLE_ADV_TYPE_LEGACY
        };
        if (r->has_cfg) {
            const drv_bluetooth_BleAdvCfg* c = &r->cfg;
            if ((c->has_channel_map && c->channel_map > 7) ||
                (c->has_addr_mode && c->addr_mode > LUAT_BLE_ADDR_MODE_NRPA) ||
                (c->has_adv_prop && c->adv_prop > UINT8_MAX) ||
                (c->has_adv_type && c->adv_type > LUAT_BLE_ADV_PERIODIC)) return -1;
            if (c->has_channel_map) cfg.channel_map = (luat_ble_adv_chnl_t)c->channel_map;
            if (c->has_addr_mode) cfg.addr_mode = (luat_ble_addr_mode_t)c->addr_mode;
            if (c->has_intv_min) cfg.intv_min = c->intv_min;
            if (c->has_intv_max) cfg.intv_max = c->intv_max;
            if (c->has_adv_prop) cfg.adv_prop = (uint8_t)c->adv_prop;
            if (c->has_adv_type) cfg.adv_type = (uint8_t)c->adv_type;
        }
        return luat_ble_create_advertising(&s_ble_handle, &cfg);
    }
    case drv_bluetooth_BleRpcRequest_adv_set_data_tag: {
        const drv_bluetooth_BleAdvSetDataRequest* r = &req->payload.adv_set_data;
        if (r->data.size > sizeof(r->data.bytes)) return -1;
        return luat_ble_set_adv_data(&s_ble_handle, (uint8_t*)r->data.bytes, (uint8_t)r->data.size);
    }
    case drv_bluetooth_BleRpcRequest_adv_set_scan_rsp_tag: {
        const drv_bluetooth_BleAdvSetScanRspRequest* r = &req->payload.adv_set_scan_rsp;
        if (r->data.size > sizeof(r->data.bytes)) return -1;
        return luat_ble_set_scan_rsp_data(&s_ble_handle, (uint8_t*)r->data.bytes, (uint8_t)r->data.size);
    }
    case drv_bluetooth_BleRpcRequest_adv_start_tag: return luat_ble_start_advertising(&s_ble_handle);
    case drv_bluetooth_BleRpcRequest_adv_stop_tag: return luat_ble_stop_advertising(&s_ble_handle);
    case drv_bluetooth_BleRpcRequest_adv_delete_tag: return luat_ble_delete_advertising(&s_ble_handle);
    case drv_bluetooth_BleRpcRequest_gatt_create_tag: {
        const drv_bluetooth_BleGattCreateRequest* r = &req->payload.gatt_create;
        if (s_owned_count >= sizeof(s_owned_gatt) / sizeof(s_owned_gatt[0]) ||
            r->packed_gatt.size > sizeof(r->packed_gatt.bytes)) return -1;
        luat_ble_gatt_service_t* gatt = NULL;
        if (luat_airlink_ble_gatt_decode(r->packed_gatt.bytes, r->packed_gatt.size, &gatt)) return -1;
        /* Install ownership BEFORE calling BK. Even failure/timeout may leave
         * references in the stack. Retain until a successful teardown barrier. */
        s_owned_gatt[s_owned_count++] = gatt;
        return luat_ble_create_gatt(&s_ble_handle, gatt);
    }
    case drv_bluetooth_BleRpcRequest_read_response_tag:
        return -1; /* No corresponding backend API. */
    case drv_bluetooth_BleRpcRequest_write_notify_tag: {
        const drv_bluetooth_BleWriteNotifyRequest* r = &req->payload.write_notify;
        if (r->att_handle > UINT16_MAX || r->data.size > sizeof(r->data.bytes)) return -1;
        luat_ble_uuid_t svc = {0}, chr = {0}, desc = {0};
        int ret = luat_ble_handle2uuid((uint16_t)r->att_handle, &svc, &chr, &desc);
        if (ret) return ret;
        return luat_ble_write_notify_value(&svc, &chr, desc.uuid_type ? &desc : NULL,
                                          (uint8_t*)r->data.bytes, (uint16_t)r->data.size);
    }
    case drv_bluetooth_BleRpcRequest_scan_create_tag: {
        const drv_bluetooth_BleScanCreateRequest* r = &req->payload.scan_create;
        luat_ble_scan_cfg_t cfg = {
            .scan_type = LUAT_BLE_PASSIVE_SCANNING, .addr_mode = LUAT_BLE_ADDR_MODE_PUBLIC,
            .scan_interval = 16, .scan_window = 16
        };
        if (r->has_cfg) {
            const drv_bluetooth_BleScanCfg* c = &r->cfg;
            if ((c->has_scan_type && c->scan_type > LUAT_BLE_ACTIVE_SCANNING) ||
                (c->has_addr_mode && c->addr_mode > LUAT_BLE_ADDR_MODE_NRPA) ||
                (c->has_scan_interval && c->scan_interval > UINT16_MAX) ||
                (c->has_scan_window && c->scan_window > UINT16_MAX)) return -1;
            if (c->has_scan_type) cfg.scan_type = (luat_ble_scan_type_t)c->scan_type;
            if (c->has_addr_mode) cfg.addr_mode = (luat_ble_addr_mode_t)c->addr_mode;
            if (c->has_scan_interval) cfg.scan_interval = (uint16_t)c->scan_interval;
            if (c->has_scan_window) cfg.scan_window = (uint16_t)c->scan_window;
        }
        return luat_ble_create_scanning(&s_ble_handle, &cfg);
    }
    case drv_bluetooth_BleRpcRequest_scan_start_tag: return luat_ble_start_scanning(&s_ble_handle);
    case drv_bluetooth_BleRpcRequest_scan_stop_tag: return luat_ble_stop_scanning(&s_ble_handle);
    case drv_bluetooth_BleRpcRequest_scan_delete_tag: return luat_ble_delete_scanning(&s_ble_handle);
    case drv_bluetooth_BleRpcRequest_connect_tag: {
        const drv_bluetooth_BleConnectRequest* r = &req->payload.connect;
        if (r->address.size != 6 || r->address_type > 1 || r->interval > UINT16_MAX ||
            r->latency > UINT16_MAX || r->timeout > UINT16_MAX) return -1;
        luat_ble_connect_req_t conn = {0};
        memcpy(conn.adv_addr, r->address.bytes, 6);
        conn.adv_addr_type = (uint8_t)r->address_type;
        conn.conn_interval = (uint16_t)r->interval;
        conn.conn_latency = (uint16_t)r->latency;
        conn.sup_to = (uint16_t)r->timeout;
        return luat_ble_connect(&s_ble_handle, &conn);
    }
    case drv_bluetooth_BleRpcRequest_disconnect_tag: return luat_ble_disconnect(&s_ble_handle);
    case drv_bluetooth_BleRpcRequest_value_tag: return ble_rpc_value(&req->payload.value);
    default: return -1;
    }
}

static void ble_rpc_send_event(ble_rpc_event_t* event) {
    drv_bluetooth_BleEventNotify notify = drv_bluetooth_BleEventNotify_init_zero;
    notify.event_type = event->event_type;
    notify.has_packed_data = true;
    notify.packed_data.size = event->length;
    memcpy(notify.packed_data.bytes, event->data, event->length);
    int mode = luat_airlink_current_mode_get();
    int rc = mode < 0 ? -1 : luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_RPC_ID_BT_EVENT,
                                                      drv_bluetooth_BleEventNotify_fields, &notify);
    if (rc) LLOGW("BLE event send failed: %d", rc);
    ble_rpc_event_free(event);
}

static void ble_rpc_worker(void* args) {
    (void)args;
    ble_rpc_work_t work;
    int pending = 0;
    for (;;) {
        if (!pending && luat_rtos_queue_recv(s_ble_queue, &work, sizeof(work), LUAT_WAIT_FOREVER)) continue;
        pending = 0;
        if (work.event) {
            ble_rpc_send_event(work.event);
            continue;
        }
        ble_rpc_job_t* job = work.job;
        int ret = ble_rpc_execute(job->req);
        ble_rpc_result(job->req, job->resp, ret);
        /* Queue command-generated events before the response. This preserves
         * INIT/DEINIT ordering during role switches. Bound draining so scan
         * reports cannot starve the synchronous response. */
        uint32_t count = 0;
        luat_rtos_queue_get_cnt(s_ble_queue, &count);
        while (count-- && !luat_rtos_queue_recv(s_ble_queue, &work, sizeof(work), LUAT_NO_WAIT)) {
            if (work.job) { pending = 1; break; }
            ble_rpc_send_event(work.event);
        }
        luat_rtos_semaphore_release(job->done);
        /* No access to job after release: the dispatcher owns it. */
    }
}

/* Called only by the serialized AirLink request dispatcher, never callbacks. */
static int ble_rpc_handler(uint16_t rpc_id, const void* raw, void* response, void* userdata) {
    (void)rpc_id; (void)userdata;
    const drv_bluetooth_BleRpcRequest* req = raw;
    drv_bluetooth_BleRpcResponse* resp = response;
    if (!s_ble_worker) {
        if (luat_rtos_queue_create(&s_ble_queue, 64, sizeof(ble_rpc_work_t))) {
            ble_rpc_result(req, resp, -1);
            return 0;
        }
        if (luat_rtos_task_create(&s_ble_worker, 6144, 50, "airlink_ble", ble_rpc_worker, NULL, 0)) {
            luat_rtos_queue_delete(s_ble_queue);
            s_ble_queue = NULL;
            s_ble_worker = NULL;
            ble_rpc_result(req, resp, -1);
            return 0;
        }
    }
    ble_rpc_job_t job = {.req = req, .resp = resp};
    if (luat_rtos_semaphore_create(&job.done, 0)) {
        ble_rpc_result(req, resp, -1);
        return 0;
    }
    /* Some FreeRTOS ports create a signaled binary semaphore for count=0.
     * Drain before publishing the borrowed stack job to the worker. */
    luat_rtos_semaphore_take(job.done, LUAT_NO_WAIT);
    ble_rpc_work_t work = {.job = &job};
    if (luat_rtos_queue_send(s_ble_queue, &work, sizeof(work), LUAT_NO_WAIT)) {
        ble_rpc_result(req, resp, -1);
    } else {
        /* Backend waits are bounded. Never abandon borrowed req/resp/job on
         * a local timeout: they must remain alive until the worker is done. */
        while (luat_rtos_semaphore_take(job.done, LUAT_WAIT_FOREVER)) {}
    }
    luat_rtos_semaphore_delete(job.done);
    return 0;
}
#else
static int ble_rpc_handler(uint16_t rpc_id, const void* req, void* resp, void* userdata) {
    (void)rpc_id; (void)userdata;
    ble_rpc_result(req, resp, -1);
    return 0;
}
#endif

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_bluetooth_reg = {
    .rpc_id = AIRLINK_RPC_ID_BT, .active = 1,
    .req_desc = drv_bluetooth_BleRpcRequest_fields,
    .req_size = sizeof(drv_bluetooth_BleRpcRequest),
    .resp_desc = drv_bluetooth_BleRpcResponse_fields,
    .resp_size = sizeof(drv_bluetooth_BleRpcResponse),
    .handler = ble_rpc_handler,
};

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_bluetooth_event_reg = {
    .rpc_id = AIRLINK_RPC_ID_BT_EVENT, .active = 1,
    .req_desc = drv_bluetooth_BleEventNotify_fields,
    .req_size = sizeof(drv_bluetooth_BleEventNotify),
    .notify_handler = ble_rpc_event_recv_handler,
};
#endif
