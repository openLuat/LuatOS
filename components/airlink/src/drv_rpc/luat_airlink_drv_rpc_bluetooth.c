#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC_BLUETOOTH

#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_mem.h"
#include "drv_bluetooth.pb.h"
#include "luat_ble.h"
#include "luat_bt.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.drv.bt"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...)

#define AIRLINK_DRV_RPC_ID_BT  0x0600

#ifndef ENOMEM
#define ENOMEM 12
#endif

/* 用户通过 luat_airlink_drv_rpc_ble_init 注册的 BLE 事件回调 */
static luat_ble_cb_t s_ble_rpc_cb = NULL;

/* GATT 服务缓存，用于 GATT_ITEM 事件重建 */
static luat_ble_gatt_service_t* s_gatts[16];

/* ---------- 事件接收处理器 (void return, matches notify_handler type) ---------- */

static void ble_rpc_notify_dispatch(uint16_t rpc_id, const void* msg_raw, void* userdata) {
    (void)rpc_id; (void)userdata;
    if (s_ble_rpc_cb == NULL) return;

    const drv_bluetooth_BleEventNotify* ev = (const drv_bluetooth_BleEventNotify*)msg_raw;
    luat_ble_event_t event = (luat_ble_event_t)ev->event_type;

    const uint8_t* data     = ev->has_packed_data ? ev->packed_data.bytes : NULL;
    pb_size_t      data_len = ev->has_packed_data ? ev->packed_data.size  : 0;

    luat_ble_param_t param;
    memset(&param, 0, sizeof(param));

    switch (event) {
    case LUAT_BLE_EVENT_CONN:
        if (data_len >= (pb_size_t)sizeof(luat_ble_conn_ind_t))
            memcpy(&param.conn_ind, data, sizeof(luat_ble_conn_ind_t));
        s_ble_rpc_cb(NULL, event, &param);
        break;

    case LUAT_BLE_EVENT_DISCONN:
        if (data_len >= (pb_size_t)sizeof(luat_ble_disconn_ind_t))
            memcpy(&param.disconn_ind, data, sizeof(luat_ble_disconn_ind_t));
        s_ble_rpc_cb(NULL, event, &param);
        break;

    case LUAT_BLE_EVENT_GATT_DONE:
        if (data_len >= (pb_size_t)sizeof(luat_ble_gatt_done_ind_t))
            memcpy(&param.gatt_done_ind, data, sizeof(luat_ble_gatt_done_ind_t));
        s_ble_rpc_cb(NULL, event, &param);
        break;

    case LUAT_BLE_EVENT_WRITE:
        if (data_len >= (pb_size_t)sizeof(luat_ble_write_req_t)) {
            memcpy(&param.write_req, data, sizeof(luat_ble_write_req_t));
            if (param.write_req.value_len > 0 &&
                data_len >= (pb_size_t)(sizeof(luat_ble_write_req_t) + param.write_req.value_len)) {
                param.write_req.value = (uint8_t*)(data + sizeof(luat_ble_write_req_t));
            }
        }
        s_ble_rpc_cb(NULL, event, &param);
        break;

    case LUAT_BLE_EVENT_READ:
        if (data_len >= (pb_size_t)sizeof(luat_ble_read_req_t))
            memcpy(&param.read_req, data, sizeof(luat_ble_read_req_t));
        s_ble_rpc_cb(NULL, event, &param);
        break;

    case LUAT_BLE_EVENT_READ_VALUE:
        if (data_len >= (pb_size_t)sizeof(luat_ble_read_req_t)) {
            memcpy(&param.read_req, data, sizeof(luat_ble_read_req_t));
            if (param.read_req.value_len > 0 &&
                data_len >= (pb_size_t)(sizeof(luat_ble_read_req_t) + param.read_req.value_len)) {
                param.read_req.value = (uint8_t*)(data + sizeof(luat_ble_read_req_t));
            }
        }
        s_ble_rpc_cb(NULL, event, &param);
        break;

    case LUAT_BLE_EVENT_SCAN_REPORT:
        if (data_len >= (pb_size_t)sizeof(luat_ble_adv_req_t)) {
            memcpy(&param.adv_req, data, sizeof(luat_ble_adv_req_t));
            if (param.adv_req.data_len > 0 &&
                data_len >= (pb_size_t)(sizeof(luat_ble_adv_req_t) + param.adv_req.data_len)) {
                param.adv_req.data = (uint8_t*)(data + sizeof(luat_ble_adv_req_t));
            }
        }
        s_ble_rpc_cb(NULL, event, &param);
        break;

    case LUAT_BLE_EVENT_GATT_ITEM: {
        if (data_len < 2) break;
        uint8_t idx   = data[0];
        uint8_t total = data[1];
        if (idx >= 16) {
            LLOGE("gatt item index %d out of range", (int)idx);
            break;
        }
        if (s_gatts[idx] != NULL) {
            luat_ble_gatt_service_t* g = s_gatts[idx];
            for (size_t ch = 0; ch < g->characteristics_num; ch++) {
                if (g->characteristics[ch].descriptor)
                    luat_heap_free(g->characteristics[ch].descriptor);
            }
            if (g->characteristics) luat_heap_free(g->characteristics);
            memset(g, 0, sizeof(*g));
        } else {
            s_gatts[idx] = (luat_ble_gatt_service_t*)luat_heap_malloc(sizeof(luat_ble_gatt_service_t));
            if (s_gatts[idx] == NULL) { LLOGE("oom for gatt service"); break; }
            memset(s_gatts[idx], 0, sizeof(luat_ble_gatt_service_t));
        }
        size_t out_len = (size_t)(data_len - 2);
        luat_ble_gatt_unpack(s_gatts[idx], (uint8_t*)(data + 2), &out_len);
        param.gatt_item_ind.gatt_service_index    = idx;
        param.gatt_item_ind.gatt_service_total_num = total;
        param.gatt_item_ind.gatt_service           = s_gatts[idx];
        s_ble_rpc_cb(NULL, event, &param);
        break;
    }

    default:
        s_ble_rpc_cb(NULL, event, NULL);
        break;
    }
}

/* 声明 exec_rpc 文件中的 setter (同一编译单元组，链接时解析) */
typedef void (*ble_rpc_notify_fn_t)(uint16_t rpc_id, const void* msg, void* userdata);
extern void luat_airlink_rpc_ble_set_notify_fn(ble_rpc_notify_fn_t fn);

/* ---------- RPC API implementations ---------- */

int luat_airlink_drv_rpc_ble_init(luat_ble_t* luat_ble, luat_ble_cb_t luat_ble_cb) {
    (void)luat_ble;
    s_ble_rpc_cb = luat_ble_cb;
    luat_airlink_rpc_ble_set_notify_fn(ble_rpc_notify_dispatch);

    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest  req  = drv_bluetooth_BleRpcRequest_init_zero;
    drv_bluetooth_BleRpcResponse resp = drv_bluetooth_BleRpcResponse_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_init_tag;
    int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields,  &req,
                                       drv_bluetooth_BleRpcResponse_fields, &resp,
                                       3000);
    if (rc != 0) return rc;
    if (resp.which_payload == drv_bluetooth_BleRpcResponse_init_tag &&
        resp.payload.init.result.has_code &&
        resp.payload.init.result.code != drv_bluetooth_BleResultCode_BLE_RES_OK) {
        return (int)resp.payload.init.result.code;
    }
    return 0;
}

int luat_airlink_drv_rpc_ble_deinit(luat_ble_t* luat_ble) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest  req  = drv_bluetooth_BleRpcRequest_init_zero;
    drv_bluetooth_BleRpcResponse resp = drv_bluetooth_BleRpcResponse_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_deinit_tag;
    return luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                     drv_bluetooth_BleRpcRequest_fields,  &req,
                                     drv_bluetooth_BleRpcResponse_fields, &resp,
                                     2000);
}

int luat_airlink_drv_rpc_ble_set_name(luat_ble_t* luat_ble, char* name, uint8_t len) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_set_name_tag;
    if (len > 32) len = 32;
    req.payload.set_name.name.size = len;
    memcpy(req.payload.set_name.name.bytes, name, len);
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_set_max_mtu(luat_ble_t* luat_ble, uint16_t max_mtu) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_set_max_mtu_tag;
    req.payload.set_max_mtu.max_mtu = max_mtu;
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_create_advertising(luat_ble_t* luat_ble, luat_ble_adv_cfg_t* adv_cfg) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest  req  = drv_bluetooth_BleRpcRequest_init_zero;
    drv_bluetooth_BleRpcResponse resp = drv_bluetooth_BleRpcResponse_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_create_tag;
    if (adv_cfg) {
        req.payload.adv_create.has_cfg             = true;
        req.payload.adv_create.cfg.has_channel_map = true;
        req.payload.adv_create.cfg.channel_map      = (uint32_t)adv_cfg->channel_map;
        req.payload.adv_create.cfg.has_addr_mode    = true;
        req.payload.adv_create.cfg.addr_mode        = (uint32_t)adv_cfg->addr_mode;
        req.payload.adv_create.cfg.has_intv_min     = true;
        req.payload.adv_create.cfg.intv_min         = adv_cfg->intv_min;
        req.payload.adv_create.cfg.has_intv_max     = true;
        req.payload.adv_create.cfg.intv_max         = adv_cfg->intv_max;
        req.payload.adv_create.cfg.has_adv_prop     = true;
        req.payload.adv_create.cfg.adv_prop         = adv_cfg->adv_prop;
        req.payload.adv_create.cfg.has_adv_type     = true;
        req.payload.adv_create.cfg.adv_type         = (uint32_t)adv_cfg->adv_type;
    }
    return luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                     drv_bluetooth_BleRpcRequest_fields,  &req,
                                     drv_bluetooth_BleRpcResponse_fields, &resp,
                                     2000);
}

int luat_airlink_drv_rpc_ble_set_adv_data(luat_ble_t* luat_ble, uint8_t* adv_buff, uint8_t adv_len) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_set_data_tag;
    if (adv_len > 31) adv_len = 31;
    req.payload.adv_set_data.data.size = adv_len;
    memcpy(req.payload.adv_set_data.data.bytes, adv_buff, adv_len);
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_set_scan_rsp_data(luat_ble_t* luat_ble, uint8_t* rsp_data, uint8_t rsp_len) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_set_scan_rsp_tag;
    if (rsp_len > 31) rsp_len = 31;
    req.payload.adv_set_scan_rsp.data.size = rsp_len;
    memcpy(req.payload.adv_set_scan_rsp.data.bytes, rsp_data, rsp_len);
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_start_advertising(luat_ble_t* luat_ble) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_start_tag;
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_stop_advertising(luat_ble_t* luat_ble) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_stop_tag;
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_delete_advertising(luat_ble_t* luat_ble) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_adv_delete_tag;
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_create_gatt(luat_ble_t* luat_ble,
                                          luat_ble_gatt_service_t* luat_ble_gatt_service) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest  req  = drv_bluetooth_BleRpcRequest_init_zero;
    drv_bluetooth_BleRpcResponse resp = drv_bluetooth_BleRpcResponse_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_gatt_create_tag;
    size_t packed_len = 0;
    luat_ble_gatt_pack(luat_ble_gatt_service, NULL, &packed_len);
    if (packed_len > 1500) {
        LLOGE("gatt pack too large %u", (unsigned)packed_len);
        return -1;
    }
    req.payload.gatt_create.packed_gatt.size = (pb_size_t)packed_len;
    luat_ble_gatt_pack(luat_ble_gatt_service,
                       req.payload.gatt_create.packed_gatt.bytes, &packed_len);
    return luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                     drv_bluetooth_BleRpcRequest_fields,  &req,
                                     drv_bluetooth_BleRpcResponse_fields, &resp,
                                     3000);
}

int luat_airlink_drv_rpc_ble_read_response_value(luat_ble_t* luat_ble, uint8_t conn_idx,
                                                  uint16_t service_id, uint16_t att_handle,
                                                  uint8_t* data, uint32_t len) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_read_response_tag;
    req.payload.read_response.conn_idx   = conn_idx;
    req.payload.read_response.service_id = service_id;
    req.payload.read_response.att_handle = att_handle;
    if (len > 1500) len = 1500;
    req.payload.read_response.data.size = (pb_size_t)len;
    if (data && len > 0) memcpy(req.payload.read_response.data.bytes, data, len);
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_write_notify_value(luat_ble_t* luat_ble, uint8_t conn_idx,
                                                 uint16_t service_id, uint16_t att_handle,
                                                 uint8_t* data, uint16_t len) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_write_notify_tag;
    req.payload.write_notify.conn_idx   = conn_idx;
    req.payload.write_notify.service_id = service_id;
    req.payload.write_notify.att_handle = att_handle;
    if (len > 1500) len = 1500;
    req.payload.write_notify.data.size = len;
    if (data && len > 0) memcpy(req.payload.write_notify.data.bytes, data, len);
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_create_scanning(luat_ble_t* luat_ble, luat_ble_scan_cfg_t* scan_cfg) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest  req  = drv_bluetooth_BleRpcRequest_init_zero;
    drv_bluetooth_BleRpcResponse resp = drv_bluetooth_BleRpcResponse_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_scan_create_tag;
    if (scan_cfg) {
        req.payload.scan_create.has_cfg              = true;
        req.payload.scan_create.cfg.has_scan_type    = true;
        req.payload.scan_create.cfg.scan_type        = (uint32_t)scan_cfg->scan_type;
        req.payload.scan_create.cfg.has_addr_mode    = true;
        req.payload.scan_create.cfg.addr_mode        = (uint32_t)scan_cfg->addr_mode;
        req.payload.scan_create.cfg.has_scan_interval = true;
        req.payload.scan_create.cfg.scan_interval    = scan_cfg->scan_interval;
        req.payload.scan_create.cfg.has_scan_window  = true;
        req.payload.scan_create.cfg.scan_window      = scan_cfg->scan_window;
    }
    return luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                     drv_bluetooth_BleRpcRequest_fields,  &req,
                                     drv_bluetooth_BleRpcResponse_fields, &resp,
                                     2000);
}

int luat_airlink_drv_rpc_ble_start_scanning(luat_ble_t* luat_ble) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_scan_start_tag;
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_stop_scanning(luat_ble_t* luat_ble) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_scan_stop_tag;
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

int luat_airlink_drv_rpc_ble_delete_scanning(luat_ble_t* luat_ble) {
    (void)luat_ble;
    int mode = luat_airlink_current_mode_get();
    drv_bluetooth_BleRpcRequest req = drv_bluetooth_BleRpcRequest_init_zero;
    req.which_payload = drv_bluetooth_BleRpcRequest_scan_delete_tag;
    return luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_DRV_RPC_ID_BT,
                                       drv_bluetooth_BleRpcRequest_fields, &req);
}

#endif /* LUAT_USE_AIRLINK_RPC_BLUETOOTH */
