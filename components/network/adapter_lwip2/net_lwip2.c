#include "platform_def.h"
#include "luat_base.h"
#include "luat_timer.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "dns_def.h"
#include "luat_network_adapter.h"
#include "lwip/init.h"
#include "lwip/tcpip.h"
#include "lwip/udp.h"
#include "lwip/sockets.h"
#include "lwip/netif.h"
#include "lwip/ip6_addr.h"
#if LWIP_IPV6
#include "lwip/ip6.h"
#endif
#include "net_lwip2.h"
#include "net_lwip2_dns.h"
#include "luat_crypto.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#define LUAT_LOG_TAG "net"
#include "luat_log.h"

#define NET_DBG	LLOGD
#define NET_ERR LLOGE

/* IPv6 双栈 socket: PCB 用 ANY 类型, 这样同一个 socket 既能连 IPv4 也能连 IPv6;
 * 监听/绑定用 IP_ANY_TYPE 才能同时接受 v4/v6 连接(只传 NULL 会被 lwIP 当作
 * IPv4 ANY, 只监听 v4)。 */
#if LWIP_IPV6
#define NET_LWIP2_TCP_NEW()   tcp_new_ip_type(IPADDR_TYPE_ANY)
#define NET_LWIP2_UDP_NEW()   udp_new_ip_type(IPADDR_TYPE_ANY)
#define NET_LWIP2_ANY_IP      IP_ANY_TYPE
#else
#define NET_LWIP2_TCP_NEW()   tcp_new()
#define NET_LWIP2_UDP_NEW()   udp_new()
#define NET_LWIP2_ANY_IP      NULL
#endif

/* RNDIS NAT 模式共存问题定位日志: 1=开启(默认), 抓完日志后改 0 或删除本块 */
#ifndef LUAT_CONF_RNDIS_NAT_DBG
#define LUAT_CONF_RNDIS_NAT_DBG 0
#endif
#if LUAT_CONF_RNDIS_NAT_DBG
#define NET_LWIP2_RNDIS_DBG(fmt, ...) luat_log_log(LUAT_LOG_INFO, "RNDIS-NAT-DBG", fmt, ##__VA_ARGS__)
#else
#define NET_LWIP2_RNDIS_DBG(fmt, ...) do {} while (0)
#endif

#ifndef SOCKET_BUF_LEN
#define SOCKET_BUF_LEN	(3 * TCP_MSS)
#endif

static int net_lwip2_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data);

enum
{
	EV_LWIP_EVENT_START = USER_EVENT_ID_START + 0x2000000,
	EV_LWIP_SOCKET_TX,
	EV_LWIP_NETIF_INPUT,
	EV_LWIP_TCP_TIMER,
	EV_LWIP_DNS_TIMER,
	EV_LWIP_SOCKET_RX_DONE,
	EV_LWIP_SOCKET_CREATE,
	EV_LWIP_SOCKET_CONNECT,
	EV_LWIP_SOCKET_DNS,
	EV_LWIP_SOCKET_DNS_IPV6,
	EV_LWIP_SOCKET_LISTEN,
	EV_LWIP_SOCKET_ACCPET,
	EV_LWIP_SOCKET_CLOSE,
	EV_LWIP_NETIF_LINK_STATE,
	EV_LWIP_DHCP_TIMER,
	EV_LWIP_FAST_TIMER,
	EV_LWIP_NETIF_SET_IP,
	EV_LWIP_NETIF_IPV6_BY_MAC,
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
	/* 新 DNS 客户端专用事件 */
	EV_LWIP_DNS_RX,		/* Param1=报文缓冲(堆, 由处理方释放) Param2=长度 Param3=适配器 */
	EV_LWIP_DNS_CFG,		/* Param1=net_lwip2_dns_ctl_t* (Lua 任务投递, tcpip 线程应用) */
#endif
};

#define SOCKET_LOCK(ID)		platform_lock_mutex(prvlwip.socket[ID].mutex)
#define SOCKET_UNLOCK(ID)	platform_unlock_mutex(prvlwip.socket[ID].mutex)
#undef platform_send_event

// static net_lwip2_ctrl_struct* lwip_ctrls[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
static net_lwip2_ctrl_struct prvlwip;
static void net_lwip2_check_network_ready(uint8_t adapter_index);
static void net_lwip2_task(void *param);
static void net_lwip2_create_socket_now(uint8_t adapter_index, uint8_t socket_id);
static void platform_send_event(void *p, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3);
static ip_addr_t *net_lwip2_get_ip6(uint8_t adapter_index);
static err_t net_lwip2_dns_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port);
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
/* ---- 新 DNS 客户端适配层 ---- */
static luat_netdrv_dns_ctx_t net_lwip2_dns_ctx;
static uint8_t net_lwip2_dns_ctx_ready;
/*
 * 调度定时器周期(clamp(min_gap, 5, 100)).
 *
 * 缓存成普通变量而不是每次 luat_netdrv_dns_cfg_get() 读 ctx->cfg:
 * net_lwip2_dns_timer_update() 也会从 Lua 任务线程被调用, 而 ctx 内的状态按约定
 * 只在 tcpip 线程改动; 跨线程去读整个 cfg 结构体会破坏那条不变式(可能读到
 * 半新半旧的配置). 这里只读一个 uint32 标量, 且只在 tcpip 线程写, 冲突面收敛到
 * "一个对齐字", 是可接受的放宽(定时器周期取到旧值也只是晚一个 tick 生效).
 */
static uint32_t net_lwip2_dns_timer_period = LUAT_NETDRV_DNS_DEF_MIN_GAP_MS;
/*
 * 各网卡调度定时器当前是否在跑.
 *
 * 用途是"只在状态切换时动定时器", 而不是每来一条 DNS 报文就重启一次:
 *   - platform_start_timer 在 FreeRTOS 移植里是
 *     xTimerIsTimerActive -> xTimerStop -> xTimerChangePeriod -> xTimerStart,
 *     对已经在跑的定时器重复调用是纯粹的浪费;
 *   - 更重要的是它会显著放大 SDK 侧"定时器回调与删除竞争"的窗口,
 *     表现是日志里反复出现 luat_timer_get ... no find!!! 。
 * 计时精度不受影响: 定时器是重复触发(is_repeat=1), 它自己会按 period 一直到期。
 */
static uint8_t net_lwip2_dns_timer_running[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
static void net_lwip2_dns_done(void *user_ctx, void *param, uint8_t adapter_index, uint8_t ip_num, luat_dns_ip_result *ip);
static uint8_t net_lwip2_dns_server_get(uint8_t adapter_index, uint8_t server_idx, luat_ip_addr_t *ip, void *user_ctx);
static uint8_t net_lwip2_dns_send_all(void);
static void net_lwip2_dns_timer_update(uint8_t adapter_index);
static uint32_t net_lwip2_dns_timer_period_update(void);
#endif
static int net_lwip2_check_ack(uint8_t adapter_index, int socket_id);
#if LWIP_IPV6 && defined(LUAT_USE_NETDRV_IPV6)
static void net_lwip2_ipv6_apply_set(uint8_t adapter_index, luat_ip_addr_t *ipv6, uint8_t prefix_len);
static uint8_t net_lwip2_ipv6_prefix_get(uint8_t adapter_index);
#endif

static uint32_t register_statue;
static uint8_t prvlwip_inited = 0;


static LUAT_RT_RET_TYPE net_lwip2_timer_cb(LUAT_RT_CB_PARAM)
{
	platform_send_event(NULL, (uint32_t)EV_LWIP_DNS_TIMER, 0, 0, (uint32_t)param);
	return LUAT_RT_RET;
}

/* ARP 1000ms 周期定时器已被完全移除. etharp 表通过收包/SET_IP 路径维护即可短时间
 * 保持网关 MAC 解析. 长时间运行可能导致 gw_mac 缓存过期, 仅用于功耗测试场景.
 * 如需恢复定时器, 回滚到 commit b4de806e0. */

void net_lwip2_init(uint8_t adapter_index)
{
	uint8_t i;
	for(i = 0; i < MAX_SOCK_NUM; i++)
	{
		INIT_LLIST_HEAD(&prvlwip.socket[i].wait_ack_head);
		INIT_LLIST_HEAD(&prvlwip.socket[i].tx_head);
		INIT_LLIST_HEAD(&prvlwip.socket[i].rx_head);
		prvlwip.socket[i].mutex = platform_create_mutex();
	}
}

void net_lwip2_set_netif(uint8_t adapter_index, struct netif *netif) {
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
		return; // 超范围了
	}
	if (0 == prvlwip_inited) {
		prvlwip_inited = 1;
		net_lwip2_init(adapter_index);
	}
	if (NULL == prvlwip.dns_client[adapter_index]) {
		prvlwip.dns_client[adapter_index] = luat_heap_zalloc(sizeof(dns_client_t));
		// memset(prvlwip.dns_client[adapter_index], 0, sizeof(dns_client_t));
		dns_init_client(prvlwip.dns_client[adapter_index]);
	}
	if (NULL == prvlwip.dns_udp[adapter_index]) {
		// prvlwip.dns_udp[adapter_index] = udp_new();
		prvlwip.dns_udp[adapter_index] = udp_new_ip_type(IPADDR_TYPE_ANY);
		prvlwip.dns_udp[adapter_index]->recv = net_lwip2_dns_recv_cb;
		prvlwip.dns_udp[adapter_index]->recv_arg = adapter_index;
		// #if LWIP_VERSION_MAJOR == 2 && LWIP_VERSION_MINOR >= 1
		extern void udp_bind_netif(struct udp_pcb *pcb, const struct netif* netif);
		udp_bind_netif(prvlwip.dns_udp[adapter_index], netif);
		// #endif
		int tmp = adapter_index;
		prvlwip.dns_timer[adapter_index] = platform_create_timer(net_lwip2_timer_cb, (void *)tmp, NULL);
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
		/* 新建的定时器处于停止态, 与 net_lwip2_dns_timer_running[] 保持一致 */
		net_lwip2_dns_timer_running[adapter_index] = 0;
#endif
	}
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
	/*
	 * 新客户端是单例(缓存全局跨网卡共享), 只需初始化一次.
	 * 放在这里而不是模块初始化里, 是因为它要用到 DNS 服务器表回调,
	 * 而服务器表要等第一次注册适配器时才建好.
	 */
	if (0 == net_lwip2_dns_ctx_ready) {
		net_lwip2_dns_ctx_ready = 1;
		luat_netdrv_dns_init(&net_lwip2_dns_ctx);
		luat_netdrv_dns_set_done_cb(&net_lwip2_dns_ctx, net_lwip2_dns_done, NULL);
		luat_netdrv_dns_set_server_cb(&net_lwip2_dns_ctx, net_lwip2_dns_server_get, NULL);
	}
#endif
	prvlwip.lwip_netif[adapter_index] = netif;
}

static int net_lwip2_del_data_cache(void *p, void *u)
{
	socket_data_t *pdata = (socket_data_t *)p;
	luat_heap_free(pdata->data);
	return LIST_DEL;
}

static int net_lwip2_next_data_cache(void *p, void *u)
{
	socket_ctrl_t *socket = (socket_ctrl_t *)u;
	socket_data_t *pdata = (socket_data_t *)p;
	if (socket->tag != pdata->tag)
	{
		NET_DBG("tag error");
		luat_heap_free(pdata->data);
		return LIST_DEL;
	}
	return LIST_FIND;
}


static socket_data_t * net_lwip2_create_data_node(uint8_t socket_id, uint8_t *data, uint32_t len, luat_ip_addr_t *remote_ip, uint16_t remote_port)
{
	socket_data_t *p = (socket_data_t *)luat_heap_zalloc(sizeof(socket_data_t));
	if (p)
	{
		memset(p, 0, sizeof(socket_data_t));
		p->len = len;
		p->port = remote_port;
		if (remote_ip)
		{
			p->ip = *remote_ip;
		}
		else
		{
			ip_addr_set_zero(&p->ip);
		}
		p->tag = prvlwip.socket[socket_id].tag;
		if (data && len)
		{
			p->data = luat_heap_zalloc(len);
			if (p->data)
			{
				memcpy(p->data, data, len);
			}
			else
			{
				luat_heap_free(p);
				return NULL;
			}
		}
	}
	return p;
}

static void net_lwip2_callback_to_nw_task(uint8_t adapter_index, uint32_t event_id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	luat_network_cb_param_t param = {.tag = 0, .param = prvlwip.user_data};
	OS_EVENT event = { .ID = event_id, .Param1 = param1, .Param2 = param2, .Param3 = param3};
	if ((event_id > EV_NW_DNS_RESULT))
	{
		if (event_id != EV_NW_SOCKET_CLOSE_OK)
		{
			event.Param3 = prvlwip.socket[param1].param;
			param.tag = prvlwip.socket[param1].tag;
		}
		else
		{
			event.Param3 = ((luat_network_cb_param_t *)param3)->param;
			param.tag = ((luat_network_cb_param_t *)param3)->tag;
		}
	}
	switch(event_id)
	{
	case EV_NW_SOCKET_CLOSE_OK:
	case EV_NW_SOCKET_CONNECT_OK:
	case EV_NW_SOCKET_ERROR:
		prvlwip.socket_busy &= ~(1 << param1);
		break;
	}
	//LLOGD("socket_cb event_id %08X param.tag %d param3 %ld", event_id, param.tag, param3);
	prvlwip.socket_cb(&event, &param);
}

static void net_lwip2_tcp_error(uint8_t adapter_index, int socket_id)
{
	prvlwip.socket[socket_id].remote_close = 1;
	net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
}

static err_t net_lwip2_tcp_connected_cb(void *arg, struct tcp_pcb *tpcb, err_t err)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	prvlwip.socket_connect &= ~(1 << socket_id);
	net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
	return ERR_OK;
}

static int net_lwip2_rx_data(int socket_id, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
	int is_mem_err = 0;
	SOCKET_LOCK(socket_id);
	socket_data_t *data_p = net_lwip2_create_data_node(socket_id, NULL, 0, addr, port);
	if (data_p)
	{
		data_p->data = luat_heap_zalloc(p->tot_len);
		if (data_p->data)
		{
			data_p->len = pbuf_copy_partial(p, data_p->data, p->tot_len, 0);
//			NET_DBG("new data %ubyte", p->tot_len);
			llist_add_tail(&data_p->node, &prvlwip.socket[socket_id].rx_head);
			prvlwip.socket[socket_id].rx_wait_size += p->tot_len;
		}
		else
		{
			luat_heap_free(data_p);
			is_mem_err = 1;
		}
	}
	else
	{
		is_mem_err = 1;
	}
	SOCKET_UNLOCK(socket_id);


	return is_mem_err;
}

static void net_lwip2_tcp_close_done(uint8_t adapter_index, int socket_id, uint8_t notify)
{
	luat_network_cb_param_t cb_param;
	// LLOGD("net_lwip2_tcp_close_done 1");
	// OS_LOCK;
	// LLOGD("net_lwip2_tcp_close_done 2");
	// 合法性检查，避免越界或非法socket_id
	if (socket_id < 0 || socket_id >= MAX_SOCK_NUM) {
		return;
	}
	SOCKET_LOCK(socket_id);
	// LLOGD("net_lwip2_tcp_close_done 3");
	cb_param.param = prvlwip.socket[socket_id].param;
	cb_param.tag = prvlwip.socket[socket_id].tag;
	prvlwip.socket[socket_id].pcb.ip = NULL;
	prvlwip.socket[socket_id].listen_tcp = NULL;
	prvlwip.socket[socket_id].remote_close = 0;
	prvlwip.socket[socket_id].state = 0;
	prvlwip.socket[socket_id].in_use = 0;
	prvlwip.socket[socket_id].param = NULL;
	prvlwip.socket[socket_id].rx_wait_size = 0;
	prvlwip.socket[socket_id].tx_wait_size = 0;
	llist_traversal(&prvlwip.socket[socket_id].wait_ack_head, net_lwip2_del_data_cache, NULL);
	llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip2_del_data_cache, NULL);
	llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip2_del_data_cache, NULL);
	prvlwip.socket_busy &= ~(1 << socket_id);
	prvlwip.socket_connect &= ~(1 << socket_id);
	// OS_UNLOCK;
	SOCKET_UNLOCK(socket_id);
	if (notify)
	{
		net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_CLOSE_OK, socket_id, 0, &cb_param);
	}
}

static err_t net_lwip2_tcp_recv_cb(void *arg, struct tcp_pcb *tpcb,
                             struct pbuf *p, err_t err)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	uint16_t len;
	if (p)
	{
//		tcp_recved(tpcb, p->tot_len);
		len = p->tot_len;
		if (net_lwip2_rx_data(socket_id, p, NULL, 0))
		{
			NET_DBG("no memory for rx data len=%d", len);
			// 立即释放收到的数据缓冲，避免后续路径重复释放或遗留
			pbuf_free(p);
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
			return ERR_OK;
		}
		else
		{
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_RX_NEW, socket_id, len, 0);
			pbuf_free(p);
		}
	}
	else if (err == ERR_OK)
	{
		{
			prvlwip.socket[socket_id].remote_close = 1;
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_REMOTE_CLOSE, socket_id, 0, 0);
		}
	}
	else
	{
		net_lwip2_tcp_error(adapter_index, socket_id);
	}
	return ERR_OK;
}

static err_t net_lwip2_tcp_sent_cb(void *arg, struct tcp_pcb *tpcb,
                              u16_t len)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	volatile uint16_t check_len = 0;
	volatile uint32_t rest_len;
	socket_data_t *p;
	SOCKET_LOCK(socket_id);
	while(check_len < len)
	{
		if (llist_empty(&prvlwip.socket[socket_id].wait_ack_head))
		{
			NET_DBG("!");
			goto SOCEKT_ERROR;
		}
		p = (socket_data_t *)prvlwip.socket[socket_id].wait_ack_head.next;
		rest_len = p->len - p->read_pos;
		if ((len - check_len) >= rest_len)
		{
//			NET_DBG("adapter %d socket %d, %ubytes ack", adapter_index, socket_id, p->len);
			llist_del(&p->node);
			luat_heap_free(p->data);
			luat_heap_free(p);
			check_len += rest_len;
		}
		else
		{
			p->read_pos += (len - check_len);
			check_len = len;
//			NET_DBG("adapter %d socket %d, all %ubytes ack %ubytes ", adapter_index, socket_id, p->len, p->read_pos);
		}
	}
	while (!llist_empty(&prvlwip.socket[socket_id].tx_head))
	{
		p = llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip2_next_data_cache, &prvlwip.socket[socket_id]);
		if (p)
		{
			#if ENABLE_PSIF
			#if defined(CHIP_EC618)
			if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, TCP_WRITE_FLAG_COPY, 0, 0, 0))
			#else
			sockdataflag_t dataflag={0};
			if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, 0, dataflag, 0))
			#endif
			#else
			if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, 0))
			#endif
			{
				llist_del(&p->node);
				llist_add_tail(&p->node, &prvlwip.socket[socket_id].wait_ack_head);
			}
			else
			{
//				NET_DBG("tcp buf is full, wait ack and send again");
				break;
			}
		}
	}

	SOCKET_UNLOCK(socket_id);
	tcp_output(tpcb);
	net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_TX_OK, socket_id, len, 0);
	return ERR_OK;
SOCEKT_ERROR:
	SOCKET_UNLOCK(socket_id);
	net_lwip2_tcp_error(adapter_index, socket_id);
	return ERR_OK;
}

static err_t net_lwip2_tcp_err_cb(void *arg, err_t err)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	// 边界检查，防止非法索引导致越界访问
	if (socket_id < 0 || socket_id >= MAX_SOCK_NUM || adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
		return 0;
	}

	// 使用互斥锁保护socket内部状态
	SOCKET_LOCK(socket_id);
	if (prvlwip.socket[socket_id].is_tcp)
	{
		if (prvlwip.socket[socket_id].pcb.tcp)
		{
			prvlwip.socket[socket_id].pcb.tcp = NULL;
		}
	}
	uint8_t should_report_error = (!prvlwip.socket[socket_id].state && !prvlwip.socket[socket_id].remote_close);
	SOCKET_UNLOCK(socket_id);

	if (should_report_error)
	{
		NET_DBG("adapter %d socket %d not closing, but error %d", adapter_index, socket_id, err);
		net_lwip2_tcp_error(adapter_index, socket_id);
	}
	return 0;
}

static err_t net_lwip2_tcp_fast_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	if (err || !newpcb)
	{
		net_lwip2_tcp_error(adapter_index, socket_id);
		return 0;
	}
	LLOGD("adapter %d socket %d new client from %s:%d", adapter_index, socket_id, ipaddr_ntoa(&newpcb->remote_ip), newpcb->remote_port);
	if (prvlwip.socket[socket_id].pcb.tcp != NULL) {
		LLOGE("accept fail, srv socket busy. from %s:%d", ipaddr_ntoa(&newpcb->remote_ip), newpcb->remote_port);
		tcp_close(newpcb);
		return ERR_OK;
	}
	prvlwip.socket[socket_id].pcb.tcp = newpcb;
	// prvlwip.socket[socket_id].pcb.tcp->sockid = socket_id;
	prvlwip.socket[socket_id].rx_wait_size = 0;
	prvlwip.socket[socket_id].tx_wait_size = 0;
	prvlwip.socket[socket_id].pcb.tcp->callback_arg = arg;
	prvlwip.socket[socket_id].pcb.tcp->recv = net_lwip2_tcp_recv_cb;
	prvlwip.socket[socket_id].pcb.tcp->sent = net_lwip2_tcp_sent_cb;
	prvlwip.socket[socket_id].pcb.tcp->errf = net_lwip2_tcp_err_cb;
	prvlwip.socket[socket_id].pcb.tcp->so_options |= SOF_KEEPALIVE|SOF_REUSEADDR;
	net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
	return ERR_OK;
}

static err_t net_lwip2_tcp_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err)
{
	// int socket_id = ((uint32_t)arg) & 0x0000ffff;
	// uint8_t adapter_index = ((uint32_t)arg) >> 16;
	return ERR_OK;
}

static err_t net_lwip2_udp_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p,
    const ip_addr_t *addr, u16_t port)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	uint16_t len = 0;
	// LLOGD("net_lwip2_udp_recv_cb %d %d", socket_id, adapter_index);
#if LUAT_CONF_RNDIS_NAT_DBG
	if (port == 67 || port == 68 || pcb->local_port == 67 || pcb->local_port == 68) {
		NET_LWIP2_RNDIS_DBG("udp_recv sock=%u ad=%u local_port=%u remote_port=%u len=%u idx=%u",
			socket_id, adapter_index, pcb->local_port, port, p ? p->tot_len : 0, pcb->netif_idx);
	}
#endif
	if (p)
	{
		len = p->tot_len;
		if (net_lwip2_rx_data(socket_id, p, addr, port))
		{
			NET_DBG("no memory!");
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
		}
		else
		{
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_RX_NEW, socket_id, len, 0);
		}
		pbuf_free(p);
	}
	return ERR_OK;
}

#ifndef LUAT_USE_NETDRV_DNS_CLIENT
static int32_t net_lwip2_dns_check_result(void *data, void *param)
{
	luat_dns_require_t *require = (luat_dns_require_t *)data;
	if (require->result != 0)
	{
		luat_heap_free(require->uri.Data);
		require->uri.Data = NULL;
		if (require->result > 0)
		{
			luat_dns_ip_result *ip_result = zalloc(sizeof(luat_dns_ip_result) * require->result);
			int i;
			for(i = 0; i < require->result; i++)
			{
				ip_result[i] = require->ip_result[i];
			}
			net_lwip2_callback_to_nw_task(require->adapter_index, EV_NW_DNS_RESULT, require->result, ip_result, require->param);
		}
		else
		{
			net_lwip2_callback_to_nw_task(require->adapter_index, EV_NW_DNS_RESULT, 0, 0, require->param);
		}

		return LIST_DEL;
	}
	else
	{
		return LIST_PASS;
	}
}
#endif /* !LUAT_USE_NETDRV_DNS_CLIENT : 仅旧 dns_run 需要 */

static err_t net_lwip2_dns_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
	uint8_t adapter_index = (uint32_t)arg;
	/*
	 * 早退前必须释放 pbuf: 这个 cb 是 lwIP 交给我们的所有权, 不释放就漏。
	 * arg 在 net_lwip2_set_netif 里是先建 pcb/recv_arg 再赋 lwip_netif 的,
	 * 所以"pcb 已绑定但 netif 还没赋上"这个窗口是真实存在的, 此时每个入包都会走到这里。
	 */
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY || prvlwip.lwip_netif[adapter_index] == NULL) {
		if (p) pbuf_free(p);
		return ERR_OK;
	}
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
	/*
	 * 新客户端不在 raw 回调里就地解析, 只把报文拷出来投递事件.
	 * NO_SYS=0 时本回调与 net_lwip2_task 同处 tcpip 线程, 本来就串行;
	 * 但 LUAT_LWIP_USE_EVENT 变体下两者分属不同循环, 就地解析会破坏
	 * "DNS 状态只在单一上下文改动" 的不变式. 这里多一次小拷贝换取该不变式
	 * 在所有 BSP 变体下都成立. 缓冲区所有权交给 EV_LWIP_DNS_RX 的处理方释放.
	 */
	if (p)
	{
		uint32_t plen = p->tot_len;
		uint8_t *dbuf = luat_heap_malloc(plen);
		if (dbuf)
		{
			pbuf_copy_partial(p, dbuf, plen, 0);
		}
		pbuf_free(p);
		p = NULL;
		if (dbuf)
		{
			platform_send_event(NULL, EV_LWIP_DNS_RX, (uint32_t)(uintptr_t)dbuf, plen,
					adapter_index);
		}
	}
	return ERR_OK;
#else
	Buffer_Struct msg_buf = {0};
	Buffer_Struct tx_msg_buf = {0,0,0};
	struct pbuf *out_p = NULL;
	int i = 0;
	int ret = 0;
	char ip_string[64] = {0};
	char ipstr2[64] = {0};
	//LLOGD("%s:%d", __FILE__, __LINE__);
	if (p)
	{
		OS_InitBuffer(&msg_buf, p->tot_len);
		pbuf_copy_partial(p, msg_buf.Data, p->tot_len, 0);
		pbuf_free(p);
		p = NULL;
		dns_run(prvlwip.dns_client[adapter_index], &msg_buf, NULL, &i);
		OS_DeInitBuffer(&msg_buf);
		llist_traversal(&prvlwip.dns_client[adapter_index]->require_head, net_lwip2_dns_check_result, NULL);
		{
			dns_run(prvlwip.dns_client[adapter_index], NULL, &tx_msg_buf, &i);
			if (tx_msg_buf.Pos && NULL != tx_msg_buf.Data)
			{
				out_p = pbuf_alloc(PBUF_TRANSPORT, tx_msg_buf.Pos, PBUF_RAM);
				if (out_p && NULL != tx_msg_buf.Data)
				{
					pbuf_take(out_p, tx_msg_buf.Data, tx_msg_buf.Pos);
					// memcpy(&prvlwip.dns_udp[adapter_index]->local_ip, &prvlwip.lwip_netif[adapter_index]->ip_addr, sizeof(ip_addr_t));
					ipaddr_ntoa_r(&prvlwip.dns_client[adapter_index]->dns_server[i], ip_string, sizeof(ip_string));
					ipaddr_ntoa_r(&prvlwip.dns_udp[adapter_index]->local_ip, ipstr2, sizeof(ipstr2));
					LLOGD("dns udp sendto %s:%d from %s", ip_string, DNS_SERVER_PORT, ipstr2);
					ret = udp_sendto_if(prvlwip.dns_udp[adapter_index], out_p, &prvlwip.dns_client[adapter_index]->dns_server[i], DNS_SERVER_PORT, prvlwip.lwip_netif[adapter_index]);
					if (ret) {
						LLOGE("dns udp sendto %s:%d ret %d", ip_string, DNS_SERVER_PORT, ret);
					}
				}
				if (out_p) {
					pbuf_free(out_p);
				}
				OS_DeInitBuffer(&tx_msg_buf);
				llist_traversal(&prvlwip.dns_client[adapter_index]->require_head, net_lwip2_dns_check_result, NULL);
			}
		}
	}
	if (!prvlwip.dns_client[adapter_index]->is_run && prvlwip.dns_timer[adapter_index])
	{
		platform_stop_timer(prvlwip.dns_timer[adapter_index]);
	}
	return ERR_OK;
#endif
}

#ifdef LUAT_USE_NETDRV_DNS_CLIENT
/*
 * 结果回调: 转成既有的 EV_NW_DNS_RESULT 事件投递给 socket 层.
 * ip 数组的所有权按既有约定转移给接收方, 这里不得释放.
 */
static void net_lwip2_dns_done(void *user_ctx, void *param, uint8_t adapter_index, uint8_t ip_num, luat_dns_ip_result *ip)
{
	(void)user_ctx;
	net_lwip2_callback_to_nw_task(adapter_index, EV_NW_DNS_RESULT, ip_num, ip, param);
}

/* 取指定适配器的 DNS 服务器; 服务器表仍复用 dns_client_t, 因此新旧实现行为一致 */
static uint8_t net_lwip2_dns_server_get(uint8_t adapter_index, uint8_t server_idx, luat_ip_addr_t *ip, void *user_ctx)
{
	(void)user_ctx;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 0;
	if (server_idx >= MAX_DNS_SERVER) return 0;
	if (prvlwip.dns_client[adapter_index] == NULL) return 0;
	/*
	 * ip 允许为 NULL(客户端只想知道该槽位有没有配服务器时会这么传),
	 * 此时按契约返回"该槽位是否有效"即可, 不要去写指针。
	 */
	if (ip == NULL) return 1;
	memcpy(ip, &prvlwip.dns_client[adapter_index]->dns_server[server_idx], sizeof(luat_ip_addr_t));
	return 1;
}

/*
 * 跑一次调度并把产出的报文全部发出去.
 * 这是"一次 pump 可发多条"的地方 —— 旧实现每次只能发一条, 且 1 秒才走一次.
 * @return 成功发出的条数
 */
static uint8_t net_lwip2_dns_send_all(void)
{
	luat_netdrv_dns_txmsg_t msgs[NETDRV_DNS_TX_BURST];
	uint32_t now = (uint32_t)luat_mcu_tick64_ms();
	uint8_t n, i, sent = 0;

	if (!net_lwip2_dns_ctx_ready) return 0;
	n = luat_netdrv_dns_pump(&net_lwip2_dns_ctx, msgs, NETDRV_DNS_TX_BURST, now);
	for (i = 0; i < n; i++)
	{
		luat_ip_addr_t server;
		struct pbuf *p;
		err_t err;
		uint8_t ai = msgs[i].adapter_index;
		if (ai >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) continue;
		if (prvlwip.lwip_netif[ai] == NULL || prvlwip.dns_udp[ai] == NULL)
		{
			luat_netdrv_dns_report_send_err(&net_lwip2_dns_ctx, ai, msgs[i].server_idx, now);
			continue;
		}
		if (!net_lwip2_dns_server_get(ai, msgs[i].server_idx, &server, NULL))
		{
			luat_netdrv_dns_report_send_err(&net_lwip2_dns_ctx, ai, msgs[i].server_idx, now);
			continue;
		}
		p = pbuf_alloc(PBUF_TRANSPORT, msgs[i].len, PBUF_RAM);
		if (p == NULL)
		{
			luat_netdrv_dns_report_send_err(&net_lwip2_dns_ctx, ai, msgs[i].server_idx, now);
			continue;
		}
		pbuf_take(p, msgs[i].data, msgs[i].len);
		err = udp_sendto_if(prvlwip.dns_udp[ai], p, &server, DNS_SERVER_PORT,
				prvlwip.lwip_netif[ai]);
		pbuf_free(p);
		if (err)
		{
			LLOGE("dns sendto adapter %d server %d err %d", ai, msgs[i].server_idx, err);
			luat_netdrv_dns_report_send_err(&net_lwip2_dns_ctx, ai, msgs[i].server_idx, now);
			continue;
		}
		NET_DBG("dns tx adapter %d server %d len %d", ai, msgs[i].server_idx, msgs[i].len);
		sent++;
	}
	return sent;
}

/* 重新计算调度定时器周期: clamp(min_gap_ms, 5, 100). 只在 tcpip 线程调用。 */
static uint32_t net_lwip2_dns_timer_period_update(void)
{
	luat_netdrv_dns_cfg_t cfg;
	uint32_t period;
	luat_netdrv_dns_cfg_get(&net_lwip2_dns_ctx, &cfg);
	period = cfg.min_gap_ms ? cfg.min_gap_ms : LUAT_NETDRV_DNS_DEF_MIN_GAP_MS;
	if (period < 5) period = 5;
	if (period > 100) period = 100;
	net_lwip2_dns_timer_period = period;
	return period;
}

/*
 * 有未完成事务就起定时器, 空闲就停, 省电.
 * 周期跟随 min_gap_ms: 定时器比节奏参数粗的话, 限速会退化成"每 tick 一条",
 * 并发能力就废了.
 *
 * 【门控口径】必须用 luat_netdrv_dns_should_schedule(), 不能用
 * net_lwip2_dns_ctx.stat.inflight > 0 —— 后者只统计已发出的事务, 排队中的不算,
 * 会出现"最后一个在途事务完成时令牌桶恰好为空、定时器被停掉、队列里的查询
 * 永久发不出去"的停摆。详见 luat_netdrv_dns_should_schedule 的声明注释。
 */
static void net_lwip2_dns_timer_update(uint8_t adapter_index)
{
	uint8_t want;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return;
	if (prvlwip.dns_timer[adapter_index] == NULL) return;
	want = luat_netdrv_dns_should_schedule(&net_lwip2_dns_ctx);
	if (want == net_lwip2_dns_timer_running[adapter_index])
	{
		/* 状态没变就不碰定时器: 避免每收一条报文都 stop/start 一次 */
		return;
	}
	if (want)
	{
		platform_start_timer(prvlwip.dns_timer[adapter_index], net_lwip2_dns_timer_period, 1);
	}
	else
	{
		platform_stop_timer(prvlwip.dns_timer[adapter_index]);
	}
	net_lwip2_dns_timer_running[adapter_index] = want;
}

/*
 * netdrv.CTRL_DNS 在真机(lwIP 传输)侧的入口。
 *
 * 名字是【平台无关】的 netdrv_dns_ctrl: 绑定层只认这个符号, 各平台各提供一个实现。
 *   真机(Air1601/Air780EPM 等) -> 本函数, 报文收发在 tcpip 线程, 配置经事件投递
 *                                 + done 握手跨线程应用
 *   PC 模拟器                  -> bsp/pc 的 POSIX 适配层里的实现, 报文收发在独立
 *                                 dns 线程, 配置同进程内直接应用
 * 之所以不让各平台各叫各的名字再由绑定层分支: 那会把"哪个平台"的知识渗进绑定层,
 * 而绑定层本来只需要知道"有个 CTRL_DNS 入口"。
 *
 * 【必须二选一】PC 上 components/network/adapter_lwip2/ 目录下的 .c 也会被编译(PC 用 lwIP
 * 头也能过编译), 但同时提供同名符号会重复定义。BSP 定义
 * LUAT_NETDRV_DNS_TRANSPORT_POSIX 即表示"传输层交给 POSIX 适配层", 本实现让位。
 * 若在 PC 上漏定义它: lwIP 实现会被链进去, 而 PC 从不调用 net_lwip2_set_netif,
 * 于是 net_lwip2_dns_ctx_ready 恒为 0, netdrv.CTRL_DNS 会一直报 "dns client not ready"。
 */
#ifndef LUAT_NETDRV_DNS_TRANSPORT_POSIX
int netdrv_dns_ctrl(net_lwip2_dns_ctl_t *ctl, uint32_t timeout_ms)
{
	uint32_t wait = 0;
	if (ctl == NULL) return -1;
	if (!net_lwip2_dns_ctx_ready) {
		/*
		 * 客户端还没初始化(本网卡未注册 / 走到的是非 lwIP 适配层)。
		 * 必须显式报错: 否则 Lua 侧只看到 "false, nil", 完全不知道原因。
		 */
		LLOGE("netdrv.CTRL_DNS: dns client not ready (net_lwip2_set_netif 未执行?)");
		return -1;
	}
	/* 周期是标量, 由 tcpip 线程维护, 这里读的是稳定值(见其声明的注释) */
	ctl->timer_period_ms = net_lwip2_dns_timer_period;
	ctl->done = 0;
	platform_send_event(NULL, EV_LWIP_DNS_CFG, (uint32_t)(uintptr_t)ctl, 0, 0);
	/*
	 * 轮询等待 tcpip 线程置位. 这里刻意不加锁: 加锁会在 tcpip 线程里引入
	 * 优先级反转/死锁风险, 而本仓库现状也没有这个先例.
	 * done 是最后写的对齐单字节, ARM 上原子的; 即便读到略旧的值,
	 * 对"统计"这种观测用途也没有影响, 超时则按 stale 处理返回.
	 */
	while (!ctl->done)
	{
		if (wait >= timeout_ms) break;
		luat_rtos_task_sleep(2);
		wait += 2;
	}
	if (!ctl->done) return -1;
	return 0;
}
#endif /* !LUAT_NETDRV_DNS_TRANSPORT_POSIX */
#endif /* LUAT_USE_NETDRV_DNS_CLIENT : 新客户端适配层到此为止 */

#ifndef LUAT_USE_NETDRV_DNS_CLIENT
static void net_lwip2_dns_tx_next(uint8_t adapter_index, Buffer_Struct *tx_msg_buf)
{
	int i = 0;
	err_t err = 0;
	struct pbuf *p = NULL;
	char ipstr[64] = {0};
	char ipstr2[64] = {0};
	dns_run(prvlwip.dns_client[adapter_index], NULL, tx_msg_buf, &i);
	char ip_string[64] = {0};
	// LLOGI("net_lwip2_dns_tx_next %d %p", adapter_index, prvlwip.dns_client[adapter_index]);
	ipaddr_ntoa_r(&prvlwip.dns_client[adapter_index]->dns_server[i], ip_string, sizeof(ip_string));
	LLOGD("adatper %d dns server %s", adapter_index, ip_string);
	if (tx_msg_buf->Pos && NULL != tx_msg_buf->Data) {
		p = pbuf_alloc(PBUF_TRANSPORT, tx_msg_buf->Pos, PBUF_RAM);
		if (p == NULL) {
			LLOGE("dns upd pbuf alloc fail!!!");
		}
		else {
			pbuf_take(p, tx_msg_buf->Data, tx_msg_buf->Pos);
			// memcpy(&prvlwip.dns_udp[adapter_index]->local_ip, &prvlwip.lwip_netif[adapter_index]->ip_addr, sizeof(ip_addr_t));
			ipaddr_ntoa_r(&prvlwip.dns_udp[adapter_index]->local_ip, ipstr2, sizeof(ipstr2));
			ipaddr_ntoa_r(&prvlwip.dns_client[adapter_index]->dns_server[i], ipstr, sizeof(ipstr));
			LLOGD("dns udp sendto %s:%d from %s", ipstr, DNS_SERVER_PORT, ipstr2);
			err = udp_sendto_if(prvlwip.dns_udp[adapter_index], p, &prvlwip.dns_client[adapter_index]->dns_server[i], DNS_SERVER_PORT, prvlwip.lwip_netif[adapter_index]);
			pbuf_free(p);
			if (err) {
				LLOGE("dns udp sendto %s:%d from %s ret %d", ipstr, DNS_SERVER_PORT, ipstr2,  err);
			}
		}
	}
	OS_DeInitBuffer(tx_msg_buf);
	if (prvlwip.dns_client[adapter_index]->new_result)
	{
		llist_traversal(&prvlwip.dns_client[adapter_index]->require_head, net_lwip2_dns_check_result, NULL);
		prvlwip.dns_client[adapter_index]->new_result = 0;
	}

}
#endif /* !LUAT_USE_NETDRV_DNS_CLIENT */

// uint32_t net_lwip2_rand()
// {
// 	PV_Union uPV;
// 	luat_crypto_trng(uPV.u8, 4);
// 	return uPV.u32;
// }


// void net_lwip2_set_local_ip6(ip6_addr_t *ip)
// {
// 	prvlwip.ec618_ipv6.u_addr.ip6 = *ip;
// 	prvlwip.ec618_ipv6.type = IPADDR_TYPE_V6;
// }

static void net_lwip2_close_tcp(int socket_id)
{
	prvlwip.socket[socket_id].pcb.tcp->sent = NULL;
	prvlwip.socket[socket_id].pcb.tcp->errf = NULL;
	prvlwip.socket[socket_id].pcb.tcp->recv = tcp_recv_null;
	prvlwip.socket[socket_id].pcb.tcp->callback_arg = 0;
	prvlwip.socket[socket_id].pcb.tcp->pollinterval = 2;
	if (tcp_close(prvlwip.socket[socket_id].pcb.tcp))
	{
		tcp_abort(prvlwip.socket[socket_id].pcb.tcp);
	}
	prvlwip.socket[socket_id].pcb.tcp = NULL;
}

static void net_lwip2_task(void *param)
{
	// luat_network_cb_param_t cb_param;
	OS_EVENT event = *((OS_EVENT *)param);
#ifdef LUAT_LWIP_USE_EVENT
#else
	luat_heap_free(param);
#endif
	Buffer_Struct tx_msg_buf = {0,0,0};
	// HANDLE cur_task = luat_get_current_task();
	socket_data_t *p = NULL;
	const ip_addr_t *p_ip, *local_ip;
	struct pbuf *out_p = NULL;
	int error = 0;
//	uint8_t active_flag;
	uint8_t socket_id = 0;
	uint8_t adapter_index = 0;
	socket_id = event.Param1;
	adapter_index = event.Param3;
	char ip_string[64] = {0};

	ip_addr_t* ips;
	uint32_t is_ipv6;

	switch(event.ID)
	{
	case EV_LWIP_SOCKET_TX:

		SOCKET_LOCK(socket_id);
		if (prvlwip.socket[socket_id].in_use && prvlwip.socket[socket_id].pcb.ip)
		{
//			if (!prvlwip.socket[socket_id].pcb.tcp->unsent && !prvlwip.socket[socket_id].pcb.tcp->unacked)
//			{
//				active_flag = 0;
//			}
//			else
//			{
//				active_flag = 1;
//			}
			if (prvlwip.socket[socket_id].is_tcp)
			{
				while (!llist_empty(&prvlwip.socket[socket_id].tx_head))
				{
					p = llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip2_next_data_cache, &prvlwip.socket[socket_id]);
					if (p->len <= tcp_sndbuf(prvlwip.socket[socket_id].pcb.tcp))
					{
						#if ENABLE_PSIF
						#if defined(CHIP_EC618)
						if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, TCP_WRITE_FLAG_COPY, 0, 0, 0))
						#else
						sockdataflag_t dataflag={0};
						if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, 0, dataflag, 0))
						#endif
						#else
						if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, TCP_WRITE_FLAG_COPY))
						#endif
						{
							llist_del(&p->node);
							llist_add_tail(&p->node, &prvlwip.socket[socket_id].wait_ack_head);
						}
						else
						{
							//	NET_DBG("tcp buf is full, wait ack and send again");
							break;
						}
					}
					else
					{
						//	NET_DBG("tcp buf is full, wait ack and send again");
						break;
					}
				}
				SOCKET_UNLOCK(socket_id);
				tcp_output(prvlwip.socket[socket_id].pcb.tcp);
				prvlwip.socket_busy |= (1 << socket_id);
			}
			else
			{
				p = llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip2_next_data_cache, &prvlwip.socket[socket_id]);
				if (p)
				{
					llist_del(&p->node);
				}
				SOCKET_UNLOCK(socket_id);
				if (p)
				{
					uint32_t len = p->len;
					out_p = pbuf_alloc(PBUF_TRANSPORT, p->len, PBUF_RAM);
					if (out_p)
					{
						pbuf_take(out_p, p->data, p->len);
						error = udp_sendto_if(prvlwip.socket[socket_id].pcb.udp, out_p, &p->ip, p->port, prvlwip.lwip_netif[adapter_index]);
						if (error) {
							ipaddr_ntoa_r(&p->ip, ip_string, sizeof(ip_string));
							LLOGI("udp_sendto_if err %d %s:%d", error, ip_string, p->port);
						}
						pbuf_free(out_p);
					}
					else
					{
						NET_DBG("mem err send fail");
					}

					luat_heap_free(p->data);
					luat_heap_free(p);
					net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_TX_OK, socket_id, len, 0);

				}
			}
		}
		else
		{
			NET_DBG("adapter %d socket %d no in use! %x", adapter_index, socket_id, prvlwip.socket[socket_id].pcb.ip);
			SOCKET_UNLOCK(socket_id);
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
		}


		break;

	case EV_LWIP_DNS_TIMER:
#ifdef LUAT_USE_DNS
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
		net_lwip2_dns_send_all();
		net_lwip2_dns_timer_update(adapter_index);
#else
		net_lwip2_dns_tx_next(adapter_index, &tx_msg_buf);
		if (!prvlwip.dns_client[adapter_index]->is_run && prvlwip.dns_timer[adapter_index])
		{
			platform_stop_timer(prvlwip.dns_timer[adapter_index]);
		}
#endif
#endif
		break;
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
	case EV_LWIP_DNS_RX:
		{
			/* Param1 是 recv 回调拷出来的报文, 所有权在本处理方 */
			uint8_t *dbuf = (uint8_t *)(uintptr_t)event.Param1;
			uint32_t dlen = event.Param2;
			if (dbuf)
			{
				luat_netdrv_dns_rx_feed(&net_lwip2_dns_ctx, dbuf, dlen,
						(uint32_t)luat_mcu_tick64_ms());
				luat_heap_free(dbuf);
			}
			/* 应答可能立刻让出"换服务器重试"或新的一腿, 这里马上补一次调度 */
			net_lwip2_dns_send_all();
			net_lwip2_dns_timer_update(adapter_index);
		}
		break;
	case EV_LWIP_DNS_CFG:
		{
			/* Lua 任务投递的控制块: 在 tcpip 线程里真正应用, 最后写 done */
			net_lwip2_dns_ctl_t *ctl = (net_lwip2_dns_ctl_t *)(uintptr_t)event.Param1;
			if (ctl)
			{
				uint32_t now = (uint32_t)luat_mcu_tick64_ms();
				if (ctl->has_cfg)
				{
					luat_netdrv_dns_cfg_apply(&net_lwip2_dns_ctx, &ctl->cfg, now);
				}
				if (ctl->flush)
				{
					luat_netdrv_dns_cache_flush(&net_lwip2_dns_ctx);
				}
				luat_netdrv_dns_cfg_get(&net_lwip2_dns_ctx, &ctl->rcfg);
				if (ctl->want_stat)
				{
					luat_netdrv_dns_stat_get(&net_lwip2_dns_ctx, &ctl->rstat);
				}
				/*
				 * 周期可能刚被 has_cfg 那一趟改掉, 在 tcpip 线程里重算并回读,
				 * 顺带让本网卡的定时器按新周期继续跑(或就此停下)。
				 */
				ctl->timer_period_ms = net_lwip2_dns_timer_period_update();
				net_lwip2_dns_timer_update(adapter_index);
				ctl->done = 1;	/* 必须最后写, Lua 侧靠它判断 */
			}
		}
		break;
#endif
	case EV_LWIP_SOCKET_RX_DONE:
		if (!prvlwip.socket[socket_id].in_use || !prvlwip.socket[socket_id].pcb.ip || !prvlwip.socket[socket_id].is_tcp)
		{
			NET_DBG("error socket %d state %d,%x,%d", socket_id, prvlwip.socket[socket_id].in_use, prvlwip.socket[socket_id].pcb.ip, prvlwip.socket[socket_id].is_tcp);
			break;
		}
//			NET_DBG("socket %d rx ack %dbytes", socket_id, event.Param2);
		tcp_recved(prvlwip.socket[socket_id].pcb.tcp, event.Param2);
		break;
	case EV_LWIP_SOCKET_CREATE:
		net_lwip2_create_socket_now(adapter_index, socket_id);
		break;
	case EV_LWIP_SOCKET_CONNECT:
		if (!prvlwip.socket[socket_id].in_use || !prvlwip.socket[socket_id].pcb.ip)
		{
			NET_DBG("adapter %d socket %d cannot use! %d,%x", adapter_index, socket_id, prvlwip.socket[socket_id].in_use, prvlwip.socket[socket_id].pcb.ip);
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
			break;
		}
		p_ip = (ip_addr_t *)event.Param2;
		ipaddr_ntoa_r(p_ip, ip_string, 64);
		LLOGD("adapter %d connect %s:%d %s", adapter_index, ip_string, prvlwip.socket[socket_id].remote_port, prvlwip.socket[socket_id].is_tcp ? "TCP" : "UDP");
		local_ip = NULL;
		#if LWIP_IPV6
		if (p_ip->type == IPADDR_TYPE_V4)
		{
		#endif
			local_ip = &prvlwip.lwip_netif[adapter_index]->ip_addr;
			// char ip_string[64];
			// ipaddr_ntoa_r(&prvlwip.lwip_netif->ip_addr, ip_string, 64);
			// LLOGD("EV_LWIP_SOCKET_CONNECT local_ip %s", ip_string);
		#if LWIP_IPV6
		}
		else
		{
			local_ip = net_lwip2_get_ip6(adapter_index);
		}
		#endif
		if (!local_ip && prvlwip.socket[socket_id].is_tcp)
		{
			NET_DBG("netif no ip !!!!!!");
			net_lwip2_tcp_error(adapter_index, socket_id);
			break;
		}
		if (prvlwip.socket[socket_id].is_tcp)
		{
			error = tcp_bind(prvlwip.socket[socket_id].pcb.tcp, local_ip, prvlwip.socket[socket_id].local_port);
			if (error) {
				NET_DBG("adapter %d socket %d tcp bind error %d", adapter_index, socket_id, error);
				net_lwip2_tcp_error(adapter_index, socket_id);
				return;
			}
			error = tcp_connect(prvlwip.socket[socket_id].pcb.tcp, p_ip, prvlwip.socket[socket_id].remote_port, net_lwip2_tcp_connected_cb);
			if (error)
			{
				NET_DBG("adapter %d socket %d connect error %d", adapter_index, socket_id, error);
				net_lwip2_tcp_error(adapter_index, socket_id);
			}
			else
			{
				prvlwip.socket_connect |= (1 << socket_id);
			}
		}
		else
		{
			// Air8000 multi-net: pin Lua/socket UDP PCB to current adapter's netif
			// so udp_input_local_match's netif_idx filter prevents cross-netif
			// (e.g. RNDIS broadcast) hijack of AP/ETH dhcpsrv.lua UDP PCB.
			if (prvlwip.lwip_netif[adapter_index]) {
				extern void udp_bind_netif(struct udp_pcb *pcb, const struct netif *netif);
				udp_bind_netif(prvlwip.socket[socket_id].pcb.udp, prvlwip.lwip_netif[adapter_index]);
			}
			// NET_DBG("udp bind %d", prvlwip.socket[socket_id].local_port);
#if LWIP_IPV6
			if (local_ip == NULL) {
				local_ip = NET_LWIP2_ANY_IP;
			}
#endif
			error = udp_bind(prvlwip.socket[socket_id].pcb.udp, local_ip, prvlwip.socket[socket_id].local_port);
			if (error) {
				NET_DBG("udp bind ret %d port %d", error, prvlwip.socket[socket_id].local_port);
				net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
				return;
			}
			error = udp_connect(prvlwip.socket[socket_id].pcb.udp, p_ip, prvlwip.socket[socket_id].remote_port);
			if (error)
			{
				NET_DBG("adapter %d socket %d connect error %d", adapter_index, socket_id, error);
				net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
			}
			else
			{
				if (!prvlwip.socket[socket_id].remote_port)
				{
					prvlwip.socket[socket_id].pcb.udp->flags &= ~UDP_FLAGS_CONNECTED;
				}
			#if LUAT_CONF_RNDIS_NAT_DBG
				NET_LWIP2_RNDIS_DBG("udp_conn ad=%u sock=%u local=0x%08X port=%u remote=0x%08X:%u pcb_idx=%u binderr=%d",
					adapter_index, socket_id,
					local_ip ? ip_addr_get_ip4_u32(local_ip) : 0,
					prvlwip.socket[socket_id].local_port,
					ip_addr_get_ip4_u32(p_ip), prvlwip.socket[socket_id].remote_port,
					prvlwip.socket[socket_id].pcb.udp->netif_idx, (int)error);
			#endif
				net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
			}

		}
		break;
	case EV_LWIP_SOCKET_DNS:
	case EV_LWIP_SOCKET_DNS_IPV6:
		// LLOGD("event dns query");
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
		{
			/*
			 * 宏开启: 域名串与 ctrl 都由事件带进来, 域名用完即释放
			 * (客户端会把域名拷进自己的事务里, 不再持有调用方的内存).
			 */
			char *domain = (char *)(uintptr_t)event.Param1;
			void *ctrl = (void *)(uintptr_t)event.Param2;
			uint8_t ipv6 = (event.ID == EV_LWIP_SOCKET_DNS_IPV6) ? 1 : 0;
			if (domain)
			{
				uint32_t dlen = (uint32_t)strlen(domain);
				/* 缓存命中会在这一步同步回调, 也可能建事务, 随后立即调度一次 */
				if (luat_netdrv_dns_query(&net_lwip2_dns_ctx, domain, dlen, ipv6, ctrl,
						adapter_index, (uint32_t)luat_mcu_tick64_ms()) != 0)
				{
					NET_DBG("dns query rejected: %.64s", domain);
					/* 入队失败也要给 socket 层一个终态, 否则它会一直等 */
					net_lwip2_callback_to_nw_task(adapter_index, EV_NW_DNS_RESULT, 0, 0, ctrl);
				}
				luat_heap_free(domain);
			}
			net_lwip2_dns_send_all();
			net_lwip2_dns_timer_update(adapter_index);
		}
#else
		if (!prvlwip.dns_client[adapter_index]->is_run && prvlwip.dns_timer[adapter_index])
		{
			platform_start_timer(prvlwip.dns_timer[adapter_index], 1000, 1);
		}
		dns_require_ipv6(prvlwip.dns_client[adapter_index], event.Param1, event.Param2, event.Param3, (event.ID - EV_LWIP_SOCKET_DNS));
		// LLOGD("event dns query 2");
		net_lwip2_dns_tx_next(adapter_index, &tx_msg_buf);
		// LLOGD("event dns query 3");
#endif
		break;
	case EV_LWIP_SOCKET_LISTEN:
		if (prvlwip.socket[socket_id].listen_tcp) {
			// 已经在监听了, 不需要重复操作, 发送事件就行
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_LISTEN, socket_id, 0, 0);
			break;
		}
		if (!prvlwip.socket[socket_id].in_use || !prvlwip.socket[socket_id].pcb.ip)
		{
			NET_DBG("adapter %d socket %d cannot use! %d,%x", adapter_index, socket_id, prvlwip.socket[socket_id].in_use, prvlwip.socket[socket_id].pcb.ip);
			net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
			break;
		}
		error = tcp_bind(prvlwip.socket[socket_id].pcb.tcp, NET_LWIP2_ANY_IP, prvlwip.socket[socket_id].local_port);
		if (error) {
			LLOGE("tcp listen port %d ret %d", prvlwip.socket[socket_id].local_port, error);
        	net_lwip2_tcp_error(adapter_index, socket_id);
		}
        IP_SET_TYPE_VAL(prvlwip.socket[socket_id].pcb.tcp->local_ip,  IPADDR_TYPE_ANY);
        IP_SET_TYPE_VAL(prvlwip.socket[socket_id].pcb.tcp->remote_ip, IPADDR_TYPE_ANY);
        // prvlwip.socket[socket_id].pcb.tcp->sockid = -1;
        prvlwip.socket[socket_id].listen_tcp = tcp_listen_with_backlog(prvlwip.socket[socket_id].pcb.tcp, 1);
        if (!prvlwip.socket[socket_id].listen_tcp) {
        	NET_DBG("socket %d listen failed");
        	net_lwip2_tcp_error(adapter_index, socket_id);
        } else {
        	PV_Union uPV;
        	uPV.u16[0] = socket_id;
        	uPV.u16[1] = adapter_index;
        	prvlwip.socket[socket_id].listen_tcp->callback_arg = uPV.u32;
        	prvlwip.socket[socket_id].listen_tcp->accept = net_lwip2_tcp_fast_accept_cb;
        	prvlwip.socket[socket_id].pcb.tcp = NULL;
        	net_lwip2_callback_to_nw_task(adapter_index, EV_NW_SOCKET_LISTEN, socket_id, 0, 0);
        }
		break;
//	case EV_LWIP_SOCKET_ACCPET:
//
//		break;
	case EV_LWIP_SOCKET_CLOSE:
		// LLOGD("event EV_LWIP_SOCKET_CLOSE 1");
		if (!prvlwip.socket[socket_id].in_use)
		{
			NET_DBG("socket %d no in use!,%x", socket_id);
			break;
		}
		// LLOGD("event EV_LWIP_SOCKET_CLOSE 2");
		if (prvlwip.socket[socket_id].listen_tcp)
		{
			tcp_close(prvlwip.socket[socket_id].listen_tcp);
			prvlwip.socket[socket_id].listen_tcp = NULL;
			if (prvlwip.socket[socket_id].pcb.tcp)
			{
				net_lwip2_close_tcp(socket_id);
			}
			net_lwip2_tcp_close_done(adapter_index, socket_id, event.Param2);
			break;
		}
		// LLOGD("event EV_LWIP_SOCKET_CLOSE 3");
		if (prvlwip.socket[socket_id].pcb.ip)
		{
			if (prvlwip.socket[socket_id].is_tcp)
			{
				net_lwip2_close_tcp(socket_id);
			}
			else
			{
				// LLOGD("event EV_LWIP_SOCKET_CLOSE 31");
				udp_remove(prvlwip.socket[socket_id].pcb.udp);
				// LLOGD("event EV_LWIP_SOCKET_CLOSE 32");
			}
			net_lwip2_tcp_close_done(adapter_index, socket_id, event.Param2);
			break;
		}
		// LLOGD("event EV_LWIP_SOCKET_CLOSE 4");
		if (prvlwip.socket[socket_id].remote_close)
		{
			net_lwip2_tcp_close_done(adapter_index, socket_id, event.Param2);
			break;
		}
		// LLOGD("event EV_LWIP_SOCKET_CLOSE DONE");
		break;
	case EV_LWIP_NETIF_LINK_STATE:
		{
			uint8_t idx = event.Param3;
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
			/*
			 * 链路断开: 这条出口的旧答案不再可信, 失效它自己的缓存。
			 * 只失效本网卡(而不是整表): share=0 时各网卡的 DNS 视图是分开的,
			 * 别的网卡的有效缓存没必要被牵连。share=1 时该函数等价于整表失效
			 * (所有条目 owner 都是 0), 语义仍然正确。
			 */
			if (event.Param1 == 0 && net_lwip2_dns_ctx_ready)
			{
				luat_netdrv_dns_cache_flush_adapter(&net_lwip2_dns_ctx, idx);
			}
#endif
			net_lwip2_check_network_ready(idx);
		}
		break;
	case EV_LWIP_NETIF_SET_IP:
		ips = (ip_addr_t*)event.Param1;
		// Param2 低 8 位是 is_ipv6 标志, 高 24 位是 IPv6 前缀长度:
		// 旧路径(net_lwip2_set_static_ip)只传 0/1, 前缀解出为 0 时消费端回落 64
		is_ipv6 = ((uint32_t)event.Param2 & 0xFF) != 0;
		if (is_ipv6) {
			#if LWIP_IPV6 && defined(LUAT_USE_NETDRV_IPV6)
			// net_lwip2_set_static_ip() 只用 p_ip[3] 装 IPv6 地址
			uint8_t prefix_len = (uint8_t)(((uint32_t)event.Param2 >> 8) & 0xFF);
			net_lwip2_ipv6_apply_set(adapter_index, &ips[3], prefix_len);
			luat_heap_free(ips);
			net_lwip2_check_network_ready(adapter_index);
			#else
			LLOGE("本固件不支持设置ipv6地址");
			luat_heap_free(ips);
			#endif
			break;
		}
		// IPv4 分支: 只更新 IPv4 地址, 绝不触碰 ip6_addr[] 槽位
		if (IP_IS_V4(&ips[0])) {
			ip4_addr_t ip4 = {.addr=ip_addr_get_ip4_u32(&ips[0])};
			ip4_addr_t netmask4 = {.addr=ip_addr_get_ip4_u32(&ips[1])};
			ip4_addr_t gw4 = {.addr=ip_addr_get_ip4_u32(&ips[2])};
			if (adapter_index == NW_ADAPTER_INDEX_LWIP_WIFI_STA) {
				#ifdef __BK72XX__
				extern void luat_netdrv_sta_set_static_ip(ip_addr_t* ip, ip_addr_t* gateway, ip_addr_t* mask);
				luat_netdrv_sta_set_static_ip(&ip4, &gw4, &netmask4);
				#endif
			}
			netif_set_addr(prvlwip.lwip_netif[adapter_index], &ip4, &netmask4, &gw4);
			net_lwip2_check_network_ready(adapter_index);
		}
		else {
			LLOGW("adapter %d 收到非法的IPv4设置请求, type=%d", adapter_index, IP_GET_TYPE(&ips[0]));
		}
		luat_heap_free(ips);
		break;
	default:
		NET_DBG("unknow event %x,%x", event.ID, event.Param1);
		break;
	}
	// LLOGD("End of lwip task");
}

#ifdef LUAT_LWIP_USE_EVENT
extern int luat_lwip_event_send(uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3);
static void platform_send_event(void *p, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	luat_lwip_event_send(id, param1, param2, param3);
}
void luat_lwip_event_run(void *p)
{
	net_lwip2_task(p);
}
#else
static void platform_send_event(void *p, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	OS_EVENT *event = luat_heap_zalloc(sizeof(OS_EVENT));
	event->ID = id;
	event->Param1 = param1;
	event->Param2 = param2;
	event->Param3 = param3;
	#if NO_SYS
	net_lwip2_task(event);
	#else
	int ret = tcpip_callback(net_lwip2_task, event);
	if (ret) {
		LLOGE("tcpip_callback fail %d event %d", ret, id);
		luat_heap_free(event);
	}
	#endif
}
#endif


static void net_lwip2_check_network_ready(uint8_t adapter_index)
{
	// ip_addr_t addr = {0};
	dns_client_t *dns_client = prvlwip.dns_client[adapter_index];
	dhcp_client_info_t* dhcpc = prvlwip.dhcpc[adapter_index];
	// char ip_string[64] = {0};
	if (prvlwip.lwip_netif[adapter_index] == NULL) {
		return;
	}
	// IPv4 非0 或 存在有效(VALID及以上)的全局 IPv6 地址, 才算网络就绪. 仅有链路本地(fe80::/10)不算就绪(见 net_lwip2_ipv6_is_ready).
	// 历史行为: 只看 IPv4; 这里放宽是为了让 IPv6-only 场景也能触发 IP_READY,
	// 纯 IPv4 网卡的行为完全不变.
	uint8_t active_flag = netif_is_link_up(prvlwip.lwip_netif[adapter_index])
		&& netif_is_up(prvlwip.lwip_netif[adapter_index])
		&& (!ip_addr_isany(&prvlwip.lwip_netif[adapter_index]->ip_addr)
			|| net_lwip2_ipv6_is_ready(adapter_index));
	if (prvlwip.netif_network_ready[adapter_index] == active_flag) {
		// LLOGD("网络[%d]状态没有变化, 跳过检查", adapter_index);
		return;
	}
	prvlwip.netif_network_ready[adapter_index] = active_flag;
	if (!active_flag)
	{
		// TODO 如果没有活跃的netif了, 应该关闭dns客户端
		net_lwip2_callback_to_nw_task(adapter_index, EV_NW_STATE, 0, 0, adapter_index);
	}
	else
	{
		NET_DBG("network ready %d, setup dns server", adapter_index);
		uint8_t dns0_set = 0;
		uint8_t dns1_set = 0;
		// LLOGD("开始设置DNS服务器 %d static? %d %d %d %d", adapter_index, dns_client->is_static_dns[0], dns_client->is_static_dns[1], prvlwip.dhcpc[adapter_index] ? prvlwip.dhcpc[adapter_index]->dns_server[0] : 0, prvlwip.dhcpc[adapter_index] ? prvlwip.dhcpc[adapter_index]->dns_server[1] : 0);
		if (dns_client->is_static_dns[0] == 0) {
			if (dhcpc && dhcpc->dns_server[0]) {
				network_set_ip_ipv4(&dns_client->dns_server[0], dhcpc->dns_server[0]);
				dns0_set = 1;
				// ipaddr_ntoa_r(&dns_client->dns_server[0], ip_string, sizeof(ip_string));
				// LLOGD("使用DHCP分配的DNS服务器作为首选DNS服务器 %d %s", adapter_index, ip_string);
			}
		}
		else {
			dns0_set = 1; // 静态DNS服务器, 就不更新了
		}
		if (dns_client->is_static_dns[1] == 0) {
			if (dhcpc && dhcpc->dns_server[1]) {
				network_set_ip_ipv4(&dns_client->dns_server[1], dhcpc->dns_server[1]);
				dns1_set = 1;
				// ipaddr_ntoa_r(&dns_client->dns_server[1], ip_string, sizeof(ip_string));
				// LLOGD("使用DHCP分配的DNS服务器作为次选DNS服务器 %d %s", adapter_index, ip_string);
			}
		}
		else {
			dns1_set = 1; // 静态DNS服务器, 就不更新了
		}

		if (dns0_set == 0) {
			if (ip_addr_isany(&prvlwip.lwip_netif[adapter_index]->gw)) {
				// 如果网关地址是0.0.0.0, 就不设置DNS服务器
				// LLOGD("网关地址是0.0.0.0, 不设置DNS服务器 %d", adapter_index);
			}
			else {
				memcpy(&dns_client->dns_server[2], &prvlwip.lwip_netif[adapter_index]->gw, sizeof(luat_ip_addr_t));
				// ipaddr_ntoa_r(&dns_client->dns_server[2], ip_string, sizeof(ip_string));
				// LLOGD("使用网关作为首选DNS服务器 %d %s", adapter_index, ip_string);
			}
		}
		else {
			// ipaddr_ntoa_r(&dns_client->dns_server[0], ip_string, sizeof(ip_string));
			// LLOGI("首选DNS服务器 %d %s", adapter_index, ip_string);
		}
		
		if (dns1_set == 0) {
			network_set_ip_ipv4(&dns_client->dns_server[3], (114 << 24) | (114 << 16) | (114 << 8) | 114); // 默认DNS服务器
			// ipaddr_ntoa_r(&dns_client->dns_server[3], ip_string, sizeof(ip_string));
			// LLOGD("使用默认DNS服务器 %d %s", adapter_index, ip_string);
		}
		net_lwip2_callback_to_nw_task(adapter_index, EV_NW_STATE, 0, 1, adapter_index);
	}
}

static int net_lwip2_check_socket(void *user_data, int socket_id, uint64_t tag)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (socket_id >= MAX_SOCK_NUM) {
		LLOGD("socket id 超出范围 %d", socket_id);
		return -1;
	}
	if (prvlwip.socket[socket_id].tag != tag) {
		LLOGD("socket tag 不匹配 %llx != %llx", prvlwip.socket[socket_id].tag, tag);
		return -1;
	}
	if (!prvlwip.socket[socket_id].in_use || prvlwip.socket[socket_id].state) {
		LLOGD("socket 状态不正确 %d,%d,%d", socket_id, prvlwip.socket[socket_id].in_use, prvlwip.socket[socket_id].state);
		return -1;
	}
	return 0;
}

static int net_lwip2_socket_check(int socket_id, uint64_t tag, void *user_data)
{
	return net_lwip2_check_socket(user_data, socket_id, tag);
}


static uint8_t net_lwip2_check_ready(void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 0;
	// LLOGD("lwip2查询网络就绪情况 %d", prvlwip.netif_network_ready[adapter_index]);
	if (prvlwip.lwip_netif[adapter_index] == NULL) {
		LLOGD("lwip netif is null %d", adapter_index);
		return 0;
	}
	if (!netif_is_up(prvlwip.lwip_netif[adapter_index])) {
		// LLOGD("netif is not up %d", adapter_index);
		return 0;
	}
	if (!netif_is_link_up(prvlwip.lwip_netif[adapter_index])) {
		// LLOGD("netif is not link up %d", adapter_index);
		return 0;
	}
	if (ip_addr_isany(&prvlwip.lwip_netif[adapter_index]->ip_addr)
		&& !net_lwip2_ipv6_is_ready(adapter_index)) {
		// LLOGD("netif addr is 0.0.0.0 %d", adapter_index);
		return 0;
	}
	return 1;
}

static void net_lwip2_create_socket_now(uint8_t adapter_index, uint8_t socket_id)
{
	PV_Union uPV;
	uPV.u16[0] = socket_id;
	uPV.u16[1] = adapter_index;
	if (socket_id >= MAX_SOCK_NUM)
		return;
	if (prvlwip.socket[socket_id].is_tcp)
	{
		prvlwip.socket[socket_id].pcb.tcp = NET_LWIP2_TCP_NEW();
		if (!prvlwip.socket[socket_id].pcb.tcp)
		{
			NET_DBG("try to abort fin wait 1 tcp");
			struct tcp_pcb *pcb, *dpcb;
			uint32_t low_time = (uint32_t)(luat_mcu_tick64_ms() / 1000);
			dpcb = NULL;
			for (pcb = tcp_active_pcbs; pcb != NULL; pcb = pcb->next)
			{
				if (FIN_WAIT_1 == pcb->state)
				{
					if (((uint32_t)pcb->callback_arg) < low_time)
					{
						dpcb = pcb;
						low_time = (uint32_t)pcb->callback_arg;
					}
				}
			}
			if (dpcb)
			{
				tcp_abort(dpcb);
			}
			prvlwip.socket[socket_id].pcb.tcp = NET_LWIP2_TCP_NEW();
		}
		if (prvlwip.socket[socket_id].pcb.tcp)
		{
			// prvlwip.socket[socket_id].pcb.tcp->sockid = socket_id;
			#if defined(CHIP_EC618) || defined(CHIP_EC718)|| defined(CHIP_EC716)
			#else
			tcp_bind_netif(prvlwip.socket[socket_id].pcb.tcp, prvlwip.lwip_netif[adapter_index]);
			#endif
			prvlwip.socket[socket_id].rx_wait_size = 0;
			prvlwip.socket[socket_id].tx_wait_size = 0;
			prvlwip.socket[socket_id].pcb.tcp->callback_arg = uPV.p;
			prvlwip.socket[socket_id].pcb.tcp->recv = net_lwip2_tcp_recv_cb;
			prvlwip.socket[socket_id].pcb.tcp->sent = net_lwip2_tcp_sent_cb;
			prvlwip.socket[socket_id].pcb.tcp->errf = net_lwip2_tcp_err_cb;
			prvlwip.socket[socket_id].pcb.tcp->so_options |= SOF_KEEPALIVE|SOF_REUSEADDR;
//					tcp_set_flags(prvlwip.socket[socket_id].pcb.tcp, TCP_NODELAY);
			#if LWIP_TCP_KEEPALIVE
			if (adapter_index == NW_ADAPTER_INDEX_LWIP_WIFI_STA ||
				adapter_index == NW_ADAPTER_INDEX_LWIP_WIFI_AP ||
				adapter_index == NW_ADAPTER_INDEX_LWIP_ETH) {
				prvlwip.socket[socket_id].pcb.tcp->keep_intvl = 5*1000;
				prvlwip.socket[socket_id].pcb.tcp->keep_idle = 45*1000;
				prvlwip.socket[socket_id].pcb.tcp->keep_cnt = 2;
			}
			#endif
		}
		else
		{
			NET_DBG("tcp pcb full!");
			net_lwip2_tcp_error(adapter_index, socket_id);
		}
	}
	else
	{
		// LLOGE("udp new in net_lwip2");
		prvlwip.socket[socket_id].pcb.udp = NET_LWIP2_UDP_NEW();
		if (prvlwip.socket[socket_id].pcb.udp)
		{
			// Air8000 multi-net: pin Lua/socket UDP PCB early to current adapter netif
			if (prvlwip.lwip_netif[adapter_index]) {
				extern void udp_bind_netif(struct udp_pcb *pcb, const struct netif *netif);
				udp_bind_netif(prvlwip.socket[socket_id].pcb.udp, prvlwip.lwip_netif[adapter_index]);
			}
			prvlwip.socket[socket_id].pcb.udp->recv_arg = uPV.p;
			prvlwip.socket[socket_id].pcb.udp->recv = net_lwip2_udp_recv_cb;
			prvlwip.socket[socket_id].pcb.udp->so_options |= SOF_BROADCAST|SOF_REUSEADDR;
		#if LUAT_CONF_RNDIS_NAT_DBG
			NET_LWIP2_RNDIS_DBG("udp_new ad=%u sock=%u netif=%p num=%u pcb_idx=%u",
				adapter_index, socket_id, prvlwip.lwip_netif[adapter_index],
				prvlwip.lwip_netif[adapter_index] ? prvlwip.lwip_netif[adapter_index]->num : 0,
				prvlwip.socket[socket_id].pcb.udp->netif_idx);
		#endif
		}
		else
		{
			NET_DBG("udp pcb full!");
			net_lwip2_tcp_error(adapter_index, socket_id);
		}
	}
}

static int gen_next_socket_id() {
	int socket_id = -1;
	int i;
	if (!prvlwip.socket[prvlwip.next_socket_index].in_use)
	{
		socket_id = prvlwip.next_socket_index;
		prvlwip.next_socket_index++;
	}
	else
	{
		for (i = 0; i < MAX_SOCK_NUM; i++)
		{
			if (!prvlwip.socket[i].in_use)
			{
				socket_id = i;
				prvlwip.next_socket_index = i + 1;
				break;
			}
		}
	}
	if (prvlwip.next_socket_index >= MAX_SOCK_NUM)
	{
		prvlwip.next_socket_index = 0;
	}
	return socket_id;
}

static int net_lwip2_create_socket(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data)
{
	// uint8_t index = (uint32_t)user_data;
	uint8_t adapter_index = (uint32_t)user_data;
	if ((uint32_t)adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 0;
	int socket_id = gen_next_socket_id();
	// OS_LOCK;
	if (socket_id >= 0)
	{
		LWIP_ASSERT("socket must free before create", !prvlwip.socket[socket_id].pcb.ip);
		prvlwip.socket_busy &= ~(1 << socket_id);
		prvlwip.socket_connect &= ~(1 << socket_id);
		prvlwip.socket_tag++;
		*tag = prvlwip.socket_tag;
		prvlwip.socket[socket_id].in_use = 1;
		prvlwip.socket[socket_id].tag = *tag;
		prvlwip.socket[socket_id].param = param;
		prvlwip.socket[socket_id].is_tcp = is_tcp;
		llist_traversal(&prvlwip.socket[socket_id].wait_ack_head, net_lwip2_del_data_cache, NULL);
		llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip2_del_data_cache, NULL);
		llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip2_del_data_cache, NULL);
		// OS_UNLOCK;
		// if (platform_get_current_task() == prvlwip.task_handle)
		// {
		// 	net_lwip2_create_socket_now(index, socket_id);
		// 	return socket_id;
		// }
		platform_send_event(NULL, EV_LWIP_SOCKET_CREATE, socket_id, 0, user_data);
	}
	else
	{
		// OS_UNLOCK;
	}

	return socket_id;
}

//作为client绑定一个port，并连接remote_ip和remote_port对应的server
static int net_lwip2_socket_connect(int socket_id, uint64_t tag,  uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	int result = net_lwip2_check_socket(user_data, socket_id, tag);
	if (result) return result;
	prvlwip.socket[socket_id].local_port = local_port;
	prvlwip.socket[socket_id].remote_port = remote_port;
	platform_send_event(NULL, EV_LWIP_SOCKET_CONNECT, socket_id, remote_ip, user_data);
	return 0;
}
//作为server绑定一个port，开始监听
static int net_lwip2_socket_listen(int socket_id, uint64_t tag,  uint16_t local_port, void *user_data)
{
	int result = net_lwip2_check_socket(user_data, socket_id, tag);
	if (result) return result;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	prvlwip.socket[socket_id].local_port = local_port;
	platform_send_event(NULL, EV_LWIP_SOCKET_LISTEN, socket_id, local_port, user_data);
	return 0;
}
//作为server接受一个client
static int net_lwip2_socket_accept(int srv_socket_id, uint64_t srv_tag,  luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	if (srv_tag == 0) {
		uint64_t tag = 0;
		LLOGD("accept tag 0, one to many");
		if (prvlwip.socket[srv_socket_id].pcb.tcp == NULL) {
			LLOGE("accept fail, srv socket not in wait-accept state");
			return -1;
		}
		// 首先,分配新的socket id
		int socket_id = gen_next_socket_id();
		if (socket_id < 0) {
			LLOGE("accept fail, too many socket");
			return -1;
		}
		network_ctrl_t* accept_ctrl = (network_ctrl_t*)user_data;
		// 然后, 把新的socket和老的socket绑定在一起
		prvlwip.socket_busy &= (1 << socket_id);
		prvlwip.socket_connect &= (1 << socket_id);
		prvlwip.socket_tag++;
		tag = prvlwip.socket_tag;
		accept_ctrl->tag = tag;
		prvlwip.socket[socket_id].in_use = 1;
		prvlwip.socket[socket_id].tag = tag;
		prvlwip.socket[socket_id].param = accept_ctrl;
		prvlwip.socket[socket_id].is_tcp = 1;

		LLOGI("accept new socket %d from srv socket %d", socket_id, srv_socket_id);
		LLOGD("accept srv tag %llx, new tag %llx accept_ctrl->tag %llx", srv_tag, tag, accept_ctrl->tag);

		//--------------------
		// 把srv暂存的pcb给新的socket
		prvlwip.socket[socket_id].pcb.tcp = prvlwip.socket[srv_socket_id].pcb.tcp;
		prvlwip.socket[srv_socket_id].pcb.tcp = NULL; // 恢复成老的监听状态
		prvlwip.socket[srv_socket_id].rx_wait_size = 0;
		prvlwip.socket[srv_socket_id].tx_wait_size = 0;
		//--------------------

		PV_Union uPV;
        uPV.u16[0] = socket_id;
        uPV.u16[1] = accept_ctrl->adapter_index;
		prvlwip.socket[socket_id].pcb.tcp->callback_arg = uPV.p;
		llist_traversal(&prvlwip.socket[socket_id].wait_ack_head, net_lwip2_del_data_cache, NULL);
		llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip2_del_data_cache, NULL);
		llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip2_del_data_cache, NULL);
		*remote_ip = prvlwip.socket[socket_id].pcb.tcp->remote_ip;
		*remote_port = prvlwip.socket[socket_id].pcb.tcp->remote_port;

		// 把srv_socket_id的对应的状态恢复好

		return socket_id;
	}
	else {
		// 一对一的情况, 兼容老的
		int socket_id = srv_socket_id;
		int result = net_lwip2_check_socket(user_data, socket_id, srv_tag);
		if (result) return result;
		uint8_t adapter_index = (uint32_t)user_data;
		if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
		*remote_ip = prvlwip.socket[socket_id].pcb.tcp->remote_ip;
		*remote_port = prvlwip.socket[socket_id].pcb.tcp->remote_port;
	}
	return 0;
}
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
static int net_lwip2_socket_disconnect(int socket_id, uint64_t tag,  void *user_data)
{
	int result = net_lwip2_check_socket(user_data, socket_id, tag);
	if (result) return result;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	prvlwip.socket[socket_id].state = 1;
	platform_send_event(NULL, EV_LWIP_SOCKET_CLOSE, socket_id, 1, user_data);
	return 0;
}

static int net_lwip2_socket_force_close(int socket_id, void *user_data)
{
	if (socket_id >= MAX_SOCK_NUM) return -1;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (prvlwip.socket[socket_id].in_use && !prvlwip.socket[socket_id].state)
	{
		prvlwip.socket[socket_id].state = 1;
		platform_send_event(NULL, EV_LWIP_SOCKET_CLOSE, socket_id, 0, user_data);
	}
	return 0;
}

static int net_lwip2_socket_close(int socket_id, uint64_t tag,  void *user_data)
{
	if (socket_id >= MAX_SOCK_NUM) return -1;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (prvlwip.socket[socket_id].tag != tag)
	{
		NET_DBG("socket %d used by other!", socket_id);
		return -1;
	}
	if (!prvlwip.socket[socket_id].in_use) return 0;
	net_lwip2_socket_force_close(socket_id, user_data);
	return 0;

}

static uint32_t net_lwip2_socket_read_data(int socket_id, uint8_t *buf, uint32_t *read_len, uint32_t len, socket_data_t *p)
{
	uint32_t dummy_len;
	dummy_len = ((p->len - p->read_pos) > (len - *read_len))?(len - *read_len):(p->len - p->read_pos);
	memcpy(buf, p->data + p->read_pos, dummy_len);
	p->read_pos += dummy_len;
	if (p->read_pos >= p->len)
	{
		if (prvlwip.socket[socket_id].is_tcp)
		{
			platform_send_event(NULL, EV_LWIP_SOCKET_RX_DONE, socket_id, p->len, 0);
		}
		llist_del(&p->node);
		luat_heap_free(p->data);
		luat_heap_free(p);
	}
	*read_len += dummy_len;
	return dummy_len;
}

static int net_lwip2_socket_receive(int socket_id, uint64_t tag,  uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	if (socket_id >= MAX_SOCK_NUM) return -1;
	int result = net_lwip2_check_socket(user_data, socket_id, tag);
	if (result) return result;

	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;

	uint32_t read_len = 0;
	uint32_t dummy_len = 0;
	if (buf)
	{
		SOCKET_LOCK(socket_id);
		socket_data_t *p = (socket_data_t *)llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip2_next_data_cache, &prvlwip.socket[socket_id]);

		if (prvlwip.socket[socket_id].is_tcp)
		{
			while((read_len < len) && p)
			{
				prvlwip.socket[socket_id].rx_wait_size -= net_lwip2_socket_read_data(socket_id, buf + read_len, &read_len, len, p);
				p = (socket_data_t *)llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip2_next_data_cache, &prvlwip.socket[socket_id]);
			}
		}
		else
		{
			int preserve_udp_remain = (flags & NETWORK_RX_FLAG_PRESERVE_UDP_REMAIN) != 0;
			if (p)
			{
				uint32_t remain_len = p->len - p->read_pos;
				if (remote_ip)
				{
					*remote_ip = p->ip;
				}
				if (remote_port)
				{
					*remote_port = p->port;
				}
				dummy_len = net_lwip2_socket_read_data(socket_id, buf + read_len, &read_len, len, p);
				prvlwip.socket[socket_id].rx_wait_size -= dummy_len;
				if (!preserve_udp_remain && (remain_len > dummy_len))
				{
					prvlwip.socket[socket_id].rx_wait_size -= (remain_len - dummy_len);
					llist_del(&p->node);
					luat_heap_free(p->data);
					luat_heap_free(p);
				}
			}
		}
		if (llist_empty(&prvlwip.socket[socket_id].rx_head))
		{
			prvlwip.socket[socket_id].rx_wait_size = 0;
		}
		SOCKET_UNLOCK(socket_id);
	}
	else
	{
		read_len = prvlwip.socket[socket_id].rx_wait_size;
	}
	return read_len;
}
static int net_lwip2_socket_send(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = net_lwip2_check_socket(user_data, socket_id, tag);
	// LLOGD("net_lwip2_socket_send check result %d socket %d", result, socket_id);
	if (result) return result;
	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	SOCKET_LOCK(socket_id);
	uint32_t save_len = 0;
	uint32_t dummy_len = 0;
	socket_data_t *p;
	// LLOGD("socket %d send len %d", socket_id, len);
	if (prvlwip.socket[socket_id].is_tcp)
	{
		while(save_len < len)
		{
			dummy_len = ((len - save_len) > SOCKET_BUF_LEN)?SOCKET_BUF_LEN:(len - save_len);


			p = net_lwip2_create_data_node(socket_id, &buf[save_len], dummy_len, remote_ip, remote_port);

			if (p)
			{
				llist_add_tail(&p->node, &prvlwip.socket[socket_id].tx_head);
			}
			else
			{
				SOCKET_UNLOCK(socket_id);
				return -1;
			}
			save_len += dummy_len;
		}
	}
	else
	{
		p = net_lwip2_create_data_node(socket_id, buf, len, remote_ip, remote_port);
		if (p)
		{
			llist_add_tail(&p->node, &prvlwip.socket[socket_id].tx_head);
		}
		else
		{
			SOCKET_UNLOCK(socket_id);
			return -1;
		}
	}

	SOCKET_UNLOCK(socket_id);
	platform_send_event(NULL, EV_LWIP_SOCKET_TX, socket_id, 0, user_data);
	result = len;
	return result;
}

void net_lwip2_socket_clean(int *vaild_socket_list, uint32_t num, void *user_data)
{
	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return;
	int socket_list[MAX_SOCK_NUM];
	memset(socket_list, 0, sizeof(socket_list));
	uint32_t i;
	for(i = 0; i < num; i++)
	{
		if ( (vaild_socket_list[i] > 0) && (vaild_socket_list[i] < MAX_SOCK_NUM) )
		{
			socket_list[vaild_socket_list[i]] = 1;
		}
		NET_DBG("%d,%d",i,vaild_socket_list[i]);
	}
	for(i = 0; i < MAX_SOCK_NUM; i++)
	{
		NET_DBG("%d,%d",i,socket_list[i]);
		if ( !socket_list[i] )
		{
			net_lwip2_socket_force_close(i, user_data);
		}
	}
}


static int net_lwip2_get_local_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (!prvlwip.lwip_netif[adapter_index]) return -1;
	*ip = prvlwip.lwip_netif[adapter_index]->ip_addr;
	*submask = prvlwip.lwip_netif[adapter_index]->netmask;
	*gateway = prvlwip.lwip_netif[adapter_index]->gw;
	return 0;
}

static int net_lwip2_get_full_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (!prvlwip.lwip_netif[adapter_index]) return -1;
	*ip = prvlwip.lwip_netif[adapter_index]->ip_addr;
	*submask = prvlwip.lwip_netif[adapter_index]->netmask;
	*gateway = prvlwip.lwip_netif[adapter_index]->gw;
	#if LWIP_IPV6
	luat_ip_addr_t *local_ip = net_lwip2_get_ip6(adapter_index);
	if (local_ip)
	{
		*ipv6 = *local_ip;
	}
	else
	{
		ipv6->type = 0xff;
	}
	#endif
	return 0;
}

static int net_lwip2_user_cmd(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data)
{
	return 0;
}

static int net_lwip2_dns(const char *domain_name, uint32_t len, void *param, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	char *prv_domain_name = (char *)zalloc(len + 1);
	memcpy(prv_domain_name, domain_name, len);
	platform_send_event(NULL, EV_LWIP_SOCKET_DNS, prv_domain_name, param, user_data);
	return 0;
}

static int net_lwip2_dns_ipv6(const char *domain_name, uint32_t len, void *param, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	char *prv_domain_name = (char *)zalloc(len + 1);
	memcpy(prv_domain_name, domain_name, len);
	// platform_send_event(prvlwip.task_handle, (prvlwip.ec618_ipv6.type != IPADDR_TYPE_V6)?EV_LWIP_SOCKET_DNS:EV_LWIP_SOCKET_DNS_IPV6, prv_domain_name, param, user_data);
	platform_send_event(NULL, EV_LWIP_SOCKET_DNS_IPV6, prv_domain_name, param, user_data);
	return 0;
}

static int net_lwip2_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (server_index >= MAX_DNS_SERVER) return -1;
	if (prvlwip.dns_client[adapter_index] == NULL) return -1;
	memcpy(&prvlwip.dns_client[adapter_index]->dns_server[server_index], ip, sizeof(luat_ip_addr_t));
	prvlwip.dns_client[adapter_index]->is_static_dns[server_index] = 1;
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
	/*
	 * 这台服务器只服务本网卡, 它变了就只失效本网卡的缓存:
	 * share=0 时别的网卡的答案由别的服务器/出口给出, 不该被牵连。
	 * share=1 时等价于整表失效(所有条目 owner 都是 0), 语义仍正确。
	 */
	if (net_lwip2_dns_ctx_ready)
	{
		luat_netdrv_dns_cache_flush_adapter(&net_lwip2_dns_ctx, adapter_index);
	}
#endif
	char buff[64] = {0};
	ipaddr_ntoa_r(ip, buff, 64);
	NET_DBG("设置DNS服务器 id %d index %d ip %s", adapter_index, server_index, buff);
	return 0;
}

static int net_lwip2_set_mac(uint8_t *mac, void *user_data)
{
	// uint8_t index = (uint32_t)user_data;
	// if (index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	// if (!prvlwip.lwip_netif) return -1;
	// memcpy(prvlwip.lwip_netif->hwaddr, mac, 6);
	return -1;
}
static int net_lwip2_set_static_ip(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data)
{
	uint8_t index = (uint32_t)user_data;
	if (index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (!prvlwip.lwip_netif[index]) return -1;
	luat_ip_addr_t *p_ip = luat_heap_zalloc(sizeof(luat_ip_addr_t) * 4);
	if (p_ip == NULL) {
		NET_ERR("net_lwip2_set_static_ip malloc fail");
		return -1;
	}
	memset(p_ip, 0, sizeof(luat_ip_addr_t) * 4);
	if (ip) {
		memcpy(&p_ip[0], ip, sizeof(luat_ip_addr_t));
	}
	if (submask) {
		memcpy(&p_ip[1], submask, sizeof(luat_ip_addr_t));
	}
	if (gateway) {
		memcpy(&p_ip[2], gateway, sizeof(luat_ip_addr_t));
	}
	if (ipv6) {
		memcpy(&p_ip[3], ipv6, sizeof(luat_ip_addr_t));
	}
	platform_send_event(prvlwip.task_handle, EV_LWIP_NETIF_SET_IP, p_ip, ipv6 != NULL, user_data);
	return 0;
}

static int32_t net_lwip2_dummy_callback(void *pData, void *pParam)
{
	return 0;
}

/* ARP 1000ms 定时器及其所有公共 API (sleep_prepare/wakeup_resume/
 * request_start/request_stop/notify_gw_mac_state) 已被完全移除.
 * 历史实现见 commit b4de806e0. */

static void net_lwip2_socket_set_callback(CBFuncEx_t cb_fun, void *param, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return;
	prvlwip.socket_cb = cb_fun?cb_fun:net_lwip2_dummy_callback;
	prvlwip.user_data = param;
}

int net_lwip2_getsockopt2(int socket_id, uint64_t tag,  int level, int optname, void *optval, uint32_t *optlen, void *user_data) {
	int result = net_lwip2_check_socket(user_data, socket_id, tag);
	if (result) return result;
	#if LWIP_SOCKET
	return lwip_getsockopt(socket_id, level, optname, optval, optlen);
	#else
	return 0;
	#endif
}

int net_lwip2_setsockopt2(int socket_id, uint64_t tag,  int level, int optname, const void *optval, uint32_t optlen, void *user_data) {
	int result = net_lwip2_check_socket(user_data, socket_id, tag);
	if (result) return result;
	#if LWIP_SOCKET
	// return lwip_setsockopt(socket_id, level, optname, optval, optlen);
	return 0;
	#else
	return 0;
	#endif
}

static const network_adapter_info prv_net_lwip2_adapter =
{
		.check_ready = net_lwip2_check_ready,
		.create_soceket = net_lwip2_create_socket,
		.socket_connect = net_lwip2_socket_connect,
		.socket_listen = net_lwip2_socket_listen,
		.socket_accept = net_lwip2_socket_accept,
		.socket_disconnect = net_lwip2_socket_disconnect,
		.socket_close = net_lwip2_socket_close,
		.socket_force_close = net_lwip2_socket_force_close,
		.socket_receive = net_lwip2_socket_receive,
		.socket_send = net_lwip2_socket_send,
		.socket_check = net_lwip2_socket_check,
		.socket_clean = net_lwip2_socket_clean,
		.getsockopt = net_lwip2_getsockopt2,
		.setsockopt = net_lwip2_setsockopt2,
		.user_cmd = net_lwip2_user_cmd,
		.dns = net_lwip2_dns,
		.set_dns_server = net_lwip2_set_dns_server,
		// .dns = net_lwip2_dns,
		.dns_ipv6 = net_lwip2_dns_ipv6,
		.set_mac = net_lwip2_set_mac,
		.set_static_ip = net_lwip2_set_static_ip,
		.get_local_ip_info = net_lwip2_get_local_ip_info,
		.get_full_ip_info = net_lwip2_get_full_ip_info,
		.socket_set_callback = net_lwip2_socket_set_callback,
		.name = "lwip",
		.max_socket_num = MAX_SOCK_NUM,
		.no_accept = 0,
		.is_posix = 1,
		.check_ack = net_lwip2_check_ack
};


void net_lwip2_register_adapter(uint8_t adapter_index)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
		return; // 超范围了
	}
	if ( (1 << adapter_index) & register_statue) {
		return; // 注册过了
	}
	network_register_adapter(adapter_index, &prv_net_lwip2_adapter, adapter_index);

	register_statue |= (1 << adapter_index);
}


static int net_lwip2_check_ack(uint8_t adapter_index, int socket_id) {
	if (prvlwip.socket[socket_id].pcb.tcp == NULL)
		return 0;
	if (!llist_empty(&prvlwip.socket[socket_id].wait_ack_head))
	{
		NET_ERR("socekt %d not all ack", socket_id);
		prvlwip.socket_busy |= (1 << socket_id);
		return -1;
	}
	if (!llist_empty(&prvlwip.socket[socket_id].tx_head))
	{
		NET_ERR("socekt %d not all send", socket_id);
		prvlwip.socket_busy |= (1 << socket_id);
		return -1;
	}
	if (prvlwip.socket[socket_id].pcb.tcp->snd_buf != TCP_SND_BUF)
	{
		NET_ERR("socket %d send buf %ubytes, need %u",socket_id, prvlwip.socket[socket_id].pcb.tcp->snd_buf, TCP_SND_BUF);
		prvlwip.socket_busy |= (1 << socket_id);
	}
	else
	{
		prvlwip.socket_busy &= ~(1 << socket_id);
	}
	return 0;
}

#if !defined(CHIP_EC718) && !defined(CHIP_EC618) && !defined(CHIP_EC716) && !defined(CONFIG_SOC_8910)
int net_lwip_check_all_ack(int socket_id)
{
	return net_lwip2_check_ack(0, socket_id);
}
#endif

void net_lwip2_set_link_state(uint8_t adapter_index, uint8_t updown)
{
	// LLOGD("net_lwip2_set_link_state %d %d", adapter_index, updown);
	platform_send_event(NULL, EV_LWIP_NETIF_LINK_STATE, updown, 0, adapter_index);
}

struct netif * net_lwip2_get_netif(uint8_t adapter_index)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY)
		return NULL;
	return prvlwip.lwip_netif[adapter_index];
}

#if LWIP_IPV6 && defined(LUAT_USE_NETDRV_IPV6)
/* 判断是否是全局(可路由)地址: 排除链路本地/环回/组播/未指定/IPv4映射 */
static int net_lwip2_ip6_addr_is_global(const ip6_addr_t *ip6)
{
	if (ip6_addr_islinklocal(ip6) || ip6_addr_ismulticast(ip6) || ip6_addr_isany(ip6)) {
		return 0;
	}
	return 1;
}

/* 在 netif 的 IPv6 地址槽里选一个"最可用"的:
 *   1) PREFERRED 全局地址  -> 2) VALID 全局地址
 *   3) PREFERRED 任意地址(含链路本地) -> 4) VALID 任意地址
 * 这样 netdrv.ipv6()/socket.localIP() 会优先给出用户显式配置或 RA 下发的全局地址,
 * 只有完全没有全局地址时才回落到 fe80:: 链路本地地址.
 * 成功时回填 slot, 返回地址指针; 否则返回 NULL.
 */
static ip6_addr_t *net_lwip2_get_ip6_slot(uint8_t adapter_index, uint8_t *slot)
{
	int i;
	struct netif *netif = prvlwip.lwip_netif[adapter_index];
	if (netif == NULL) {
		return NULL;
	}
	for(i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++)
	{
		if (IP6_ADDR_PREFERRED == (netif->ip6_addr_state[i] & IP6_ADDR_PREFERRED)
			&& net_lwip2_ip6_addr_is_global(netif_ip6_addr(netif, i)))
		{
			if (slot) *slot = (uint8_t)i;
			return &netif->ip6_addr[i];
		}
	}
	for(i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++)
	{
		if ((netif->ip6_addr_state[i] & IP6_ADDR_VALID)
			&& net_lwip2_ip6_addr_is_global(netif_ip6_addr(netif, i)))
		{
			if (slot) *slot = (uint8_t)i;
			return &netif->ip6_addr[i];
		}
	}
	for(i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++)
	{
		if (IP6_ADDR_PREFERRED == (netif->ip6_addr_state[i] & IP6_ADDR_PREFERRED))
		{
			if (slot) *slot = (uint8_t)i;
			return &netif->ip6_addr[i];
		}
	}
	for(i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++)
	{
		if (netif->ip6_addr_state[i] & IP6_ADDR_VALID)
		{
			if (slot) *slot = (uint8_t)i;
			return &netif->ip6_addr[i];
		}
	}
	return NULL;
}

/* slot 0 专门留给链路本地地址 */
#define NET_LWIP2_IP6_SLOT_LINKLOCAL 0

uint8_t net_lwip2_ipv6_supported(void)
{
	return 1;
}

int net_lwip2_ipv6_linklocal_addr_info(uint8_t adapter_index, luat_ip_addr_t *addr, uint8_t *prefix)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	struct netif *netif = prvlwip.lwip_netif[adapter_index];
	if (netif == NULL) return -1;
	ip6_addr_t *ip6 = &netif->ip6_addr[NET_LWIP2_IP6_SLOT_LINKLOCAL];
	if (!ip6_addr_isvalid(netif_ip6_addr_state(netif, NET_LWIP2_IP6_SLOT_LINKLOCAL))
		|| !ip6_addr_islinklocal(ip6)) {
		return -1;
	}
	if (addr) {
		memset(addr, 0, sizeof(luat_ip_addr_t));
		memcpy(&addr->u_addr.ip6, ip6, sizeof(ip6_addr_t));
		addr->type = IPADDR_TYPE_V6;
	}
	if (prefix) {
		*prefix = net_lwip2_ipv6_prefix_get(adapter_index);
	}
	return 0;
}

int net_lwip2_ipv6_addr_info(uint8_t adapter_index, luat_ip_addr_t *addr, uint8_t *prefix)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (prvlwip.lwip_netif[adapter_index] == NULL) return -1;
	ip6_addr_t *ip6 = net_lwip2_get_ip6_slot(adapter_index, NULL);
	if (ip6 == NULL) {
		return -1;
	}
	if (addr) {
		memset(addr, 0, sizeof(luat_ip_addr_t));
		memcpy(&addr->u_addr.ip6, ip6, sizeof(ip6_addr_t));
		addr->type = IPADDR_TYPE_V6;
	}
	if (prefix) {
		*prefix = net_lwip2_ipv6_prefix_get(adapter_index);
	}
	return 0;
}

int net_lwip2_ipv6_is_ready(uint8_t adapter_index)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 0;
	struct netif *netif = prvlwip.lwip_netif[adapter_index];
	if (netif == NULL) return 0;
	// 就绪要求"可路由"的全局地址: 仅有链路本地(fe80::/10)不算就绪,
	// 否则链路本地自动生成后, DHCPv4 未完成时 socket 层就会被误判为网络就绪
	int i;
	for (i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++) {
		if ((netif->ip6_addr_state[i] & IP6_ADDR_VALID)
			&& net_lwip2_ip6_addr_is_global(netif_ip6_addr(netif, i))) {
			return 1;
		}
	}
	return 0;
}

int net_lwip2_ipv6_create_linklocal(uint8_t adapter_index)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	struct netif *netif = prvlwip.lwip_netif[adapter_index];
	if (netif == NULL) return -1;
	// hwaddr 全 0 时生成出来的链路本地地址非法(接口标识全 0), 直接跳过.
	// 典型场景: CH390H 的 MAC 是异步从芯片读出来的, 读回来之前无法生成.
	if (netif->hwaddr_len != ETH_HWADDR_LEN) return -1;
	if (memcmp(netif->hwaddr, "\x00\x00\x00\x00\x00\x00", 6) == 0) {
		LLOGD("adapter %d hwaddr 未就绪, 暂不生成链路本地地址", adapter_index);
		return -1;
	}
	// 幂等: 槽 0 已经是有效地址就不重复生成(重复生成会打断 DAD)
	if (ip6_addr_isvalid(netif_ip6_addr_state(netif, 0))
		&& ip6_addr_islinklocal(netif_ip6_addr(netif, 0))) {
		return 0;
	}
	netif_create_ip6_linklocal_address(netif, 1);
	// 直接置为 PREFERRED, 让地址立即可用.
	// 不做 DAD: 链路本地地址由 MAC(EUI-64)推导, 唯一性已由 MAC 保证;
	// 若保持 TENTATIVE, 出向报文(ICMPv6/ND)会因"无有效源地址"而发不出去.
	netif_ip6_addr_set_state(netif, 0, IP6_ADDR_PREFERRED);
	if (prvlwip.ip6_prefix[adapter_index] == 0) {
		prvlwip.ip6_prefix[adapter_index] = 64;
	}
	LLOGI("adapter %d 链路本地地址已生成, prefix %d", adapter_index, prvlwip.ip6_prefix[adapter_index]);
	return 0;
}

/* 在 tcpip 线程内执行静态 IPv6 地址写入 */
static void net_lwip2_ipv6_apply_set(uint8_t adapter_index, luat_ip_addr_t *ipv6, uint8_t prefix_len)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return;
	struct netif *netif = prvlwip.lwip_netif[adapter_index];
	if (netif == NULL) {
		LLOGW("adapter %d netif 不存在, 无法设置IPv6地址", adapter_index);
		return;
	}
	if (ipv6 == NULL || ipv6->type != IPADDR_TYPE_V6) {
		LLOGW("adapter %d IPv6地址非法", adapter_index);
		return;
	}
	if (prefix_len == 0 || prefix_len > 128) {
		prefix_len = 64;
	}
	ip6_addr_t *ip6 = ip_2_ip6(ipv6);
	// 全局地址: 已存在则原位更新, 否则放第一个空闲的非 0 槽位(槽 0 永远留给链路本地)
	uint8_t slot = 0xFF;
	uint8_t i;
	if (ip6_addr_islinklocal(ip6)) {
		slot = 0;
	}
	else {
		// 先查重: 同一地址重复设置时复用原槽位, 避免占满本就不多的全局槽
		for (i = 1; i < LWIP_IPV6_NUM_ADDRESSES; i++) {
			if (ip6_addr_cmp(netif_ip6_addr(netif, i), ip6)) {
				slot = i;
				break;
			}
		}
		// 没有相同地址, 再取第一个空闲的非 0 槽位; 槽 0 永远留给链路本地地址
		if (slot == 0xFF) {
			for (i = 1; i < LWIP_IPV6_NUM_ADDRESSES; i++) {
				if (netif_ip6_addr_state(netif, i) == IP6_ADDR_INVALID) {
					slot = i;
					break;
				}
			}
		}
		if (slot == 0xFF) {
			// 没有空闲槽位了, 覆盖最后一个
			slot = LWIP_IPV6_NUM_ADDRESSES - 1;
			LLOGW("adapter %d IPv6 槽位已满, 覆盖槽 %d", adapter_index, slot);
		}
	}
	netif_ip6_addr_set(netif, slot, ip6);
	prvlwip.ip6_prefix[adapter_index] = prefix_len;
	// 不跑 DAD: 静态配置由用户保证唯一性, 直接置为 PREFERRED 立即可用;
	// 状态迁移会经 netif_issue_reports() 触发 MLD6 加组与 ND6 上报.
	netif_ip6_addr_set_state(netif, slot, IP6_ADDR_PREFERRED);
	prvlwip.netif_network_ready[adapter_index] = 0; // 强制重算就绪状态
	char buff[64] = {0};
	ip6addr_ntoa_r(ip6, buff, sizeof(buff));
	LLOGI("adapter %d 设置IPv6地址成功 slot=%d %s/%d", adapter_index, slot, buff, prefix_len);
}

/* 读取 netif 的 IPv6 前缀长度; 未设置过则回落到 64 */
uint8_t net_lwip2_ipv6_prefix_get(uint8_t adapter_index)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 64;
	uint8_t prefix = prvlwip.ip6_prefix[adapter_index];
	if (prefix == 0) {
		return 64;
	}
	return prefix;
}

int net_lwip2_set_static_ip6_info(uint8_t adapter_index, luat_ip_addr_t *ipv6, uint8_t prefix_len)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (prvlwip.lwip_netif[adapter_index] == NULL) return -1;
	if (ipv6 == NULL) return -1;
	if (prefix_len == 0 || prefix_len > 128) return -1;
	luat_ip_addr_t *p_ip = luat_heap_zalloc(sizeof(luat_ip_addr_t) * 4);
	if (p_ip == NULL) {
		NET_ERR("net_lwip2_set_static_ip6_info malloc fail");
		return -1;
	}
	memcpy(&p_ip[3], ipv6, sizeof(luat_ip_addr_t));
	// 前缀打包进 Param2 高 24 位, 由 tcpip 线程在 apply_set 内统一写 ip6_prefix, 此处不预写
	platform_send_event(prvlwip.task_handle, EV_LWIP_NETIF_SET_IP, p_ip,
		1 | ((uint32_t)prefix_len << 8), adapter_index);
	return 0;
}

#else /* !(LWIP_IPV6 && defined(LUAT_USE_NETDRV_IPV6)) */

uint8_t net_lwip2_ipv6_supported(void) { return 0; }
int net_lwip2_ipv6_addr_info(uint8_t adapter_index, luat_ip_addr_t *addr, uint8_t *prefix) { return -1; }
int net_lwip2_ipv6_linklocal_addr_info(uint8_t adapter_index, luat_ip_addr_t *addr, uint8_t *prefix) { return -1; }
int net_lwip2_ipv6_create_linklocal(uint8_t adapter_index) { return -1; }
int net_lwip2_set_static_ip6_info(uint8_t adapter_index, luat_ip_addr_t *ipv6, uint8_t prefix_len) { return -1; }
int net_lwip2_ipv6_is_ready(uint8_t adapter_index) { return 0; }

#endif /* LWIP_IPV6 && defined(LUAT_USE_NETDRV_IPV6) */

/* 返回带 type 的 ip_addr_t 副本。不能直接把 netif->ip6_addr[] 强转成
 * ip_addr_t*: ip6_addr_t 只有 16 字节地址, ip_addr_t 末尾还有 type(以及
 * zone 字段), 强转会读到相邻内存, 导致 IP_IS_V6() 判断错误。 */
static ip_addr_t net_lwip2_ip6_source[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];

static ip_addr_t *net_lwip2_get_ip6(uint8_t adapter_index)
{
	#if LWIP_IPV6 && defined(LUAT_USE_NETDRV_IPV6)
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
		return NULL;
	}
	if (net_lwip2_ipv6_addr_info(adapter_index, &net_lwip2_ip6_source[adapter_index], NULL) == 0) {
		return &net_lwip2_ip6_source[adapter_index];
	}
	return NULL;
	#else
	return NULL;
	#endif
}

void net_lwip2_set_dhcp_client(uint8_t adapter_index, dhcp_client_info_t *dhcp_client) {
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
		return; // 超范围了
	}
	if (prvlwip.dhcpc[adapter_index]) {
		return;
	}
	prvlwip.dhcpc[adapter_index] = dhcp_client;
}
