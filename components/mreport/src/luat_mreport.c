#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/udp.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_mobile.h"
#include "luat_hmeta.h"
#include "luat_pm.h"
#include "luat_adc.h"
#include "luat_str.h"
#include "cJSON.h"

#define LUAT_LOG_TAG "netdrv.napt.mreport"
#include "luat_log.h"

#define MREPORT_DOMAIN "47.94.236.172"
#define MREPORT_PORT (12388)
// #define MREPORT_DOMAIN "112.125.89.8"
// #define MREPORT_PORT (42919)

static struct udp_pcb* mreport_pcb;
static luat_rtos_timer_t mreport_timer;

static inline uint16_t u162bcd(uint16_t src) {
    uint8_t high = (src >> 8) & 0xFF;
    uint8_t low  = src & 0xFF;
    uint16_t dst = 0;
    dst += (low & 0x0F) + (low >> 4) * 10;
    dst += ((high & 0x0F) + (high >> 4) * 10) * 100;
    //LLOGD("src %04X dst %d", src, dst);
    return dst;
}

// 模块的基础信息
void luat_mreport_mobile(cJSON* mreport_data) {
    // IMEI
    char imei[16] = {0};
    luat_mobile_get_imei(0, imei, 16);                  
    cJSON_AddStringToObject(mreport_data, "imei", imei);

    // MUID
    char muid[33] = {0};
    luat_mobile_get_muid(muid, 32);
    muid[32] = '\0';
    cJSON_AddStringToObject(mreport_data, "muid", muid);

    // unique_id
	size_t len = 0;
    char buff[128] = {0};
    const char* unique_id = luat_mcu_unique_id(&len);
    luat_str_tohex(unique_id, len, buff);
    cJSON_AddStringToObject(mreport_data, "unique_id", buff);

    // 版本号
    cJSON_AddStringToObject(mreport_data, "bspver", luat_version_str());

    // 模组型号
    char model_name[20] = {0};
    luat_hmeta_model_name(model_name);
    cJSON_AddStringToObject(mreport_data, "model", model_name);

    // 硬件版本
    char hwversion[20] = {0};
    luat_hmeta_hwversion(hwversion);
    cJSON_AddStringToObject(mreport_data, "hwver", hwversion);

    // sdk固件类型 0:luatos 1:
    cJSON_AddNumberToObject(mreport_data, "sdk", 0);


    // cJSON_AddStringToObject(mreport_data, "pver", "1.0.0");
    // cJSON_AddStringToObject(mreport_data, "proj", "air8000_wifi");
}

// 网络信息
void luat_mreport_sim_network(cJSON* mreport_data, struct netif* netif) {
    cJSON* cells = cJSON_CreateArray();
    // ICCID
    char iccid[24] = {0};
    luat_mobile_get_iccid(0, (char*)iccid, 24);
    iccid[23] = '\0';   // 防止iccid为空时，导致字符串结束符丢失
    cJSON_AddStringToObject(mreport_data, "iccid", iccid);

    // IMSI
    char imsi[16] = {0};
    luat_mobile_get_imsi(0, imsi, 16);
    cJSON_AddStringToObject(mreport_data, "imsi", imsi);

    // VSIM
    cJSON_AddNumberToObject(mreport_data, "vsim", 0);

    // 信号强度
    luat_mobile_signal_strength_info_t info = {0};
    if (luat_mobile_get_signal_strength_info(&info) == 0) {
        cJSON_AddNumberToObject(mreport_data, "rssi", info.lte_signal_strength.rssi);
        cJSON_AddNumberToObject(mreport_data, "rsrq", info.lte_signal_strength.rsrq);
        cJSON_AddNumberToObject(mreport_data, "rsrp", info.lte_signal_strength.rsrp);
        cJSON_AddNumberToObject(mreport_data, "snr", info.lte_signal_strength.snr);
    }

    // 基站/小区
    luat_mobile_get_cell_info_async(5);
    luat_mobile_cell_info_t* cell_info = luat_heap_malloc(sizeof(luat_mobile_cell_info_t));
    if (cell_info == NULL) {
        LLOGE("out of memory when malloc cell_info");
    }
    else {
        int ret = luat_mobile_get_last_notify_cell_info(cell_info);
        if (ret != 0) {
            LLOGI("none cell info found %d", ret);
        }
        else {
            cJSON_AddNumberToObject(mreport_data, "cid", cell_info->lte_service_info.cid);
            cJSON_AddNumberToObject(mreport_data, "pci", cell_info->lte_service_info.pci);
            cJSON_AddNumberToObject(mreport_data, "tac", cell_info->lte_service_info.tac);
            cJSON_AddNumberToObject(mreport_data, "band", cell_info->lte_service_info.band);
            cJSON_AddNumberToObject(mreport_data, "earfcn", cell_info->lte_service_info.earfcn);
            cJSON_AddNumberToObject(mreport_data, "mcc", u162bcd(cell_info->lte_service_info.mcc));
            cJSON_AddNumberToObject(mreport_data, "mnc", u162bcd(cell_info->lte_service_info.mnc));
            uint32_t eci;
            if (luat_mobile_get_service_cell_identifier(&eci) == 0) {
                cJSON_AddNumberToObject(mreport_data, "eci", eci);
            }
            
            if (cell_info->lte_neighbor_info_num > 0) {
                for (size_t i = 0; i < cell_info->lte_neighbor_info_num; i++) {
                    cJSON * cell = cJSON_CreateObject();
                    // 邻近小区的信息
	                cJSON_AddNumberToObject(cell, "cid", cell_info->lte_info[i].cid);
                    cJSON_AddNumberToObject(cell, "pci", cell_info->lte_info[i].pci);
                    cJSON_AddNumberToObject(cell, "rsrp", cell_info->lte_info[i].rsrp);
                    cJSON_AddNumberToObject(cell, "rsrq", cell_info->lte_info[i].rsrq);
                    cJSON_AddNumberToObject(cell, "snr", cell_info->lte_info[i].snr);
                    cJSON_AddNumberToObject(cell, "tac", cell_info->lte_info[i].tac);
                    cJSON_AddItemToArray(cells, cell);
                }
                cJSON_AddItemToObject(mreport_data, "cells", cells);
            }
        }
    }

    // ip地址
    cJSON_AddStringToObject(mreport_data, "ipv4", ip4addr_ntoa(&netif->ip_addr));
    // cJSON_AddStringToObject(mreport_data, "ipv6", ip6addr_ntoa(&netif->ip6_addr));

    // 当前使用的apn
    char buff[64] = {0};
    luat_mobile_get_apn(0, 0, buff, sizeof(buff) - 1);
    cJSON_AddStringToObject(mreport_data, "apn", buff);

    // uplink 上行流量 && downlink 下行流量
    uint64_t uplink;
    uint64_t downlink;
    luat_mobile_get_ip_data_traffic(&uplink, &downlink);
    cJSON_AddNumberToObject(mreport_data, "uplink", uplink);
    cJSON_AddNumberToObject(mreport_data, "downlink", downlink);
}

void luat_mreport_send(void) {
    ip_addr_t host = {0};
    int ret = 0;
    size_t olen = 0;
    cJSON* mreport_data = cJSON_CreateObject();

    luat_netdrv_t* netdrv = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_GPRS);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return;
    }

    struct netif *netif = netdrv->netif;
    if (netif == NULL || ip_addr_isany(&netif->ip_addr)) {
        // LLOGD("还没联网");
        return;
    }

    if (mreport_pcb == NULL) {
        mreport_pcb = udp_new();
        if (mreport_pcb == NULL) {
            LLOGE("创建udp pcb 失败, 内存不足?");
            return;
        }
    }
    // ipaddr_aton("47.94.236.172", &host);
    ipaddr_aton(MREPORT_DOMAIN, &host);
    ret = udp_connect(mreport_pcb, &host, MREPORT_PORT);
    if (ret) {
        LLOGD("udp_connect %d", ret);
        return;
    }

    // 时间戳
    struct tm* ts;
	time_t t;
	time(&t);
    localtime_r(&t, &ts);
    time_t timestamp = mktime(&ts);
    cJSON_AddNumberToObject(mreport_data, "localtime", timestamp);

    // 模组信息
    luat_mreport_mobile(mreport_data);

    // sim卡和网络相关
    luat_mreport_sim_network(mreport_data, netif);

    // rndis
    cJSON_AddNumberToObject(mreport_data, "rndis", 0);
    // usb
    cJSON_AddNumberToObject(mreport_data, "usb", 1);
    // vbus
    cJSON_AddNumberToObject(mreport_data, "vbus", 1);
    
    // adc-vbat
    if (luat_adc_open(LUAT_ADC_CH_VBAT, NULL) == 0) {
        int val = 0xFF;
        int val2 = 0xFF;
        if (luat_adc_read(LUAT_ADC_CH_VBAT, &val, &val2) == 0) {
            cJSON_AddNumberToObject(mreport_data, "vbat", val2);
        }
    }
    // adc-cpu
    if (luat_adc_open(LUAT_ADC_CH_CPU, NULL) == 0) {
        int val = 0xFF;
        int val2 = 0xFF;
        if (luat_adc_read(LUAT_ADC_CH_CPU, &val, &val2) == 0) {
            cJSON_AddNumberToObject(mreport_data, "cputemp", val2);
        }
    }

    // 开机原因
    cJSON_AddNumberToObject(mreport_data, "powerreson", luat_pm_get_poweron_reason());
    // 当前内存状态
    size_t total = 0;
    size_t used = 0;
    size_t max_used = 0;
    cJSON* meminfo_sram = cJSON_CreateArray();
    luat_meminfo_opt_sys(LUAT_HEAP_SRAM, &total, &used, &max_used);
    cJSON_AddItemToArray(meminfo_sram, cJSON_CreateNumber(total));
    cJSON_AddItemToArray(meminfo_sram, cJSON_CreateNumber(used));
    cJSON_AddItemToArray(meminfo_sram, cJSON_CreateNumber(max_used));
    cJSON_AddItemToObject(mreport_data, "mem_sram", meminfo_sram);
    
    cJSON* meminfo_psram = cJSON_CreateArray();
    luat_meminfo_opt_sys(LUAT_HEAP_PSRAM, &total, &used, &max_used);
    cJSON_AddItemToArray(meminfo_psram, cJSON_CreateNumber(total));
    cJSON_AddItemToArray(meminfo_psram, cJSON_CreateNumber(used));
    cJSON_AddItemToArray(meminfo_psram, cJSON_CreateNumber(max_used));
    cJSON_AddItemToObject(mreport_data, "mem_sys", meminfo_psram);
    cJSON_AddItemToObject(mreport_data, "mem_psram", meminfo_psram);

    cJSON* meminfo_luavm = cJSON_CreateArray();
    luat_meminfo_luavm(&total, &used, &max_used);
    cJSON_AddItemToArray(meminfo_luavm, cJSON_CreateNumber(total));
    cJSON_AddItemToArray(meminfo_luavm, cJSON_CreateNumber(used));
    cJSON_AddItemToArray(meminfo_luavm, cJSON_CreateNumber(max_used));
    cJSON_AddItemToObject(mreport_data, "mem_lua", meminfo_luavm);
    cJSON_AddNumberToObject(mreport_data, "memfree", total - used);

    // 开机次数
    cJSON_AddNumberToObject(mreport_data, "bootc", 1);

    // 开机时长
    uint64_t tick64 = luat_mcu_tick64();
    uint64_t tmms = tick64 / 1000000;
    uint64_t tms = tick64 % 1000000;
    cJSON_AddNumberToObject(mreport_data, "tmms", tmms);
    cJSON_AddNumberToObject(mreport_data, "tms", tms);

    // 结束 转换成json字符串
    char* json = cJSON_PrintUnformatted(mreport_data);
    LLOGE("mreport json --- len: %d\r\n%s", strlen(json), json);

    struct pbuf* p = pbuf_alloc(PBUF_TRANSPORT, strlen(json), PBUF_RAM);
    if (p == NULL) {
        LLOGE("获取pbuf失败 %d", strlen(json));
        return;
    }
    pbuf_take(p, json, strlen(json));
    ret = udp_sendto_if(mreport_pcb, p, &host, MREPORT_PORT, netif);
    pbuf_free(p);
    LLOGD("ret %d", ret);
    if (ret) {
        LLOGD("ret %d", ret);
    }
}

static void mreport_timer_cb(void* params) {
    luat_mreport_send();
    LLOGD("mreport定时器回调");
}

void luat_mreport_start(void) {
    int ret = luat_rtos_timer_create(&mreport_timer);
    if (ret) {
        LLOGE("luat_rtos_timer_create %d", ret);
        return;
    }
    ret = luat_rtos_timer_start(mreport_timer, 1*60*1000, 1, mreport_timer_cb, NULL);
    if (ret) {
        LLOGE("luat_rtos_timer_start %d", ret);
    }
    luat_mreport_send();    // 启动后立即发送一次
}

void luat_mreport_stop(void) {
    if (mreport_timer) {
        luat_stop_rtos_timer(mreport_timer);
        luat_rtos_timer_delete(mreport_timer);
        mreport_timer = NULL;
    }
}

void luat_mreport_config(const char* config, int val) {
    LLOGD("luat_netdrv_mreport %s %d", config, val);
    if (strcmp(config, "enable") == 0) {
        if (val == 0) {
            luat_mreport_stop();
        }
        else if (val == 1){
            luat_mreport_start();
        }
        else
        {
            LLOGE("luat_netdrv_mreport enable %d error", val);
        }
    }
}

int l_mreport_config(lua_State *L) {
    char* config = luaL_checkstring(L, 1);
    int value = lua_toboolean(L, 2);
    luat_mreport_config(config, value);
    return 0;
}