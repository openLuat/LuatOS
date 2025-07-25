
#include "luat_base.h"

#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_rtc.h"

#include "luat_sntp.h"

#define LUAT_LOG_TAG "sntp"
#include "luat_log.h"

// 这里使用SNTP协议,非NTP协议,所以不需要传递本地时间戳
// static const uint8_t sntp_packet[48]={0x1b};



static char ntp1 [SNTP_SERVER_LEN_MAX] = "ntp.aliyun.com";
static char ntp2 [SNTP_SERVER_LEN_MAX] = "ntp.ntsc.ac.cn";
static char ntp3 [SNTP_SERVER_LEN_MAX] = "time1.cloud.tencent.com";
char* sntp_servers[SNTP_SERVER_COUNT] = {
    ntp1, ntp2, ntp3
};

sntp_ctx_t g_sntp_ctx;

int luat_ntp_on_result(network_ctrl_t *sntp_netc, int result);



#ifdef __LUATOS__
int l_sntp_event_handle(lua_State* L, void* ptr);
#endif

void ntp_cleanup(void) {
    g_sntp_ctx.is_running = 0;
    if (g_sntp_ctx.timer != NULL) {
        luat_rtos_timer_stop(g_sntp_ctx.timer);
        luat_rtos_timer_delete(g_sntp_ctx.timer);
        g_sntp_ctx.timer = NULL;
    }
    g_sntp_ctx.timer_running = 0;
    if (g_sntp_ctx.ctrl != NULL) {
        network_force_close_socket(g_sntp_ctx.ctrl);
        network_release_ctrl(g_sntp_ctx.ctrl);
        g_sntp_ctx.ctrl = NULL;
    }
    g_sntp_ctx.next_server_index = 0;
}


void ntp_timeout_cb(LUAT_RT_CB_PARAM) {
    (void)param;
    // LLOGD("ntp_timeout_cb");
    if (g_sntp_ctx.is_running && g_sntp_ctx.ctrl != NULL) {
        g_sntp_ctx.timer_running = 0;
        LLOGW("timeout send ntp_error");
#ifdef __LUATOS__
        rtos_msg_t msg = {0};
        msg.handler = l_sntp_event_handle;
        msg.arg1 = NTP_TIMEOUT;
        luat_msgbus_put(&msg, 0);
#else
        ntp_cleanup();
#endif
    }
}

int luat_sntp_connect(network_ctrl_t *sntp_netc){
    int ret = 0;
    if (g_sntp_ctx.next_server_index >= SNTP_SERVER_COUNT) {
        return -1;
    }
    char* host = sntp_servers[g_sntp_ctx.next_server_index];
    g_sntp_ctx.next_server_index++;
    LLOGD("query %s", host);
	ret = network_connect(sntp_netc, host, strlen(host), NULL, g_sntp_ctx.port ? g_sntp_ctx.port : 123, 1000);
	if (ret < 0) {
        LLOGD("network_connect ret %d", ret);
        return -1;
    }
    ret = luat_rtos_timer_start(g_sntp_ctx.timer, NTP_TIMEOUT_MS, 0, ntp_timeout_cb, NULL);
    // LLOGD("启动 timer %d %s", ret, host);
    if (ret == 0) {
        g_sntp_ctx.timer_running = 1;
    }
    return ret;
}

int luat_ntp_on_result(network_ctrl_t *sntp_netc, int result) {
#ifdef __LUATOS__
    rtos_msg_t msg = {0};
#endif
    if (result == NTP_UPDATE) {
#ifdef __LUATOS__
        msg.handler = l_sntp_event_handle;
        msg.arg1 = result;
        luat_msgbus_put(&msg, 0);
#else
        ntp_cleanup();
#endif
        return 0;
    }
    if (g_sntp_ctx.next_server_index < SNTP_SERVER_COUNT) {
        // 没有成功, 继续下一个
        if (g_sntp_ctx.next_server_index) {
            network_force_close_socket(sntp_netc);
        }
        if (g_sntp_ctx.timer_running) {
            LLOGD("timer在运行, 关闭之");
            luat_rtos_timer_stop(g_sntp_ctx.timer);
            g_sntp_ctx.timer_running = 0;
        }
        LLOGD("前一个ntp服务器未响应,尝试下一个");
        int ret = luat_sntp_connect(sntp_netc);
        if (ret == 0) {
            // 没问题, 可以继续下一个了
            return 0;
        }
        LLOGD("luat_sntp_connect %d", ret);
    }
    // 没救了,通知清理吧
#ifdef __LUATOS__
    msg.handler = l_sntp_event_handle;
    msg.arg1 = result;
    luat_msgbus_put(&msg, 0);
#else
    ntp_cleanup();
#endif
    return 0;
}

static uint32_t ntptime2u32(const uint8_t* p, int plus) {
    if (plus && p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0)  {
        return 0;
    }
    // LLOGDUMP(p, 4);
    uint32_t t = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
    if (plus == 0) {
        return t / 4295;
    }
    if (plus == 2) {
        return t;
    }
    
    if (t > 0x83AA7E80){
        t -= 0x83AA7E80;
    }else{
        t += 0x7C558180;
    }
    return t;
}

int32_t luat_sntp_callback(void *data, void *param) {
	OS_EVENT *event = (OS_EVENT *)data;
	network_ctrl_t *sntp_netc =(network_ctrl_t *)param;
	int ret = 0;
    uint32_t tx_len = 0;
    sntp_msg_t smsg = {0};

    // LLOGD("LINK %08X ON_LINE %08X EVENT %08X TX_OK %08X CLOSED %08X",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);

    if (g_sntp_ctx.is_running == 0) {
        // LLOGD("已经查询完了, 为啥还有回调 %08X", event->ID);
        return 0;
    }

	// LLOGD("network sntp cb %8X %s %8X",event->ID & 0x0ffffffff, event2str(event->ID & 0x0ffffffff) ,event->Param1);
	// LLOGD("luat_sntp_callback %08X", event->ID);
    if (event->ID == EV_NW_RESULT_LINK){
		return 0; // 这里应该直接返回, 不能往下调用network_wait_event
	}else if(event->ID == EV_NW_RESULT_CONNECT){
        memset(&smsg, 0, sizeof(smsg));
        smsg.li_vn_mode = 0x1B;
        if (g_sntp_ctx.sysboot_diff_sec > 0) {
            uint64_t tick64 = luat_mcu_tick64() / luat_mcu_us_period();
            uint64_t ll_sec = (uint32_t)(tick64 / 1000 / 1000);
            uint64_t ll_ms = (uint32_t)((tick64 / 1000) % 1000);
            uint64_t rt_ms = g_sntp_ctx.sysboot_diff_sec + ll_sec;
            rt_ms *= 1000;
            rt_ms += g_sntp_ctx.sysboot_diff_ms + ll_ms + g_sntp_ctx.network_delay_ms;
            uint64_t rt_sec = (rt_ms / 1000) - 0x7C558180;
            uint64_t rt_us = ((rt_ms % 1000) & 0xFFFFFFFF) * 1000;
            uint64_t rt_ush = rt_us * 4295; // 1/2us为单位
            uint8_t* ptr = (uint8_t*)smsg.transmit_timestamp;
            ptr[0] = (rt_sec >> 24) & 0xFF;
            ptr[1] = (rt_sec >> 16) & 0xFF;
            ptr[2] = (rt_sec >> 8) & 0xFF;
            ptr[3] = (rt_sec >> 0) & 0xFF;
            ptr[4] = (rt_ush >> 24) & 0xFF;
            ptr[5] = (rt_ush >> 16) & 0xFF;
            ptr[6] = (rt_ush >> 8) & 0xFF;
            ptr[7] = (rt_ush >> 0) & 0xFF;
        }

        ret = network_tx(sntp_netc, (const uint8_t*)&smsg, sizeof(smsg), 0, NULL, 0, &tx_len, 0);
        // LLOGD("network_tx %d", ret);
        if (tx_len != sizeof(smsg)) {
            LLOGI("请求包传输失败!!");
            luat_ntp_on_result(sntp_netc, NTP_ERROR);
            return -1;
        }
        // LLOGD("luat_sntp_callback tx_len:%d",tx_len);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		uint32_t rx_len = 0;
        // uint8_t resp_buff[64] = {0};
        
        // 本地时间tick,尽早生成
        uint64_t tick64 = luat_mcu_tick64() / luat_mcu_us_period();
        uint32_t ll_sec = (uint32_t)(tick64 / 1000 / 1000);
        uint32_t ll_ms = (uint32_t)((tick64 / 1000) % 1000);

		int result = network_rx(sntp_netc, (uint8_t*)&smsg, sizeof(smsg), 0, NULL, NULL, &rx_len);
        if (result == 0 && rx_len >= NTP_RESP_SIZE) {
            const uint8_t *p = ((const uint8_t *)&smsg)+40;
            // LLOGD("reference_timestamp %d %08u", ntptime2u32((uint8_t*)&smsg.reference_timestamp[0], 1), ntptime2u32((uint8_t*)&smsg.reference_timestamp[1], 0));
            // LLOGD("originate_timestamp %d %06u", ntptime2u32((uint8_t*)&smsg.originate_timestamp[0], 1), ntptime2u32((uint8_t*)&smsg.originate_timestamp[1], 0));
            // LLOGD("receive_timestamp   %d %06u", ntptime2u32((uint8_t*)&smsg.receive_timestamp[0], 1),   ntptime2u32((uint8_t*)&smsg.receive_timestamp[1], 0));
            // LLOGD("transmit_timestamp  %d %06u", ntptime2u32((uint8_t*)&smsg.transmit_timestamp[0], 1),  ntptime2u32((uint8_t*)&smsg.transmit_timestamp[1], 0));
            // uint32_t time =  ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
            uint32_t time = ntptime2u32(p, 1);
            luat_rtc_set_tamp32(time);
            // 计算误差

            // 参考时间戳reference_timestamp == rft
            // uint32_t rft_sec = ntptime2u32((uint8_t*)&smsg.reference_timestamp[0], 1);
            // uint32_t rft_us = ntptime2u32((uint8_t*)&smsg.reference_timestamp[1], 0);
            // uint32_t rft_ms = (uint32_t)((rft_us / 1000));
            // uint32_t rft_ms = ((((uint64_t)rft_us) * 1000L * 1000L) >> 32 & 0xFFFFFFFF) / 1000;
            // 原始时间戳originate_timestamp == ot
            uint32_t ot_sec = ntptime2u32((uint8_t*)&smsg.originate_timestamp[0], 1);
            uint32_t ot_us = ntptime2u32((uint8_t*)&smsg.originate_timestamp[1], 0);
            uint32_t ot_ms = (uint32_t)((ot_us / 1000));
            uint64_t ot_tt = ((uint64_t)ot_sec) * 1000 + ot_ms;
            // uint32_t ot_ms = ((((uint64_t)ot_us) * 1000L * 1000L) >> 32 & 0xFFFFFFFF) / 1000;
            // 服务器接收时间戳receive_timestamp == rt
            uint32_t rt_sec = ntptime2u32((uint8_t*)&smsg.receive_timestamp[0], 1);
            uint32_t rt_us = ntptime2u32((uint8_t*)&smsg.receive_timestamp[1], 0);
            uint32_t rt_ms = (uint32_t)((rt_us / 1000));
            uint64_t rt_tt = ((uint64_t)rt_sec) * 1000 + rt_ms;
            // uint32_t rt_ms = ((((uint64_t)rt_us) * 1000L * 1000L) >> 32 & 0xFFFFFFFF) / 1000;
            // 服务响应时间戳transmit_timestamp == tt
            uint32_t tt_sec = ntptime2u32((uint8_t*)&smsg.transmit_timestamp[0], 1);
            uint32_t tt_us = ntptime2u32((uint8_t*)&smsg.transmit_timestamp[1], 0);
            uint32_t tt_ms = (uint32_t)((tt_us / 1000));
            uint64_t tt_tt = ((uint64_t)tt_sec) * 1000 + tt_ms;
            // uint32_t tt_ms = ((((uint64_t)tt_us) * 1000L * 1000L) >> 32 & 0xFFFFFFFF) / 1000;
            // 名义接收时间戳 mean_timestamp == mt
            uint64_t mt_tt = (g_sntp_ctx.sysboot_diff_sec & 0xFFFFFFFF) + ll_sec;
            mt_tt = mt_tt * 1000 + g_sntp_ctx.sysboot_diff_ms + ll_ms;
            // uint32_t mt_sec = mt_tt / 1000;
            // uint32_t mt_ms = (mt_tt % 1000) & 0xFFFF;

            // 上行耗时
            int64_t uplink_diff_ms = rt_tt - ot_tt;
            int64_t downlink_diff_ms = mt_tt - tt_tt; 

            int32_t total_diff_ms = (int32_t)(uplink_diff_ms + downlink_diff_ms) / 2;
            // LLOGD("下行差值(ms) %d", downlink_diff_ms);
            // LLOGD("上行差值(ms) %d", uplink_diff_ms);
            // LLOGD("上下行平均偏差 %d 差值 %d", total_diff_ms, total_diff_ms - g_sntp_ctx.network_delay_ms);

            g_sntp_ctx.sysboot_diff_sec = (uint32_t)(tt_sec - ll_sec);
            if (tt_ms < ll_ms) {
                g_sntp_ctx.sysboot_diff_sec --;
                g_sntp_ctx.sysboot_diff_ms = ll_ms - tt_ms;
            }
            else {
                g_sntp_ctx.sysboot_diff_ms = tt_ms - ll_ms;
            }
            // 1. 发起传输时, 使用0时间戳, 就是第一次
            if (ot_sec != 0) {
                // 修正本地偏移量
                if (g_sntp_ctx.ndelay_c == 0) {
                    g_sntp_ctx.ndelay_c = NTP_NETWORK_DELAY_CMAX;
                }
                if (g_sntp_ctx.network_delay_ms == 0) {
                    for (size_t ik = 0; ik < NTP_NETWORK_DELAY_CMAX; ik++)
                    {
                        g_sntp_ctx.ndelay_array[ik] = total_diff_ms;
                    }
                }
                else {
                    for (uint8_t ij = 0; ij < NTP_NETWORK_DELAY_CMAX - 1; ij++)
                    {
                        g_sntp_ctx.ndelay_array[ij] = g_sntp_ctx.ndelay_array[ij+1];
                    }
                    g_sntp_ctx.ndelay_array[NTP_NETWORK_DELAY_CMAX - 1] = total_diff_ms;
                }
                // LLOGD("ndelay %d %d %d %d %d %d %d %d", ndelay_array[0], ndelay_array[1], ndelay_array[2], ndelay_array[3] , ndelay_array[4], ndelay_array[5], ndelay_array[6], ndelay_array[7]);
                int32_t ttt = 0;
                for (size_t iv = 0; iv < g_sntp_ctx.ndelay_c; iv++)
                {
                    ttt += g_sntp_ctx.ndelay_array[iv];
                }
                if (ttt < 0) {
                    ttt = 0;
                }
                LLOGD("修正网络延时(ms) %d -> %d", g_sntp_ctx.network_delay_ms, ttt / g_sntp_ctx.ndelay_c);
                g_sntp_ctx.network_delay_ms = ttt / g_sntp_ctx.ndelay_c;
            }
            LLOGD("Unix timestamp: %d",time);
            luat_ntp_on_result(sntp_netc, NTP_UPDATE);
            return 0;
		}else{
            LLOGI("响应包不合法 result %d rx_len %d", result, rx_len);
            //luat_ntp_on_result(sntp_netc, NTP_ERROR);
			return -1;
		}
	}else if(event->ID == EV_NW_RESULT_TX){

	}else if(event->ID == EV_NW_RESULT_CLOSE){
        // LLOGD("closed");
	}
	if (event->Param1){
		// LLOGW("sntp_callback param1 %d, closing socket", event->Param1);
		luat_ntp_on_result(sntp_netc, NTP_ERROR);
        return -1;
	}
	ret = network_wait_event(sntp_netc, NULL, 0, NULL);
	if (ret < 0){
		// LLOGW("network_wait_event ret %d, closing socket", ret);
		luat_ntp_on_result(sntp_netc, NTP_ERROR);
		return -1;
	}
    return 0;
}

int ntp_get(int adapter_index){
    if (-1 == adapter_index){
        adapter_index = network_register_get_default();
    }
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY){
		return -1;
	}
	network_ctrl_t *sntp_netc = network_alloc_ctrl((uint8_t)adapter_index);
	if (!sntp_netc){
		LLOGE("network_alloc_ctrl fail");
		return -1;
	}
	network_init_ctrl(sntp_netc, NULL, luat_sntp_callback, sntp_netc);
	network_set_base_mode(sntp_netc, 0, 10000, 0, 0, 0, 0);
	network_set_local_port(sntp_netc, 0);
	network_deinit_tls(sntp_netc);
    g_sntp_ctx.ctrl = sntp_netc;
    g_sntp_ctx.is_running = 1;
    int ret = 0;
    ret = luat_rtos_timer_create(&g_sntp_ctx.timer);
    if (ret) {
        return ret;
    }
    ret = luat_sntp_connect(sntp_netc);
    if (ret) {
        return ret;
    }
    return ret;
}
