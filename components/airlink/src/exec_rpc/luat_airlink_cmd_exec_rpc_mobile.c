#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC

#include "luat_airlink_rpc.h"
#include "luat_airlink.h"
#include "drv_mobile.pb.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "airlink.rpc.mobile"
#include "luat_log.h"

#define AIRLINK_RPC_ID_MOBILE         0x0700
#define AIRLINK_RPC_ID_MOBILE_NOTIFY  0x0701

#ifndef EBUSY
#define EBUSY 16
#endif

#ifndef ENOMEM
#define ENOMEM 12
#endif

static void mobile_set_result_ok(drv_mobile_MobileResult* result) {
    result->has_code = true;
    result->code = drv_mobile_MobileResultCode_MOBILE_RES_OK;
}

static void mobile_set_result_code(drv_mobile_MobileResult* result,
                                   drv_mobile_MobileResultCode code,
                                   int os_err) {
    result->has_code = true;
    result->code = code;
    result->has_os_errno = true;
    result->os_errno = os_err;
}

static void mobile_set_result_fail(drv_mobile_MobileResult* result, int os_err) {
    mobile_set_result_code(result, drv_mobile_MobileResultCode_MOBILE_RES_FAIL, os_err);
}

static void mobile_set_result_einval(drv_mobile_MobileResult* result, int os_err) {
    mobile_set_result_code(result, drv_mobile_MobileResultCode_MOBILE_RES_EINVAL, os_err);
}

static int mobile_result_status(const drv_mobile_MobileResult* result) {
    if (result == NULL) return 0;
    if (result->has_os_errno && result->os_errno != 0) return result->os_errno;
    if (result->has_code &&
        result->code != drv_mobile_MobileResultCode_MOBILE_RES_OK) {
        return (int)result->code;
    }
    return 0;
}

typedef void (*mobile_event_notify_fn_t)(uint16_t rpc_id, const void* msg, void* userdata);
static mobile_event_notify_fn_t s_mobile_notify_fn = NULL;

void luat_airlink_rpc_mobile_set_event_notify_fn(mobile_event_notify_fn_t fn) {
    s_mobile_notify_fn = fn;
}

static void mobile_event_notify_handler(uint16_t rpc_id, const void* msg, void* userdata) {
    (void)userdata;
    if (s_mobile_notify_fn) {
        s_mobile_notify_fn(rpc_id, msg, userdata);
    }
}

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_mobile_event_reg = {
    .rpc_id         = AIRLINK_RPC_ID_MOBILE_NOTIFY,
    .active         = 1,
    .req_desc       = drv_mobile_MobileCellScanNotify_fields,
    .req_size       = sizeof(drv_mobile_MobileCellScanNotify),
    .resp_desc      = NULL,
    .resp_size      = 0,
    .handler        = NULL,
    .notify_handler = mobile_event_notify_handler,
    .userdata       = NULL,
};

#ifdef LUAT_USE_AIRLINK_EXEC_MOBILE

#include <string.h>
#include "luat_airlink_drv_mobile.h"
#include "luat_mobile.h"
#include "luat_mcu.h"

typedef struct {
    uint32_t req_id;
    uint8_t timeout_sec;
} mobile_cell_scan_task_ctx_t;

static luat_rtos_mutex_t s_mobile_cell_scan_lock = NULL;
static luat_rtos_queue_t s_mobile_cell_scan_queue = NULL;
static luat_rtos_task_handle s_mobile_cell_scan_task = NULL;
static uint8_t s_pending_cell_scan_mode = LUAT_AIRLINK_MODE_UNKNOW;
static uint8_t s_pending_cell_scan_valid = 0;
static uint8_t s_pending_cell_scan_ready = 0;
static drv_mobile_MobileCellScanNotify s_pending_cell_scan_notify =
    drv_mobile_MobileCellScanNotify_init_zero;

static uint32_t mobile_bcd16_to_decimal(uint16_t src) {
    uint8_t high = (src >> 8) & 0xFF;
    uint8_t low = src & 0xFF;
    return (uint32_t)((low & 0x0F) + (low >> 4) * 10 +
                      ((high & 0x0F) + (high >> 4) * 10) * 100);
}

static void mobile_fill_gsm_service_info(drv_mobile_MobileGsmServiceCellInfo* dst,
                                         const luat_mobile_gsm_service_cell_info_t* src) {
    dst->has_cid = true;
    dst->cid = src->cid;
    dst->has_mcc = true;
    dst->mcc = mobile_bcd16_to_decimal((uint16_t)src->mcc);
    dst->has_mnc = true;
    dst->mnc = mobile_bcd16_to_decimal((uint16_t)src->mnc);
    dst->has_lac = true;
    dst->lac = src->lac;
    dst->has_arfcn = true;
    dst->arfcn = src->arfcn;
    dst->has_bsic = true;
    dst->bsic = src->bsic;
    dst->has_rssi = true;
    dst->rssi = src->rssi;
}

static void mobile_fill_gsm_neighbor_info(drv_mobile_MobileGsmCellInfo* dst,
                                          const luat_mobile_gsm_cell_info_t* src) {
    dst->has_cid = true;
    dst->cid = src->cid;
    dst->has_mcc = true;
    dst->mcc = mobile_bcd16_to_decimal((uint16_t)src->mcc);
    dst->has_mnc = true;
    dst->mnc = mobile_bcd16_to_decimal((uint16_t)src->mnc);
    dst->has_lac = true;
    dst->lac = src->lac;
    dst->has_arfcn = true;
    dst->arfcn = src->arfcn;
    dst->has_bsic = true;
    dst->bsic = src->bsic;
    dst->has_rssi = true;
    dst->rssi = src->rssi;
}

static void mobile_fill_lte_service_info(drv_mobile_MobileLteServiceCellInfo* dst,
                                         const luat_mobile_lte_service_cell_info_t* src) {
    dst->has_cid = true;
    dst->cid = src->cid;
    dst->has_mcc = true;
    dst->mcc = mobile_bcd16_to_decimal(src->mcc);
    dst->has_mnc = true;
    dst->mnc = mobile_bcd16_to_decimal(src->mnc);
    dst->has_tac = true;
    dst->tac = src->tac;
    dst->has_pci = true;
    dst->pci = src->pci;
    dst->has_earfcn = true;
    dst->earfcn = src->earfcn;
    dst->has_rssi = true;
    dst->rssi = src->rssi;
    dst->has_rsrp = true;
    dst->rsrp = src->rsrp;
    dst->has_rsrq = true;
    dst->rsrq = src->rsrq;
    dst->has_snr = true;
    dst->snr = src->snr;
    dst->has_is_tdd = true;
    dst->is_tdd = src->is_tdd ? true : false;
    dst->has_band = true;
    dst->band = src->band;
    dst->has_ulbandwidth = true;
    dst->ulbandwidth = src->ulbandwidth;
    dst->has_dlbandwidth = true;
    dst->dlbandwidth = src->dlbandwidth;
}

static void mobile_fill_lte_neighbor_info(drv_mobile_MobileLteCellInfo* dst,
                                          const luat_mobile_lte_cell_info_t* src) {
    dst->has_cid = true;
    dst->cid = src->cid;
    dst->has_mcc = true;
    dst->mcc = mobile_bcd16_to_decimal(src->mcc);
    dst->has_mnc = true;
    dst->mnc = mobile_bcd16_to_decimal(src->mnc);
    dst->has_tac = true;
    dst->tac = src->tac;
    dst->has_pci = true;
    dst->pci = src->pci;
    dst->has_earfcn = true;
    dst->earfcn = src->earfcn;
    dst->has_bandwidth = true;
    dst->bandwidth = src->bandwidth;
    dst->has_celltype = true;
    dst->celltype = src->celltype;
    dst->has_rsrp = true;
    dst->rsrp = src->rsrp;
    dst->has_rsrq = true;
    dst->rsrq = src->rsrq;
    dst->has_snr = true;
    dst->snr = src->snr;
    dst->has_rssi = true;
    dst->rssi = src->rssi;
}

static void mobile_fill_cell_info(drv_mobile_MobileCellInfo* dst,
                                  const luat_mobile_cell_info_t* src) {
    uint32_t gsm_count = src->gsm_neighbor_info_num;
    uint32_t lte_count = src->lte_neighbor_info_num;

    if (gsm_count > LUAT_MOBILE_CELL_MAX_NUM) gsm_count = LUAT_MOBILE_CELL_MAX_NUM;
    if (lte_count > LUAT_MOBILE_CELL_MAX_NUM) lte_count = LUAT_MOBILE_CELL_MAX_NUM;

    dst->has_version = true;
    dst->version = src->version;
    dst->has_gsm_info_valid = true;
    dst->gsm_info_valid = src->gsm_info_valid ? true : false;
    dst->has_gsm_neighbor_count = true;
    dst->gsm_neighbor_count = gsm_count;
    dst->has_lte_info_valid = true;
    dst->lte_info_valid = src->lte_info_valid ? true : false;
    dst->has_lte_neighbor_count = true;
    dst->lte_neighbor_count = lte_count;

    if (src->gsm_service_info.cid != 0) {
        dst->has_gsm_service = true;
        mobile_fill_gsm_service_info(&dst->gsm_service, &src->gsm_service_info);
    }
    dst->gsm_neighbors_count = (pb_size_t)gsm_count;
    for (uint32_t i = 0; i < gsm_count; i++) {
        mobile_fill_gsm_neighbor_info(&dst->gsm_neighbors[i], &src->gsm_info[i]);
    }

    if (src->lte_service_info.cid != 0) {
        dst->has_lte_service = true;
        mobile_fill_lte_service_info(&dst->lte_service, &src->lte_service_info);
    }
    dst->lte_neighbors_count = (pb_size_t)lte_count;
    for (uint32_t i = 0; i < lte_count; i++) {
        mobile_fill_lte_neighbor_info(&dst->lte_neighbors[i], &src->lte_info[i]);
    }
}

static int mobile_fill_sim_identity_status_response(drv_mobile_MobileSimIdentityStatusResponse* payload,
                                                    int sim_id) {
    char imei[16] = {0};
    char imsi[16] = {0};
    char iccid[21] = {0};
    uint8_t sim_ready = luat_mobile_get_sim_ready(sim_id);
    int ret = 0;

    payload->has_status = true;
    payload->status.has_sim_ready = true;
    payload->status.sim_ready = sim_ready ? true : false;

    ret = luat_mobile_get_imei(sim_id, imei, sizeof(imei));
    if (ret <= 0) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }
    payload->status.has_imei = true;
    memcpy(payload->status.imei, imei, sizeof(payload->status.imei));

    ret = luat_mobile_get_imsi(sim_id, imsi, sizeof(imsi));
    if (ret > 0) {
        payload->status.has_imsi = true;
        memcpy(payload->status.imsi, imsi, sizeof(payload->status.imsi));
    } else if (sim_ready) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }

    ret = luat_mobile_get_iccid(sim_id, iccid, sizeof(iccid));
    if (ret > 0) {
        payload->status.has_iccid = true;
        memcpy(payload->status.iccid, iccid, sizeof(payload->status.iccid));
    } else if (sim_ready) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }

    mobile_set_result_ok(&payload->result);
    return 0;
}

static int mobile_fill_global_status_response(drv_mobile_MobileGlobalStatusResponse* payload) {
    char sn[33] = {0};
    char muid[33] = {0};
    int ret = 0;

    payload->has_status = true;
    payload->status.has_sim_status = true;
    payload->status.sim_status = (uint32_t)luat_mobile_get_sim_status();
    payload->status.has_register_status = true;
    payload->status.register_status = (uint32_t)luat_mobile_get_register_status();

    ret = luat_mobile_get_sn(sn, sizeof(sn));
    if (ret < 0) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }
    if (ret > 0) {
        payload->status.has_sn = true;
        memcpy(payload->status.sn, sn, sizeof(payload->status.sn));
    }

    ret = luat_mobile_get_muid(muid, sizeof(muid));
    if (ret < 0) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }
    if (ret > 0) {
        payload->status.has_muid = true;
        memcpy(payload->status.muid, muid, sizeof(payload->status.muid));
    }

    mobile_set_result_ok(&payload->result);
    return 0;
}

static int mobile_fill_signal_response(drv_mobile_MobileSignalResponse* payload) {
    luat_mobile_signal_strength_info_t info;
    uint8_t csq = 0;
    int ret = 0;

    memset(&info, 0, sizeof(info));
    ret = luat_mobile_get_signal_strength_info(&info);
    if (ret != 0) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }

    payload->has_info = true;
    payload->info.has_gw_valid = true;
    payload->info.gw_valid = info.luat_mobile_gw_signal_strength_vaild ? true : false;
    payload->info.has_lte_valid = true;
    payload->info.lte_valid = info.luat_mobile_lte_signal_strength_vaild ? true : false;

    ret = luat_mobile_get_signal_strength(&csq);
    if (ret == 0) {
        payload->info.has_csq = true;
        payload->info.csq = csq;
    }

    if (info.luat_mobile_gw_signal_strength_vaild) {
        payload->info.has_gw = true;
        payload->info.gw.has_rssi = true;
        payload->info.gw.rssi = info.gw_signal_strength.rssi;
        payload->info.gw.has_bit_error_rate = true;
        payload->info.gw.bit_error_rate = info.gw_signal_strength.bitErrorRate;
        payload->info.gw.has_rscp = true;
        payload->info.gw.rscp = info.gw_signal_strength.rscp;
        payload->info.gw.has_ecno = true;
        payload->info.gw.ecno = info.gw_signal_strength.ecno;
    }

    if (info.luat_mobile_lte_signal_strength_vaild) {
        payload->info.has_lte = true;
        payload->info.lte.has_rssi = true;
        payload->info.lte.rssi = info.lte_signal_strength.rssi;
        payload->info.lte.has_rsrp = true;
        payload->info.lte.rsrp = info.lte_signal_strength.rsrp;
        payload->info.lte.has_rsrq = true;
        payload->info.lte.rsrq = info.lte_signal_strength.rsrq;
        payload->info.lte.has_snr = true;
        payload->info.lte.snr = info.lte_signal_strength.snr;
    }

    mobile_set_result_ok(&payload->result);
    return 0;
}

static int mobile_fill_sync_cell_info_response(drv_mobile_MobileSyncCellInfoResponse* payload) {
    luat_mobile_cell_info_t info;
    int ret = 0;

    memset(&info, 0, sizeof(info));
    ret = luat_mobile_get_cell_info(&info);
    if (ret != 0) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }

    payload->has_info = true;
    mobile_fill_cell_info(&payload->info, &info);
    mobile_set_result_ok(&payload->result);
    return 0;
}

static int mobile_fill_scell_extern_response(drv_mobile_MobileScellExternInfoResponse* payload) {
    luat_mobile_scell_extern_info_t info;
    uint32_t eci = 0;
    uint16_t tac = 0;
    int ret = 0;
    int band = 0;

    memset(&info, 0, sizeof(info));
    ret = luat_mobile_get_extern_service_cell_info(&info);
    if (ret != 0) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }

    payload->has_info = true;
    payload->info.has_earfcn = true;
    payload->info.earfcn = info.earfcn;
    payload->info.has_pci = true;
    payload->info.pci = info.pci;
    payload->info.has_mcc = true;
    payload->info.mcc = mobile_bcd16_to_decimal(info.mcc);
    payload->info.has_mnc = true;
    payload->info.mnc = mobile_bcd16_to_decimal(info.mnc);

    band = luat_mobile_get_band_from_earfcn(info.earfcn);
    if (band >= 0) {
        payload->info.has_band = true;
        payload->info.band = (uint32_t)band;
    }

    ret = luat_mobile_get_service_cell_identifier(&eci);
    if (ret != 0) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }
    payload->info.has_eci = true;
    payload->info.eci = eci;
    payload->info.has_cid = true;
    payload->info.cid = eci;

    ret = luat_mobile_get_service_tac_or_lac(&tac);
    if (ret != 0) {
        mobile_set_result_fail(&payload->result, ret);
        return 0;
    }
    payload->info.has_tac = true;
    payload->info.tac = tac;

    mobile_set_result_ok(&payload->result);
    return 0;
}

static int mobile_rpc_ensure_scan_lock(void) {
    if (s_mobile_cell_scan_lock) {
        return 0;
    }
    return luat_rtos_mutex_create(&s_mobile_cell_scan_lock);
}

static void mobile_rpc_lock_scan(void) {
    if (s_mobile_cell_scan_lock) {
        luat_rtos_mutex_lock(s_mobile_cell_scan_lock, LUAT_WAIT_FOREVER);
    }
}

static void mobile_rpc_unlock_scan(void) {
    if (s_mobile_cell_scan_lock) {
        luat_rtos_mutex_unlock(s_mobile_cell_scan_lock);
    }
}

static void mobile_rpc_clear_pending_scan_locked(void) {
    s_pending_cell_scan_valid = 0;
    s_pending_cell_scan_ready = 0;
    s_pending_cell_scan_mode = LUAT_AIRLINK_MODE_UNKNOW;
    memset(&s_pending_cell_scan_notify, 0, sizeof(s_pending_cell_scan_notify));
}

static void mobile_rpc_prepare_pending_scan(uint32_t req_id) {
    memset(&s_pending_cell_scan_notify, 0, sizeof(s_pending_cell_scan_notify));
    s_pending_cell_scan_notify.has_req_id = true;
    s_pending_cell_scan_notify.req_id = req_id;
    s_pending_cell_scan_valid = 1;
    s_pending_cell_scan_ready = 0;
    s_pending_cell_scan_mode = (uint8_t)luat_airlink_current_mode_get();
}

static drv_mobile_MobileResult* mobile_exec_result_ptr(drv_mobile_MobileRpcResponse* resp,
                                                       pb_size_t which_payload) {
    switch (which_payload) {
    case drv_mobile_MobileRpcRequest_sim_identity_status_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_sim_identity_status_tag;
        return &resp->payload.sim_identity_status.result;
    case drv_mobile_MobileRpcRequest_signal_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_signal_tag;
        return &resp->payload.signal.result;
    case drv_mobile_MobileRpcRequest_sync_cell_info_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_sync_cell_info_tag;
        return &resp->payload.sync_cell_info.result;
    case drv_mobile_MobileRpcRequest_cell_scan_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_cell_scan_tag;
        return &resp->payload.cell_scan.result;
    case drv_mobile_MobileRpcRequest_scell_extern_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_scell_extern_tag;
        return &resp->payload.scell_extern.result;
    case drv_mobile_MobileRpcRequest_global_status_tag:
    default:
        resp->which_payload = drv_mobile_MobileRpcResponse_global_status_tag;
        return &resp->payload.global_status.result;
    }
}

static void mobile_rpc_complete_pending_scan(uint32_t req_id, int ret,
                                             const luat_mobile_cell_info_t* info) {
    int sim_id = 0;

    if (mobile_rpc_ensure_scan_lock() != 0) {
        return;
    }

    mobile_rpc_lock_scan();
    if (!s_pending_cell_scan_valid ||
        !s_pending_cell_scan_notify.has_req_id ||
        s_pending_cell_scan_notify.req_id != req_id) {
        mobile_rpc_unlock_scan();
        return;
    }

    s_pending_cell_scan_notify.has_sim_id = true;
    s_pending_cell_scan_notify.sim_id =
        (luat_mobile_get_sim_id(&sim_id) == 0) ? (uint32_t)sim_id : 0;
    if (ret == 0 && info) {
        s_pending_cell_scan_notify.has_info = true;
        mobile_fill_cell_info(&s_pending_cell_scan_notify.info, info);
        mobile_set_result_ok(&s_pending_cell_scan_notify.result);
    } else {
        s_pending_cell_scan_notify.has_info = false;
        mobile_set_result_fail(&s_pending_cell_scan_notify.result, ret);
    }
    s_pending_cell_scan_ready = 1;
    mobile_rpc_unlock_scan();
}

static int mobile_rpc_try_notify_pending_scan(void) {
    int mode;
    int rc;
    uint8_t should_send = 0;
    drv_mobile_MobileCellScanNotify notify = drv_mobile_MobileCellScanNotify_init_zero;
    uint32_t notify_req_id = 0;

    if (mobile_rpc_ensure_scan_lock() != 0) {
        return -1;
    }

    mobile_rpc_lock_scan();
    if (s_pending_cell_scan_valid && s_pending_cell_scan_ready) {
        notify = s_pending_cell_scan_notify;
        notify_req_id = s_pending_cell_scan_notify.req_id;
        should_send = 1;
    }
    mobile_rpc_unlock_scan();

    if (!should_send) {
        return 0;
    }

    mode = luat_airlink_current_mode_get();
    if (mode < 0 || mode > LUAT_AIRLINK_MODE_UART) {
        mode = s_pending_cell_scan_mode;
    }
    if (mode < 0 || mode > LUAT_AIRLINK_MODE_UART) {
        return -1;
    }

    rc = luat_airlink_rpc_nb_notify((uint8_t)mode, AIRLINK_RPC_ID_MOBILE_NOTIFY,
                                    drv_mobile_MobileCellScanNotify_fields,
                                    &notify);
    if (rc != 0) {
        if (g_airlink_debug) {
            LLOGW("mobile cell scan notify send failed rc=%d req_id=%lu",
                  rc, (unsigned long)notify.req_id);
        }
        return rc;
    }

    mobile_rpc_lock_scan();
    if (s_pending_cell_scan_valid &&
        s_pending_cell_scan_ready &&
        s_pending_cell_scan_notify.has_req_id &&
        s_pending_cell_scan_notify.req_id == notify_req_id) {
        mobile_rpc_clear_pending_scan_locked();
    }
    mobile_rpc_unlock_scan();
    return 0;
}

static int mobile_rpc_ensure_scan_worker(void);

static void mobile_rpc_cell_scan_task(void* userdata) {
    mobile_cell_scan_task_ctx_t req;
    luat_mobile_cell_info_t info;
    int ret = -1;
    uint64_t deadline_ms = 0;

    (void)userdata;

    for (;;) {
        memset(&req, 0, sizeof(req));
        if (s_mobile_cell_scan_queue == NULL) {
            luat_rtos_task_sleep(1000);
            continue;
        }
        if (luat_rtos_queue_recv(s_mobile_cell_scan_queue, &req, sizeof(req), LUAT_WAIT_FOREVER) != 0) {
            continue;
        }

        ret = luat_mobile_get_cell_info_async(req.timeout_sec);
        if (ret == 0) {
            deadline_ms = luat_mcu_tick64_ms() + ((uint64_t)req.timeout_sec * 1000U) + 500U;
            do {
                memset(&info, 0, sizeof(info));
                ret = luat_mobile_get_last_notify_cell_info(&info);
                if (ret == 0) {
                    break;
                }
                luat_rtos_task_sleep(200);
            } while (luat_mcu_tick64_ms() < deadline_ms);
        }

        mobile_rpc_complete_pending_scan(req.req_id, ret, (ret == 0) ? &info : NULL);
        mobile_rpc_try_notify_pending_scan();
    }
}

static int mobile_rpc_ensure_scan_worker(void) {
    int ret = 0;

    if (mobile_rpc_ensure_scan_lock() != 0) {
        return -1;
    }

    mobile_rpc_lock_scan();
    if (s_mobile_cell_scan_task == NULL) {
        if (s_mobile_cell_scan_queue == NULL) {
            ret = luat_rtos_queue_create(&s_mobile_cell_scan_queue, 1, sizeof(mobile_cell_scan_task_ctx_t));
            if (ret != 0) {
                mobile_rpc_unlock_scan();
                return ret;
            }
        }
        ret = luat_rtos_task_create(&s_mobile_cell_scan_task, 8 * 1024, 45,
                                    "airlink_mscan", mobile_rpc_cell_scan_task,
                                    NULL, 0);
        if (ret != 0) {
            if (s_mobile_cell_scan_queue != NULL) {
                luat_rtos_queue_delete(s_mobile_cell_scan_queue);
                s_mobile_cell_scan_queue = NULL;
            }
            mobile_rpc_unlock_scan();
            return ret;
        }
    }
    mobile_rpc_unlock_scan();
    return 0;
}

static int mobile_rpc_handler(uint16_t rpc_id,
                              const void* req_raw, void* resp_raw,
                              void* userdata) {
    const drv_mobile_MobileRpcRequest* req = (const drv_mobile_MobileRpcRequest*)req_raw;
    drv_mobile_MobileRpcResponse* resp = (drv_mobile_MobileRpcResponse*)resp_raw;
    int op_ret = 0;
    uint32_t timeout_sec = 15;
    uint8_t scan_pending = 0;
    drv_mobile_MobileResult* busy_result = NULL;

    (void)rpc_id;
    (void)userdata;

    if (req == NULL || resp == NULL) {
        return -500;
    }
    if (g_airlink_debug) {
        LLOGD("mobile rpc handler req_id=%lu tag=%u", (unsigned long)req->req_id, (unsigned)req->which_payload);
    }

    resp->has_req_id = true;
    resp->req_id = req->req_id;

    if (req->which_payload != drv_mobile_MobileRpcRequest_cell_scan_tag) {
        if (mobile_rpc_ensure_scan_lock() == 0) {
            mobile_rpc_lock_scan();
            scan_pending = s_pending_cell_scan_valid ? 1 : 0;
            mobile_rpc_unlock_scan();
        }
        if (scan_pending) {
            busy_result = mobile_exec_result_ptr(resp, req->which_payload);
            mobile_set_result_fail(busy_result, -EBUSY);
            if (g_airlink_debug) {
                LLOGW("mobile rpc rejected while cell_scan pending req_id=%lu tag=%u",
                      (unsigned long)req->req_id, (unsigned)req->which_payload);
            }
            return 0;
        }
    }

    switch (req->which_payload) {
    case drv_mobile_MobileRpcRequest_sim_identity_status_tag: {
        int sim_id = req->payload.sim_identity_status.has_sim_id ? (int)req->payload.sim_identity_status.sim_id : 0;
        resp->which_payload = drv_mobile_MobileRpcResponse_sim_identity_status_tag;
        op_ret = mobile_fill_sim_identity_status_response(&resp->payload.sim_identity_status, sim_id);
        if (op_ret == 0) {
            op_ret = mobile_result_status(&resp->payload.sim_identity_status.result);
        }
        if (g_airlink_debug) {
            LLOGD("mobile sim_identity_status sim=%d ret=%d", sim_id, op_ret);
        }
        break;
    }
    case drv_mobile_MobileRpcRequest_global_status_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_global_status_tag;
        op_ret = mobile_fill_global_status_response(&resp->payload.global_status);
        if (op_ret == 0) {
            op_ret = mobile_result_status(&resp->payload.global_status.result);
        }
        if (g_airlink_debug) {
            LLOGD("mobile global_status ret=%d", op_ret);
        }
        break;
    case drv_mobile_MobileRpcRequest_signal_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_signal_tag;
        op_ret = mobile_fill_signal_response(&resp->payload.signal);
        if (op_ret == 0) {
            op_ret = mobile_result_status(&resp->payload.signal.result);
        }
        if (g_airlink_debug) {
            LLOGD("mobile signal ret=%d", op_ret);
        }
        break;
    case drv_mobile_MobileRpcRequest_sync_cell_info_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_sync_cell_info_tag;
        op_ret = mobile_fill_sync_cell_info_response(&resp->payload.sync_cell_info);
        if (op_ret == 0) {
            op_ret = mobile_result_status(&resp->payload.sync_cell_info.result);
        }
        if (g_airlink_debug) {
            LLOGD("mobile sync_cell_info ret=%d", op_ret);
        }
        break;
    case drv_mobile_MobileRpcRequest_cell_scan_tag: {
        mobile_cell_scan_task_ctx_t task_ctx = {0};

        resp->which_payload = drv_mobile_MobileRpcResponse_cell_scan_tag;
        timeout_sec = req->payload.cell_scan.has_timeout_sec ? req->payload.cell_scan.timeout_sec : 15;
        if (timeout_sec > 0xFF) {
            op_ret = -22;
            mobile_set_result_einval(&resp->payload.cell_scan.result, op_ret);
            if (g_airlink_debug) {
                LLOGW("mobile cell_scan invalid timeout=%u", timeout_sec);
            }
            break;
        }
        if (mobile_rpc_ensure_scan_lock() != 0) {
            op_ret = -1;
            mobile_set_result_fail(&resp->payload.cell_scan.result, op_ret);
            if (g_airlink_debug) {
                LLOGW("mobile cell_scan scan lock init failed");
            }
            break;
        }
        (void)mobile_rpc_try_notify_pending_scan();
        mobile_rpc_lock_scan();
        if (s_pending_cell_scan_valid) {
            op_ret = -EBUSY;
            mobile_set_result_fail(&resp->payload.cell_scan.result, op_ret);
            if (g_airlink_debug) {
                LLOGW("mobile cell_scan rejected: req_id=%lu still pending previous req_id=%lu",
                      (unsigned long)req->req_id,
                      (unsigned long)s_pending_cell_scan_notify.req_id);
            }
            mobile_rpc_unlock_scan();
            break;
        }
        mobile_rpc_unlock_scan();
        op_ret = mobile_rpc_ensure_scan_worker();
        if (op_ret != 0) {
            mobile_set_result_fail(&resp->payload.cell_scan.result, op_ret);
            if (g_airlink_debug) {
                LLOGW("mobile cell_scan worker init failed ret=%d", op_ret);
            }
            break;
        }
        mobile_rpc_lock_scan();
        if (s_pending_cell_scan_valid) {
            op_ret = -EBUSY;
            mobile_set_result_fail(&resp->payload.cell_scan.result, op_ret);
            if (g_airlink_debug) {
                LLOGW("mobile cell_scan rejected (recheck): req_id=%lu still pending previous req_id=%lu",
                      (unsigned long)req->req_id,
                      (unsigned long)s_pending_cell_scan_notify.req_id);
            }
            mobile_rpc_unlock_scan();
            break;
        }
        mobile_rpc_prepare_pending_scan(req->req_id);
        task_ctx.req_id = req->req_id;
        task_ctx.timeout_sec = (uint8_t)timeout_sec;
        op_ret = luat_rtos_queue_send(s_mobile_cell_scan_queue, &task_ctx, sizeof(task_ctx), 0);
        if (op_ret == 0) {
            mobile_set_result_ok(&resp->payload.cell_scan.result);
        } else {
            mobile_rpc_clear_pending_scan_locked();
            mobile_set_result_fail(&resp->payload.cell_scan.result, op_ret);
        }
        mobile_rpc_unlock_scan();
        if (g_airlink_debug) {
            LLOGD("mobile cell_scan timeout=%u ret=%d", timeout_sec, op_ret);
        }
        break;
    }
    case drv_mobile_MobileRpcRequest_scell_extern_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_scell_extern_tag;
        op_ret = mobile_fill_scell_extern_response(&resp->payload.scell_extern);
        if (op_ret == 0) {
            op_ret = mobile_result_status(&resp->payload.scell_extern.result);
        }
        LLOGD("mobile scell_extern ret=%d", op_ret);
        break;
    default:
        LLOGW("mobile_rpc: 未知 which_payload=%d", (int)req->which_payload);
        return -1;
    }

    return 0;
}

#else /* !LUAT_USE_AIRLINK_EXEC_MOBILE */

static drv_mobile_MobileResult* mobile_stub_result_ptr(drv_mobile_MobileRpcResponse* resp,
                                                       pb_size_t which_payload) {
    switch (which_payload) {
    case drv_mobile_MobileRpcRequest_sim_identity_status_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_sim_identity_status_tag;
        return &resp->payload.sim_identity_status.result;
    case drv_mobile_MobileRpcRequest_signal_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_signal_tag;
        return &resp->payload.signal.result;
    case drv_mobile_MobileRpcRequest_sync_cell_info_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_sync_cell_info_tag;
        return &resp->payload.sync_cell_info.result;
    case drv_mobile_MobileRpcRequest_cell_scan_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_cell_scan_tag;
        return &resp->payload.cell_scan.result;
    case drv_mobile_MobileRpcRequest_scell_extern_tag:
        resp->which_payload = drv_mobile_MobileRpcResponse_scell_extern_tag;
        return &resp->payload.scell_extern.result;
    case drv_mobile_MobileRpcRequest_global_status_tag:
    default:
        resp->which_payload = drv_mobile_MobileRpcResponse_global_status_tag;
        return &resp->payload.global_status.result;
    }
}

static int mobile_rpc_handler(uint16_t rpc_id,
                              const void* req_raw, void* resp_raw,
                              void* userdata) {
    const drv_mobile_MobileRpcRequest* req = (const drv_mobile_MobileRpcRequest*)req_raw;
    drv_mobile_MobileRpcResponse* resp = (drv_mobile_MobileRpcResponse*)resp_raw;
    drv_mobile_MobileResult* result = NULL;

    (void)rpc_id;
    (void)userdata;

    resp->has_req_id = true;
    resp->req_id = req->req_id;
    result = mobile_stub_result_ptr(resp, req->which_payload);
    mobile_set_result_fail(result, -1);
    return 0;
}

#endif /* LUAT_USE_AIRLINK_EXEC_MOBILE */

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_mobile_reg = {
    .rpc_id         = AIRLINK_RPC_ID_MOBILE,
    .active         = 1,
    .req_desc       = drv_mobile_MobileRpcRequest_fields,
    .req_size       = sizeof(drv_mobile_MobileRpcRequest),
    .resp_desc      = drv_mobile_MobileRpcResponse_fields,
    .resp_size      = sizeof(drv_mobile_MobileRpcResponse),
    .handler        = mobile_rpc_handler,
    .notify_handler = NULL,
    .userdata       = NULL,
};

#endif /* LUAT_USE_AIRLINK_RPC */
