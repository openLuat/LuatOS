#include "luat_base.h"

#if defined(LUAT_USE_AIRLINK_RPC) && (defined(LUAT_USE_MOBILE) || defined(LUAT_USE_DRV_MOBILE))

#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_airlink_drv_rpc_mobile.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#include "drv_mobile.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...)

#define AIRLINK_DRV_RPC_ID_MOBILE        0x0700
#define AIRLINK_DRV_RPC_ID_MOBILE_NOTIFY 0x0701

#define AIRLINK_DRV_RPC_MOBILE_TIMEOUT_MS      2000
#define AIRLINK_DRV_RPC_MOBILE_DEFAULT_SCAN_SEC 15

#ifndef EINVAL
#define EINVAL 22
#endif

static uint32_t s_mobile_req_id = 1;
static luat_airlink_drv_rpc_mobile_notify_cb_t s_mobile_notify_cb = NULL;
static void* s_mobile_notify_userdata = NULL;
typedef void (*mobile_event_notify_fn_t)(uint16_t rpc_id, const void* msg, void* userdata);
#if defined(_MSC_VER)
void luat_airlink_rpc_mobile_set_event_notify_fn_stub(mobile_event_notify_fn_t fn) {
    (void)fn;
}
#if defined(_M_IX86)
#pragma comment(linker, "/alternatename:_luat_airlink_rpc_mobile_set_event_notify_fn=_luat_airlink_rpc_mobile_set_event_notify_fn_stub")
#else
#pragma comment(linker, "/alternatename:luat_airlink_rpc_mobile_set_event_notify_fn=luat_airlink_rpc_mobile_set_event_notify_fn_stub")
#endif
extern void luat_airlink_rpc_mobile_set_event_notify_fn(mobile_event_notify_fn_t fn);
#elif defined(__GNUC__) || defined(__clang__)
void __attribute__((weak)) luat_airlink_rpc_mobile_set_event_notify_fn(mobile_event_notify_fn_t fn) {
    (void)fn;
}
#else
extern void luat_airlink_rpc_mobile_set_event_notify_fn(mobile_event_notify_fn_t fn);
#endif
void luat_airlink_drv_rpc_mobile_notify_dispatch(
    uint16_t rpc_id,
    const void* msg_raw,
    void* userdata
);
static bool s_mobile_notify_registered = false;
static bool s_mobile_last_notify_valid = false;
static luat_airlink_drv_rpc_mobile_cell_scan_notify_t s_mobile_last_notify;

struct mobile_notify_ctx {
    luat_airlink_drv_rpc_mobile_cell_scan_notify_t event;
};

static void mobile_notify_ensure_registered(void) {
    if (!s_mobile_notify_registered) {
        s_mobile_notify_registered = true;
        luat_airlink_rpc_mobile_set_event_notify_fn(luat_airlink_drv_rpc_mobile_notify_dispatch);
    }
}

static void mobile_clear_last_notify(void) {
    s_mobile_last_notify_valid = false;
    memset(&s_mobile_last_notify, 0, sizeof(s_mobile_last_notify));
}

static void mobile_invalidate_stale_scan_notify(uint32_t req_id) {
    if (!s_mobile_last_notify_valid) {
        return;
    }
    if (s_mobile_last_notify.req_id == req_id) {
        return;
    }
    mobile_clear_last_notify();
}

static size_t mobile_copy_string(char* dst, size_t dst_size, const char* src, size_t src_size) {
    size_t actual_len = 0;

    if (!dst || !dst_size) return 0;
    dst[0] = 0;
    if (!src || !src_size) return 0;

    while (actual_len < src_size && src[actual_len] != 0) {
        actual_len++;
    }
    if (actual_len >= dst_size) {
        actual_len = dst_size - 1;
    }
    if (actual_len > 0) {
        memcpy(dst, src, actual_len);
    }
    dst[actual_len] = 0;
    return actual_len;
}

static int mobile_copy_string_field(char* dst, size_t dst_size, const char* src, size_t src_size) {
    if (!dst || dst_size == 0) return -EINVAL;
    return (int)mobile_copy_string(dst, dst_size, src, src_size);
}

static uint16_t mobile_decimal_to_bcd(uint32_t value) {
    uint16_t out = 0;
    uint8_t ones;
    uint8_t tens;
    uint8_t hundreds;

    if (value > 999) {
        return 0;
    }

    ones = (uint8_t)(value % 10);
    tens = (uint8_t)((value / 10) % 10);
    hundreds = (uint8_t)((value / 100) % 10);

    out |= (uint16_t)((tens << 4) | ones);
    out |= (uint16_t)(hundreds << 8);
    return out;
}

static int mobile_result_check(const drv_mobile_MobileResult* result) {
    if (!result) return -EINVAL;
    if (result->has_os_errno && result->os_errno != 0) return result->os_errno;
    if (!result->has_code) return 0;
    if (result->code == drv_mobile_MobileResultCode_MOBILE_RES_OK) return 0;
    return (int)result->code;
}

static uint32_t mobile_next_req_id(void) {
    uint32_t req_id = s_mobile_req_id++;
    if (s_mobile_req_id == 0) {
        s_mobile_req_id = 1;
    }
    return req_id;
}

static int mobile_do_call(
    drv_mobile_MobileRpcRequest* req,
    drv_mobile_MobileRpcResponse* resp,
    pb_size_t expected_tag
) {
    int rc;
    int mode = luat_airlink_current_mode_get();

    if (!req || !resp) return -EINVAL;
    if (mode < 0) {
        mode = LUAT_AIRLINK_MODE_UART;
    }
    LLOGD("rpc call mode=%d rpc=0x%04x tag=%u req_id=%lu", mode, AIRLINK_DRV_RPC_ID_MOBILE, (unsigned)req->which_payload, (unsigned long)req->req_id);

    rc = luat_airlink_rpc_nb_call(
        (uint8_t)mode,
        AIRLINK_DRV_RPC_ID_MOBILE,
        drv_mobile_MobileRpcRequest_fields,
        req,
        drv_mobile_MobileRpcResponse_fields,
        resp,
        AIRLINK_DRV_RPC_MOBILE_TIMEOUT_MS
    );
    if (rc != 0) return rc;
    LLOGD("rpc resp mode=%d rpc=0x%04x which=%u req_id=%lu", mode, AIRLINK_DRV_RPC_ID_MOBILE, (unsigned)resp->which_payload, (unsigned long)resp->req_id);
    if (resp->which_payload != expected_tag) return AIRLINK_DRV_RPC_MOBILE_PROTO_ERR;
    if (resp->has_req_id && resp->req_id != req->req_id) return AIRLINK_DRV_RPC_MOBILE_REQID_MISMATCH;
    return 0;
}

static int mobile_fill_sim_identity_status(
    const drv_mobile_MobileSimIdentityStatus* src,
    luat_airlink_drv_rpc_mobile_sim_identity_status_t* out
) {
    if (!out) return -EINVAL;
    memset(out, 0, sizeof(*out));
    if (!src) return 0;

    if (src->has_imei) {
        mobile_copy_string(out->imei, sizeof(out->imei), src->imei, sizeof(src->imei));
    }
    if (src->has_imsi) {
        mobile_copy_string(out->imsi, sizeof(out->imsi), src->imsi, sizeof(src->imsi));
    }
    if (src->has_iccid) {
        mobile_copy_string(out->iccid, sizeof(out->iccid), src->iccid, sizeof(src->iccid));
    }
    out->sim_ready = (uint8_t)((src->has_sim_ready && src->sim_ready) ? 1 : 0);
    return 0;
}

static int mobile_fill_global_status(
    const drv_mobile_MobileGlobalStatus* src,
    luat_airlink_drv_rpc_mobile_global_status_t* out
) {
    if (!out) return -EINVAL;
    memset(out, 0, sizeof(*out));
    if (!src) return 0;

    if (src->has_sn) {
        mobile_copy_string(out->sn, sizeof(out->sn), src->sn, sizeof(src->sn));
    }
    if (src->has_muid) {
        mobile_copy_string(out->muid, sizeof(out->muid), src->muid, sizeof(src->muid));
    }
    if (src->has_sim_status) {
        out->sim_status = (LUAT_MOBILE_SIM_STATUS_E)src->sim_status;
    }
    if (src->has_register_status) {
        out->register_status = (LUAT_MOBILE_REGISTER_STATUS_E)src->register_status;
    }
    return 0;
}

static void mobile_fill_signal_strength(
    const drv_mobile_MobileSignalInfo* src,
    luat_airlink_drv_rpc_mobile_signal_info_t* out
) {
    memset(out, 0, sizeof(*out));
    if (!src) return;

    if (src->has_csq) {
        out->csq = (uint8_t)src->csq;
    }

    if (src->has_gw_valid) {
        out->signal.luat_mobile_gw_signal_strength_vaild = src->gw_valid ? 1 : 0;
    }
    if (src->has_gw) {
        if (src->gw.has_rssi) out->signal.gw_signal_strength.rssi = src->gw.rssi;
        if (src->gw.has_bit_error_rate) out->signal.gw_signal_strength.bitErrorRate = src->gw.bit_error_rate;
        if (src->gw.has_rscp) out->signal.gw_signal_strength.rscp = src->gw.rscp;
        if (src->gw.has_ecno) out->signal.gw_signal_strength.ecno = src->gw.ecno;
    }

    if (src->has_lte_valid) {
        out->signal.luat_mobile_lte_signal_strength_vaild = src->lte_valid ? 1 : 0;
    }
    if (src->has_lte) {
        if (src->lte.has_rssi) out->signal.lte_signal_strength.rssi = (int16_t)src->lte.rssi;
        if (src->lte.has_rsrp) out->signal.lte_signal_strength.rsrp = (int16_t)src->lte.rsrp;
        if (src->lte.has_rsrq) out->signal.lte_signal_strength.rsrq = (int16_t)src->lte.rsrq;
        if (src->lte.has_snr) out->signal.lte_signal_strength.snr = (int16_t)src->lte.snr;
    }
}

static int mobile_fill_cell_info(
    const drv_mobile_MobileCellInfo* src,
    luat_mobile_cell_info_t* out
) {
    pb_size_t i;

    if (!out) return -EINVAL;
    memset(out, 0, sizeof(*out));
    if (!src) return 0;

    if (src->has_gsm_service) {
        out->gsm_service_info.cid = src->gsm_service.has_cid ? src->gsm_service.cid : 0;
        out->gsm_service_info.mcc = src->gsm_service.has_mcc ? mobile_decimal_to_bcd(src->gsm_service.mcc) : 0;
        out->gsm_service_info.mnc = src->gsm_service.has_mnc ? mobile_decimal_to_bcd(src->gsm_service.mnc) : 0;
        out->gsm_service_info.lac = src->gsm_service.has_lac ? src->gsm_service.lac : 0;
        out->gsm_service_info.arfcn = src->gsm_service.has_arfcn ? src->gsm_service.arfcn : 0;
        out->gsm_service_info.bsic = src->gsm_service.has_bsic ? src->gsm_service.bsic : 0;
        out->gsm_service_info.rssi = src->gsm_service.has_rssi ? src->gsm_service.rssi : 0;
    }

    out->gsm_neighbor_info_num = (uint8_t)src->gsm_neighbors_count;
    if (out->gsm_neighbor_info_num > LUAT_MOBILE_CELL_MAX_NUM) {
        out->gsm_neighbor_info_num = LUAT_MOBILE_CELL_MAX_NUM;
    }
    for (i = 0; i < out->gsm_neighbor_info_num; i++) {
        const drv_mobile_MobileGsmCellInfo* in = &src->gsm_neighbors[i];
        luat_mobile_gsm_cell_info_t* item = &out->gsm_info[i];
        item->cid = in->has_cid ? in->cid : 0;
        item->mcc = in->has_mcc ? mobile_decimal_to_bcd(in->mcc) : 0;
        item->mnc = in->has_mnc ? mobile_decimal_to_bcd(in->mnc) : 0;
        item->lac = in->has_lac ? in->lac : 0;
        item->arfcn = in->has_arfcn ? in->arfcn : 0;
        item->bsic = in->has_bsic ? in->bsic : 0;
        item->rssi = in->has_rssi ? in->rssi : 0;
    }

    if (src->has_lte_service) {
        out->lte_service_info.cid = src->lte_service.has_cid ? src->lte_service.cid : 0;
        out->lte_service_info.mcc = src->lte_service.has_mcc ? mobile_decimal_to_bcd(src->lte_service.mcc) : 0;
        out->lte_service_info.mnc = src->lte_service.has_mnc ? mobile_decimal_to_bcd(src->lte_service.mnc) : 0;
        out->lte_service_info.tac = src->lte_service.has_tac ? (uint16_t)src->lte_service.tac : 0;
        out->lte_service_info.pci = src->lte_service.has_pci ? (uint16_t)src->lte_service.pci : 0;
        out->lte_service_info.earfcn = src->lte_service.has_earfcn ? src->lte_service.earfcn : 0;
        out->lte_service_info.rssi = src->lte_service.has_rssi ? (int16_t)src->lte_service.rssi : 0;
        out->lte_service_info.rsrp = src->lte_service.has_rsrp ? (int16_t)src->lte_service.rsrp : 0;
        out->lte_service_info.rsrq = src->lte_service.has_rsrq ? (int16_t)src->lte_service.rsrq : 0;
        out->lte_service_info.snr = src->lte_service.has_snr ? (int16_t)src->lte_service.snr : 0;
        out->lte_service_info.is_tdd = src->lte_service.has_is_tdd ? (uint8_t)(src->lte_service.is_tdd ? 1 : 0) : 0;
        out->lte_service_info.band = src->lte_service.has_band ? (uint8_t)src->lte_service.band : 0;
        out->lte_service_info.ulbandwidth = src->lte_service.has_ulbandwidth ? (uint8_t)src->lte_service.ulbandwidth : 0;
        out->lte_service_info.dlbandwidth = src->lte_service.has_dlbandwidth ? (uint8_t)src->lte_service.dlbandwidth : 0;
    }

    out->lte_neighbor_info_num = (uint8_t)src->lte_neighbors_count;
    if (out->lte_neighbor_info_num > LUAT_MOBILE_CELL_MAX_NUM) {
        out->lte_neighbor_info_num = LUAT_MOBILE_CELL_MAX_NUM;
    }
    for (i = 0; i < out->lte_neighbor_info_num; i++) {
        const drv_mobile_MobileLteCellInfo* in = &src->lte_neighbors[i];
        luat_mobile_lte_cell_info_t* item = &out->lte_info[i];
        item->cid = in->has_cid ? in->cid : 0;
        item->mcc = in->has_mcc ? mobile_decimal_to_bcd(in->mcc) : 0;
        item->mnc = in->has_mnc ? mobile_decimal_to_bcd(in->mnc) : 0;
        item->tac = in->has_tac ? (uint16_t)in->tac : 0;
        item->pci = in->has_pci ? (uint16_t)in->pci : 0;
        item->earfcn = in->has_earfcn ? in->earfcn : 0;
        item->bandwidth = in->has_bandwidth ? (uint16_t)in->bandwidth : 0;
        item->celltype = in->has_celltype ? (uint16_t)in->celltype : 0;
        item->rsrp = in->has_rsrp ? (int16_t)in->rsrp : 0;
        item->rsrq = in->has_rsrq ? (int16_t)in->rsrq : 0;
        item->snr = in->has_snr ? (int16_t)in->snr : 0;
        item->rssi = in->has_rssi ? (int16_t)in->rssi : 0;
    }

    out->version = src->has_version ? src->version : 0;
    out->gsm_info_valid = src->has_gsm_info_valid ? (uint8_t)(src->gsm_info_valid ? 1 : 0)
                                                  : (uint8_t)((src->has_gsm_service || src->gsm_neighbors_count > 0) ? 1 : 0);
    out->lte_info_valid = src->has_lte_info_valid ? (uint8_t)(src->lte_info_valid ? 1 : 0)
                                                  : (uint8_t)((src->has_lte_service || src->lte_neighbors_count > 0) ? 1 : 0);
    return 0;
}

static int mobile_fill_scell_extern(
    const drv_mobile_MobileScellExternInfo* src,
    luat_airlink_drv_rpc_mobile_scell_extern_info_t* out
) {
    if (!out) return -EINVAL;
    memset(out, 0, sizeof(*out));
    if (!src) return 0;

    out->earfcn = src->has_earfcn ? src->earfcn : 0;
    out->pci = src->has_pci ? src->pci : 0;
    out->mcc = src->has_mcc ? src->mcc : 0;
    out->mnc = src->has_mnc ? src->mnc : 0;
    out->band = src->has_band ? src->band : 0;
    out->eci = src->has_eci ? src->eci : 0;
    out->cid = src->has_cid ? src->cid : 0;
    out->tac = src->has_tac ? src->tac : 0;
    return 0;
}

static int mobile_notify_handler(lua_State* L, void* ptr) {
    struct mobile_notify_ctx* ctx = (struct mobile_notify_ctx*)ptr;
    (void)L;

    if (!ctx) return 0;

    LLOGD("notify dispatch req_id=%lu sim_id=%u result=%d has_info=%u",
          (unsigned long)ctx->event.req_id, ctx->event.sim_id, ctx->event.result, ctx->event.has_info);
    s_mobile_last_notify = ctx->event;
    s_mobile_last_notify_valid = true;
    if (s_mobile_notify_cb) {
        s_mobile_notify_cb(&ctx->event, s_mobile_notify_userdata);
    }
    luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx);
    return 0;
}

int luat_airlink_drv_rpc_mobile_sim_identity_status(
    uint8_t sim_id,
    luat_airlink_drv_rpc_mobile_sim_identity_status_t* out
) {
    drv_mobile_MobileRpcRequest req = drv_mobile_MobileRpcRequest_init_zero;
    drv_mobile_MobileRpcResponse resp = drv_mobile_MobileRpcResponse_init_zero;
    int rc;

    if (!out) return -EINVAL;

    req.req_id = mobile_next_req_id();
    req.which_payload = drv_mobile_MobileRpcRequest_sim_identity_status_tag;
    req.payload.sim_identity_status.has_sim_id = true;
    req.payload.sim_identity_status.sim_id = sim_id;

    rc = mobile_do_call(&req, &resp, drv_mobile_MobileRpcResponse_sim_identity_status_tag);
    if (rc != 0) return rc;

    rc = mobile_result_check(&resp.payload.sim_identity_status.result);
    if (rc != 0) return rc;
    if (!resp.payload.sim_identity_status.has_status) {
        memset(out, 0, sizeof(*out));
        return 0;
    }
    return mobile_fill_sim_identity_status(&resp.payload.sim_identity_status.status, out);
}

int luat_airlink_drv_rpc_mobile_global_status(
    luat_airlink_drv_rpc_mobile_global_status_t* out
) {
    drv_mobile_MobileRpcRequest req = drv_mobile_MobileRpcRequest_init_zero;
    drv_mobile_MobileRpcResponse resp = drv_mobile_MobileRpcResponse_init_zero;
    int rc;

    if (!out) return -EINVAL;

    req.req_id = mobile_next_req_id();
    req.which_payload = drv_mobile_MobileRpcRequest_global_status_tag;

    rc = mobile_do_call(&req, &resp, drv_mobile_MobileRpcResponse_global_status_tag);
    if (rc != 0) return rc;

    rc = mobile_result_check(&resp.payload.global_status.result);
    if (rc != 0) return rc;
    if (!resp.payload.global_status.has_status) {
        memset(out, 0, sizeof(*out));
        return 0;
    }
    return mobile_fill_global_status(&resp.payload.global_status.status, out);
}

int luat_airlink_drv_rpc_mobile_signal(
    luat_airlink_drv_rpc_mobile_signal_info_t* out
) {
    drv_mobile_MobileRpcRequest req = drv_mobile_MobileRpcRequest_init_zero;
    drv_mobile_MobileRpcResponse resp = drv_mobile_MobileRpcResponse_init_zero;
    int rc;

    if (!out) return -EINVAL;

    req.req_id = mobile_next_req_id();
    req.which_payload = drv_mobile_MobileRpcRequest_signal_tag;

    rc = mobile_do_call(&req, &resp, drv_mobile_MobileRpcResponse_signal_tag);
    if (rc != 0) return rc;

    rc = mobile_result_check(&resp.payload.signal.result);
    if (rc != 0) return rc;
    mobile_fill_signal_strength(resp.payload.signal.has_info ? &resp.payload.signal.info : NULL, out);
    return 0;
}

int luat_airlink_drv_rpc_mobile_sync_cell_info(
    luat_mobile_cell_info_t* out
) {
    drv_mobile_MobileRpcRequest req = drv_mobile_MobileRpcRequest_init_zero;
    drv_mobile_MobileRpcResponse resp = drv_mobile_MobileRpcResponse_init_zero;
    int rc;

    if (!out) return -EINVAL;

    req.req_id = mobile_next_req_id();
    req.which_payload = drv_mobile_MobileRpcRequest_sync_cell_info_tag;

    rc = mobile_do_call(&req, &resp, drv_mobile_MobileRpcResponse_sync_cell_info_tag);
    if (rc != 0) return rc;

    rc = mobile_result_check(&resp.payload.sync_cell_info.result);
    if (rc != 0) return rc;
    return mobile_fill_cell_info(
        resp.payload.sync_cell_info.has_info ? &resp.payload.sync_cell_info.info : NULL,
        out
    );
}

int luat_airlink_drv_rpc_mobile_cell_scan(
    uint8_t timeout_sec,
    uint32_t* req_id
) {
    drv_mobile_MobileRpcRequest req = drv_mobile_MobileRpcRequest_init_zero;
    drv_mobile_MobileRpcResponse resp = drv_mobile_MobileRpcResponse_init_zero;
    int rc;

    mobile_notify_ensure_registered();
    req.req_id = mobile_next_req_id();
    if (req_id) {
        *req_id = req.req_id;
    }
    req.which_payload = drv_mobile_MobileRpcRequest_cell_scan_tag;
    req.payload.cell_scan.has_timeout_sec = true;
    req.payload.cell_scan.timeout_sec = timeout_sec ? timeout_sec : AIRLINK_DRV_RPC_MOBILE_DEFAULT_SCAN_SEC;

    rc = mobile_do_call(&req, &resp, drv_mobile_MobileRpcResponse_cell_scan_tag);
    if (rc != 0) return rc;
    rc = mobile_result_check(&resp.payload.cell_scan.result);
    if (rc == 0) {
        mobile_invalidate_stale_scan_notify(req.req_id);
    }
    return rc;
}

int luat_airlink_drv_rpc_mobile_scell_extern(
    luat_airlink_drv_rpc_mobile_scell_extern_info_t* out
) {
    drv_mobile_MobileRpcRequest req = drv_mobile_MobileRpcRequest_init_zero;
    drv_mobile_MobileRpcResponse resp = drv_mobile_MobileRpcResponse_init_zero;
    int rc;

    if (!out) return -EINVAL;

    req.req_id = mobile_next_req_id();
    req.which_payload = drv_mobile_MobileRpcRequest_scell_extern_tag;

    rc = mobile_do_call(&req, &resp, drv_mobile_MobileRpcResponse_scell_extern_tag);
    if (rc != 0) return rc;

    rc = mobile_result_check(&resp.payload.scell_extern.result);
    if (rc != 0) return rc;
    return mobile_fill_scell_extern(
        resp.payload.scell_extern.has_info ? &resp.payload.scell_extern.info : NULL,
        out
    );
}

int luat_airlink_drv_rpc_mobile_get_imei(
    uint8_t sim_id,
    char* buff,
    size_t buf_len
) {
    luat_airlink_drv_rpc_mobile_sim_identity_status_t status;
    int rc;

    rc = luat_airlink_drv_rpc_mobile_sim_identity_status(sim_id, &status);
    if (rc != 0) return rc;
    return mobile_copy_string_field(buff, buf_len, status.imei, sizeof(status.imei));
}

int luat_airlink_drv_rpc_mobile_get_imsi(
    uint8_t sim_id,
    char* buff,
    size_t buf_len
) {
    luat_airlink_drv_rpc_mobile_sim_identity_status_t status;
    int rc;

    rc = luat_airlink_drv_rpc_mobile_sim_identity_status(sim_id, &status);
    if (rc != 0) return rc;
    return mobile_copy_string_field(buff, buf_len, status.imsi, sizeof(status.imsi));
}

int luat_airlink_drv_rpc_mobile_get_iccid(
    uint8_t sim_id,
    char* buff,
    size_t buf_len
) {
    luat_airlink_drv_rpc_mobile_sim_identity_status_t status;
    int rc;

    rc = luat_airlink_drv_rpc_mobile_sim_identity_status(sim_id, &status);
    if (rc != 0) return rc;
    return mobile_copy_string_field(buff, buf_len, status.iccid, sizeof(status.iccid));
}

int luat_airlink_drv_rpc_mobile_get_sim_ready(
    uint8_t sim_id,
    uint8_t* sim_ready
) {
    luat_airlink_drv_rpc_mobile_sim_identity_status_t status;
    int rc;

    if (!sim_ready) return -EINVAL;

    rc = luat_airlink_drv_rpc_mobile_sim_identity_status(sim_id, &status);
    if (rc != 0) return rc;
    *sim_ready = status.sim_ready;
    return 0;
}

int luat_airlink_drv_rpc_mobile_get_sn(
    char* buff,
    size_t buf_len
) {
    luat_airlink_drv_rpc_mobile_global_status_t status;
    int rc;

    rc = luat_airlink_drv_rpc_mobile_global_status(&status);
    if (rc != 0) return rc;
    return mobile_copy_string_field(buff, buf_len, status.sn, sizeof(status.sn));
}

int luat_airlink_drv_rpc_mobile_get_muid(
    char* buff,
    size_t buf_len
) {
    luat_airlink_drv_rpc_mobile_global_status_t status;
    int rc;

    rc = luat_airlink_drv_rpc_mobile_global_status(&status);
    if (rc != 0) return rc;
    return mobile_copy_string_field(buff, buf_len, status.muid, sizeof(status.muid));
}

int luat_airlink_drv_rpc_mobile_get_sim_status(
    LUAT_MOBILE_SIM_STATUS_E* sim_status
) {
    luat_airlink_drv_rpc_mobile_global_status_t status;
    int rc;

    if (!sim_status) return -EINVAL;

    rc = luat_airlink_drv_rpc_mobile_global_status(&status);
    if (rc != 0) return rc;
    *sim_status = status.sim_status;
    return 0;
}

int luat_airlink_drv_rpc_mobile_get_register_status(
    LUAT_MOBILE_REGISTER_STATUS_E* register_status
) {
    luat_airlink_drv_rpc_mobile_global_status_t status;
    int rc;

    if (!register_status) return -EINVAL;

    rc = luat_airlink_drv_rpc_mobile_global_status(&status);
    if (rc != 0) return rc;
    *register_status = status.register_status;
    return 0;
}

int luat_airlink_drv_rpc_mobile_get_signal_strength(
    uint8_t* csq
) {
    luat_airlink_drv_rpc_mobile_signal_info_t signal;
    int rc;

    if (!csq) return -EINVAL;

    rc = luat_airlink_drv_rpc_mobile_signal(&signal);
    if (rc != 0) return rc;
    *csq = signal.csq;
    return 0;
}

int luat_airlink_drv_rpc_mobile_get_signal_strength_info(
    luat_mobile_signal_strength_info_t* info
) {
    luat_airlink_drv_rpc_mobile_signal_info_t signal;
    int rc;

    if (!info) return -EINVAL;

    rc = luat_airlink_drv_rpc_mobile_signal(&signal);
    if (rc != 0) return rc;
    *info = signal.signal;
    return 0;
}

int luat_airlink_drv_rpc_mobile_get_cell_info(
    luat_mobile_cell_info_t* info
) {
    return luat_airlink_drv_rpc_mobile_sync_cell_info(info);
}

int luat_airlink_drv_rpc_mobile_get_last_notify_cell_info(
    luat_mobile_cell_info_t* info
) {
    mobile_notify_ensure_registered();
    if (!info) return -EINVAL;
    memset(info, 0, sizeof(*info));
    if (!s_mobile_last_notify_valid) {
        return AIRLINK_DRV_RPC_MOBILE_NOTIFY_EMPTY;
    }
    if (s_mobile_last_notify.result != 0) {
        return s_mobile_last_notify.result;
    }
    if (!s_mobile_last_notify.has_info) {
        return AIRLINK_DRV_RPC_MOBILE_NOTIFY_NO_INFO;
    }
    *info = s_mobile_last_notify.info;
    return 0;
}

int luat_airlink_drv_rpc_mobile_get_extern_service_cell_info(
    luat_mobile_scell_extern_info_t* info
) {
    luat_airlink_drv_rpc_mobile_scell_extern_info_t scell;
    int rc;

    if (!info) return -EINVAL;

    rc = luat_airlink_drv_rpc_mobile_scell_extern(&scell);
    if (rc != 0) return rc;

    memset(info, 0, sizeof(*info));
    info->earfcn = scell.earfcn;
    info->pci = (uint16_t)scell.pci;
    info->mcc = mobile_decimal_to_bcd(scell.mcc);
    info->mnc = mobile_decimal_to_bcd(scell.mnc);
    return 0;
}

int luat_airlink_drv_rpc_mobile_get_last_cell_scan_notify(
    luat_airlink_drv_rpc_mobile_cell_scan_notify_t* out
) {
    mobile_notify_ensure_registered();
    if (!out) return -EINVAL;
    if (!s_mobile_last_notify_valid) {
        memset(out, 0, sizeof(*out));
        return AIRLINK_DRV_RPC_MOBILE_NOTIFY_EMPTY;
    }
    *out = s_mobile_last_notify;
    return out->result;
}

void luat_airlink_drv_rpc_mobile_set_notify_callback(
    luat_airlink_drv_rpc_mobile_notify_cb_t cb,
    void* userdata
) {
    s_mobile_notify_cb = cb;
    s_mobile_notify_userdata = userdata;
    if (cb) {
        mobile_notify_ensure_registered();
    }
}

void luat_airlink_drv_rpc_mobile_notify_dispatch(
    uint16_t rpc_id,
    const void* msg_raw,
    void* userdata
) {
    const drv_mobile_MobileCellScanNotify* notify = (const drv_mobile_MobileCellScanNotify*)msg_raw;
    struct mobile_notify_ctx* ctx;
    rtos_msg_t msg = {0};
    int rc;

    (void)userdata;
    if (rpc_id != AIRLINK_DRV_RPC_ID_MOBILE_NOTIFY || !notify) return;

    ctx = (struct mobile_notify_ctx*)luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(struct mobile_notify_ctx));
    if (!ctx) return;
    memset(ctx, 0, sizeof(*ctx));

    ctx->event.req_id = notify->has_req_id ? notify->req_id : 0;
    ctx->event.sim_id = notify->has_sim_id ? (uint8_t)notify->sim_id : 0;
    ctx->event.result = mobile_result_check(&notify->result);
    ctx->event.has_info = notify->has_info ? 1 : 0;
    if (notify->has_info) {
        rc = mobile_fill_cell_info(&notify->info, &ctx->event.info);
        if (rc != 0 && ctx->event.result == 0) {
            ctx->event.result = rc;
        }
    }

    msg.handler = mobile_notify_handler;
    msg.ptr = ctx;
    if (luat_msgbus_put(&msg, 0) != 0) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx);
    }
}

#endif /* LUAT_USE_AIRLINK_RPC && (LUAT_USE_MOBILE || LUAT_USE_DRV_MOBILE) */
