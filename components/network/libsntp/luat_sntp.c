/*
@module  socket
@summary 网络接口
@version 1.0
@date    2022.11.13
*/

#include "luat_base.h"

#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"

#include "luat_malloc.h"
#include "luat_rtc.h"

#include "luat_sntp.h"

#define LUAT_LOG_TAG "sntp"
#include "luat_log.h"

#define SNTP_SERVER_COUNT       3
#define SNTP_SERVER_LEN_MAX     32

static char sntp_server[SNTP_SERVER_COUNT][SNTP_SERVER_LEN_MAX] = {
    "ntp.aliyun.com",
    "ntp1.aliyun.com",
    "ntp2.aliyun.com"
};

static size_t sntp_server_num = 0;

static const uint8_t sntp_packet[48]={0x1b};

#define NTP_UPDATE 1
#define NTP_ERROR  2

static int l_sntp_event_handle(lua_State* L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (lua_getglobal(L, "sys_pub") != LUA_TFUNCTION) {
        return 0;
    };
    switch (msg->arg1)
    {
/*
@sys_pub socket
时间已经同步
NTP_UPDATE
@usage
sys.subscribe("NTP_UPDATE", function()
    log.info("socket", "sntp", os.date())
end)
*/
    case NTP_UPDATE:
        lua_pushstring(L, "NTP_UPDATE");
        break;
/*
@sys_pub socket
时间同步失败
NTP_ERROR
@usage
sys.subscribe("NTP_ERROR", function()
    log.info("socket", "sntp error")
end)
*/
    case NTP_ERROR:
        lua_pushstring(L, "NTP_ERROR");
        break;
    default:
        return 0;
    }
    lua_call(L, 1, 0);
    return 0;
}


int luat_sntp_connect(network_ctrl_t *sntp_netc){
    int ret;
    if (sntp_server_num >= SNTP_SERVER_COUNT) {
        return -1;
    }
	ret = network_connect(sntp_netc, sntp_server[sntp_server_num], strlen(sntp_server[sntp_server_num]), NULL, 123, 1000);
    sntp_server_num++;
	// LLOGD("network_connect ret %d", ret);
	if (ret < 0) {
        network_close(sntp_netc, 0);
        return -1;
    }
    return 0;
}

int luat_sntp_close_socket(network_ctrl_t *sntp_netc){
    if (sntp_netc){
		network_force_close_socket(sntp_netc);
	}
    if (sntp_server_num == 0){
#ifdef __LUATOS__
        rtos_msg_t msg;
        msg.handler = l_sntp_event_handle;
        msg.arg1 = NTP_UPDATE;
        luat_msgbus_put(&msg, 0);
#endif
        network_release_ctrl(sntp_netc);
        return 0;
	}
	if (sntp_server_num < sizeof(sntp_server)){
		luat_sntp_connect(sntp_netc);
	}else{
        network_release_ctrl(sntp_netc);
        sntp_server_num = 0;
#ifdef __LUATOS__
        rtos_msg_t msg;
        msg.handler = l_sntp_event_handle;
        msg.arg1 = NTP_ERROR;
        luat_msgbus_put(&msg, 0);
#endif
    }
    return 0;
}

int32_t luat_sntp_callback(void *data, void *param) {
	OS_EVENT *event = (OS_EVENT *)data;
	network_ctrl_t *sntp_netc =(network_ctrl_t *)param;
	int ret = 0;
    uint32_t tx_len = 0;

	// LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	// LLOGD("network sntp cb %8X %s %8X",event->ID & 0x0ffffffff, event2str(event->ID & 0x0ffffffff) ,event->Param1);
	if (event->ID == EV_NW_RESULT_LINK){
		return 0; // 这里应该直接返回, 不能往下调用network_wait_event
	}else if(event->ID == EV_NW_RESULT_CONNECT){
        network_tx(sntp_netc, sntp_packet, sizeof(sntp_packet), 0, NULL, 0, &tx_len, 0);
        // LLOGD("luat_sntp_callback tx_len:%d",tx_len);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		uint32_t total_len = 0;
		uint32_t rx_len = 0;
		int result = network_rx(sntp_netc, NULL, 0, 0, NULL, NULL, &total_len);
		// LLOGD("result:%d total_len:%d",result,total_len);
		if (0 == result){
			if (total_len>0){
				uint8_t* resp_buff = luat_heap_malloc(total_len + 1);
				resp_buff[total_len] = 0x00;
next:
				result = network_rx(sntp_netc, resp_buff, total_len, 0, NULL, NULL, &rx_len);
				// LLOGD("result:%d rx_len:%d",result,rx_len);
				// LLOGD("resp_buff:%.*s len:%d",total_len,resp_buff,total_len);
				if (result)
					goto next;
				if (rx_len == 0||result!=0) {
                    luat_heap_free(resp_buff);
					luat_sntp_close_socket(sntp_netc);
					return -1;
				}
                const uint8_t *p = (const uint8_t *)resp_buff+40;
                uint32_t time =  (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
                if (time > 0x83AA7E80){
                    time -= 0x83AA7E80;
                }else{
                    time += 0x7C558180;
                }
                luat_rtc_set_tamp32(time);
                LLOGD("Unix timestamp:%d",time);
                sntp_server_num = 0;
                luat_sntp_close_socket(sntp_netc);
                luat_heap_free(resp_buff);
                return 0;
			}
		}else{
			luat_sntp_close_socket(sntp_netc);
			return -1;
		}
	}else if(event->ID == EV_NW_RESULT_TX){

	}else if(event->ID == EV_NW_RESULT_CLOSE){

	}
	if (event->Param1){
		// LLOGW("sntp_callback param1 %d, closing socket", event->Param1);
		luat_sntp_close_socket(sntp_netc);
	}
	ret = network_wait_event(sntp_netc, NULL, 0, NULL);
	if (ret < 0){
		// LLOGW("network_wait_event ret %d, closing socket", ret);
		luat_sntp_close_socket(sntp_netc);
		return -1;
	}
    return 0;
}

int ntp_get(void){
	int adapter_index = network_get_last_register_adapter();
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY){
		return -1;
	}
	network_ctrl_t *sntp_netc = network_alloc_ctrl(adapter_index);
	if (!sntp_netc){
		LLOGE("network_alloc_ctrl fail");
		return -1;
	}
	network_init_ctrl(sntp_netc, NULL, luat_sntp_callback, sntp_netc);
	network_set_base_mode(sntp_netc, 0, 10000, 0, 0, 0, 0);
	network_set_local_port(sntp_netc, 0);
	network_deinit_tls(sntp_netc);
    return luat_sntp_connect(sntp_netc);
}

/*
sntp时间同步
@api    socket.sntp(sntp_server)
@tag LUAT_USE_SNTP
@string/table sntp服务器地址 选填
@usage
socket.sntp()
--socket.sntp("ntp.aliyun.com") --自定义sntp服务器地址
--socket.sntp({"ntp.aliyun.com","ntp1.aliyun.com","ntp2.aliyun.com"}) --sntp自定义服务器地址
sys.subscribe("NTP_UPDATE", function()
    log.info("sntp", "time", os.date())
end)
sys.subscribe("NTP_ERROR", function()
    log.info("socket", "sntp error")
    socket.sntp()
end)
*/
int l_sntp_get(lua_State *L){
    size_t len = 0;
	if (lua_isstring(L, 1)){
        const char * server_addr = luaL_checklstring(L, 1, &len);
        if (len < SNTP_SERVER_LEN_MAX){
            memcpy(sntp_server[0], server_addr, len);
            sntp_server[0][len] = 0x00;
        }else{
            LLOGE("server_addr too lang");
        }
	}else if(lua_istable(L, 1)){
        size_t count = lua_rawlen(L, 1);
        if (count > SNTP_SERVER_COUNT){
            count = SNTP_SERVER_COUNT;
        }
		for (size_t i = 1; i <= count; i++){
			lua_geti(L, 1, i);
			const char * server_addr = luaL_checklstring(L, -1, &len);
            if (len < SNTP_SERVER_LEN_MAX){
                memcpy(sntp_server[i-1], server_addr, len);
                sntp_server[i-1][len] = 0x00;
            }else{
                LLOGE("server_addr too lang");
            }
			lua_pop(L, 1);
		}
	}
    ntp_get();
	return 0;
}


