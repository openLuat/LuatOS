#include "luat_base.h"
#include "luat_sys.h"
#include "luat_mobile.h"
#include "luat_str.h"
#include "luat_mcu.h"
#include "luat_crypto.h"
#include "luat_log.h"
#define LUAT_LOG_TAG "mobile"
#ifdef LUAT_USE_LWIP
#include "lwip/ip_addr.h"
#endif

static uint8_t generate_imei_check_digit(const char* imei);

/* ============================================================
 *  PC 端 RF 测试状态 (rfa 回环模拟器的存储)
 *  故意放在文件顶部, 让 luat_mobile_rf_test_mode/input 能直接引用
 *  真机不需要这一段 (luatos-soc-2024 在 PLAT 层维护)
 * ============================================================ */
static struct {
    int      state;
    int      npi_rfCaliDone, npi_rfNSTDone, npi_rfCTDone;
    char     imei[16];
    int      erf_mode;
    uint8_t  uart_id;     /* 0xff = 未进入 */
    luat_mobile_rf_test_rx_cb_t cb;
} s_rf_test = {
    .state = 0,
    .imei  = "864317081553409",  /* 默认 IMEI, 与 luatos-soc-2024 一致 */
};

int luat_mobile_get_imei(int sim_id, char* buff, size_t buf_len)
{
    size_t mcu_uuid_len = 0;
    char md5buff[32] = {0};
    char hexbuff[33] = {0};
    const char* mcu_uuid = luat_mcu_unique_id(&mcu_uuid_len);
    if(mcu_uuid_len > 0) {
        luat_crypto_md("MD5", mcu_uuid, mcu_uuid_len, md5buff, NULL, 0);
        luat_str_tohex(md5buff, 16, hexbuff);

        // 从MD5的十六进制字符串中提取数字，生成9-10位的十进制字符串
        // 取前8个字节(16个十六进制字符)转换为64位整数，再取模得到10位数字
        unsigned long long num = 0;
        for (int i = 0; i < 16 && hexbuff[i]; i++) {
            num = num * 16;
            if (hexbuff[i] >= '0' && hexbuff[i] <= '9') {
                num += hexbuff[i] - '0';
            } else if (hexbuff[i] >= 'a' && hexbuff[i] <= 'f') {
                num += hexbuff[i] - 'a' + 10;
            } else if (hexbuff[i] >= 'A' && hexbuff[i] <= 'F') {
                num += hexbuff[i] - 'A' + 10;
            }
        }

        num = (num % 900000000ULL) + 100000000ULL;
        snprintf(buff, buf_len, "86228905%llu", num);
        buff[15] = 0x00; //确保结束符
        buff[14] = '0' + generate_imei_check_digit((const char*)buff);
        // TODO imei的最后一位是校验位,这里没有计算
        return 1;
    }

    return -1;
}
int luat_mobile_get_sn(char* buff, size_t buf_len)
{
    return 0;
}
int luat_mobile_set_sn(char* buff, uint8_t buf_len)
{
    return 0;
}
int luat_mobile_get_muid(char* buff, size_t buf_len)
{
    return 0;
}
int luat_mobile_get_iccid(int sim_id, char* buff, size_t buf_len)
{
    return 0;
}
int luat_mobile_get_imsi(int sim_id, char* buff, size_t buf_len)
{
    return 0;
}
int luat_mobile_get_sim_number(int sim_id, char* buff, size_t buf_len)
{
    return 0;
}
int luat_mobile_get_sim_id(int *id)
{
    return 0;
}
int luat_mobile_set_sim_id(int id)
{
    return 0;
}
int luat_mobile_set_sim_pin(int id, uint8_t operation, char pin1[9], char pin2[9])
{
    return 0;
}
uint8_t luat_mobile_get_sim_ready(int id)
{
    return 0;
}
void luat_mobile_set_sim_detect_sim0_first(void)
{
    
}
void luat_mobile_set_default_pdn_ipv6(uint8_t onoff)
{

}
void luat_mobile_set_default_pdn_only_ipv6(uint8_t onoff)
{

}
uint8_t luat_mobile_get_default_pdn_ipv6(void)
{

    return 0;
}
int luat_mobile_get_apn(int sim_id, int cid, char* buff, size_t buf_len)
{
    return 0;
}
void luat_mobile_user_ctrl_apn(void)
{   

}
void luat_mobile_user_ctrl_apn_stop(void)
{

}
int luat_mobile_set_apn_base_info(int sim_id, int cid, uint8_t type, uint8_t* apn_name, uint8_t name_len)
{
    return 0;
}

int luat_mobile_active_apn(int sim_id, int cid, uint8_t state)
{
    return 0;
}
int luat_mobile_active_netif(int sim_id, int cid)
{
    return 0;
}
void luat_mobile_user_apn_auto_active(int sim_id, uint8_t cid,
		uint8_t ip_type,
		uint8_t protocol_type,
		uint8_t *apn_name, uint8_t apn_name_len,
		uint8_t *user, uint8_t user_len,
		uint8_t *password, uint8_t password_len)
{

}
int luat_mobile_get_default_apn(int sim_id, char* buff, size_t buf_len)
{
    return 0;
}
int luat_mobile_del_apn(int sim_id, uint8_t cid, uint8_t is_dedicated)
{
    return 0;
}
int luat_mobile_set_flymode(int index, int mode)
{
    return 0;
}
int luat_mobile_get_flymode(int index)
{
    return 0;
}
#ifdef LUAT_USE_LWIP
int luat_mobile_get_local_ip(int sim_id, int cid, ip_addr_t *ip_v4, ip_addr_t *ip_v6)
{
    return 0;
}
#endif
int luat_mobile_get_cell_info(luat_mobile_cell_info_t  *info)
{
    return 0;
}
int luat_mobile_get_cell_info_async(uint8_t max_time)
{
    return 0;
}
int luat_mobile_get_cell_info_async_with_sim_id(uint8_t sim_id)
{
    return 0;
}
int luat_mobile_get_last_notify_cell_info(luat_mobile_cell_info_t  *info)
{
    return 0;
}
int luat_mobile_get_last_notify_cell_info_with_sim_id(uint8_t sim_id, luat_mobile_cell_info_t  *info)
{
    return 0;
}
void luat_mobile_print_last_notify_cell_info_with_sim_id(uint8_t sim_id)
{   

}
uint8_t luat_mobile_rssi_to_csq(int8_t rssi)
{
    return 0;
}
int luat_mobile_get_signal_strength_info(luat_mobile_signal_strength_info_t *info)
{   
    return 0;
}
int luat_mobile_get_signal_strength(uint8_t *csq)
{   
    return 0;
}
int luat_mobile_get_last_notify_signal_strength_info(luat_mobile_signal_strength_info_t *info)
{
    return 0;
}
int luat_mobile_get_last_notify_signal_strength(uint8_t *csq)
{
    return 0;
}
int luat_mobile_get_service_cell_identifier(uint32_t *eci)
{
    return 0;
}
int luat_mobile_get_service_tac_or_lac(uint16_t *tac)
{
    return 0;
}

LUAT_MOBILE_SIM_STATUS_E luat_mobile_get_sim_status(void)
{
    return 0;
}

LUAT_MOBILE_REGISTER_STATUS_E luat_mobile_get_register_status(void)
{
    return 0;
}
int luat_mobile_event_register_handler(luat_mobile_event_callback_t callback_fun)
{
    return 0;
}
int luat_mobile_event_deregister_handler(void)
{
    return 0;
}
int luat_mobile_sms_sdk_event_register_handler(luat_mobile_sms_event_callback_t callback_fun)
{
    return 0;
}
int luat_mobile_sms_event_register_handler(luat_mobile_sms_event_callback_t callback_fun)
{
    return 0;
}

#ifndef __USE_SDK_LWIP__
 void net_lwip_check_switch(uint8_t onoff)
{
	
}
#endif
void luat_mobile_set_rrc_auto_release_time(uint8_t s)
{

}
//实验性质API，请勿使用
void luat_mobile_set_auto_rrc(uint8_t s1, uint32_t s2)
{

}
void luat_mobile_set_auto_rrc_default(void)
{
    
}
void luat_mobile_rrc_auto_release_pause(uint8_t onoff)
{

}
void luat_mobile_rrc_release_once(void)
{   

}
int luat_mobile_reset_stack(void)
{
    return 0;
}
void luat_mobile_fatal_error_auto_reset_stack(uint8_t onoff)
{   

}
int luat_mobile_set_period_work(uint32_t get_cell_period, uint32_t check_sim_period, uint8_t search_cell_time)
{
    return 0;
}
int luat_mobile_set_check_sim(uint32_t check_sim_period)
{
    return 0;
}
void luat_mobile_set_check_network_period(uint32_t period)
{
    
}
void luat_mobile_get_ip_data_traffic(uint64_t *uplink, uint64_t *downlink)
{

}
void luat_mobile_clear_ip_data_traffic(uint8_t clear_uplink, uint8_t clear_downlink)
{

}
int luat_mobile_get_support_band(uint8_t *band,  uint8_t *total_num)
{
    return 0;
}
int luat_mobile_get_band(uint8_t *band,  uint8_t *total_num)
{
    return 0;
}
int luat_mobile_set_band(uint8_t *band,  uint8_t total_num)
{
    return 0;
}
int luat_mobile_config(uint8_t item, uint32_t value)
{
    return 0;
}
void luat_mobile_rf_test_mode(uint8_t uart_id, uint8_t on_off)
{
    s_rf_test.uart_id = on_off ? uart_id : 0xff;
    if (on_off) {
        LLOGD("rf_test: enter mode, uart=%d", uart_id);
    } else {
        LLOGD("rf_test: exit mode");
    }
}
void luat_mobile_rf_test_input(char *data, uint32_t data_len)
{
    // 保留原 API 的双语义: data!=NULL && len>0 透传到 Lua 回调, NULL/0 触发 flush
    if (data && data_len) {
        if (s_rf_test.cb.on_rx) {
            s_rf_test.cb.on_rx((const uint8_t *)data, data_len, s_rf_test.cb.userdata);
        }
    } else {
        // flush: 通知 Lua 触发切行处理 (对流式接收的 UART 接收方有意义)
        if (s_rf_test.cb.on_rx) {
            s_rf_test.cb.on_rx(NULL, 0, s_rf_test.cb.userdata);
        }
    }
}
uint32_t luat_mobile_sim_write_counter(void)
{
    return 0;
}
// int luat_mobile_get_isp_from_plmn(uint16_t mcc, uint8_t mnc)
// {
//     return 0;
// }
// int luat_mobile_get_plmn_from_imsi(char *imsi, uint16_t *mcc, uint8_t *mnc)
// {
//     return 0;
// }
void luat_mobile_get_last_call_num(char *buf, uint8_t buf_len)
{

}
int luat_mobile_make_call(uint8_t sim_id, char *number, uint8_t len)
{
    return 0;
}
void luat_mobile_hangup_call(uint8_t sim_id)
{

}
int luat_mobile_answer_call(uint8_t sim_id)
{
    return 0;
}
int luat_mobile_speech_init(uint8_t multimedia_id,void *callback)
{
    return 0;
}
int luat_mobile_speech_upload(uint8_t *data, uint32_t len)
{
    return 0;
}
void luat_mobile_set_sync_time(uint8_t on_off)
{
    
}
uint8_t luat_mobile_get_sync_time(void)
{
    return 0;
}
int luat_mobile_softsim_onoff(uint8_t on_off)
{   
    return 0;
}
int luat_mobile_sim_detect_onoff(uint8_t on_off)
{
    return 0;
}
void luat_mobile_softsim_init_default(void)
{   

}
int luat_mobile_lock_cell(uint32_t op, uint32_t earfcn, uint16_t pci)
{
    return 0;
}
int luat_mobile_get_extern_service_cell_info(luat_mobile_scell_extern_info_t *info)
{
    return 0;
}
void luat_mobile_vsim_user_heartbeat_once(void)
{   

}
uint32_t luat_mobile_get_search_plmn(void)
{
    return 0;
}
void luat_mobile_data_ip_mode(uint8_t on_off)
{

}

// void luat_mobile_init_auto_apn_by_plmn(void)
// {
    
// }
void luat_mobile_init_auto_apn(void)
{

}
// void luat_mobile_add_auto_apn_item(uint16_t mcc, uint16_t mnc, uint8_t ip_type, uint8_t protocol, char *name, uint8_t name_len, char *user, uint8_t user_len, char *password, uint8_t password_len, uint8_t task_safe)
// {
    
// }
// int luat_mobile_find_apn_by_mcc_mnc(uint16_t mcc, uint16_t mnc, apn_info_t *apn)
// {
//     return 0;
// }
// void luat_mobile_print_apn_by_mcc_mnc(uint16_t mcc, uint16_t mnc)
// {   

// }


// 补充一个空实现
void luat_mobile_rrc_get_idle_meas_threshold(int16_t *sIntraSearchP, int16_t *sNonIntraSearchP, int16_t *sIntraSearchQ, int16_t *sNonIntraSearchQ) {
	*sIntraSearchP = 0;
	*sNonIntraSearchP = 0;
	*sIntraSearchQ = 0;
	*sNonIntraSearchQ = 0;
}

// 辅助函数
// 计算imei的校验位
#include <stdint.h>
#include <ctype.h>

static uint8_t generate_imei_check_digit(const char* imei) {
    int sum = 0;
    
    // 遍历前14位数字
    for (int i = 0; i < 14; i++) {
        // 检查字符是否为数字
        if (!isdigit(imei[i])) {
            return 0xFF; // 返回错误值
        }
        
        int digit = imei[i] - '0';
        
        // 从右向左，偶数位置（从0开始计数）需要特殊处理
        if ((13 - i) % 2 == 1) {
            digit *= 2;
            // 如果结果大于9，则将各位数字相加
            if (digit > 9) {
                digit = digit / 10 + digit % 10;
            }
        }
        
        sum += digit;
    }
    
    // 计算校验位：使得总和能被10整除的数字
    uint8_t check_digit = (10 - (sum % 10)) % 10;

    return check_digit;
}

/* ============================================================
 *  新增 luat_mobile_rf_test_param / imei_get / imei_set / set_rx_cb
 *  这些函数**不做**任何 AT 派发, 只是 PC 端"模组"的存储后端
 *  全部 AT 协议由 Lua rfa.* 模块负责
 *  真机直接返回 -1 (NPI/NV 不走此口)
 * ============================================================ */
#include <string.h>

int luat_mobile_rf_test_set_rx_cb(const luat_mobile_rf_test_rx_cb_t *cb) {
    if (cb) {
        s_rf_test.cb = *cb;
    } else {
        s_rf_test.cb.on_rx = NULL;
        s_rf_test.cb.userdata = NULL;
    }
    return 0;
}

int luat_mobile_rf_test_param(const char *key, int *value, int is_set) {
    if (!key || !value) return -1;
    if (is_set) {
        if      (!strcmp(key, "save"))                        return 0; /* PC 仿真无需落 flash, no-op */
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_NPI_CALI)) s_rf_test.npi_rfCaliDone = !!*value;
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_NPI_NST))  s_rf_test.npi_rfNSTDone  = !!*value;
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_NPI_CT))   s_rf_test.npi_rfCTDone   = !!*value;
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_STATE))    s_rf_test.state          = *value;
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_ERF_MODE)) s_rf_test.erf_mode       = !!*value;
        else return -1;
    } else {
        if      (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_NPI_CALI)) *value = s_rf_test.npi_rfCaliDone;
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_NPI_NST))  *value = s_rf_test.npi_rfNSTDone;
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_NPI_CT))   *value = s_rf_test.npi_rfCTDone;
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_STATE))    *value = s_rf_test.state;
        else if (!strcmp(key, LUAT_MOBILE_RF_TEST_KEY_ERF_MODE)) *value = s_rf_test.erf_mode;
        else return -1;
    }
    return 0;
}

int luat_mobile_rf_test_imei_get(char *out, uint32_t len) {
    if (!out || len < 16) return -1;
    memcpy(out, s_rf_test.imei, 16);
    return 0;
}

int luat_mobile_rf_test_imei_set(const char *imei) {
    if (!imei || strlen(imei) != 15) return -1;
    memcpy(s_rf_test.imei, imei, 15);
    s_rf_test.imei[15] = 0;
    return 0;
}
