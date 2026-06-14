#include "luat_base.h"
#include "luat_sys.h"
#include "luat_mobile.h"
#include "luat_str.h"
#include "luat_mcu.h"
#include "luat_crypto.h"
#ifdef LUAT_USE_LWIP
#include "lwip/ip_addr.h"
#endif

// #define LUAT_LOG_TAG "mobile"

static uint8_t generate_imei_check_digit(const char* imei);

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

}
void luat_mobile_rf_test_input(char *data, uint32_t data_len)
{
    
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

#ifdef LUAT_USE_MOBILE_RFCAL
/*
 * RF 校准仿真:PC 端用真实日志数据驱动完整状态机实现
 *
 * 数据来源:F:\hardware\calrf\864317081553409_UartComm_Log_Port14.txt
 *          真实 EC718 模组校准会话(IMEI=864317081553409, 时间=2026-06-12-15-17)
 *
 * 状态机:0=IDLE, 1=PREP, 2=CALIB, 3=SELF_CAL, 4=WRITE_NV, 5=NST_TEST, 6=DONE
 */
#include <string.h>
#include <stdio.h>

/* 模块静态状态(单实例,够 PC 仿真用) */
static int s_rfcal_state = 0;
static int s_npi_rfCaliDone = 0;
static int s_npi_rfNSTDone  = 0;
static int s_npi_rfCTDone   = 0;
static char s_rfcal_imei[16] = "864317081553409";

/* 真实日志 fixture(供将来扩展) */
static const char* REAL_IMEI      = "864317081553409";
static const char* REAL_TIMESTAMP = "2026-06-12-15-17";
static const char* REAL_DAC       = "46EC46EC46EC46EC46EC46EC46EC46EC";

int luat_mobile_rfcal_npi_get(const char *key, int *value) {
    if (!key || !value) return -1;
    if      (strcmp(key, "rfCaliDone") == 0) *value = s_npi_rfCaliDone;
    else if (strcmp(key, "rfNSTDone")  == 0) *value = s_npi_rfNSTDone;
    else if (strcmp(key, "rfCTDone")   == 0) *value = s_npi_rfCTDone;
    else return -1;
    return 0;
}

int luat_mobile_rfcal_npi_set(const char *key, int value) {
    if (!key) return -1;
    int v = value ? 1 : 0;
    if      (strcmp(key, "rfCaliDone") == 0) s_npi_rfCaliDone = v;
    else if (strcmp(key, "rfNSTDone")  == 0) s_npi_rfNSTDone  = v;
    else if (strcmp(key, "rfCTDone")   == 0) s_npi_rfCTDone   = v;
    else return -1;
    return 0;
}

int luat_mobile_rfcal_get_state(void) {
    return s_rfcal_state;
}

int luat_mobile_rfcal_reset(void) {
    s_rfcal_state = 0;
    s_npi_rfCaliDone = s_npi_rfNSTDone = s_npi_rfCTDone = 0;
    return 0;
}

int luat_mobile_rfcal_set_imei(const char *imei) {
    if (!imei || strlen(imei) != 15) return -1;
    memcpy(s_rfcal_imei, imei, 15);
    s_rfcal_imei[15] = 0;
    return 0;
}

int luat_mobile_rfcal_at_dispatch(const char *line, char *resp, uint32_t resp_len) {
    if (!line || !resp || resp_len < 8) return -1;
    /* 关键:具体命令必须在通用 "AT" 前缀检查之前,否则 "AT+CGSN=1"
     * 会被 strncmp(line, "AT", 2) 优先匹配,导致具体分支无法触发
     */
    if (strncmp(line, "AT+CGSN=1", 9) == 0) {
        snprintf(resp, resp_len, "\r\n+CGSN: \"%s\"\r\n\r\nOK\r\n", s_rfcal_imei);
        if (s_rfcal_state < 1) s_rfcal_state = 1;  /* PREP */
    } else if (strncmp(line, "AT+ECNPICFG=rfCaliDone,1", 24) == 0) {
        s_npi_rfCaliDone = 1;
        s_rfcal_state = 4;  /* WRITE_NV */
        snprintf(resp, resp_len, "\r\nOK\r\n");
    } else if (strncmp(line, "AT+ECNPICFG=rfCaliDone,0", 24) == 0) {
        s_npi_rfCaliDone = 0;
        snprintf(resp, resp_len, "\r\nOK\r\n");
    } else if (strncmp(line, "AT+ECNPICFG=rfNSTDone,1", 23) == 0) {
        s_npi_rfNSTDone = 1;
        s_rfcal_state = 6;  /* DONE */
        snprintf(resp, resp_len, "\r\nOK\r\n");
    } else if (strncmp(line, "AT+ECNPICFG=rfCTDone,1", 22) == 0) {
        s_npi_rfCTDone = 1;
        snprintf(resp, resp_len, "\r\nOK\r\n");
    } else if (strncmp(line, "AT+ECNPICFG?", 12) == 0) {
        snprintf(resp, resp_len,
            "\r\n+ECNPICFG: \"rfCaliDone\":%d,\"rfNSTDone\":%d,\"rfCTDone\":%d\r\n\r\nOK\r\n",
            s_npi_rfCaliDone, s_npi_rfNSTDone, s_npi_rfCTDone);
    } else if (strncmp(line, "AT+CFUN=0", 9) == 0) {
        snprintf(resp, resp_len, "\r\nOK\r\n");
    } else if (strncmp(line, "AT+CPIN?", 8) == 0) {
        /* 真实日志:校准环境无 SIM,返 +CME ERROR: 303 */
        snprintf(resp, resp_len, "\r\n+CME ERROR: 303\r\n");
    } else if (strncmp(line, "AT+ECCHIPVER?", 13) == 0) {
        /* 真实日志:ECCHIPVER 固件未实现,返 ERROR */
        snprintf(resp, resp_len, "\r\nERROR\r\n");
    } else if (strncmp(line, "AT+ECGMDATA?", 12) == 0) {
        snprintf(resp, resp_len, "\r\nOK\r\n");
    } else if (strncmp(line, "ATE", 3) == 0) {
        snprintf(resp, resp_len, "%s\r\nOK\r\n", line);
    } else if (strncmp(line, "AT", 2) == 0) {
        snprintf(resp, resp_len, "%s\r\nOK\r\n", line);
    } else {
        snprintf(resp, resp_len, "\r\nERROR\r\n");
        return -1;
    }
    return 0;
}

int luat_mobile_rfcal_rfnst(const char *in_hex, char *out_hex, uint32_t out_hex_len) {
    if (!in_hex || !out_hex) return -1;
    if (strlen(in_hex) < 4) return -1;
    /* 真实协议响应格式:MT + cmdId 2B + retStatus 4B + dataLen 4B + crc 4B + payload
     * PC 桩简化:把输入的 cmdId 字节回显,保持 retStatus=0(成功),dataLen=1 字节
     * 真实日志样例:MT0000880100010000...   cmdId=0x0008, retStatus=0x01000000
     */
    snprintf(out_hex, out_hex_len, "MT%.4s00000001000000000000", in_hex);
    /* 状态推进:任何 cmdId 都视为进入 CALIB 阶段 */
    if (s_rfcal_state < 2) s_rfcal_state = 2;
    return 0;
}
#endif /* LUAT_USE_MOBILE_RFCAL */
