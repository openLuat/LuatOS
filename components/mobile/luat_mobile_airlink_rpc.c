#include "luat_base.h"

#if defined(LUAT_USE_AIRLINK_RPC) && defined(LUAT_USE_DRV_MOBILE) && defined(LUAT_USE_MOBILE) && !defined(LUAT_USE_AIRLINK_EXEC_MOBILE)

#include "luat_airlink_drv_rpc_mobile.h"
#include "luat_mobile.h"
#define LUAT_LOG_TAG "mobile.rpc"
#include "luat_log.h"
#include <string.h>
#ifdef LUAT_USE_LWIP
#include "lwip/ip_addr.h"
#endif

extern void luat_mobile_event_cb(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status, void* ptr);

static luat_mobile_event_callback_t s_mobile_event_cb = NULL;
static luat_mobile_cell_info_t s_last_cell_info;
static uint8_t s_last_cell_info_valid = 0;
static uint8_t s_mobile_notify_hooked = 0;
static int s_mobile_sim_id = 0;
static int s_mobile_flymode = 0;
static uint8_t s_mobile_default_pdn_ipv6 = 0;
static uint8_t s_mobile_sync_time = 0;

static void luat_mobile_rpc_fire_event(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status) {
    if (s_mobile_event_cb) {
        s_mobile_event_cb(event, index, status);
    }
    luat_mobile_event_cb(event, index, status, NULL);
}

static void luat_mobile_rpc_notify_cb(const luat_airlink_drv_rpc_mobile_cell_scan_notify_t* event, void* userdata) {
    (void)userdata;
    if (!event) return;
    if (event->result == 0 && event->has_info) {
        s_last_cell_info = event->info;
        s_last_cell_info_valid = 1;
    }
    luat_mobile_rpc_fire_event(LUAT_MOBILE_EVENT_CELL_INFO, event->sim_id, LUAT_MOBILE_CELL_INFO_UPDATE);
}

static void luat_mobile_rpc_hook_notify_once(void) {
    if (!s_mobile_notify_hooked) {
        s_mobile_notify_hooked = 1;
        luat_airlink_drv_rpc_mobile_set_notify_callback(luat_mobile_rpc_notify_cb, NULL);
    }
}

int luat_mobile_get_imei(int sim_id, char* buff, size_t buf_len) {
    int ret;
    // LLOGD("imei req sim_id=%d len=%u", sim_id, (unsigned)buf_len);
    ret = luat_airlink_drv_rpc_mobile_get_imei((uint8_t)sim_id, buff, buf_len);
    // LLOGD("imei resp ret=%d val=%s", ret, (ret > 0 && buff) ? buff : "nil");
    return ret;
}

int luat_mobile_get_imsi(int sim_id, char* buff, size_t buf_len) {
    int ret;
    // LLOGD("imsi req sim_id=%d len=%u", sim_id, (unsigned)buf_len);
    ret = luat_airlink_drv_rpc_mobile_get_imsi((uint8_t)sim_id, buff, buf_len);
    // LLOGD("imsi resp ret=%d val=%s", ret, (ret > 0 && buff) ? buff : "nil");
    return ret;
}

int luat_mobile_get_iccid(int sim_id, char* buff, size_t buf_len) {
    int ret;
    // LLOGD("iccid req sim_id=%d len=%u", sim_id, (unsigned)buf_len);
    ret = luat_airlink_drv_rpc_mobile_get_iccid((uint8_t)sim_id, buff, buf_len);
    // LLOGD("iccid resp ret=%d val=%s", ret, (ret > 0 && buff) ? buff : "nil");
    return ret;
}

int luat_mobile_get_sn(char* buff, size_t buf_len) {
    return luat_airlink_drv_rpc_mobile_get_sn(buff, buf_len);
}

int luat_mobile_get_muid(char* buff, size_t buf_len) {
    return luat_airlink_drv_rpc_mobile_get_muid(buff, buf_len);
}

uint8_t luat_mobile_get_sim_ready(int id) {
    uint8_t sim_ready = 0;
    if (luat_airlink_drv_rpc_mobile_get_sim_ready((uint8_t)id, &sim_ready) != 0) {
        return 0;
    }
    return sim_ready;
}

LUAT_MOBILE_SIM_STATUS_E luat_mobile_get_sim_status(void) {
    LUAT_MOBILE_SIM_STATUS_E status = LUAT_MOBILE_NO_SIM;
    if (luat_airlink_drv_rpc_mobile_get_sim_status(&status) != 0) {
        return LUAT_MOBILE_NO_SIM;
    }
    return status;
}

LUAT_MOBILE_REGISTER_STATUS_E luat_mobile_get_register_status(void) {
    LUAT_MOBILE_REGISTER_STATUS_E status = LUAT_MOBILE_STATUS_UNREGISTER;
    if (luat_airlink_drv_rpc_mobile_get_register_status(&status) != 0) {
        return LUAT_MOBILE_STATUS_UNREGISTER;
    }
    return status;
}

int luat_mobile_get_signal_strength(uint8_t *csq) {
    int ret = luat_airlink_drv_rpc_mobile_get_signal_strength(csq);
    // LLOGD("csq resp ret=%d csq=%d", ret, csq ? *csq : -1);
    return ret;
}

int luat_mobile_get_signal_strength_info(luat_mobile_signal_strength_info_t *info) {
    return luat_airlink_drv_rpc_mobile_get_signal_strength_info(info);
}

int luat_mobile_get_cell_info(luat_mobile_cell_info_t *info) {
    int ret = luat_airlink_drv_rpc_mobile_get_cell_info(info);
    // LLOGD("getCellInfo resp ret=%d lte_valid=%d gsm_valid=%d", ret, info ? info->lte_info_valid : -1, info ? info->gsm_info_valid : -1);
    return ret;
}

int luat_mobile_get_cell_info_async(uint8_t max_time) {
    uint32_t req_id = 0;
    // LLOGD("reqCellInfo req timeout=%u", max_time);
    luat_mobile_rpc_hook_notify_once();
    {
        int ret = luat_airlink_drv_rpc_mobile_cell_scan(max_time, &req_id);
        // LLOGD("reqCellInfo resp ret=%d req_id=%lu", ret, (unsigned long)req_id);
        return ret;
    }
}

int luat_mobile_get_last_notify_cell_info(luat_mobile_cell_info_t  *info) {
    int ret;
    if (!info) return -1;
    ret = luat_airlink_drv_rpc_mobile_get_last_notify_cell_info(info);
    // LLOGD("last_notify_cell_info ret=%d valid=%d", ret, s_last_cell_info_valid);
    if (ret == 0) {
        s_last_cell_info = *info;
        s_last_cell_info_valid = 1;
        return 0;
    }
    if (s_last_cell_info_valid) {
        *info = s_last_cell_info;
        return 0;
    }
    memset(info, 0, sizeof(*info));
    return ret;
}

int luat_mobile_get_extern_service_cell_info(luat_mobile_scell_extern_info_t *info) {
    return luat_airlink_drv_rpc_mobile_get_extern_service_cell_info(info);
}

int luat_mobile_get_apn(int sim_id, int cid, char* buff, size_t buf_len) {
    (void)sim_id;
    (void)cid;
    if (!buff || buf_len == 0) {
        return -1;
    }
    buff[0] = 0;
    return 0;
}

void luat_mobile_get_ip_data_traffic(uint64_t *uplink, uint64_t *downlink) {
    if (uplink) {
        *uplink = 0;
    }
    if (downlink) {
        *downlink = 0;
    }
}

void luat_mobile_clear_ip_data_traffic(uint8_t clear_uplink, uint8_t clear_downlink) {
    (void)clear_uplink;
    (void)clear_downlink;
}

int luat_mobile_get_service_cell_identifier(uint32_t *eci) {
    luat_mobile_cell_info_t info;
    int ret;
    if (!eci) return -1;
    ret = luat_mobile_get_cell_info(&info);
    if (ret != 0) return ret;
    if (info.lte_info_valid) {
        *eci = info.lte_service_info.cid;
        return 0;
    }
    if (info.gsm_info_valid) {
        *eci = info.gsm_service_info.cid;
        return 0;
    }
    *eci = 0;
    return -1;
}

int luat_mobile_get_service_tac_or_lac(uint16_t *tac) {
    luat_mobile_cell_info_t info;
    int ret;
    if (!tac) return -1;
    ret = luat_mobile_get_cell_info(&info);
    if (ret != 0) return ret;
    if (info.lte_info_valid) {
        *tac = info.lte_service_info.tac;
        return 0;
    }
    if (info.gsm_info_valid) {
        *tac = info.gsm_service_info.lac;
        return 0;
    }
    *tac = 0;
    return -1;
}

int luat_mobile_get_sim_number(int sim_id, char* buff, size_t buf_len) {
    (void)sim_id;
    if (!buff || buf_len == 0) return -1;
    buff[0] = 0;
    return 0;
}

int luat_mobile_get_sim_id(int *id) {
    if (!id) return -1;
    *id = s_mobile_sim_id;
    return 0;
}

int luat_mobile_set_sim_id(int id) {
    s_mobile_sim_id = id;
    return 0;
}

int luat_mobile_set_sim_pin(int id, uint8_t operation, char pin1[9], char pin2[9]) {
    (void)id;
    (void)operation;
    (void)pin1;
    (void)pin2;
    return 0;
}

void luat_mobile_set_sim_detect_sim0_first(void) {
}

void luat_mobile_set_default_pdn_ipv6(uint8_t onoff) {
    s_mobile_default_pdn_ipv6 = onoff ? 1 : 0;
}

void luat_mobile_set_default_pdn_only_ipv6(uint8_t onoff) {
    (void)onoff;
}

uint8_t luat_mobile_get_default_pdn_ipv6(void) {
    return s_mobile_default_pdn_ipv6;
}

void luat_mobile_user_ctrl_apn(void) {
}

void luat_mobile_user_ctrl_apn_stop(void) {
}

int luat_mobile_set_apn_base_info(int sim_id, int cid, uint8_t type, uint8_t* apn_name, uint8_t name_len) {
    (void)sim_id;
    (void)cid;
    (void)type;
    (void)apn_name;
    (void)name_len;
    return 0;
}

int luat_mobile_set_apn_auth_info(int sim_id, int cid, uint8_t protocol, uint8_t *user_name, uint8_t user_name_len, uint8_t *password, uint8_t password_len) {
    (void)sim_id;
    (void)cid;
    (void)protocol;
    (void)user_name;
    (void)user_name_len;
    (void)password;
    (void)password_len;
    return 0;
}

int luat_mobile_active_apn(int sim_id, int cid, uint8_t state) {
    (void)sim_id;
    (void)cid;
    (void)state;
    return 0;
}

int luat_mobile_active_netif(int sim_id, int cid) {
    (void)sim_id;
    (void)cid;
    return 0;
}

void luat_mobile_user_apn_auto_active(int sim_id, uint8_t cid,
		uint8_t ip_type,
		uint8_t protocol_type,
		uint8_t *apn_name, uint8_t apn_name_len,
		uint8_t *user, uint8_t user_len,
		uint8_t *password, uint8_t password_len) {
    (void)sim_id;
    (void)cid;
    (void)ip_type;
    (void)protocol_type;
    (void)apn_name;
    (void)apn_name_len;
    (void)user;
    (void)user_len;
    (void)password;
    (void)password_len;
}

int luat_mobile_get_default_apn(int sim_id, char* buff, size_t buf_len) {
    (void)sim_id;
    if (!buff || buf_len == 0) return -1;
    buff[0] = 0;
    return 0;
}

int luat_mobile_del_apn(int sim_id, uint8_t cid, uint8_t is_dedicated) {
    (void)sim_id;
    (void)cid;
    (void)is_dedicated;
    return 0;
}

int luat_mobile_set_flymode(int index, int mode) {
    (void)index;
    int old = s_mobile_flymode;
    s_mobile_flymode = mode ? 1 : 0;
    return old;
}

int luat_mobile_get_flymode(int index) {
    (void)index;
    return s_mobile_flymode;
}

#ifdef LUAT_USE_LWIP
int luat_mobile_get_local_ip(int sim_id, int cid, ip_addr_t *ip_v4, ip_addr_t *ip_v6) {
    (void)sim_id;
    (void)cid;
    (void)ip_v4;
    (void)ip_v6;
    return 0;
}
#endif

uint8_t luat_mobile_rssi_to_csq(int8_t rssi) {
    if (rssi <= -113) return 0;
    if (rssi >= -51) return 31;
    return (uint8_t)((rssi + 113) / 2);
}

int luat_mobile_get_last_notify_signal_strength_info(luat_mobile_signal_strength_info_t *info) {
    if (!info) return -1;
    memset(info, 0, sizeof(*info));
    return 0;
}

int luat_mobile_get_last_notify_signal_strength(uint8_t *csq) {
    if (!csq) return -1;
    *csq = 0;
    return 0;
}

void luat_mobile_rrc_auto_release_pause(uint8_t onoff) {
    (void)onoff;
}

void luat_mobile_rrc_release_once(void) {
}

int luat_mobile_set_check_sim(uint32_t check_sim_period) {
    (void)check_sim_period;
    return 0;
}

void luat_mobile_set_check_network_period(uint32_t period) {
    (void)period;
}

int luat_mobile_reset_stack(void) {
    return 0;
}

void luat_mobile_fatal_error_auto_reset_stack(uint8_t onoff) {
    (void)onoff;
}

int luat_mobile_set_period_work(uint32_t get_cell_period, uint32_t check_sim_period, uint8_t search_cell_time) {
    (void)get_cell_period;
    (void)check_sim_period;
    (void)search_cell_time;
    return 0;
}

int luat_mobile_get_support_band(uint8_t *band,  uint8_t *total_num) {
    if (band) band[0] = 0;
    if (total_num) *total_num = 0;
    return 0;
}

int luat_mobile_get_band(uint8_t *band,  uint8_t *total_num) {
    if (band) band[0] = 0;
    if (total_num) *total_num = 0;
    return 0;
}

int luat_mobile_set_band(uint8_t *band,  uint8_t total_num) {
    (void)band;
    (void)total_num;
    return 0;
}

int luat_mobile_config(uint8_t item, uint32_t value) {
    (void)item;
    (void)value;
    return 0;
}

void luat_mobile_rf_test_mode(uint8_t uart_id, uint8_t on_off) {
    (void)uart_id;
    (void)on_off;
}

void luat_mobile_rf_test_input(char *data, uint32_t data_len) {
    (void)data;
    (void)data_len;
}

void luat_mobile_set_sync_time(uint8_t on_off) {
    s_mobile_sync_time = on_off ? 1 : 0;
}

uint8_t luat_mobile_get_sync_time(void) {
    return s_mobile_sync_time;
}

int luat_mobile_softsim_onoff(uint8_t on_off) {
    (void)on_off;
    return 0;
}

int luat_mobile_sim_detect_onoff(uint8_t on_off) {
    (void)on_off;
    return 0;
}

void luat_mobile_softsim_init_default(void) {
}

int luat_mobile_lock_cell(uint32_t op, uint32_t earfcn, uint16_t pci) {
    (void)op;
    (void)earfcn;
    (void)pci;
    return 0;
}

void luat_mobile_vsim_user_heartbeat_once(void) {
}

uint32_t luat_mobile_get_search_plmn(void) {
    return 0;
}

void luat_mobile_data_ip_mode(uint8_t on_off) {
    (void)on_off;
}

void luat_mobile_init_auto_apn(void) {
}

void net_lwip_check_switch(uint8_t onoff) {
    (void)onoff;
}

void luat_mobile_set_rrc_auto_release_time(uint8_t s) {
    (void)s;
}

void luat_mobile_set_auto_rrc(uint8_t s1, uint32_t s2) {
    (void)s1;
    (void)s2;
}

int luat_mobile_make_call(uint8_t sim_id, char *number, uint8_t len) {
    (void)sim_id;
    (void)number;
    (void)len;
    return 0;
}

void luat_mobile_hangup_call(uint8_t sim_id) {
    (void)sim_id;
}

int luat_mobile_answer_call(uint8_t sim_id) {
    (void)sim_id;
    return 0;
}

int luat_mobile_speech_init(uint8_t multimedia_id,void *callback) {
    (void)multimedia_id;
    (void)callback;
    return 0;
}

int luat_mobile_speech_upload(uint8_t *data, uint32_t len) {
    (void)data;
    (void)len;
    return 0;
}

void luat_mobile_rrc_get_idle_meas_threshold(int16_t *sIntraSearchP, int16_t *sNonIntraSearchP, int16_t *sIntraSearchQ, int16_t *sNonIntraSearchQ) {
    if (sIntraSearchP) *sIntraSearchP = 0;
    if (sNonIntraSearchP) *sNonIntraSearchP = 0;
    if (sIntraSearchQ) *sIntraSearchQ = 0;
    if (sNonIntraSearchQ) *sNonIntraSearchQ = 0;
}

int luat_mobile_event_register_handler(luat_mobile_event_callback_t callback_fun) {
    LLOGD("event register cb=%p", callback_fun);
    s_mobile_event_cb = callback_fun;
    luat_mobile_rpc_hook_notify_once();
    return 0;
}

int luat_mobile_event_deregister_handler(void) {
    s_mobile_event_cb = NULL;
    return 0;
}

#endif
