/*
 * AirLink BLE nanopb RPC exec handler (服务端) + 客户端事件接收
 *
 * RPC 分配:
 *   0x0600 — BleRpcRequest/Response: 客户端→服务端请求，服务端处理后响应
 *   0x0601 — BleEventNotify:         服务端→客户端事件通知 (nb_notify, 无响应)
 *
 * 服务端（Air780E）：
 *   收到 BleRpcRequest (0x0600) → 调用 luat_ble_* → 填写 BleRpcResponse
 *   BLE 事件触发时 → 编码 BleEventNotify → luat_airlink_rpc_nb_notify(0x0601)
 *
 * 客户端（Air8000/PC）：
 *   调用 luat_airlink_rpc_ble_set_notify_fn() 注册回调
 *   收到 BleEventNotify (0x0601) → notify_handler 解码 → 回调用户函数
 */

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC

#include "luat_airlink_rpc.h"
#include "drv_bluetooth.pb.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "airlink.rpc.bt"
#include "luat_log.h"

#define AIRLINK_RPC_ID_BT        0x0600  /* BleRpcRequest/Response */
#define AIRLINK_RPC_ID_BT_EVENT  0x0601  /* BleEventNotify (server → client) */

/* 客户端注册的 BLE 事件回调 (由 luat_airlink_drv_ble_init 通过 setter 设置) */
typedef void (*ble_rpc_notify_fn_t)(uint16_t rpc_id, const void* msg, void* userdata);
static ble_rpc_notify_fn_t s_client_notify_fn = NULL;

/*
 * luat_airlink_rpc_ble_set_notify_fn — 供客户端驱动调用，注册 BleEventNotify 接收回调
 * 线程安全性: 在任务初始化阶段调用一次即可，无需加锁
 */
void luat_airlink_rpc_ble_set_notify_fn(ble_rpc_notify_fn_t fn) {
    s_client_notify_fn = fn;
}

/* 客户端侧 BleEventNotify 接收处理器 (由 nb_dispatch 在 0x0601 NOTIFY 时调用) */
static void ble_rpc_event_recv_handler(uint16_t rpc_id, const void* msg, void* userdata) {
    if (s_client_notify_fn) {
        s_client_notify_fn(rpc_id, msg, userdata);
    }
}

#ifdef LUAT_USE_AIRLINK_EXEC_BLUETOOTH
#include "luat_ble.h"
#include "luat_drv_ble.h"

static luat_ble_t s_ble_handle;

static void set_result_ok(drv_bluetooth_BleResult* r) {
    r->has_code = true;
    r->code = drv_bluetooth_BleResultCode_BLE_RES_OK;
}

static void set_result_fail(drv_bluetooth_BleResult* r, int os_err) {
    r->has_code = true;
    r->code = drv_bluetooth_BleResultCode_BLE_RES_FAIL;
    r->has_os_errno = true;
    r->os_errno = os_err;
}

/* BLE 事件回调 — 将事件序列化为 BleEventNotify 并通过 nb_notify 发送给客户端 */
static void ble_rpc_event_cb(luat_ble_t* ble, luat_ble_event_t event, luat_ble_param_t* param) {
    (void)ble;
    drv_bluetooth_BleEventNotify notify;
    memset(&notify, 0, sizeof(notify));
    notify.event_type = (uint32_t)event;

    if (param) {
        uint8_t* dst = notify.packed_data.bytes;
        pb_size_t len = 0;

        switch (event) {
        case LUAT_BLE_EVENT_CONN:
            len = (pb_size_t)sizeof(luat_ble_conn_ind_t);
            memcpy(dst, &param->conn_ind, len);
            break;
        case LUAT_BLE_EVENT_DISCONN:
            len = (pb_size_t)sizeof(luat_ble_disconn_ind_t);
            memcpy(dst, &param->disconn_ind, len);
            break;
        case LUAT_BLE_EVENT_GATT_DONE:
            len = (pb_size_t)sizeof(luat_ble_gatt_done_ind_t);
            memcpy(dst, &param->gatt_done_ind, len);
            break;
        case LUAT_BLE_EVENT_WRITE:
            if (sizeof(luat_ble_write_req_t) <= 1500) {
                len = (pb_size_t)sizeof(luat_ble_write_req_t);
                memcpy(dst, &param->write_req, len);
                if (param->write_req.value && param->write_req.value_len > 0 &&
                    (size_t)(len + param->write_req.value_len) <= 1500) {
                    memcpy(dst + len, param->write_req.value, param->write_req.value_len);
                    len += (pb_size_t)param->write_req.value_len;
                }
            }
            break;
        case LUAT_BLE_EVENT_READ:
            len = (pb_size_t)sizeof(luat_ble_read_req_t);
            memcpy(dst, &param->read_req, len);
            break;
        case LUAT_BLE_EVENT_READ_VALUE:
            len = (pb_size_t)sizeof(luat_ble_read_req_t);
            memcpy(dst, &param->read_req, len);
            if (param->read_req.value && param->read_req.value_len > 0 &&
                (size_t)(len + param->read_req.value_len) <= 1500) {
                memcpy(dst + len, param->read_req.value, param->read_req.value_len);
                len += (pb_size_t)param->read_req.value_len;
            }
            break;
        case LUAT_BLE_EVENT_SCAN_REPORT:
            len = (pb_size_t)sizeof(luat_ble_adv_req_t);
            memcpy(dst, &param->adv_req, len);
            if (param->adv_req.data && param->adv_req.data_len > 0 &&
                (size_t)(len + param->adv_req.data_len) <= 1500) {
                memcpy(dst + len, param->adv_req.data, param->adv_req.data_len);
                len += (pb_size_t)param->adv_req.data_len;
            }
            break;
        case LUAT_BLE_EVENT_GATT_ITEM: {
            luat_ble_gatt_service_t* gatt = param->gatt_item_ind.gatt_service;
            if (gatt && 2 <= 1500) {
                dst[0] = param->gatt_item_ind.gatt_service_index;
                dst[1] = param->gatt_item_ind.gatt_service_total_num;
                len = 2;
                size_t gatt_len = 0;
                luat_ble_gatt_pack(gatt, NULL, &gatt_len);
                if (gatt_len > 0 && (size_t)(len + gatt_len) <= 1500) {
                    luat_ble_gatt_pack(gatt, dst + len, &gatt_len);
                    len += (pb_size_t)gatt_len;
                }
            }
            break;
        }
        default:
            break;
        }

        if (len > 0) {
            notify.has_packed_data = true;
            notify.packed_data.size = len;
        }
    }

    int rc = luat_airlink_rpc_nb_notify(0, AIRLINK_RPC_ID_BT_EVENT,
                                         drv_bluetooth_BleEventNotify_fields, &notify);
    if (rc != 0 && event != LUAT_BLE_EVENT_SCAN_REPORT) {
        LLOGW("ble event notify failed event=%d rc=%d", (int)event, rc);
    }
}

static int ble_rpc_handler(uint16_t rpc_id,
                            const void* req_raw, void* resp_raw,
                            void* userdata) {
    (void)rpc_id; (void)userdata;
    const drv_bluetooth_BleRpcRequest* req  = (const drv_bluetooth_BleRpcRequest*)req_raw;
    drv_bluetooth_BleRpcResponse*      resp = (drv_bluetooth_BleRpcResponse*)resp_raw;
    int ret = 0;

    resp->has_req_id = true;
    resp->req_id     = req->req_id;

    switch (req->which_payload) {

    case drv_bluetooth_BleRpcRequest_init_tag:
        memset(&s_ble_handle, 0, sizeof(s_ble_handle));
        ret = luat_ble_init(&s_ble_handle, ble_rpc_event_cb);
        resp->which_payload = drv_bluetooth_BleRpcResponse_init_tag;
        if (ret == 0) set_result_ok(&resp->payload.init.result);
        else          set_result_fail(&resp->payload.init.result, ret);
        break;

    case drv_bluetooth_BleRpcRequest_deinit_tag:
        ret = luat_ble_deinit(&s_ble_handle);
        resp->which_payload = drv_bluetooth_BleRpcResponse_deinit_tag;
        if (ret == 0) set_result_ok(&resp->payload.deinit.result);
        else          set_result_fail(&resp->payload.deinit.result, ret);
        break;

    case drv_bluetooth_BleRpcRequest_set_name_tag: {
        const drv_bluetooth_BleSetNameRequest* r = &req->payload.set_name;
        char name[33] = {0};
        uint8_t name_len = (uint8_t)r->name.size;
        if (name_len > 32) name_len = 32;
        memcpy(name, r->name.bytes, name_len);
        ret = luat_ble_set_name(&s_ble_handle, name, name_len);
        resp->which_payload = drv_bluetooth_BleRpcResponse_set_name_tag;
        if (ret == 0) set_result_ok(&resp->payload.set_name.result);
        else          set_result_fail(&resp->payload.set_name.result, ret);
        break;
    }

    case drv_bluetooth_BleRpcRequest_set_max_mtu_tag:
        ret = luat_ble_set_max_mtu(&s_ble_handle, (uint16_t)req->payload.set_max_mtu.max_mtu);
        resp->which_payload = drv_bluetooth_BleRpcResponse_set_max_mtu_tag;
        if (ret == 0) set_result_ok(&resp->payload.set_max_mtu.result);
        else          set_result_fail(&resp->payload.set_max_mtu.result, ret);
        break;

    case drv_bluetooth_BleRpcRequest_adv_create_tag: {
        const drv_bluetooth_BleAdvCreateRequest* r = &req->payload.adv_create;
        luat_ble_adv_cfg_t cfg = {
            .channel_map = LUAT_BLE_ADV_CHNLS_ALL,
            .addr_mode   = LUAT_BLE_ADDR_MODE_PUBLIC,
            .intv_min    = 160,
            .intv_max    = 160,
            .adv_prop    = 0,
            .adv_type    = LUAT_BLE_ADV_TYPE_LEGACY,
        };
        if (r->has_cfg) {
            const drv_bluetooth_BleAdvCfg* c = &r->cfg;
            if (c->has_channel_map) cfg.channel_map = (luat_ble_adv_chnl_t)c->channel_map;
            if (c->has_addr_mode)   cfg.addr_mode   = (luat_ble_addr_mode_t)c->addr_mode;
            if (c->has_intv_min)    cfg.intv_min    = c->intv_min;
            if (c->has_intv_max)    cfg.intv_max    = c->intv_max;
            if (c->has_adv_prop)    cfg.adv_prop    = (uint8_t)c->adv_prop;
            if (c->has_adv_type)    cfg.adv_type    = (uint8_t)c->adv_type;
        }
        ret = luat_ble_create_advertising(&s_ble_handle, &cfg);
        resp->which_payload = drv_bluetooth_BleRpcResponse_adv_create_tag;
        if (ret == 0) set_result_ok(&resp->payload.adv_create.result);
        else          set_result_fail(&resp->payload.adv_create.result, ret);
        break;
    }

    case drv_bluetooth_BleRpcRequest_adv_set_data_tag: {
        const drv_bluetooth_BleAdvSetDataRequest* r = &req->payload.adv_set_data;
        ret = luat_ble_set_adv_data(&s_ble_handle,
                                     (uint8_t*)r->data.bytes, (uint8_t)r->data.size);
        resp->which_payload = drv_bluetooth_BleRpcResponse_adv_set_data_tag;
        if (ret == 0) set_result_ok(&resp->payload.adv_set_data.result);
        else          set_result_fail(&resp->payload.adv_set_data.result, ret);
        break;
    }

    case drv_bluetooth_BleRpcRequest_adv_set_scan_rsp_tag: {
        const drv_bluetooth_BleAdvSetScanRspRequest* r = &req->payload.adv_set_scan_rsp;
        ret = luat_ble_set_scan_rsp_data(&s_ble_handle,
                                          (uint8_t*)r->data.bytes, (uint8_t)r->data.size);
        resp->which_payload = drv_bluetooth_BleRpcResponse_adv_set_scan_rsp_tag;
        if (ret == 0) set_result_ok(&resp->payload.adv_set_scan_rsp.result);
        else          set_result_fail(&resp->payload.adv_set_scan_rsp.result, ret);
        break;
    }

    case drv_bluetooth_BleRpcRequest_adv_start_tag:
        ret = luat_ble_start_advertising(&s_ble_handle);
        resp->which_payload = drv_bluetooth_BleRpcResponse_adv_start_tag;
        if (ret == 0) set_result_ok(&resp->payload.adv_start.result);
        else          set_result_fail(&resp->payload.adv_start.result, ret);
        break;

    case drv_bluetooth_BleRpcRequest_adv_stop_tag:
        ret = luat_ble_stop_advertising(&s_ble_handle);
        resp->which_payload = drv_bluetooth_BleRpcResponse_adv_stop_tag;
        if (ret == 0) set_result_ok(&resp->payload.adv_stop.result);
        else          set_result_fail(&resp->payload.adv_stop.result, ret);
        break;

    case drv_bluetooth_BleRpcRequest_adv_delete_tag:
        ret = luat_ble_delete_advertising(&s_ble_handle);
        resp->which_payload = drv_bluetooth_BleRpcResponse_adv_delete_tag;
        if (ret == 0) set_result_ok(&resp->payload.adv_delete.result);
        else          set_result_fail(&resp->payload.adv_delete.result, ret);
        break;

    case drv_bluetooth_BleRpcRequest_gatt_create_tag: {
        const drv_bluetooth_BleGattCreateRequest* r = &req->payload.gatt_create;
        luat_ble_gatt_service_t gatt;
        memset(&gatt, 0, sizeof(gatt));
        size_t out_len = 0;
        int rc = luat_ble_gatt_unpack(&gatt, (uint8_t*)r->packed_gatt.bytes, &out_len);
        if (rc == 0 && out_len > 0) {
            ret = luat_ble_create_gatt(&s_ble_handle, &gatt);
            for (size_t i = 0; i < gatt.characteristics_num; i++) {
                if (gatt.characteristics[i].descriptor) {
                    luat_heap_free(gatt.characteristics[i].descriptor);
                }
            }
            if (gatt.characteristics) luat_heap_free(gatt.characteristics);
        } else {
            ret = -1;
        }
        resp->which_payload = drv_bluetooth_BleRpcResponse_gatt_create_tag;
        if (ret == 0) set_result_ok(&resp->payload.gatt_create.result);
        else          set_result_fail(&resp->payload.gatt_create.result, ret);
        break;
    }

    case drv_bluetooth_BleRpcRequest_read_response_tag: {
        /* read_response: luat_ble.h 暂无直接 API，通过 luat_drv_bt_msg_send 实现 */
        const drv_bluetooth_BleReadResponseRequest* r = &req->payload.read_response;
        resp->which_payload = drv_bluetooth_BleRpcResponse_read_response_tag;
        /* 构造 drv msg 并发送 */
        size_t msg_size = sizeof(luat_drv_ble_msg_t) + r->data.size;
        luat_drv_ble_msg_t* msg = (luat_drv_ble_msg_t*)luat_heap_malloc(msg_size);
        if (msg) {
            memset(msg, 0, sizeof(luat_drv_ble_msg_t));
            msg->cmd_id = LUAT_DRV_BT_CMD_BLE_SEND_READ_RESP;
            msg->len    = (uint16_t)r->data.size;
            memcpy(msg->data, r->data.bytes, r->data.size);
            ret = luat_drv_bt_msg_send(msg);
            if (ret != 0) luat_heap_free(msg);
        } else {
            ret = -ENOMEM;
        }
        if (ret == 0) set_result_ok(&resp->payload.read_response.result);
        else          set_result_fail(&resp->payload.read_response.result, ret);
        break;
    }

    case drv_bluetooth_BleRpcRequest_write_notify_tag: {
        const drv_bluetooth_BleWriteNotifyRequest* r = &req->payload.write_notify;
        luat_ble_uuid_t uuid_svc  = {0};
        luat_ble_uuid_t uuid_chr  = {0};
        luat_ble_uuid_t uuid_desc = {0};
        luat_ble_handle2uuid((uint16_t)r->att_handle, &uuid_svc, &uuid_chr, &uuid_desc);
        ret = luat_ble_write_notify_value(&uuid_svc, &uuid_chr, &uuid_desc,
                                           (uint8_t*)r->data.bytes, (uint16_t)r->data.size);
        resp->which_payload = drv_bluetooth_BleRpcResponse_write_notify_tag;
        if (ret == 0) set_result_ok(&resp->payload.write_notify.result);
        else          set_result_fail(&resp->payload.write_notify.result, ret);
        break;
    }

    case drv_bluetooth_BleRpcRequest_scan_create_tag: {
        const drv_bluetooth_BleScanCreateRequest* r = &req->payload.scan_create;
        luat_ble_scan_cfg_t cfg = {
            .scan_type     = LUAT_BLE_PASSIVE_SCANNING,
            .addr_mode     = LUAT_BLE_ADDR_MODE_PUBLIC,
            .scan_interval = 16,
            .scan_window   = 16,
        };
        if (r->has_cfg) {
            const drv_bluetooth_BleScanCfg* c = &r->cfg;
            if (c->has_scan_type)     cfg.scan_type     = (luat_ble_scan_type_t)c->scan_type;
            if (c->has_addr_mode)     cfg.addr_mode     = (luat_ble_addr_mode_t)c->addr_mode;
            if (c->has_scan_interval) cfg.scan_interval = (uint16_t)c->scan_interval;
            if (c->has_scan_window)   cfg.scan_window   = (uint16_t)c->scan_window;
        }
        ret = luat_ble_create_scanning(&s_ble_handle, &cfg);
        resp->which_payload = drv_bluetooth_BleRpcResponse_scan_create_tag;
        if (ret == 0) set_result_ok(&resp->payload.scan_create.result);
        else          set_result_fail(&resp->payload.scan_create.result, ret);
        break;
    }

    case drv_bluetooth_BleRpcRequest_scan_start_tag:
        ret = luat_ble_start_scanning(&s_ble_handle);
        resp->which_payload = drv_bluetooth_BleRpcResponse_scan_start_tag;
        if (ret == 0) set_result_ok(&resp->payload.scan_start.result);
        else          set_result_fail(&resp->payload.scan_start.result, ret);
        break;

    case drv_bluetooth_BleRpcRequest_scan_stop_tag:
        ret = luat_ble_stop_scanning(&s_ble_handle);
        resp->which_payload = drv_bluetooth_BleRpcResponse_scan_stop_tag;
        if (ret == 0) set_result_ok(&resp->payload.scan_stop.result);
        else          set_result_fail(&resp->payload.scan_stop.result, ret);
        break;

    case drv_bluetooth_BleRpcRequest_scan_delete_tag:
        ret = luat_ble_delete_scanning(&s_ble_handle);
        resp->which_payload = drv_bluetooth_BleRpcResponse_scan_delete_tag;
        if (ret == 0) set_result_ok(&resp->payload.scan_delete.result);
        else          set_result_fail(&resp->payload.scan_delete.result, ret);
        break;

    default:
        LLOGW("ble_rpc: 未知 which_payload=%d", (int)req->which_payload);
        return -1;
    }

    return 0;
}

#else /* !LUAT_USE_AIRLINK_EXEC_BLUETOOTH — PC 模拟器 stub */

static int ble_rpc_handler(uint16_t rpc_id,
                            const void* req_raw, void* resp_raw,
                            void* userdata) {
    (void)rpc_id; (void)req_raw; (void)userdata;
    drv_bluetooth_BleRpcResponse* resp = (drv_bluetooth_BleRpcResponse*)resp_raw;
    resp->which_payload = drv_bluetooth_BleRpcResponse_init_tag;
    resp->payload.init.result.has_code    = true;
    resp->payload.init.result.code        = drv_bluetooth_BleResultCode_BLE_RES_FAIL;
    resp->payload.init.result.has_os_errno = true;
    resp->payload.init.result.os_errno    = -1; /* ENOTSUP */
    return 0;
}

#endif /* LUAT_USE_AIRLINK_EXEC_BLUETOOTH */

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_bluetooth_reg = {
    .rpc_id         = AIRLINK_RPC_ID_BT,
    .active         = 1,
    .req_desc       = drv_bluetooth_BleRpcRequest_fields,
    .req_size       = sizeof(drv_bluetooth_BleRpcRequest),
    .resp_desc      = drv_bluetooth_BleRpcResponse_fields,
    .resp_size      = sizeof(drv_bluetooth_BleRpcResponse),
    .handler        = ble_rpc_handler,
    .notify_handler = NULL,
    .userdata       = NULL,
};

/* 客户端侧注册：0x0601 接收服务端发来的 BleEventNotify */
const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_bluetooth_event_reg = {
    .rpc_id         = AIRLINK_RPC_ID_BT_EVENT,
    .active         = 1,
    .req_desc       = drv_bluetooth_BleEventNotify_fields,
    .req_size       = sizeof(drv_bluetooth_BleEventNotify),
    .resp_desc      = NULL,
    .resp_size      = 0,
    .handler        = NULL,
    .notify_handler = ble_rpc_event_recv_handler,
    .userdata       = NULL,
};

#endif /* LUAT_USE_AIRLINK_RPC */
