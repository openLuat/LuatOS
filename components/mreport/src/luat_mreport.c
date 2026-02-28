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
#include "luat_airlink.h"

#define LUAT_LOG_TAG "mreport"
#include "luat_log.h"

#define MREPORT_DOMAIN "47.94.236.172"
#define MREPORT_PORT (12388)

typedef struct mreport_ctx {
    struct udp_pcb* mreport_pcb;
    luat_rtos_timer_t mreport_timer;
    char project_name[64];             // luatos项目名称
    char project_version[32];          // luatos项目版本号
    int s_adapter_index;                  // 网络适配器索引
} mreport_ctx_t;

static mreport_ctx_t* s_mreport_ctx;

static int luat_mreport_init_ctx(void) {
    if (s_mreport_ctx == NULL) {
        s_mreport_ctx = (mreport_ctx_t*)luat_heap_malloc(sizeof(mreport_ctx_t));
        if (s_mreport_ctx == NULL) {
            LLOGE("mreport malloc ctx failed");
            return -1;
        }
        memset(s_mreport_ctx, 0, sizeof(mreport_ctx_t));
        memcpy(s_mreport_ctx->project_name, "unkonw", 6);
        memcpy(s_mreport_ctx->project_version, "0.0.0", 6);
        s_mreport_ctx->s_adapter_index = 0;
    }
    return 0;
}

static void luat_mreport_init(lua_State *L) {
    if (luat_mreport_init_ctx() != 0) {
        return;
    }
    if (L == NULL) {
        return;
    }
    if (strcmp(s_mreport_ctx->project_name, "unkonw") == 0) {
        lua_getglobal(L, "PROJECT");
        if (LUA_TSTRING == lua_type(L, -1))
        {
            size_t project_len;
            const char *project_name = lua_tolstring(L, -1, &project_len);
            size_t copy_len = project_len < sizeof(s_mreport_ctx->project_name) - 1  ? project_len : sizeof(s_mreport_ctx->project_name) - 1;
            memcpy(s_mreport_ctx->project_name, project_name, copy_len);
            s_mreport_ctx->project_name[copy_len] = '\0';
        }
        lua_pop(L, 1);
    }

    if (strcmp(s_mreport_ctx->project_version, "0.0.0") == 0) {
        lua_getglobal(L, "VERSION");
        if (LUA_TSTRING == lua_type(L, -1))
        {
            size_t version_len;
            const char *project_version = lua_tolstring(L, -1, &version_len);
            size_t copy_len = version_len < sizeof(s_mreport_ctx->project_version) - 1  ? version_len : sizeof(s_mreport_ctx->project_version) - 1;
            memcpy(s_mreport_ctx->project_version, project_version, copy_len);
            s_mreport_ctx->project_version[copy_len] = '\0';
        }
        lua_pop(L, 1);
    }
}

static inline uint16_t u162bcd(uint16_t src) {
    uint8_t high = (src >> 8) & 0xFF;
    uint8_t low  = src & 0xFF;
    uint16_t dst = 0;
    dst += (low & 0x0F) + (low >> 4) * 10;
    dst += ((high & 0x0F) + (high >> 4) * 10) * 100;
    //LLOGD("src %04X dst %d", src, dst);
    return dst;
}

// 基础信息
static void luat_mreport_sys_basic(cJSON* mreport_data) {
    // 时间戳
	time_t t;
	time(&t);
    cJSON_AddNumberToObject(mreport_data, "localtime", t);

    // luatos项目信息
    cJSON_AddStringToObject(mreport_data, "proj", s_mreport_ctx->project_name);
    cJSON_AddStringToObject(mreport_data, "pver", s_mreport_ctx->project_version);
    
    // rndis
    cJSON_AddNumberToObject(mreport_data, "rndis", 0);
    // usb
    cJSON_AddNumberToObject(mreport_data, "usb", 1);
    // vbus
    cJSON_AddNumberToObject(mreport_data, "vbus", 1);

    // 开机原因
    cJSON_AddNumberToObject(mreport_data, "powerreson", luat_pm_get_poweron_reason());

    // 开机次数
    cJSON_AddNumberToObject(mreport_data, "bootc", 1);

    // 开机时长
    uint64_t tick64 = luat_mcu_tick64();
    uint64_t tmms = tick64 / 1000000;
    uint64_t tms = tick64 % 1000000;
    cJSON_AddNumberToObject(mreport_data, "tmms", tmms);
    cJSON_AddNumberToObject(mreport_data, "tms", tms);
}

// 模块的信息
static void luat_mreport_mobile(cJSON* mreport_data) {
    // IMEI
    char imei[16] = {0};
    luat_mobile_get_imei(0, imei, 16);                  
    cJSON_AddStringToObject(mreport_data, "imei", imei);

    // MUID
    char muid[33] = {0};
    luat_mobile_get_muid(muid, 32); // TODO 如果不是cat1,要从mcu库取.
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

}

// 网络信息
static void luat_mreport_sim_network(cJSON* mreport_data, struct netif* netif) {
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
    luat_mobile_scell_extern_info_t scell_info = {0};
    if (luat_mobile_get_extern_service_cell_info(&scell_info) == 0) {
        int band = 0;
        uint32_t eci = 0;
        uint16_t tac = 0;
        band = luat_mobile_get_band_from_earfcn(scell_info.earfcn);
        luat_mobile_get_service_cell_identifier(&eci);
        luat_mobile_get_service_tac_or_lac(&tac);
        cJSON_AddNumberToObject(mreport_data, "cid", eci);
        cJSON_AddNumberToObject(mreport_data, "pci", scell_info.pci);
        cJSON_AddNumberToObject(mreport_data, "tac", tac);
        cJSON_AddNumberToObject(mreport_data, "band", band);
        cJSON_AddNumberToObject(mreport_data, "earfcn", scell_info.earfcn);
        cJSON_AddNumberToObject(mreport_data, "mcc", u162bcd(scell_info.mcc));
        cJSON_AddNumberToObject(mreport_data, "mnc", u162bcd(scell_info.mnc));
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

// adc信息
static void luat_mreport_adc(cJSON* mreport_data) {
    // adc-vbat
    if (luat_adc_open(LUAT_ADC_CH_VBAT, NULL) == 0) {
        int val = 0xFF;
        int val2 = 0xFF;
        if (luat_adc_read(LUAT_ADC_CH_VBAT, &val, &val2) == 0) {
            cJSON_AddNumberToObject(mreport_data, "vbat", val2);
        }
        luat_adc_close(LUAT_ADC_CH_VBAT);
    }
    // adc-cpu
    if (luat_adc_open(LUAT_ADC_CH_CPU, NULL) == 0) {
        int val = 0xFF;
        int val2 = 0xFF;
        if (luat_adc_read(LUAT_ADC_CH_CPU, &val, &val2) == 0) {
            cJSON_AddNumberToObject(mreport_data, "cputemp", val2);
        }
        luat_adc_close(LUAT_ADC_CH_CPU);
    }
}

// wifi信息
static void luat_mreport_wifi(cJSON* mreport_data) {
    // wifi版本
    uint32_t wifi_version = 0;
    if (g_airlink_ext_dev_info.tp == 0x01) {
        memcpy(&wifi_version, g_airlink_ext_dev_info.wifi.version, 4);
    }
    cJSON_AddNumberToObject(mreport_data, "wifi_ver", wifi_version);

    // wifi mac
    char mac[18] = {0};
    sprintf_(mac, "%02x:%02x:%02x:%02x:%02x:%02x", g_airlink_ext_dev_info.wifi.sta_mac[0], g_airlink_ext_dev_info.wifi.sta_mac[1], g_airlink_ext_dev_info.wifi.sta_mac[2], g_airlink_ext_dev_info.wifi.sta_mac[3], g_airlink_ext_dev_info.wifi.sta_mac[4], g_airlink_ext_dev_info.wifi.sta_mac[5]);
    cJSON_AddStringToObject(mreport_data, "wifi_sta_mac", mac);
    sprintf_(mac, "%02x:%02x:%02x:%02x:%02x:%02x", g_airlink_ext_dev_info.wifi.ap_mac[0], g_airlink_ext_dev_info.wifi.ap_mac[1], g_airlink_ext_dev_info.wifi.ap_mac[2], g_airlink_ext_dev_info.wifi.ap_mac[3], g_airlink_ext_dev_info.wifi.ap_mac[4], g_airlink_ext_dev_info.wifi.ap_mac[5]);
    cJSON_AddStringToObject(mreport_data, "wifi_ap_mac", mac);
    sprintf_(mac, "%02x:%02x:%02x:%02x:%02x:%02x", g_airlink_ext_dev_info.wifi.bt_mac[0], g_airlink_ext_dev_info.wifi.bt_mac[1], g_airlink_ext_dev_info.wifi.bt_mac[2], g_airlink_ext_dev_info.wifi.bt_mac[3], g_airlink_ext_dev_info.wifi.bt_mac[4], g_airlink_ext_dev_info.wifi.bt_mac[5]);
    cJSON_AddStringToObject(mreport_data, "wifi_bt_mac", mac);

    // wifi状态
    cJSON_AddNumberToObject(mreport_data, "wifi_sta_state", g_airlink_ext_dev_info.wifi.sta_state);
    cJSON_AddNumberToObject(mreport_data, "wifi_ap_state", g_airlink_ext_dev_info.wifi.ap_state);

    // wifi connect ap bssid/rssi/channel
    if (g_airlink_ext_dev_info.wifi.sta_state == 1) {
        sprintf_(mac, "%02x:%02x:%02x:%02x:%02x:%02x", g_airlink_ext_dev_info.wifi.sta_ap_bssid[0], g_airlink_ext_dev_info.wifi.sta_ap_bssid[1], g_airlink_ext_dev_info.wifi.sta_ap_bssid[2], g_airlink_ext_dev_info.wifi.sta_ap_bssid[3], g_airlink_ext_dev_info.wifi.sta_ap_bssid[4], g_airlink_ext_dev_info.wifi.sta_ap_bssid[5]);
        cJSON_AddStringToObject(mreport_data, "wifi_bssid", mac);
        cJSON_AddNumberToObject(mreport_data, "wifi_rssi", g_airlink_ext_dev_info.wifi.sta_ap_rssi);
        cJSON_AddNumberToObject(mreport_data, "wifi_channel", g_airlink_ext_dev_info.wifi.sta_ap_channel);
    }
}

// 内存信息
static void luat_mreport_meminfo(cJSON* mreport_data) {
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
    cJSON_AddItemToObject(mreport_data, "mem_psram", meminfo_psram);

    cJSON* meminfo_luavm = cJSON_CreateArray();
    luat_meminfo_luavm(&total, &used, &max_used);
    cJSON_AddItemToArray(meminfo_luavm, cJSON_CreateNumber(total));
    cJSON_AddItemToArray(meminfo_luavm, cJSON_CreateNumber(used));
    cJSON_AddItemToArray(meminfo_luavm, cJSON_CreateNumber(max_used));
    cJSON_AddItemToObject(mreport_data, "mem_lua", meminfo_luavm);
    cJSON_AddNumberToObject(mreport_data, "memfree", total - used);
}

void luat_mreport_send(void) {
    ip_addr_t host = {0};
    int ret = 0;
    cJSON* mreport_data = cJSON_CreateObject();
    int adapter_id = 0;

    if (luat_mreport_init_ctx() != 0) {
        cJSON_Delete(mreport_data);
        return;
    }

    if (s_mreport_ctx->s_adapter_index == 0) 
    {
        adapter_id = network_register_get_default();
    }
    else
    {
        adapter_id = s_mreport_ctx->s_adapter_index;
    }

	if (adapter_id < 0 || adapter_id >= NW_ADAPTER_QTY){
		LLOGE("尚无已注册的网络适配器");
        cJSON_Delete(mreport_data);
		return;
	}
    luat_netdrv_t* netdrv = luat_netdrv_get(adapter_id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        LLOGE("当前使用的网络适配器id:%d, 还没初始化", adapter_id);
        cJSON_Delete(mreport_data);
        return;
    }

    struct netif *netif = netdrv->netif;
    if (ip_addr_isany(&netif->ip_addr)) {
        LLOGE("当前使用的网络适配器id:%d, 还没分配到ip地址", adapter_id);
        cJSON_Delete(mreport_data);
        return;
    }

    if (s_mreport_ctx->mreport_pcb == NULL) {
        s_mreport_ctx->mreport_pcb = udp_new();
        if (s_mreport_ctx->mreport_pcb == NULL) {
            LLOGE("创建,mreport udp pcb 失败, 内存不足?");
            cJSON_Delete(mreport_data);
            return;
        }
    }
    // ipaddr_aton("47.94.236.172", &host);
    ipaddr_aton(MREPORT_DOMAIN, &host);
    ret = udp_connect(s_mreport_ctx->mreport_pcb, &host, MREPORT_PORT);
    if (ret) {
        LLOGD("udp_connect %d", ret);
        cJSON_Delete(mreport_data);
        return;
    }

    // 基础信息
    luat_mreport_sys_basic(mreport_data);
    // 模组信息, TODO 有mobile库的才添加
    luat_mreport_mobile(mreport_data);
    // sim卡和网络相关, TODO 有mobile库的才添加
    luat_mreport_sim_network(mreport_data, netif);
    // adc信息
    luat_mreport_adc(mreport_data);
    // wifi信息
#ifdef LUAT_USE_DRV_WLAN
    luat_mreport_wifi(mreport_data);
#endif
    // 内存信息
    luat_mreport_meminfo(mreport_data);

    // 结束 转换成json字符串
    char* json = cJSON_PrintUnformatted(mreport_data);
    if (json == NULL) {
        LLOGE("拼接转换为json数据格式, 失败");
        cJSON_Delete(mreport_data);
        return;
    }
    // LLOGE("mreport json --- len: %d\r\n%s", strlen(json), json);

    struct pbuf* p = pbuf_alloc(PBUF_TRANSPORT, strlen(json), PBUF_RAM);
    if (p == NULL) {
        LLOGE("获取pbuf失败 %d", strlen(json));
        luat_heap_free(json);
        cJSON_Delete(mreport_data);
        return;
    }

    pbuf_take(p, json, strlen(json));
    memcpy(&s_mreport_ctx->mreport_pcb->local_ip, &netif->ip_addr, sizeof(ip_addr_t));
    ret = udp_sendto_if(s_mreport_ctx->mreport_pcb, p, &host, MREPORT_PORT, netif);
    pbuf_free(p);
    luat_heap_free(json);
    cJSON_Delete(mreport_data);
    if (ret) {
        LLOGE("send fail ret %d", ret);
    }
}

static void mreport_timer_cb(void* params) {
    luat_mreport_send();
    // LLOGD("mreport定时器回调");
}

void luat_mreport_start(void) {
    if (luat_mreport_init_ctx() != 0) {
        return;
    }
    if (s_mreport_ctx->mreport_timer) {
        return;
    }
    int ret = luat_rtos_timer_create(&s_mreport_ctx->mreport_timer);
    if (ret) {
        LLOGE("luat_rtos_timer_create %d", ret);
        return;
    }
    ret = luat_rtos_timer_start(s_mreport_ctx->mreport_timer, 1*60*1000, 1, mreport_timer_cb, NULL);
    if (ret) {
        LLOGE("luat_rtos_timer_start %d", ret);
    }
    luat_mreport_send();    // 启动后立即发送一次
}

void luat_mreport_stop(void) {
    if (s_mreport_ctx == NULL) {
        return;
    }
    if (s_mreport_ctx->mreport_timer) {
        luat_stop_rtos_timer(s_mreport_ctx->mreport_timer);
        luat_rtos_timer_delete(s_mreport_ctx->mreport_timer);
        s_mreport_ctx->mreport_timer = NULL;
    }
    if (s_mreport_ctx->mreport_pcb) {
        udp_remove(s_mreport_ctx->mreport_pcb);
        s_mreport_ctx->mreport_pcb = NULL;
    }
}

void luat_mreport_config(const char* config, int val) {
    if (luat_mreport_init_ctx() != 0) {
        return;
    }
    if (config == NULL) {
        LLOGE("luat_mreport config is NULL");
        return;
    }
    // LLOGD("luat_mreport_config %s %d", config, val);
    if (strcmp(config, "enable") == 0) {
        if (val == 0) {
            luat_mreport_stop();
        }
        else if (val == 1) {
            luat_mreport_start();
        }
        else {
            LLOGE("luat_mreport enable %d error", val);
        }
    }
    else if (strcmp(config, "adapter_id") == 0) {
        if (val >= 0 && val < NW_ADAPTER_QTY) {
			s_mreport_ctx->s_adapter_index = val;
		}
        else {
            LLOGE("luat_mreport adapter_id %d error", val);
            s_mreport_ctx->s_adapter_index = network_register_get_default(); // 默认使用默认网络适配器
        }
    }
}

int l_mreport_config(lua_State *L) {
    int num_args = lua_gettop(L);
    if (num_args == 0) {
        luat_mreport_send();
    }
    else if (num_args == 2) {
        char* config = luaL_checkstring(L, 1);
        int value = -1;
        if (lua_isboolean(L, 2))
        {
            value = lua_toboolean(L, 2);
        }
        else if (lua_isnumber(L, 2))
        {
            value = lua_tonumber(L, 2);
        }
        luat_mreport_init(L);
        luat_mreport_config(config, value);
    }
    return 0;
}
