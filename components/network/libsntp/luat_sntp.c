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

#define NTP_UPDATE 1
#define NTP_ERROR  2
#define NTP_TIMEOUT 3

// 2秒超时, 每个server给一次机会
#define NTP_TIMEOUT_MS    (2000)
#define NTP_RESP_SIZE     (44)

static char sntp_server[SNTP_SERVER_COUNT][SNTP_SERVER_LEN_MAX] = {
    "ntp.aliyun.com",
    "ntp.ntsc.ac.cn",
    "time1.cloud.tencent.com"
};
// 这里使用SNTP协议,非NTP协议,所以不需要传递本地时间戳
static const uint8_t sntp_packet[48]={0x1b};

typedef struct sntp_ctx
{
    network_ctrl_t *ctrl; // 用于对接network层
    size_t next_server_index; // 因为有多个server,所以这里逐个尝试
    int is_running;       // 是否正在运行的标记, 是的话就不要再启动新的
    luat_rtos_timer_t timer;
    int timer_running;
}sntp_ctx_t;

static sntp_ctx_t ctx;

static int luat_ntp_on_result(network_ctrl_t *sntp_netc, int result);

static void cleanup(void) {
    ctx.is_running = 0;
    if (ctx.timer != NULL) {
        luat_rtos_timer_stop(ctx.timer);
        luat_rtos_timer_delete(ctx.timer);
        ctx.timer = NULL;
    }
    ctx.timer_running = 0;
    if (ctx.ctrl != NULL) {
        network_force_close_socket(ctx.ctrl);
        network_release_ctrl(ctx.ctrl);
        ctx.ctrl = NULL;
    }
    ctx.next_server_index = 0;
}

static int l_sntp_event_handle(lua_State* L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    // 清理现场
    if (msg->arg1 == NTP_TIMEOUT) {
        luat_ntp_on_result(ctx.ctrl, NTP_ERROR);
        return 0;
    }
    cleanup();
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
    }
    lua_call(L, 1, 0);
    return 0;
}

void ntp_timeout_cb(LUAT_RT_CB_PARAM) {
    (void)param;
    // LLOGD("ntp_timeout_cb");
    if (ctx.is_running && ctx.ctrl != NULL) {
        ctx.timer_running = 0;
        LLOGW("timeout send ntp_error");
#ifdef __LUATOS__
        rtos_msg_t msg = {0};
        msg.handler = l_sntp_event_handle;
        msg.arg1 = NTP_TIMEOUT;
        luat_msgbus_put(&msg, 0);
#else
        cleanup();
#endif
    }
}

int luat_sntp_connect(network_ctrl_t *sntp_netc){
    int ret = 0;
    if (ctx.next_server_index >= SNTP_SERVER_COUNT) {
        return -1;
    }
    char* host = sntp_server[ctx.next_server_index];
    ctx.next_server_index++;
    LLOGD("query %s", host);
	ret = network_connect(sntp_netc, host, strlen(host), NULL, 123, 1000);
	if (ret < 0) {
        LLOGD("network_connect ret %d", ret);
        return -1;
    }
    ret = luat_rtos_timer_start(ctx.timer, NTP_TIMEOUT_MS, 0, ntp_timeout_cb, NULL);
    // LLOGD("启动 timer %d %s", ret, host);
    if (ret == 0) {
        ctx.timer_running = 1;
    }
    return ret;
}

static int luat_ntp_on_result(network_ctrl_t *sntp_netc, int result) {
#ifdef __LUATOS__
    rtos_msg_t msg = {0};
#endif
    if (result == NTP_UPDATE) {
#ifdef __LUATOS__
        msg.handler = l_sntp_event_handle;
        msg.arg1 = result;
        luat_msgbus_put(&msg, 0);
#else
        cleanup();
#endif
        return 0;
    }
    if (ctx.next_server_index < SNTP_SERVER_COUNT) {
        // 没有成功, 继续下一个
        if (ctx.next_server_index) {
            network_force_close_socket(sntp_netc);
        }
        if (ctx.timer_running) {
            LLOGD("timer在运行, 关闭之");
            luat_rtos_timer_stop(ctx.timer);
            ctx.timer_running = 0;
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
    cleanup();
#endif
    return 0;
}

int32_t luat_sntp_callback(void *data, void *param) {
	OS_EVENT *event = (OS_EVENT *)data;
	network_ctrl_t *sntp_netc =(network_ctrl_t *)param;
	int ret = 0;
    uint32_t tx_len = 0;

    // LLOGD("LINK %08X ON_LINE %08X EVENT %08X TX_OK %08X CLOSED %08X",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);

    if (ctx.is_running == 0) {
        // LLOGD("已经查询完了, 为啥还有回调 %08X", event->ID);
        return 0;
    }

	// LLOGD("network sntp cb %8X %s %8X",event->ID & 0x0ffffffff, event2str(event->ID & 0x0ffffffff) ,event->Param1);
	// LLOGD("luat_sntp_callback %08X", event->ID);
    if (event->ID == EV_NW_RESULT_LINK){
		return 0; // 这里应该直接返回, 不能往下调用network_wait_event
	}else if(event->ID == EV_NW_RESULT_CONNECT){
        ret = network_tx(sntp_netc, sntp_packet, sizeof(sntp_packet), 0, NULL, 0, &tx_len, 0);
        // LLOGD("network_tx %d", ret);
        if (tx_len != sizeof(sntp_packet)) {
            LLOGI("请求包传输失败!!");
            luat_ntp_on_result(sntp_netc, NTP_ERROR);
            return -1;
        }
        // LLOGD("luat_sntp_callback tx_len:%d",tx_len);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		uint32_t rx_len = 0;
        uint8_t resp_buff[64] = {0};
		int result = network_rx(sntp_netc, resp_buff, NTP_RESP_SIZE, 0, NULL, NULL, &rx_len);
        if (result == 0 && rx_len >= NTP_RESP_SIZE) {
            const uint8_t *p = (const uint8_t *)resp_buff+40;
            uint32_t time =  ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
            if (time > 0x83AA7E80){
                time -= 0x83AA7E80;
            }else{
                time += 0x7C558180;
            }
            luat_rtc_set_tamp32(time);
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
        adapter_index = network_get_last_register_adapter();
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
    ctx.ctrl = sntp_netc;
    ctx.is_running = 1;
    int ret = 0;
    ret = luat_rtos_timer_create(&ctx.timer);
    if (ret) {
        return ret;
    }
    ret = luat_sntp_connect(sntp_netc);
    if (ret) {
        return ret;
    }
    return ret;
}

/*
sntp时间同步
@api    socket.sntp(sntp_server)
@tag LUAT_USE_SNTP
@string/table sntp服务器地址 选填
@int 适配器序号， 只能是socket.ETH0（外置以太网），socket.LWIP_ETH（内置以太网），socket.LWIP_STA（内置WIFI的STA），socket.LWIP_AP（内置WIFI的AP），socket.LWIP_GP（内置蜂窝网络的GPRS），socket.USB（外置USB网卡），如果不填，优先选择soc平台自带能上外网的适配器，若仍然没有，选择最后一个注册的适配器
@usage
socket.sntp()
--socket.sntp("ntp.aliyun.com") --自定义sntp服务器地址
--socket.sntp({"ntp.aliyun.com","ntp1.aliyun.com","ntp2.aliyun.com"}) --sntp自定义服务器地址
--socket.sntp(nil, socket.ETH0) --sntp自定义适配器序号
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
        if (len < SNTP_SERVER_LEN_MAX - 1){
            memcpy(sntp_server[0], server_addr, len + 1);
        }else{
            LLOGE("server_addr too long %s", server_addr);
        }
	}else if(lua_istable(L, 1)){
        size_t count = lua_rawlen(L, 1);
        if (count > SNTP_SERVER_COUNT){
            count = SNTP_SERVER_COUNT;
        }
		for (size_t i = 1; i <= count; i++){
			lua_geti(L, 1, i);
			const char * server_addr = luaL_checklstring(L, -1, &len);
            if (len < SNTP_SERVER_LEN_MAX - 1){
                memcpy(sntp_server[i-1], server_addr, len + 1);
            }else{
                LLOGE("server_addr too long %s", server_addr);
            }
			lua_pop(L, 1);
		}
	}
    if (ctx.is_running) {
        LLOGI("sntp is running");
        return 0;
    }
    int adapter_index = luaL_optinteger(L, 2, network_get_last_register_adapter());
    int ret = ntp_get(adapter_index);
    if (ret) {
#ifdef __LUATOS__
        rtos_msg_t msg;
        msg.handler = l_sntp_event_handle;
        msg.arg1 = NTP_ERROR;
        luat_msgbus_put(&msg, 0);
#else
        cleanup();
#endif
    }
	return 0;
}

