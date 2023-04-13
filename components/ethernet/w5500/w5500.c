#include "platform_def.h"
#include "luat_base.h"
#include "luat_spi.h"
#ifdef LUAT_USE_W5500
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_gpio.h"
#include "w5500_def.h"
#include "luat_crypto.h"
#include "luat_mcu.h"
#include "luat_timer.h"
#include "luat_malloc.h"

#include "luat_network_adapter.h"

//extern void DBG_Printf(const char* format, ...);
//extern void DBG_HexPrintf(void *Data, unsigned int len);
//#if 0
//#define LLOGD(x,y...)
//#define LLOGE(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
//#else
//#define LLOGD(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
//#define LLOGE(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
//#endif

#define LUAT_LOG_TAG "W5500"
#include "luat_log.h"

#define socket_index(n)	(n << 5)
#define common_reg	(0)
#define socket_reg	(1 << 3)
#define socket_tx	(2 << 3)
#define socket_rx	(3 << 3)
#define is_write	(1 << 2)

#define MAX_SOCK_NUM				8
#define SYS_SOCK_ID					0

#define MR_RST                       0x80		/**< reset */
#define MR_WOL                       0x20		/**< Wake on Lan */
#define MR_PB                        0x10		/**< ping block */
#define MR_PPPOE                     0x08		/**< enable pppoe */
#define MR_UDP_FARP                  0x02		/**< enbale FORCE ARP */


#define IR_CONFLICT                  0x80		/**< check ip confict */
#define IR_UNREACH                   0x40		/**< get the destination unreachable message in UDP sending */
#define IR_PPPoE                     0x20		/**< get the PPPoE close message */
#define IR_MAGIC                     0x10		/**< get the magic packet interrupt */


#define Sn_MR_CLOSE                  0x00		/**< unused socket */
#define Sn_MR_TCP                    0x01		/**< TCP */
#define Sn_MR_UDP                    0x02		/**< UDP */
#define Sn_MR_IPRAW                  0x03		/**< IP LAYER RAW SOCK */
#define Sn_MR_MACRAW                 0x04		/**< MAC LAYER RAW SOCK */
#define Sn_MR_PPPOE                  0x05		/**< PPPoE */
#define Sn_MR_UCASTB                 0x10		/**< Unicast Block in UDP Multicating*/
#define Sn_MR_ND                     0x20		/**< No Delayed Ack(TCP) flag */
#define Sn_MR_MC                     0x20		/**< Multicast IGMP (UDP) flag */
#define Sn_MR_BCASTB                 0x40		/**< Broadcast blcok in UDP Multicating */
#define Sn_MR_MULTI                  0x80		/**< support UDP Multicating */


#define Sn_MR_MIP6N                  0x10		/**< IPv6 packet Block */
#define Sn_MR_MMB                    0x20		/**< IPv4 Multicasting Block */
//#define Sn_MR_BCASTB                 0x40     /**< Broadcast blcok */
#define Sn_MR_MFEN                   0x80		/**< support MAC filter enable */


#define Sn_CR_OPEN                   0x01		/**< initialize or open socket */
#define Sn_CR_LISTEN                 0x02		/**< wait connection request in tcp mode(Server mode) */
#define Sn_CR_CONNECT                0x04		/**< send connection request in tcp mode(Client mode) */
#define Sn_CR_DISCON                 0x08		/**< send closing reqeuset in tcp mode */
#define Sn_CR_CLOSE                  0x10		/**< close socket */
#define Sn_CR_SEND                   0x20		/**< update txbuf pointer, send data */
#define Sn_CR_SEND_MAC               0x21		/**< send data with MAC address, so without ARP process */
#define Sn_CR_SEND_KEEP              0x22		/**<  send keep alive message */
#define Sn_CR_RECV                   0x40		/**< update rxbuf pointer, recv data */


#define Sn_IR_SEND_OK                0x10		/**< complete sending */
#define Sn_IR_TIMEOUT                0x08		/**< assert timeout */
#define Sn_IR_RECV                   0x04		/**< receiving data */
#define Sn_IR_DISCON                 0x02		/**< closed socket */
#define Sn_IR_CON                    0x01		/**< established connection */


#define SOCK_CLOSED                  0x00		/**< closed */
#define SOCK_INIT                    0x13		/**< init state */
#define SOCK_LISTEN                  0x14		/**< listen state */
#define SOCK_SYNSENT                 0x15		/**< connection state */
#define SOCK_SYNRECV                 0x16		/**< connection state */
#define SOCK_ESTABLISHED             0x17		/**< success to connect */
#define SOCK_FIN_WAIT                0x18		/**< closing state */
#define SOCK_CLOSING                 0x1A		/**< closing state */
#define SOCK_TIME_WAIT               0x1B		/**< closing state */
#define SOCK_CLOSE_WAIT              0x1C		/**< closing state */
#define SOCK_LAST_ACK                0x1D		/**< closing state */
#define SOCK_UDP                     0x22		/**< udp socket */
#define SOCK_IPRAW                   0x32		/**< ip raw mode socket */
#define SOCK_MACRAW                  0x42		/**< mac raw mode socket */
#define SOCK_PPPOE                   0x5F		/**< pppoe socket */

#define SOCK_BUF_LEN				(20 * 1024)


#include "dhcp_def.h"
#include "dns_def.h"
#define W5500_LOCK	platform_lock_mutex(prv_w5500_ctrl->Sem)
#define W5500_UNLOCK platform_unlock_mutex(prv_w5500_ctrl->Sem)

enum
{
	W5500_COMMON_MR,
	W5500_COMMON_GAR0,
	W5500_COMMON_SUBR0 = 5,
	W5500_COMMON_MAC0 = 9,
	W5500_COMMON_IP0 = 0x0f,
	W5500_COMMON_INTLEVEL0 = 0x13,
	W5500_COMMON_IR = 0x15,
	W5500_COMMON_IMR,
	W5500_COMMON_SOCKET_IR,
	W5500_COMMON_SOCKET_IMR,
	W5500_COMMON_SOCKET_RTR0,
	W5500_COMMON_SOCKET_RCR = 0x1b,
	W5500_COMMON_PPP,
	W5500_COMMON_UIPR0 = 0x28,
	W5500_COMMON_UPORT0 = 0x2c,
	W5500_COMMON_PHY = 0x2e,
	W5500_COMMON_VERSIONR = 0x39,
	W5500_COMMON_QTY,

	W5500_SOCKET_MR = 0,
	W5500_SOCKET_CR,
	W5500_SOCKET_IR,
	W5500_SOCKET_SR,
	W5500_SOCKET_SOURCE_PORT0,
	W5500_SOCKET_DEST_MAC0 = 0x06,
	W5500_SOCKET_DEST_IP0 = 0x0C,
	W5500_SOCKET_DEST_PORT0 = 0x10,
	W5500_SOCKET_SEGMENT0 = 0x12,
	W5500_SOCKET_TOS = 0x15,
	W5500_SOCKET_TTL,
	W5500_SOCKET_RX_MEM_SIZE = 0x1e,
	W5500_SOCKET_TX_MEM_SIZE,
	W5500_SOCKET_TX_FREE_SIZE0 = 0x20,
	W5500_SOCKET_TX_READ_POINT0 = 0x22,
	W5500_SOCKET_TX_WRITE_POINT0 = 0x24,
	W5500_SOCKET_RX_SIZE0 = 0x26,
	W5500_SOCKET_RX_READ_POINT0 = 0x28,
	W5500_SOCKET_RX_WRITE_POINT0 = 0x2A,
	W5500_SOCKET_IMR = 0x2C,
	W5500_SOCKET_IP_HEAD_FRAG_VALUE0,
	W5500_SOCKET_KEEP_TIME = 0x2f,
	W5500_SOCKET_QTY,

	EV_W5500_IRQ = USER_EVENT_ID_START + 1,
	EV_W5500_LINK,
	//以下event的顺序不能变，新增event请在上方添加
	EV_W5500_SOCKET_TX,
	EV_W5500_SOCKET_CONNECT,
	EV_W5500_SOCKET_CLOSE,
	EV_W5500_SOCKET_LISTEN,
	EV_W5500_SOCKET_DNS,
	EV_W5500_RE_INIT,
	EV_W5500_REG_OP,

	W5500_SOCKET_OFFLINE = 0,
	W5500_SOCKET_CONFIG,
	W5500_SOCKET_CONNECT,
	W5500_SOCKET_ONLINE,
	W5500_SOCKET_CLOSING,
};

typedef struct
{
	llist_head node;
	uint64_t tag;	//考虑到socket复用的问题，必须有tag来做比对
	luat_ip_addr_t ip;
	uint8_t *data;
	uint32_t read_pos;
	uint32_t len;
	uint16_t port;
	uint8_t is_sending;
}socket_data_t;

typedef struct
{
	socket_ctrl_t socket[MAX_SOCK_NUM];
	dhcp_client_info_t dhcp_client;
	dns_client_t dns_client;
	uint64_t last_tx_time;
	uint64_t tag;
	CBFuncEx_t socket_cb;
	void *user_data;
	void *task_handle;
	HANDLE Sem;
	uint32_t static_ip; //大端格式存放
	uint32_t static_submask; //大端格式存放
	uint32_t static_gateway; //大端格式存放
	uint16_t RTR;
	uint8_t RCR;
	uint8_t force_arp;
	uint8_t auto_speed;
	uint8_t spi_id;
	uint8_t cs_pin;
	uint8_t rst_pin;
	uint8_t irq_pin;
	uint8_t link_pin;
	uint8_t speed_status;
	uint8_t link_ready;
	uint8_t ip_ready;
	uint8_t network_ready;
	uint8_t inter_error;
	uint8_t device_on;
	uint8_t last_udp_send_ok;
	uint8_t rx_buf[2048 + 8];
	uint8_t tx_buf[2048 + 8];
	uint8_t mac[6];
	uint8_t next_socket_index;
	uint8_t self_index;
}w5500_ctrl_t;

static w5500_ctrl_t *prv_w5500_ctrl;

static void w5500_ip_state(w5500_ctrl_t *w5500, uint8_t check_state);
static void w5500_check_dhcp(w5500_ctrl_t *w5500);
static void w5500_init_reg(w5500_ctrl_t *w5500);

static int w5500_del_data_cache(void *p, void *u)
{
	socket_data_t *pdata = (socket_data_t *)p;
	free(pdata->data);
	return LIST_DEL;
}

static int w5500_next_data_cache(void *p, void *u)
{
	socket_ctrl_t *socket = (socket_ctrl_t *)u;
	socket_data_t *pdata = (socket_data_t *)p;
	if (socket->tag != pdata->tag)
	{
		LLOGD("tag error");
		free(pdata->data);
		return LIST_DEL;
	}
	return LIST_FIND;
}


static int32_t w5500_irq(int pin, void *args)
{
	w5500_ctrl_t *w5500 = (w5500_ctrl_t *)args;
	if ((pin & 0x00ff) == w5500->irq_pin)
	{
		platform_send_event(w5500->task_handle, EV_W5500_IRQ, 0, 0, 0);
	}
	if ((pin & 0x00ff) == w5500->link_pin)
	{
		platform_send_event(w5500->task_handle, EV_W5500_LINK, 0, 0, 0);
	}
	return 0;
}

static void w5500_callback_to_nw_task(w5500_ctrl_t *w5500, uint32_t event_id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	luat_network_cb_param_t param = {.tag = 0, .param = w5500->user_data};
	OS_EVENT event = { .ID = event_id, .Param1 = param1, .Param2 = param2, .Param3 = param3};
	if (event_id > EV_NW_DNS_RESULT)
	{
		event.Param3 = prv_w5500_ctrl->socket[param1].param;
		param.tag = prv_w5500_ctrl->socket[param1].tag;
		if (EV_NW_SOCKET_CLOSE_OK == event_id)
		{
			prv_w5500_ctrl->socket[param1].param = NULL;
		}
	}
	w5500->socket_cb(&event, &param);
}



static void w5500_xfer(w5500_ctrl_t *w5500, uint16_t address, uint8_t ctrl, uint8_t *data, uint32_t len)
{
	BytesPutBe16(w5500->tx_buf, address);
	w5500->tx_buf[2] = ctrl;
	if (data && len)
	{
		memcpy(w5500->tx_buf + 3, data, len);
	}
	luat_gpio_set(w5500->cs_pin, 0);
	// TODO 选个更通用的宏
	#if defined(AIR101) || defined(AIR103)
	// 不支持全双工的BSP,通过半双工API读写
	if (ctrl & is_write) {
		// 整体传输就行
		if (data && len)
			luat_spi_send(w5500->spi_id, (const char* )w5500->tx_buf, len + 3);
		else
			luat_spi_send(w5500->spi_id, (const char* )w5500->tx_buf, 3);
	}
	else {
		// 先发3字的控制块
		luat_spi_send(w5500->spi_id, (const char* )w5500->tx_buf, 3);
		// 然后按len读取数据
		if (data && len)
			luat_spi_recv(w5500->spi_id, (const char* )w5500->rx_buf + 3, len);
	}
	#else
	luat_spi_transfer(w5500->spi_id, (const char* )w5500->tx_buf, len + 3, (char*)w5500->rx_buf, len + 3);
	#endif
	luat_gpio_set(w5500->cs_pin, 1);
	if (data && len)
	{
		memcpy(data, w5500->rx_buf + 3, len);
	}
}


static uint8_t w5500_socket_state(w5500_ctrl_t *w5500, uint8_t socket_id)
{
	uint8_t retry = 0;
	uint8_t temp[4];
	do
	{
		w5500_xfer(w5500, W5500_SOCKET_MR, socket_index(socket_id)|socket_reg, temp, 4);
		if (temp[W5500_SOCKET_MR] == 0xff)	//模块读不到了
		{
			w5500->device_on = 0;
			return 0;
		}
		retry++;
	}while(temp[W5500_SOCKET_CR] && (retry < 10));
	if (retry >= 10)
	{
		w5500->inter_error++;
		LLOGE("check too much times, error %d", w5500->inter_error);

	}
	return temp[W5500_SOCKET_SR];
}

static void w5500_socket_disconnect(w5500_ctrl_t *w5500, uint8_t socket_id)
{
	uint8_t temp;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return;

	if (SOCK_CLOSED == temp)
	{
		w5500->socket[socket_id].state = W5500_SOCKET_OFFLINE;
//		LLOGD("socket %d already closed");
		return;
	}
//	if ((temp >= SOCK_FIN_WAIT) && (temp <= SOCK_LAST_ACK))
//	{
//		w5500->socket[socket_id].state = W5500_SOCKET_CLOSING;
//		LLOGD("socket %d is closing");
//		return;
//
//	}
	temp = Sn_CR_DISCON;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, &temp, 1);
	w5500->socket[socket_id].state = W5500_SOCKET_CLOSING;
}

static void w5500_socket_close(w5500_ctrl_t *w5500, uint8_t socket_id)
{
	uint8_t temp;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return;
//
//	if (SOCK_CLOSED == temp)
//	{
//		w5500->socket[socket_id].state = W5500_SOCKET_OFFLINE;
////		LLOGD("socket %d already closed");
//		return;
//	}
	temp = Sn_CR_CLOSE;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, &temp, 1);
	w5500->socket[socket_id].state = W5500_SOCKET_OFFLINE;
}

static int w5500_socket_config(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t is_tcp, uint16_t local_port)
{
	uint8_t delay_cnt = 0;
	uint8_t temp = 0;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if (SOCK_CLOSED != temp)
	{
		LLOGE("socket %d not closed state %x", socket_id, temp);
		return -1;
	}
	uint8_t cmd[32];
	uint16_t wtemp;
	for(temp = 0; temp < 3; temp++)
	{
		cmd[W5500_SOCKET_MR] = is_tcp?Sn_MR_TCP:Sn_MR_UDP;
		cmd[W5500_SOCKET_CR] = 0;
		cmd[W5500_SOCKET_IR] = 0xff;
		BytesPutBe16(&cmd[W5500_SOCKET_SOURCE_PORT0], local_port);
		BytesPutLe32(&cmd[W5500_SOCKET_DEST_IP0], 0xffffffff);
		BytesPutBe16(&cmd[W5500_SOCKET_DEST_PORT0], 0);
		BytesPutBe16(&cmd[W5500_SOCKET_SEGMENT0], is_tcp?1460:1472);
		w5500_xfer(w5500, W5500_SOCKET_MR, socket_index(socket_id)|socket_reg|is_write, cmd, W5500_SOCKET_TOS - 1);
		w5500_xfer(w5500, W5500_SOCKET_MR, socket_index(socket_id)|socket_reg, cmd, W5500_SOCKET_TOS - 1);
		wtemp = BytesGetBe16(&cmd[W5500_SOCKET_SOURCE_PORT0]);
		if (wtemp != local_port)
		{
			LLOGE("error port %u %u", wtemp, local_port);
		}
		else
		{
			goto W5500_SOCKET_CONFIG_START;
		}

	}
	return -1;
W5500_SOCKET_CONFIG_START:
	cmd[0] = Sn_CR_OPEN;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, cmd, 1);
	do
	{
		temp = w5500_socket_state(w5500, socket_id);
		if (!w5500->device_on) return -1;
		delay_cnt++;
	}while((temp != SOCK_INIT) && (temp != SOCK_UDP) && (delay_cnt < 100));
	if (delay_cnt >= 100)
	{
		w5500->inter_error++;
		LLOGE("socket %d config timeout, error %d", socket_id, w5500->inter_error);
		return -1;
	}
	w5500->socket[socket_id].state = is_tcp?W5500_SOCKET_CONFIG:W5500_SOCKET_ONLINE;
	return 0;
}

static int w5500_socket_connect(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t is_listen, uint32_t remote_ip, uint16_t remote_port)
{
	uint32_t ip;
	uint16_t port;
	uint8_t delay_cnt;
	uint8_t temp;
	uint8_t cmd[16];
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if ((temp != SOCK_INIT) && (temp != SOCK_UDP))
	{
		LLOGD("socket %d not config state %x", socket_id, temp);
		return -1;
	}
//	BytesPutLe32(cmd, remote_ip);
//	LLOGD("%02d.%02d.%02d,%02d, %u, %d", cmd[0], cmd[1], cmd[2], cmd[3], remote_port, is_listen);
	if (!is_listen)
	{
//		w5500_xfer(w5500, W5500_SOCKET_DEST_IP0, socket_index(socket_id)|socket_reg, cmd, 6);
//		ip = BytesGetLe32(cmd);
//		port = BytesGetBe16(cmd + 4);
//		if (ip != remote_ip || port != remote_port)
		{
			BytesPutLe32(cmd, remote_ip);
			BytesPutBe16(&cmd[W5500_SOCKET_DEST_PORT0 - W5500_SOCKET_DEST_IP0], remote_port);
			w5500_xfer(w5500, W5500_SOCKET_DEST_IP0, socket_index(socket_id)|socket_reg|is_write, cmd, 6);
		}

	}
// W5500_SOCKET_CONNECT_START:
	if (temp != SOCK_UDP)
	{
		uint8_t temp = is_listen?Sn_CR_LISTEN:Sn_CR_CONNECT;
		w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, &temp, 1);
		w5500->socket[socket_id].state = W5500_SOCKET_CONNECT;
	}
	return 0;
}

static int w5500_socket_auto_heart(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t time)
{
	uint8_t point[6];
	point[0] = time;
	w5500_xfer(w5500, W5500_SOCKET_KEEP_TIME, socket_index(socket_id)|socket_reg|is_write, point, 1);
	return 0;
}

static int w5500_socket_tx(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t *data, uint32_t len)
{
	uint8_t delay_cnt;
	uint8_t temp;
	uint8_t point[6];
	uint16_t tx_free, tx_point;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if ((temp != SOCK_ESTABLISHED) && (temp != SOCK_UDP))
	{
		LLOGD("socket %d not online state %x", socket_id, temp);
		return -1;
	}
	w5500->socket[socket_id].state = W5500_SOCKET_ONLINE;
	if (!data || !len)
	{
		point[0] = Sn_CR_SEND_KEEP;
		w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, point, 1);
	}

	w5500_xfer(w5500, W5500_SOCKET_TX_FREE_SIZE0, socket_index(socket_id)|socket_reg, point, 6);
	tx_free = BytesGetBe16(point);
	tx_point = BytesGetBe16(point + 4);
//	if (tx_free != 2048)
//	{
//		LLOGD("%d,0x%04x,%u,%u", socket_id, tx_point, len,tx_free);
//	}
//	DBG_HexPrintf(data, len);
	if (len > tx_free)
	{
		len = tx_free;
	}

	w5500->last_tx_time = luat_mcu_tick64_ms();
	w5500_xfer(w5500, tx_point, socket_index(socket_id)|socket_tx|is_write, data, len);
	tx_point += len;
	BytesPutBe16(point, tx_point);
	w5500_xfer(w5500, W5500_SOCKET_TX_WRITE_POINT0, socket_index(socket_id)|socket_reg|is_write, point, 2);
	point[0] = Sn_CR_SEND;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, point, 1);
	return len;
}

static int w5500_socket_rx(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t *data, uint16_t len)
{
	uint8_t delay_cnt;
	uint8_t temp;
	uint8_t point[4];
	uint16_t rx_size, rx_point;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if ((temp < SOCK_ESTABLISHED) || (temp > SOCK_UDP))
	{
		LLOGD("socket %d not config state %x", socket_id, temp);
		return -1;
	}
	w5500->socket[socket_id].state = W5500_SOCKET_ONLINE;
	w5500_xfer(w5500, W5500_SOCKET_RX_SIZE0, socket_index(socket_id)|socket_reg, point, 4);

	rx_size = BytesGetBe16(point);
	rx_point = BytesGetBe16(point + 2);
//	LLOGD("%d,0x%04x,%u", socket_id, rx_point, rx_size);
	if (!rx_size) return 0;
	if (rx_size < len)
	{
		len = rx_size;
	}
	w5500_xfer(w5500, rx_point, socket_index(socket_id)|socket_rx, data, len);
	rx_point += len;
	BytesPutBe16(point, rx_point);
	w5500_xfer(w5500, W5500_SOCKET_RX_READ_POINT0, socket_index(socket_id)|socket_reg|is_write, point, 2);
	point[0] = Sn_CR_RECV;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, point, 1);
	return len;
}

extern void w5500_nw_state_cb(int state, uint32_t ip);

static void w5500_nw_state(w5500_ctrl_t *w5500)
{
	int i;
	PV_Union uIP;
	if (w5500->link_ready && w5500->ip_ready)
	{
		if (!w5500->network_ready)
		{
			w5500->network_ready = 1;
			dns_clear(&w5500->dns_client);
			w5500->socket[0].tx_wait_size = 0;	//dns可以继续发送了
			w5500_callback_to_nw_task(w5500, EV_NW_STATE, 0, 1, w5500->self_index);
			LLOGD("network ready");
			w5500_nw_state_cb(1, w5500->dhcp_client.temp_ip == 0 ? w5500->static_ip : w5500->dhcp_client.temp_ip);
			for(i = 0; i < MAX_DNS_SERVER; i++)
			{
#ifdef LUAT_USE_LWIP
				if (network_ip_is_vaild_ipv4(&w5500->dns_client.dns_server[i]))
				{
					uIP.u32 = ip_addr_get_ip4_u32(&w5500->dns_client.dns_server[i]);
					LLOGD("DNS%d:%d.%d.%d.%d",i, uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
				}
#else
				if (w5500->dns_client.dns_server[i].is_ipv6 != 0xff)
				{
					uIP.u32 = w5500->dns_client.dns_server[i].ipv4;
					LLOGD("DNS%d:%d.%d.%d.%d",i, uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
				}
#endif
			}
		}
	}
	else
	{
		if (w5500->network_ready)
		{
			w5500->network_ready = 0;
			dns_clear(&w5500->dns_client);
			w5500_callback_to_nw_task(w5500, EV_NW_STATE, 0, 0, w5500->self_index);
			LLOGD("network not ready");
			w5500_nw_state_cb(0, 0);
			for(i = 0; i < MAX_SOCK_NUM; i++)
			{
				w5500->socket[i].tx_wait_size = 0;
//				llist_traversal(&w5500->socket[i].tx_head, w5500_del_data_cache, NULL);
//				llist_traversal(&w5500->socket[i].rx_head, w5500_del_data_cache, NULL);
			}
		}
	}
}


static void w5500_check_dhcp(w5500_ctrl_t *w5500)
{
	if (w5500->static_ip) return;
	if (DHCP_STATE_CHECK == w5500->dhcp_client.state)
	{
		w5500->dhcp_client.state = DHCP_STATE_WAIT_LEASE_P1;
		uint8_t temp[24];
		PV_Union uIP;
		memset(temp, 0, sizeof(temp));
		temp[0] = w5500->force_arp?MR_UDP_FARP:0;
		BytesPutLe32(&temp[W5500_COMMON_GAR0], w5500->dhcp_client.gateway);
		BytesPutLe32(&temp[W5500_COMMON_SUBR0], w5500->dhcp_client.submask);
		BytesPutLe32(&temp[W5500_COMMON_IP0], w5500->dhcp_client.ip);
		memcpy(&temp[W5500_COMMON_MAC0], w5500->dhcp_client.mac, 6);
		w5500_xfer(w5500, W5500_COMMON_MR, is_write, temp, W5500_COMMON_INTLEVEL0);
		w5500->dhcp_client.discover_cnt = 0;

		uIP.u32 = w5500->dhcp_client.ip;
		LLOGD("动态IP:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		uIP.u32 = w5500->dhcp_client.submask;
		LLOGD("子网掩码:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		uIP.u32 = w5500->dhcp_client.gateway;
		LLOGD("网关:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		LLOGD("租约时间:%u秒", w5500->dhcp_client.lease_time);
		int i;
		for(i = 0; i < MAX_DNS_SERVER; i++)
		{
			if (w5500->dns_client.is_static_dns[i])
			{
				goto PRINT_DNS;
			}
		}
#ifdef LUAT_USE_LWIP
		if (w5500->dhcp_client.dns_server[0])
		{
			network_set_ip_ipv4(&w5500->dns_client.dns_server[0], w5500->dhcp_client.dns_server[0]);
		}

		if (w5500->dhcp_client.dns_server[1])
		{
			network_set_ip_ipv4(&w5500->dns_client.dns_server[1], w5500->dhcp_client.dns_server[1]);
		}
#else
		if (w5500->dhcp_client.dns_server[0])
		{
			w5500->dns_client.dns_server[0].ipv4 = w5500->dhcp_client.dns_server[0];
			w5500->dns_client.dns_server[0].is_ipv6 = 0;
		}

		if (w5500->dhcp_client.dns_server[1])
		{
			w5500->dns_client.dns_server[1].ipv4 = w5500->dhcp_client.dns_server[1];
			w5500->dns_client.dns_server[1].is_ipv6 = 0;
		}
#endif
PRINT_DNS:
		w5500_ip_state(w5500, 1);

	}
	if ((!w5500->last_udp_send_ok && w5500->dhcp_client.discover_cnt >= 1) || (w5500->last_udp_send_ok && w5500->dhcp_client.discover_cnt >= 3))
	{
		LLOGD("dhcp long time not get ip, reboot w5500");
		memset(&w5500->dhcp_client, 0, sizeof(w5500->dhcp_client));
		platform_send_event(w5500->task_handle, EV_W5500_RE_INIT, 0, 0, 0);
	}


}

static void w5500_link_state(w5500_ctrl_t *w5500, uint8_t check_state)
{
	Buffer_Struct tx_msg_buf = {0,0,0};
	uint32_t remote_ip;
	int result;
	if (w5500->link_ready != check_state)
	{
		LLOGD("link %d -> %d", w5500->link_ready, check_state);
		w5500->link_ready = check_state;

		if (w5500->link_ready)
		{
			if (!w5500->static_ip)
			{
				w5500_ip_state(w5500, 0);
				w5500->dhcp_client.state = w5500->dhcp_client.ip?DHCP_STATE_REQUIRE:DHCP_STATE_DISCOVER;
				uint8_t temp[1];
				temp[0] = MR_UDP_FARP;
				w5500_xfer(w5500, W5500_COMMON_MR, is_write, temp, 1);
				result = ip4_dhcp_run(&w5500->dhcp_client, NULL, &tx_msg_buf, &remote_ip);
				w5500_check_dhcp(w5500);
				if (tx_msg_buf.Pos)
				{
					w5500_socket_connect(w5500, SYS_SOCK_ID, 0, remote_ip, DHCP_SERVER_PORT);
					w5500_socket_tx(w5500, SYS_SOCK_ID, tx_msg_buf.Data, tx_msg_buf.Pos);
					w5500->last_udp_send_ok = 0;
				}
				OS_DeInitBuffer(&tx_msg_buf);
			}
		}
		else
		{
			if (luat_mcu_tick64_ms() < (w5500->last_tx_time + 1500))
			{
				w5500->inter_error++;
				LLOGE("link down too fast, error %u", w5500->inter_error);
			}
		}


		w5500_nw_state(w5500);
	}
}

static void w5500_ip_state(w5500_ctrl_t *w5500, uint8_t check_state)
{
	if (w5500->ip_ready != check_state)
	{
		LLOGD("ip %d -> %d", w5500->ip_ready, check_state);
		w5500->ip_ready = check_state;
		w5500_nw_state(w5500);
	}
}

static void w5500_init_reg(w5500_ctrl_t *w5500)
{
	uint8_t temp[64];
	luat_gpio_set(w5500->rst_pin, 0);
	msleep(5);
	luat_gpio_set(w5500->rst_pin, 1);
	msleep(10);
	w5500->ip_ready = 0;
	w5500->network_ready = 0;
	if (w5500->static_ip)
	{
		w5500->dhcp_client.state = DHCP_STATE_NOT_WORK;
	}
	else
	{
		if (w5500->auto_speed)
		{
			w5500->dhcp_client.state = DHCP_STATE_DISCOVER;
		}
		else
		{
			if ((w5500->dhcp_client.state == DHCP_STATE_NOT_WORK) || !w5500->dhcp_client.ip)
			{
				w5500->dhcp_client.state = DHCP_STATE_DISCOVER;
			}
			else
			{
				w5500->dhcp_client.state = DHCP_STATE_REQUIRE;
			}
		}
	}
	w5500_callback_to_nw_task(w5500, EV_NW_RESET, 0, 0, w5500->self_index);

	luat_gpio_close(w5500->link_pin);
	luat_gpio_close(w5500->irq_pin);

	w5500_xfer(w5500, W5500_COMMON_MR, 0, temp, W5500_COMMON_QTY);
	w5500->device_on = (0x04 == temp[W5500_COMMON_VERSIONR])?1:0;
	w5500_link_state(w5500, w5500->device_on?(temp[W5500_COMMON_PHY] & 0x01):0);

	temp[W5500_COMMON_MR] = w5500->force_arp?MR_UDP_FARP:0;
	if (w5500->static_ip)
	{
		BytesPutLe32(&temp[W5500_COMMON_GAR0], w5500->static_gateway);	//已经是大端格式了不需要转换
		BytesPutLe32(&temp[W5500_COMMON_SUBR0], w5500->static_submask); //已经是大端格式了不需要转换
		BytesPutLe32(&temp[W5500_COMMON_IP0], w5500->static_ip); //已经是大端格式了不需要转换
	}
	else if (w5500->dhcp_client.ip)
	{
		BytesPutLe32(&temp[W5500_COMMON_GAR0], w5500->dhcp_client.gateway);
		BytesPutLe32(&temp[W5500_COMMON_SUBR0], w5500->dhcp_client.submask);
		BytesPutLe32(&temp[W5500_COMMON_IP0], w5500->dhcp_client.ip);
	}
	else
	{
		BytesPutLe32(&temp[W5500_COMMON_GAR0], 0);
		BytesPutLe32(&temp[W5500_COMMON_SUBR0], 0);
		BytesPutLe32(&temp[W5500_COMMON_IP0], 0);
	}


	memcpy(&temp[W5500_COMMON_MAC0], w5500->mac, 6);

	memcpy(w5500->dhcp_client.mac, &temp[W5500_COMMON_MAC0], 6);
	sprintf_(w5500->dhcp_client.name, "airm2m-%02x%02x%02x%02x%02x%02x",
			w5500->dhcp_client.mac[0],w5500->dhcp_client.mac[1], w5500->dhcp_client.mac[2],
			w5500->dhcp_client.mac[3],w5500->dhcp_client.mac[4], w5500->dhcp_client.mac[5]);


//	BytesPutBe16(&temp[W5500_COMMON_SOCKET_RTR0], w5500->RTR);
	temp[W5500_COMMON_IMR] = IR_CONFLICT|IR_UNREACH|IR_MAGIC;
	temp[W5500_COMMON_SOCKET_IMR] = 0xff;
//	temp[W5500_COMMON_SOCKET_RCR] = w5500->RCR;
//	DBG_HexPrintf(temp + W5500_COMMON_SOCKET_RTR0, 3);
	w5500_xfer(w5500, W5500_COMMON_MR, is_write, temp, W5500_COMMON_QTY);
//	memset(temp, 0, sizeof(temp));
//	w5500_xfer(w5500, W5500_COMMON_MR, 0, NULL, W5500_COMMON_QTY);
//	DBG_HexPrintf(temp, W5500_COMMON_QTY);
	w5500_ip_state(w5500, w5500->static_ip?1:0);

	luat_gpio_t gpio = {0};
	gpio.pin = w5500->irq_pin;
	gpio.mode = Luat_GPIO_IRQ;
	gpio.pull = Luat_GPIO_PULLUP;
	gpio.irq = Luat_GPIO_FALLING;
	gpio.irq_cb = w5500_irq;
	gpio.irq_args = w5500;
	luat_gpio_setup(&gpio);

	gpio.pin = w5500->link_pin;
	gpio.pull = Luat_GPIO_DEFAULT;
	gpio.irq = Luat_GPIO_BOTH;
	gpio.irq_cb = w5500_irq;
	gpio.irq_args = w5500;
	luat_gpio_setup(&gpio);

	w5500_socket_auto_heart(w5500, SYS_SOCK_ID, 2);
	w5500_socket_config(w5500, SYS_SOCK_ID, 0, DHCP_CLIENT_PORT);

	if (w5500->auto_speed)
	{
		temp[0] = 0x78;
		w5500_xfer(w5500, W5500_COMMON_PHY, is_write, temp, 1);
		temp[0] = 0x78+ 0x80;
		w5500_xfer(w5500, W5500_COMMON_PHY, is_write, temp, 1);
	}
	w5500->inter_error = 0;
	w5500->next_socket_index = 1;
	int i;
	for(i = 0; i < MAX_DNS_SERVER; i++)
	{
		if (!w5500->dns_client.is_static_dns[i])
		{
#ifdef LUAT_USE_LWIP
			network_set_ip_invaild(&w5500->dns_client.dns_server[i]);
#else
			w5500->dns_client.dns_server[i].is_ipv6 = 0xff;
#endif
		}
	}

}

static int32_t w5500_dummy_callback(void *pData, void *pParam)
{
	return 0;
}

static socket_data_t * w5500_create_data_node(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t *data, uint32_t len, luat_ip_addr_t *remote_ip, uint16_t remote_port)
{
	socket_data_t *p = (socket_data_t *)malloc(sizeof(socket_data_t));
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
#ifdef 	LUAT_USE_LWIP
			network_set_ip_invaild(&p->ip);
#else
			p->ip.is_ipv6 = 0xff;
#endif
		}
		p->tag = w5500->socket[socket_id].tag;
		if (data && len)
		{
			p->data = malloc(len);
			if (p->data)
			{
				memcpy(p->data, data, len);
			}
			else
			{
				free(p);
				return NULL;
			}
		}
	}
	return p;
}

static void w5500_socket_tx_next_data(w5500_ctrl_t *w5500, uint8_t socket_id)
{
	W5500_LOCK;
	socket_data_t *p = llist_traversal(&w5500->socket[socket_id].tx_head, w5500_next_data_cache, &prv_w5500_ctrl->socket[socket_id]);
	W5500_UNLOCK;
	if (p)
	{
		if (!w5500->socket[socket_id].is_tcp)
		{
#ifdef 	LUAT_USE_LWIP
			w5500_socket_connect(w5500, socket_id, 0, ip_addr_get_ip4_u32(&p->ip), p->port);
#else
			w5500_socket_connect(w5500, socket_id, 0, p->ip.ipv4, p->port);
#endif
		}
		if (p->data && p->len)
		{
			p->read_pos += w5500_socket_tx(w5500, socket_id, p->data + p->read_pos, p->len - p->read_pos);
			p->is_sending = 1;
		}
		else
		{
			w5500_socket_tx(w5500, socket_id, NULL, 0);
			p->len = 0;
			p->read_pos = 0;
			p->is_sending = 1;
		}
	}
}

static int32_t w5500_dns_check_result(void *data, void *param)
{
	luat_dns_require_t *require = (luat_dns_require_t *)data;
	if (require->result != 0)
	{
		free(require->uri.Data);
		require->uri.Data = NULL;
		if (require->result > 0)
		{
			luat_dns_ip_result *ip_result = zalloc(sizeof(luat_dns_ip_result) * require->result);
			int i;
			for(i = 0; i < require->result; i++)
			{
				ip_result[i] = require->ip_result[i];
			}
			w5500_callback_to_nw_task(param, EV_NW_DNS_RESULT, require->result, ip_result, require->param);
		}
		else
		{
			w5500_callback_to_nw_task(param, EV_NW_DNS_RESULT, 0, 0, require->param);
		}

		return LIST_DEL;
	}
	else
	{
		return LIST_PASS;
	}
}

static void w5500_dns_tx_next(w5500_ctrl_t *w5500, Buffer_Struct *tx_msg_buf)
{
	int i;
	if (w5500->socket[SYS_SOCK_ID].tx_wait_size) return;
	dns_run(&w5500->dns_client, NULL, tx_msg_buf, &i);
	if (tx_msg_buf->Pos)
	{
#ifdef 	LUAT_USE_LWIP
		w5500_socket_connect(w5500, SYS_SOCK_ID, 0, ip_addr_get_ip4_u32(&w5500->dns_client.dns_server[i]), DNS_SERVER_PORT);
#else
		w5500_socket_connect(w5500, SYS_SOCK_ID, 0, w5500->dns_client.dns_server[i].ipv4, DNS_SERVER_PORT);
#endif
		if (!w5500_socket_tx(w5500, SYS_SOCK_ID, tx_msg_buf->Data, tx_msg_buf->Pos))
		{
			w5500->socket[SYS_SOCK_ID].tx_wait_size = 1;
		}
		OS_DeInitBuffer(tx_msg_buf);
		llist_traversal(&w5500->dns_client.require_head, w5500_dns_check_result, w5500);
	}
}

static void w5500_sys_socket_callback(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t event)
{
	Buffer_Struct rx_buf;
	Buffer_Struct msg_buf;
	Buffer_Struct tx_msg_buf = {0,0,0};
	int result, i;
	uint32_t ip;
	uint16_t port;
	uint16_t len;
	socket_data_t *p;
	luat_ip_addr_t ip_addr;
	switch(event)
	{
	case Sn_IR_SEND_OK:
		if (!socket_id)
		{
			w5500->last_udp_send_ok = 1;
			if (w5500->network_ready)
			{
				w5500->socket[SYS_SOCK_ID].tx_wait_size = 0;
				w5500_dns_tx_next(w5500, &tx_msg_buf);
			}
		}
		else if (w5500->network_ready)
		{
			W5500_LOCK;
			p = llist_traversal(&w5500->socket[socket_id].tx_head, w5500_next_data_cache, &prv_w5500_ctrl->socket[socket_id]);

			if (p && !p->is_sending)
			{
				LLOGE("socket %d should sending!", socket_id);
				p->read_pos = 0;
			}
			if (p && (p->read_pos >= p->len))
			{
				ip = p->len;
				w5500->socket[socket_id].tx_wait_size -= p->len;
				llist_del(&p->node);
				free(p->data);
				free(p);
				W5500_UNLOCK;
				w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_TX_OK, socket_id, ip, 0);
			}
			else
			{
				W5500_UNLOCK;
			}
			w5500_socket_tx_next_data(w5500, socket_id);
			if (llist_empty(&w5500->socket[socket_id].tx_head))
			{
				w5500->socket[socket_id].tx_wait_size = 0;
			}


		}
		break;
	case Sn_IR_RECV:
		if (socket_id && (w5500->socket[socket_id].rx_wait_size >= SOCK_BUF_LEN))
		{
			LLOGD("socket %d, wait %dbyte", socket_id, w5500->socket[socket_id].rx_wait_size);
			w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_RX_FULL, socket_id, 0, 0);
			w5500->socket[socket_id].rx_waiting = 1;
			break;
		}
		OS_InitBuffer(&rx_buf, 2048);
		result = w5500_socket_rx(w5500, socket_id, rx_buf.Data, rx_buf.MaxLen);
		if (result > 0)
		{
			if (socket_id)
			{
				if (w5500->socket[socket_id].is_tcp)
				{
					socket_data_t *p = w5500_create_data_node(w5500, socket_id, rx_buf.Data, result, NULL, 0);
					W5500_LOCK;
					llist_add_tail(&p->node, &prv_w5500_ctrl->socket[socket_id].rx_head);
					prv_w5500_ctrl->socket[socket_id].rx_wait_size += result;
					W5500_UNLOCK;
					w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_RX_NEW, socket_id, result, 0);
				}
				else
				{
					W5500_LOCK;
					rx_buf.Pos = 0;
					while (rx_buf.Pos < result)
					{
#ifdef LUAT_USE_LWIP
						network_set_ip_ipv4(&ip_addr, BytesGetLe32(rx_buf.Data + rx_buf.Pos));
#else
						ip_addr.ipv4 = BytesGetLe32(rx_buf.Data + rx_buf.Pos);
						ip_addr.is_ipv6 = 0;
#endif
						port = BytesGetBe16(rx_buf.Data + rx_buf.Pos + 4);
						len = BytesGetBe16(rx_buf.Data + rx_buf.Pos + 6);
						msg_buf.Data = rx_buf.Data + rx_buf.Pos + 8;
						msg_buf.MaxLen = len;
						socket_data_t *p = w5500_create_data_node(w5500, socket_id, rx_buf.Data + rx_buf.Pos + 8, len, &ip_addr, port);
						rx_buf.Pos += 8 + len;
						llist_add_tail(&p->node, &prv_w5500_ctrl->socket[socket_id].rx_head);
						prv_w5500_ctrl->socket[socket_id].rx_wait_size += len;
					}
					W5500_UNLOCK;
					w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_RX_NEW, socket_id, result, 0);
				}
			}
			else
			{
				rx_buf.Pos = 0;
				while (rx_buf.Pos < result)
				{
					ip = BytesGetBe32(rx_buf.Data + rx_buf.Pos);
					port = BytesGetBe16(rx_buf.Data + rx_buf.Pos + 4);
					len = BytesGetBe16(rx_buf.Data + rx_buf.Pos + 6);
					msg_buf.Data = rx_buf.Data + rx_buf.Pos + 8;
					msg_buf.MaxLen = len;
					msg_buf.Pos = 0;
					switch(port)
					{
					case DHCP_SERVER_PORT:
						ip4_dhcp_run(&w5500->dhcp_client, &msg_buf, &tx_msg_buf, &ip);
						w5500_check_dhcp(w5500);
						if (tx_msg_buf.Pos)
						{
							w5500_socket_connect(w5500, SYS_SOCK_ID, 0, ip, DHCP_SERVER_PORT);
							w5500_socket_tx(w5500, SYS_SOCK_ID, tx_msg_buf.Data, tx_msg_buf.Pos);
							w5500->last_udp_send_ok = 0;
						}
						OS_DeInitBuffer(&tx_msg_buf);

						break;
					case DNS_SERVER_PORT:
						dns_run(&w5500->dns_client, &msg_buf, NULL, &i);
						llist_traversal(&w5500->dns_client.require_head, w5500_dns_check_result, w5500);
						if (!w5500->socket[SYS_SOCK_ID].tx_wait_size)
						{
							dns_run(&w5500->dns_client, NULL, &tx_msg_buf, &i);
							if (tx_msg_buf.Pos)
							{
#ifdef LUAT_USE_LWIP
								w5500_socket_connect(w5500, SYS_SOCK_ID, 0, ip_addr_get_ip4_u32(&w5500->dns_client.dns_server[i]), DNS_SERVER_PORT);
#else
								w5500_socket_connect(w5500, SYS_SOCK_ID, 0, w5500->dns_client.dns_server[i].ipv4, DNS_SERVER_PORT);
#endif
								if (!w5500_socket_tx(w5500, SYS_SOCK_ID, tx_msg_buf.Data, tx_msg_buf.Pos))
								{
									w5500->socket[SYS_SOCK_ID].tx_wait_size = 1;
								}
								OS_DeInitBuffer(&tx_msg_buf);
							}
						}

						break;
					}
					rx_buf.Pos += 8 + len;
				}
			}
		}
		OS_DeInitBuffer(&rx_buf);
		break;
	case Sn_IR_TIMEOUT:
		LLOGE("socket %d timeout", socket_id);
		if (socket_id)
		{
			w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
		}
		break;
	case Sn_IR_CON:
		LLOGD("socket %d connected", socket_id);
		w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
		break;
	case Sn_IR_DISCON:
		LLOGE("socket %d disconnect", socket_id);
		if (w5500_socket_state(w5500, socket_id) != SOCK_CLOSED)
		{
			w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_REMOTE_CLOSE, socket_id, 0, 0);
		}
		else
		{
			w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_CLOSE_OK, socket_id, 0, 0);
		}

		break;
	default:
		break;
	}
}

static void w5500_read_irq(w5500_ctrl_t *w5500)
{
	OS_EVENT socket_event;
	uint8_t temp[64];
	uint8_t socket_irqs[MAX_SOCK_NUM];
	uint8_t socket_irq, common_irq;
	Buffer_Struct tx_msg_buf = {0,0,0};
	uint32_t remote_ip;
	int i, j;
RETRY:
	w5500_xfer(w5500, W5500_COMMON_IR, 0, temp, W5500_COMMON_QTY - W5500_COMMON_IR);
	common_irq = temp[0] & 0xf0;
	socket_irq = temp[W5500_COMMON_SOCKET_IR - W5500_COMMON_IR];
	w5500->device_on = (0x04 == temp[W5500_COMMON_VERSIONR - W5500_COMMON_IR])?1:0;
	w5500_link_state(w5500, w5500->device_on?(temp[W5500_COMMON_PHY - W5500_COMMON_IR] & 0x01):0);
	memset(socket_irqs, 0, MAX_SOCK_NUM);

	if (!w5500->device_on)
	{
		luat_gpio_close(w5500->link_pin);
		luat_gpio_close(w5500->irq_pin);

		return;
	}
	if (common_irq)
	{
		if (common_irq & IR_CONFLICT)
		{
			memset(temp, 0, 4);
			w5500_xfer(w5500, W5500_COMMON_IP0, is_write, temp, 4);
			w5500->dhcp_client.state = DHCP_STATE_DECLINE;
			ip4_dhcp_run(&w5500->dhcp_client, NULL, &tx_msg_buf, &remote_ip);
			if (tx_msg_buf.Pos)
			{
				w5500_socket_connect(w5500, SYS_SOCK_ID, 0, remote_ip, DHCP_SERVER_PORT);
				w5500_socket_tx(w5500, SYS_SOCK_ID, tx_msg_buf.Data, tx_msg_buf.Pos);
				w5500->last_udp_send_ok = 0;
			}
			OS_DeInitBuffer(&tx_msg_buf);
			w5500_ip_state(w5500, 0);
		}
	}

	if (socket_irq)
	{
		for(i = 0; i < MAX_SOCK_NUM; i++)
		{
			if (socket_irq & (1 << i))
			{
				w5500_xfer(w5500, W5500_SOCKET_IR, socket_index(i)|socket_reg, &socket_irqs[i], 1);
				temp[0] = socket_irqs[i];
//				LLOGD("%d,%x",i, socket_irqs[i]);
				w5500_xfer(w5500, W5500_SOCKET_IR, socket_index(i)|socket_reg|is_write, temp, 1);
			}
		}
	}

	temp[0] = 0;
	temp[W5500_COMMON_IMR - W5500_COMMON_IR] = IR_CONFLICT|IR_UNREACH|IR_MAGIC;
	temp[W5500_COMMON_SOCKET_IR - W5500_COMMON_IR] = 0;
	w5500_xfer(w5500, W5500_COMMON_IR, is_write, temp, 1);
	if (socket_irq)
	{
		for(i = 0; i < MAX_SOCK_NUM; i++)
		{
			if (socket_irqs[i])
			{
				for (j = 4; j >= 0; j--)
				{
					if (socket_irqs[i] & (1 << j))
					{
						w5500_sys_socket_callback(w5500, i, (1 << j));
					}
				}
			}
		}
	}

	if (luat_gpio_get(w5500->irq_pin) != 1)
	{
//		LLOGD("irq not clear!");
		goto RETRY;
	}
}



static void w5500_task(void *param)
{
	w5500_ctrl_t *w5500 = (w5500_ctrl_t *)param;
	OS_EVENT event;
	int result;
	Buffer_Struct tx_msg_buf = {0,0,0};
	uint32_t remote_ip, sleep_time;
	PV_Union uPV;
	socket_data_t *p;
	w5500_init_reg(w5500);
	while(1)
	{
		if (w5500->inter_error >= 2)
		{
			LLOGD("error too much, reboot");
			w5500_init_reg(w5500);
		}
		sleep_time = 100;
		if (w5500->network_ready)
		{
			if (!w5500->dns_client.is_run && (w5500->link_pin != 0xff))
			{
				sleep_time = 0;
			}
			else
			{
				sleep_time = 1000;
			}
		}
		else if (w5500->link_ready)
		{
			sleep_time = 500;
		}
		else if (w5500->link_pin != 0xff)
		{
			sleep_time = 0;
		}
		result = platform_wait_event(w5500->task_handle, 0, &event, NULL, sleep_time);
		w5500_xfer(w5500, W5500_COMMON_MR, 0, NULL, W5500_COMMON_QTY);
		w5500->device_on = (0x04 == w5500->rx_buf[3 + W5500_COMMON_VERSIONR])?1:0;
		if (w5500->device_on && w5500->rx_buf[3 + W5500_COMMON_IMR] != (IR_CONFLICT|IR_UNREACH|IR_MAGIC))
		{
			w5500_init_reg(w5500);
		}
		if (!w5500->device_on)
		{
			w5500_link_state(w5500, 0);
			luat_gpio_close(w5500->link_pin);
			luat_gpio_close(w5500->irq_pin);
		}
		else
		{
			w5500_link_state(w5500, w5500->rx_buf[3 + W5500_COMMON_PHY] & 0x01);
			w5500->speed_status = w5500->rx_buf[3 + W5500_COMMON_PHY] & (3 << 1);
		}
		if (result)
		{
			if (w5500->network_ready)
			{
				w5500_dns_tx_next(w5500, &tx_msg_buf);
			}
			else if (w5500->link_ready)
			{
				result = ip4_dhcp_run(&w5500->dhcp_client, NULL, &tx_msg_buf, &remote_ip);
				w5500_check_dhcp(w5500);
				if (tx_msg_buf.Pos)
				{
					w5500_socket_connect(w5500, SYS_SOCK_ID, 0, remote_ip, DHCP_SERVER_PORT);
					w5500_socket_tx(w5500, SYS_SOCK_ID, tx_msg_buf.Data, tx_msg_buf.Pos);
					w5500->last_udp_send_ok = 0;
				}
				OS_DeInitBuffer(&tx_msg_buf);
			}
			continue;
		}



		switch(event.ID)
		{
		case EV_W5500_IRQ:
			if (w5500->device_on)
			{
				w5500_read_irq(w5500);
			}
			break;
		case EV_W5500_SOCKET_TX:
			if (event.Param1) W5500_LOCK;
			p = llist_traversal(&w5500->socket[event.Param1].tx_head, w5500_next_data_cache, &prv_w5500_ctrl->socket[event.Param1]);
			if (event.Param1) W5500_UNLOCK;
			if (p && p->is_sending)
			{
				LLOGD("socket %d is sending, need wait!", event.Param1);
			}
			else
			{
				w5500_socket_tx_next_data(w5500, event.Param1);
				if (!p->is_sending)
				{
					w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_ERROR, event.Param1, 0, 0);
				}
			}
			break;
		case EV_W5500_SOCKET_CONNECT:
			uPV.u8[0] = 0;
			while(w5500_socket_state(w5500, event.Param1) != SOCK_CLOSED)
			{
				w5500_socket_close(w5500, event.Param1);
				uPV.u8[0]++;
				if (uPV.u8[0] > 100)
				{
					w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_ERROR, event.Param1, 0, 0);
					break;
				}
			}
			uPV.u32 = event.Param3;
			w5500_socket_config(w5500, event.Param1, w5500->socket[event.Param1].is_tcp, uPV.u16[0]);
			w5500_socket_connect(w5500, event.Param1, 0, event.Param2, uPV.u16[1]);
			if (!w5500->socket[event.Param1].is_tcp)
			{
				w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_CONNECT_OK, event.Param1, 0, 0);
			}
			break;
		case EV_W5500_SOCKET_CLOSE:
			if ((w5500_socket_state(w5500, event.Param1) != SOCK_CLOSED))
			{
				w5500_socket_disconnect(w5500, event.Param1);
			}
			else
			{
				w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_CLOSE_OK, event.Param1, 0, 0);
			}
			break;
		case EV_W5500_SOCKET_LISTEN:
			uPV.u8[0] = 0;
			while(w5500_socket_state(w5500, event.Param1) != SOCK_CLOSED)
			{
				w5500_socket_close(w5500, event.Param1);
				uPV.u8[0]++;
				if (uPV.u8[0] > 100)
				{
					w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_ERROR, event.Param1, 0, 0);
				}
			}
			uPV.u32 = event.Param3;
			w5500_socket_config(w5500, event.Param1, w5500->socket[event.Param1].is_tcp, event.Param2);
			w5500_socket_connect(w5500, event.Param1, 1, 0xffffffff, 0xff00);
			w5500_callback_to_nw_task(w5500, EV_NW_SOCKET_LISTEN, event.Param1, 0, 0);
			break;
		case EV_W5500_SOCKET_DNS:
			if (w5500->network_ready)
			{
				dns_require(&w5500->dns_client, event.Param1, event.Param2, event.Param3);
				w5500_dns_tx_next(w5500, &tx_msg_buf);
			}
			break;
		case EV_W5500_RE_INIT:
			w5500_init_reg(w5500);
			break;
		case EV_W5500_REG_OP:
			uPV.u8[0] = event.Param3;
			w5500_xfer(w5500, event.Param1, socket_index(event.Param2)|socket_reg|is_write, uPV.u8, 1);
			break;
		case EV_W5500_LINK:
			w5500_link_state(w5500, !luat_gpio_get(w5500->link_pin));
			break;
		}
	}
}

void w5500_set_static_ip(uint32_t ipv4, uint32_t submask, uint32_t gateway)
{
	if (prv_w5500_ctrl)
	{
		prv_w5500_ctrl->static_ip = ipv4;
		prv_w5500_ctrl->static_submask = submask;
		prv_w5500_ctrl->static_gateway = gateway;
	}
}

void w5500_set_mac(uint8_t mac[6])
{
	if (prv_w5500_ctrl)
	{
		memcpy(prv_w5500_ctrl->mac, mac, 6);
	}
}

void w5500_get_mac(uint8_t mac[6])
{
	if (prv_w5500_ctrl)
	{
		memcpy(mac, prv_w5500_ctrl->mac, 6);
	}
	else
	{
		memset(mac, 0xff, 6);
	}
}

void w5500_set_param(uint16_t timeout, uint8_t retry, uint8_t auto_speed, uint8_t force_arp)
{
	if (prv_w5500_ctrl)
	{
		prv_w5500_ctrl->RTR = timeout;
		prv_w5500_ctrl->RTR = retry;
		prv_w5500_ctrl->auto_speed = auto_speed;
		prv_w5500_ctrl->force_arp = force_arp;
	}
}

int w5500_reset(void)
{
	if (prv_w5500_ctrl && prv_w5500_ctrl->device_on)
	{
		platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_RE_INIT, 0, 0, 0);
		return 0;
	}
	else
	{
		return -1;
	}
}

void w5500_init(luat_spi_t* spi, uint8_t irq_pin, uint8_t rst_pin, uint8_t link_pin)
{
	uint8_t *uid;
	size_t t, i;
	if (!prv_w5500_ctrl)
	{
		w5500_ctrl_t *w5500 = malloc(sizeof(w5500_ctrl_t));
		memset(w5500, 0, sizeof(w5500_ctrl_t));
		w5500->socket_cb = w5500_dummy_callback;
		w5500->tag = luat_mcu_tick64_ms();
		w5500->RCR = 8;
		w5500->RTR = 2000;
		w5500->spi_id = spi->id;
		w5500->cs_pin = spi->cs;
		w5500->irq_pin = irq_pin;
		w5500->rst_pin = rst_pin;
		w5500->link_pin = link_pin;
		spi->cs = 0xff;
		luat_spi_setup(spi);
		luat_gpio_t gpio = {0};
		gpio.pin = w5500->cs_pin;
		gpio.mode = Luat_GPIO_OUTPUT;
		gpio.pull = Luat_GPIO_DEFAULT;
		luat_gpio_setup(&gpio);
		luat_gpio_set(w5500->cs_pin, 1);

		gpio.pin = w5500->rst_pin;
		luat_gpio_setup(&gpio);
		luat_gpio_set(w5500->rst_pin, 0);


		char rands[4];
		luat_crypto_trng(rands, 4);

		for(i = 0; i < MAX_SOCK_NUM; i++)
		{
			INIT_LLIST_HEAD(&w5500->socket[i].tx_head);
			INIT_LLIST_HEAD(&w5500->socket[i].rx_head);
		}
		INIT_LLIST_HEAD(&w5500->dns_client.process_head);
		INIT_LLIST_HEAD(&w5500->dns_client.require_head);

		w5500->dhcp_client.xid = BytesGetBe32(rands);
		w5500->dhcp_client.state = DHCP_STATE_NOT_WORK;
#ifdef LUAT_USE_MOBILE
		uint8_t imei[16];
		luat_mobile_get_imei(0, imei, 16);
		for(i = 0; i < 6; i++)
		{
			w5500->mac[i] = AsciiToU32(imei + i*2 + 2, 2);
		}
#else
		uid = luat_mcu_unique_id(&t);
		memcpy(w5500->mac, &uid[10], 6);
#endif
		w5500->mac[0] &= 0xfe;
		platform_create_task(&w5500->task_handle, 4 * 1024, 30, "w5500", w5500_task, w5500, 64);
		prv_w5500_ctrl = w5500;

		prv_w5500_ctrl->device_on = 1;
		prv_w5500_ctrl->Sem = luat_mutex_create();
	}
}

uint8_t w5500_device_ready(void)
{
	if (prv_w5500_ctrl)
	{
		return prv_w5500_ctrl->device_on;
	}
	else
	{
		return 0;
	}
}

static int w5500_check_socket(w5500_ctrl_t *w5500, int socket_id, uint64_t tag)
{
	if (w5500 != prv_w5500_ctrl) return -1;
	if (socket_id < 1 || socket_id >= MAX_SOCK_NUM) return -1;
	if (w5500->socket[socket_id].tag != tag) return -1;
	if (!w5500->socket[socket_id].in_use) return -1;
	return 0;
}

static int w5500_socket_check(int socket_id, uint64_t tag, void *user_data)
{
	return w5500_check_socket(user_data, socket_id, tag);
}


static uint8_t w5500_check_ready(void *user_data)
{
	return ((w5500_ctrl_t *)user_data)->network_ready;
}

static int w5500_create_soceket(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
	int i, socket_id;
	socket_id = -1;
	W5500_LOCK;
	if (!prv_w5500_ctrl->socket[prv_w5500_ctrl->next_socket_index].in_use)
	{
		socket_id = prv_w5500_ctrl->next_socket_index;
		prv_w5500_ctrl->next_socket_index++;
	}
	else
	{
		for (i = 1; i < MAX_SOCK_NUM; i++)
		{
			if (!prv_w5500_ctrl->socket[i].in_use)
			{
				socket_id = i;
				prv_w5500_ctrl->next_socket_index = i + 1;
				break;
			}
		}
	}
	if (prv_w5500_ctrl->next_socket_index >= MAX_SOCK_NUM)
	{
		prv_w5500_ctrl->next_socket_index = 1;
	}
	if (socket_id > 0)
	{
		prv_w5500_ctrl->tag++;
		*tag = prv_w5500_ctrl->tag;

		prv_w5500_ctrl->socket[socket_id].in_use = 1;
		prv_w5500_ctrl->socket[socket_id].tag = *tag;
		prv_w5500_ctrl->socket[socket_id].rx_wait_size = 0;
		prv_w5500_ctrl->socket[socket_id].tx_wait_size = 0;
		prv_w5500_ctrl->socket[socket_id].param = param;
		prv_w5500_ctrl->socket[socket_id].is_tcp = is_tcp;
		prv_w5500_ctrl->socket[socket_id].rx_waiting = 0;
		llist_traversal(&prv_w5500_ctrl->socket[socket_id].tx_head, w5500_del_data_cache, NULL);
		llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_del_data_cache, NULL);
	}
	W5500_UNLOCK;
	return socket_id;
}

//作为client绑定一个port，并连接remote_ip和remote_port对应的server
static int w5500_socket_connect_ex(int socket_id, uint64_t tag,  uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	PV_Union uPV;
	uPV.u16[0] = local_port;
	uPV.u16[1] = remote_port;
	W5500_LOCK;
	llist_traversal(&prv_w5500_ctrl->socket[socket_id].tx_head, w5500_del_data_cache, NULL);
	llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_del_data_cache, NULL);
	W5500_UNLOCK;
#ifdef LUAT_USE_LWIP
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_CONNECT, socket_id, ip_addr_get_ip4_u32(remote_ip), uPV.u32);
	uPV.u32 = ip_addr_get_ip4_u32(remote_ip);
#else
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_CONNECT, socket_id, remote_ip->ipv4, uPV.u32);
	uPV.u32 = remote_ip->ipv4;
#endif
//	LLOGD("%u.%u.%u.%u", uPV.u8[0], uPV.u8[1], uPV.u8[2], uPV.u8[3]);
	return 0;
}
//作为server绑定一个port，开始监听
static int w5500_socket_listen(int socket_id, uint64_t tag,  uint16_t local_port, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_LISTEN, socket_id, local_port, NULL);
	return 0;
}
//作为server接受一个client
static int w5500_socket_accept(int socket_id, uint64_t tag,  luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	uint8_t temp[16];
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	w5500_xfer(user_data, W5500_SOCKET_DEST_IP0, socket_index(socket_id)|socket_reg, temp, 6);
#ifdef LUAT_USE_LWIP
	network_set_ip_ipv4(remote_ip, BytesGetLe32(temp));
#else
	remote_ip->is_ipv6 = 0;
	remote_ip->ipv4 = BytesGetLe32(temp);
#endif
	*remote_port = BytesGetBe16(temp + 4);
	LLOGD("client %d.%d.%d.%d, %u", temp[0], temp[1], temp[2], temp[3], *remote_port);
	return 0;
}
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
static int w5500_socket_disconnect_ex(int socket_id, uint64_t tag,  void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_CLOSE, socket_id, 0, 0);
	return 0;
}

static int w5500_socket_force_close(int socket_id, void *user_data)
{
	W5500_LOCK;
	w5500_socket_close(prv_w5500_ctrl, socket_id);
	if (prv_w5500_ctrl->socket[socket_id].in_use)
	{
		prv_w5500_ctrl->socket[socket_id].in_use = 0;
		prv_w5500_ctrl->socket[socket_id].tag = 0;
		llist_traversal(&prv_w5500_ctrl->socket[socket_id].tx_head, w5500_del_data_cache, NULL);
		llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_del_data_cache, NULL);
		prv_w5500_ctrl->socket[socket_id].rx_wait_size = 0;
		prv_w5500_ctrl->socket[socket_id].tx_wait_size = 0;
		prv_w5500_ctrl->socket[socket_id].param = NULL;
	}
	W5500_UNLOCK;
	return 0;
}

static int w5500_socket_close_ex(int socket_id, uint64_t tag,  void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	return w5500_socket_force_close(socket_id, user_data);

}

static uint32_t w5500_socket_read_data(uint8_t *buf, uint32_t *read_len, uint32_t len, socket_data_t *p)
{
	uint32_t dummy_len;
	dummy_len = ((p->len - p->read_pos) > (len - *read_len))?(len - *read_len):(p->len - p->read_pos);
	memcpy(buf, p->data + p->read_pos, dummy_len);
	p->read_pos += dummy_len;
	if (p->read_pos >= p->len)
	{
		llist_del(&p->node);
		free(p->data);
		free(p);
	}
	*read_len += dummy_len;
	return dummy_len;
}

static int w5500_socket_receive(int socket_id, uint64_t tag,  uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	W5500_LOCK;
	uint32_t read_len = 0;
	if (buf)
	{
		socket_data_t *p = (socket_data_t *)llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_next_data_cache, &prv_w5500_ctrl->socket[socket_id]);

		if (prv_w5500_ctrl->socket[socket_id].is_tcp)
		{
			while((read_len < len) && p)
			{
				prv_w5500_ctrl->socket[socket_id].rx_wait_size -= w5500_socket_read_data(buf + read_len, &read_len, len, p);
				p = (socket_data_t *)llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_next_data_cache, &prv_w5500_ctrl->socket[socket_id]);
			}
		}
		else
		{
			prv_w5500_ctrl->socket[socket_id].rx_wait_size -= w5500_socket_read_data(buf + read_len, &read_len, len, p);
			*remote_ip = p->ip;
			*remote_port = p->port;
		}
		if (llist_empty(&prv_w5500_ctrl->socket[socket_id].rx_head))
		{
			prv_w5500_ctrl->socket[socket_id].rx_wait_size = 0;
		}
	}
	else
	{
		read_len = prv_w5500_ctrl->socket[socket_id].rx_wait_size;
	}
	W5500_UNLOCK;
	if ((prv_w5500_ctrl->socket[socket_id].rx_wait_size < SOCK_BUF_LEN) && prv_w5500_ctrl->socket[socket_id].rx_waiting)
	{
		prv_w5500_ctrl->socket[socket_id].rx_waiting = 0;
		LLOGD("read waiting data");
		w5500_sys_socket_callback(prv_w5500_ctrl, socket_id, Sn_IR_RECV);
	}
	return read_len;
}
static int w5500_socket_send(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	if (prv_w5500_ctrl->socket[socket_id].tx_wait_size >= SOCK_BUF_LEN) return 0;

	socket_data_t *p = w5500_create_data_node(prv_w5500_ctrl, socket_id, buf, len, remote_ip, remote_port);
	if (p)
	{
		W5500_LOCK;
		llist_add_tail(&p->node, &prv_w5500_ctrl->socket[socket_id].tx_head);
		prv_w5500_ctrl->socket[socket_id].tx_wait_size += len;
		W5500_UNLOCK;
		platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_TX, socket_id, 0, 0);
		result = len;
	}
	else
	{
		result = -1;
	}
	return result;
}

void w5500_socket_clean(int *vaild_socket_list, uint32_t num, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return;
	int socket_list[MAX_SOCK_NUM] = {0,0,0,0,0,0,0,0};
	uint32_t i;
	for(i = 1; i < num + 1; i++)
	{
		if ( (vaild_socket_list[i] > 0) && (vaild_socket_list[i] < MAX_SOCK_NUM) )
		{
			socket_list[vaild_socket_list[i]] = 1;
		}
		LLOGD("socket clean check %d,%d",i,vaild_socket_list[i]);
	}
	for(i = 1; i < MAX_SOCK_NUM; i++)
	{
		LLOGD("socket clean %d,%d",i,socket_list[i]);
		if ( !socket_list[i] )
		{
			W5500_LOCK;
			prv_w5500_ctrl->socket[i].in_use = 0;
			prv_w5500_ctrl->socket[i].tag = 0;
			llist_traversal(&prv_w5500_ctrl->socket[i].tx_head, w5500_del_data_cache, NULL);
			llist_traversal(&prv_w5500_ctrl->socket[i].rx_head, w5500_del_data_cache, NULL);
			prv_w5500_ctrl->socket[i].rx_wait_size = 0;
			prv_w5500_ctrl->socket[i].tx_wait_size = 0;
			w5500_socket_close(prv_w5500_ctrl, i);
			W5500_UNLOCK;
		}
	}
}

static int w5500_getsockopt(int socket_id, uint64_t tag,  int level, int optname, void *optval, uint32_t *optlen, void *user_data)
{
	return -1;
}
static int w5500_setsockopt(int socket_id, uint64_t tag,  int level, int optname, const void *optval, uint32_t optlen, void *user_data)
{
	return -1;
}
static int w5500_get_local_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;

	if (prv_w5500_ctrl->static_ip)
	{
#ifdef LUAT_USE_LWIP
		network_set_ip_ipv4(ip, prv_w5500_ctrl->static_ip);
		network_set_ip_ipv4(submask, prv_w5500_ctrl->static_submask);
		network_set_ip_ipv4(gateway, prv_w5500_ctrl->static_gateway);
#else
		ip->ipv4 = prv_w5500_ctrl->static_ip;
		ip->is_ipv6 = 0;
		submask->ipv4 = prv_w5500_ctrl->static_submask;
		submask->is_ipv6 = 0;
		gateway->ipv4 = prv_w5500_ctrl->static_gateway;
		gateway->is_ipv6 = 0;
#endif
		return 0;
	}
	else
	{
		if (!prv_w5500_ctrl->ip_ready)
		{
			return -1;
		}
#ifdef LUAT_USE_LWIP
		network_set_ip_ipv4(ip, prv_w5500_ctrl->dhcp_client.ip);
		network_set_ip_ipv4(submask, prv_w5500_ctrl->dhcp_client.submask);
		network_set_ip_ipv4(gateway, prv_w5500_ctrl->dhcp_client.gateway);
#else
		ip->ipv4 = prv_w5500_ctrl->dhcp_client.ip;
		ip->is_ipv6 = 0;
		submask->ipv4 = prv_w5500_ctrl->dhcp_client.submask;
		submask->is_ipv6 = 0;
		gateway->ipv4 = prv_w5500_ctrl->dhcp_client.gateway;
		gateway->is_ipv6 = 0;
#endif
		return 0;
	}
}

static int w5500_user_cmd(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	switch (cmd)
	{
	case NW_CMD_AUTO_HEART_TIME:
		value = (value + 4) / 5;
		platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_REG_OP, W5500_SOCKET_KEEP_TIME, socket_id, value);
		break;
	default:
		return -1;
	}
	return 0;
}

static int w5500_dns(const char *domain_name, uint32_t len, void *param, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
	char *prv_domain_name = (char *)malloc(len);
	memcpy(prv_domain_name, domain_name, len);
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_DNS, prv_domain_name, len, param);
	return 0;
}

static int w5500_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
	if (server_index >= MAX_DNS_SERVER) return -1;
	prv_w5500_ctrl->dns_client.dns_server[server_index] = *ip;
	prv_w5500_ctrl->dns_client.is_static_dns[server_index] = 1;
	return 0;
}

static void w5500_socket_set_callback(CBFuncEx_t cb_fun, void *param, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return ;
	((w5500_ctrl_t *)user_data)->socket_cb = cb_fun?cb_fun:w5500_dummy_callback;
	((w5500_ctrl_t *)user_data)->user_data = param;
}

static int w5500_set_mac_lwip(uint8_t *mac, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
	w5500_set_mac(mac);
	return 0;
}
static int w5500_set_static_ip_lwip(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
	w5500_set_static_ip(ip, submask, gateway);
	return 0;
}
static int w5500_get_full_ip_info_lwip(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
#ifdef LUAT_USE_LWIP
	network_set_ip_invaild(ipv6);
#else
	ipv6->is_ipv6 = 0xff;
#endif
	return w5500_get_local_ip_info(ip, submask, gateway, user_data);
}

static network_adapter_info prv_w5500_adapter =
{
		.check_ready = w5500_check_ready,
		.create_soceket = w5500_create_soceket,
		.socket_connect = w5500_socket_connect_ex,
		.socket_listen = w5500_socket_listen,
		.socket_accept = w5500_socket_accept,
		.socket_disconnect = w5500_socket_disconnect_ex,
		.socket_close = w5500_socket_close_ex,
		.socket_force_close = w5500_socket_force_close,
		.socket_receive = w5500_socket_receive,
		.socket_send = w5500_socket_send,
		.socket_check = w5500_socket_check,
		.socket_clean = w5500_socket_clean,
		.getsockopt = w5500_getsockopt,
		.setsockopt = w5500_setsockopt,
		.user_cmd = w5500_user_cmd,
		.dns = w5500_dns,
		.dns_ipv6 = w5500_dns,
		.set_dns_server = w5500_set_dns_server,
		.set_mac = w5500_set_mac_lwip,
		.set_static_ip = w5500_set_static_ip_lwip,
		.get_full_ip_info = w5500_get_full_ip_info_lwip,
		.get_local_ip_info = w5500_get_local_ip_info,
		.socket_set_callback = w5500_socket_set_callback,
		.name = "w5500",
		.max_socket_num = MAX_SOCK_NUM - 1,
		.no_accept = 1,
		.is_posix = 0,
};

void w5500_register_adapter(int index)
{
	if (prv_w5500_ctrl)
	{
		prv_w5500_ctrl->self_index = index;
		network_register_adapter(index, &prv_w5500_adapter, prv_w5500_ctrl);
	}
}
#endif

