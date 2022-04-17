#include "luat_base.h"
#ifdef LUAT_USE_W5500
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "luat_network_adapter.h"
#include "bsp_common.h"
#include "w5500_def.h"
#include "dhcp_def.h"
#include "dns_def.h"
extern void DBG_Printf(const char* format, ...);
extern void DBG_HexPrintf(void *Data, unsigned int len);
#define DBG(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
#define DBG_ERR(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)

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
	EV_W5500_SOCKET_CONFIG,
	EV_W5500_SOCKET_LISTEN,
	EV_W5500_SOCKET_ACCEPT,
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
	dhcp_client_info_t dhcp_client;
	uint64_t last_tx_time;
	CBFuncEx_t socket_cb;
	void *user_data;
	void *task_handle;
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
	uint8_t socket_state[MAX_SOCK_NUM];
	uint8_t mac[6];
}w5500_ctrl_t;

static w5500_ctrl_t *prv_w5500_ctrl;

static void w5500_ip_state(w5500_ctrl_t *w5500, uint8_t check_state);
static void w5500_check_dhcp(w5500_ctrl_t *w5500);
static void w5500_init_reg(w5500_ctrl_t *w5500);

static int32_t w5500_irq(int pin, void *args)
{
	w5500_ctrl_t *w5500 = (w5500_ctrl_t *)args;
	if ((pin & 0x00ff) == w5500->irq_pin)
	{
		luat_send_event_to_task(w5500->task_handle, EV_W5500_IRQ, 0, 0, 0);
	}
	if ((pin & 0x00ff) == w5500->link_pin)
	{
		luat_send_event_to_task(w5500->task_handle, EV_W5500_LINK, 0, 0, 0);
	}
}

static void w5500_callback_to_nw_task(w5500_ctrl_t *w5500, uint32_t event, uint32_t param1, uint32_t param2, uint32_t param3)
{

}

static void w5500_xfer(w5500_ctrl_t *w5500, uint16_t address, uint8_t ctrl, uint8_t *data, uint32_t len)
{
	BytesPutBe16(w5500->rx_buf, address);
	w5500->rx_buf[2] = ctrl;
	if (data && len)
	{
		memcpy(w5500->rx_buf + 3, data, len);
	}
	luat_gpio_set(w5500->cs_pin, 0);
	luat_spi_transfer(w5500->spi_id, w5500->rx_buf, len + 3, w5500->rx_buf, len + 3);
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
		DBG_ERR("check too much times, error %d", w5500->inter_error);

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
		w5500->socket_state[socket_id] = W5500_SOCKET_OFFLINE;
		DBG("socket %d already closed");
		return;
	}
	if ((temp >= SOCK_FIN_WAIT) && (temp <= SOCK_LAST_ACK))
	{
		w5500->socket_state[socket_id] = W5500_SOCKET_CLOSING;
		DBG("socket %d is closing");
		return;

	}
	temp = Sn_CR_DISCON;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, &temp, 1);
	w5500->socket_state[socket_id] = W5500_SOCKET_CLOSING;
}

static void w5500_socket_close(w5500_ctrl_t *w5500, uint8_t socket_id)
{
	uint8_t temp;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return;

	if (SOCK_CLOSED == temp)
	{
		w5500->socket_state[socket_id] = W5500_SOCKET_OFFLINE;
		DBG("socket %d already closed");
		return;
	}
	temp = Sn_CR_CLOSE;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, &temp, 1);
	w5500->socket_state[socket_id] = W5500_SOCKET_OFFLINE;
}

static int w5500_socket_config(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t is_tcp, uint16_t local_port)
{
	uint8_t delay_cnt;
	uint8_t temp;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if (SOCK_CLOSED != temp)
	{
		DBG_ERR("socket %d not closed state %x", socket_id, temp);
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
		BytesPutBe16(&cmd[W5500_SOCKET_DEST_PORT0], 67);
		BytesPutBe16(&cmd[W5500_SOCKET_SEGMENT0], is_tcp?1460:1472);
		w5500_xfer(w5500, W5500_SOCKET_MR, socket_index(socket_id)|socket_reg|is_write, cmd, W5500_SOCKET_TOS - 1);
		w5500_xfer(w5500, W5500_SOCKET_MR, socket_index(socket_id)|socket_reg, cmd, W5500_SOCKET_TOS - 1);
		wtemp = BytesGetBe16(&cmd[W5500_SOCKET_SOURCE_PORT0]);
		if (wtemp != local_port)
		{
			DBG_ERR("error port %u %u", wtemp, local_port);
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
		DBG_ERR("socket %d config timeout, error %d", socket_id, w5500->inter_error);
		return -1;
	}

	w5500->socket_state[socket_id] = is_tcp?W5500_SOCKET_CONFIG:W5500_SOCKET_ONLINE;
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
		DBG("socket %d not config state %x", socket_id, temp);
		return -1;
	}
//	DBG("%08x, %u", remote_ip, remote_port);
	if (!is_listen)
	{
		w5500_xfer(w5500, W5500_SOCKET_DEST_IP0, socket_index(socket_id)|socket_reg, cmd, 6);
		ip = BytesGetLe32(cmd);
		port = BytesGetBe16(cmd + 4);
		if (ip != remote_ip || port != remote_port)
		{
			BytesPutLe32(cmd, remote_ip);
			BytesPutBe16(&cmd[W5500_SOCKET_DEST_PORT0 - W5500_SOCKET_DEST_IP0], remote_port);
			w5500_xfer(w5500, W5500_SOCKET_DEST_IP0, socket_index(socket_id)|socket_reg|is_write, cmd, 6);
//			if (temp == SOCK_UDP)
//			{
//				cmd[0] = Sn_CR_SEND;
//				w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, cmd, 1);
//			}
		}

	}
W5500_SOCKET_CONNECT_START:
	if (temp != SOCK_UDP)
	{

		uint8_t temp = is_listen?Sn_CR_LISTEN:Sn_CR_CONNECT;
		w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, &temp, 1);
		w5500->socket_state[socket_id] = W5500_SOCKET_CONNECT;
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

static int w5500_socket_tx(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t *data, uint16_t len)
{
	uint8_t delay_cnt;
	uint8_t temp;
	uint8_t point[6];
	uint16_t tx_free, tx_point;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if ((temp != SOCK_ESTABLISHED) && (temp != SOCK_UDP))
	{
		DBG("socket %d not online state %x", socket_id, temp);
		return -1;
	}
	w5500->socket_state[socket_id] = W5500_SOCKET_ONLINE;
	if (!data || !len)
	{
		point[0] = Sn_CR_SEND_KEEP;
		w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, point, 1);
	}

	w5500_xfer(w5500, W5500_SOCKET_TX_FREE_SIZE0, socket_index(socket_id)|socket_reg, point, 6);
	tx_free = BytesGetBe16(point);
	tx_point = BytesGetBe16(point + 4);
	if (len > tx_free)
	{
		len = tx_free;
	}
	DBG("%d,0x%04x,%u", socket_id, tx_point, len);
	w5500->last_tx_time = GetSysTickMS();
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
	if ((temp != SOCK_ESTABLISHED) && (temp != SOCK_UDP))
	{
		DBG("socket %d not config state %x", socket_id, temp);
		return -1;
	}
	w5500->socket_state[socket_id] = W5500_SOCKET_ONLINE;
	w5500_xfer(w5500, W5500_SOCKET_RX_SIZE0, socket_index(socket_id)|socket_reg, point, 4);

	rx_size = BytesGetBe16(point);
	rx_point = BytesGetBe16(point + 2);
	DBG("%d,0x%04x,%u", socket_id, rx_point, rx_size);
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

static void w5500_nw_state(w5500_ctrl_t *w5500)
{
	if (w5500->link_ready && w5500->ip_ready)
	{
		if (!w5500->network_ready)
		{
			w5500->network_ready = 1;
			w5500_callback_to_nw_task(w5500, 0, 0, 0, 0);
			DBG("network ready");
		}
	}
	else
	{
		if (w5500->network_ready)
		{
			w5500->network_ready = 0;
			w5500_callback_to_nw_task(w5500, 0, 0, 0, 0);
			DBG("network not ready");
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
		w5500_ip_state(w5500, 1);
		uIP.u32 = w5500->dhcp_client.ip;
		DBG("动态IP:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		uIP.u32 = w5500->dhcp_client.submask;
		DBG("子网掩码:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		uIP.u32 = w5500->dhcp_client.gateway;
		DBG("网关:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		DBG("租约时间:%u秒", w5500->dhcp_client.lease_time);
	}
	if ((!w5500->last_udp_send_ok && w5500->dhcp_client.discover_cnt >= 1) || (w5500->last_udp_send_ok && w5500->dhcp_client.discover_cnt >= 3))
	{
		DBG("dhcp long time not get ip, reboot w5500");
		memset(&w5500->dhcp_client, 0, sizeof(w5500->dhcp_client));
		luat_send_event_to_task(w5500->task_handle, EV_W5500_RE_INIT, 0, 0, 0);
	}


}

static void w5500_link_state(w5500_ctrl_t *w5500, uint8_t check_state)
{
	Buffer_Struct tx_msg_buf = {0,0,0};
	uint32_t remote_ip;
	int result;
	if (w5500->link_ready != check_state)
	{
		DBG("link %d -> %d", w5500->link_ready, check_state);
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
			if (GetSysTickMS() < (w5500->last_tx_time + 1500))
			{
				w5500->inter_error++;
				DBG_ERR("link down too fast, error %u", w5500->inter_error);
			}
		}


		w5500_nw_state(w5500);
	}
}

static void w5500_ip_state(w5500_ctrl_t *w5500, uint8_t check_state)
{
	if (w5500->ip_ready != check_state)
	{
		DBG("ip %d -> %d", w5500->ip_ready, check_state);
		w5500->ip_ready = check_state;
		w5500_nw_state(w5500);
	}
}

static void w5500_init_reg(w5500_ctrl_t *w5500)
{
	uint8_t temp[64];
	luat_gpio_set(w5500->rst_pin, 0);
	luat_timer_mdelay(5);
	luat_gpio_set(w5500->rst_pin, 1);
	luat_timer_mdelay(10);
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
	w5500_callback_to_nw_task(w5500, 0, 0, 0, 0);

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


	BytesPutBe16(&temp[W5500_COMMON_SOCKET_RTR0], w5500->RTR);
	temp[W5500_COMMON_IMR] = IR_CONFLICT|IR_UNREACH|IR_MAGIC;
	temp[W5500_COMMON_SOCKET_IMR] = 0xff;
	temp[W5500_COMMON_SOCKET_RCR] = w5500->RCR;
//	DBG_HexPrintf(temp, W5500_COMMON_QTY);
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

	memset(w5500->socket_state, W5500_SOCKET_OFFLINE, MAX_SOCK_NUM);
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
}

static int32_t w5500_dummy_callback(void *pData, void *pParam)
{
	OS_EVENT *socket_event = (OS_EVENT *)pData;
	switch(socket_event->ID)
	{
	case NW_EVENT_RECV:
		break;
	case NW_EVENT_CONNECTED:
		break;
	case NW_EVENT_REMOTE_CLOSE:
		break;
	case NW_EVENT_ERR:
		break;
	default:
		break;
	}
}

static void w5500_sys_socket_callback(w5500_ctrl_t *w5500, uint8_t event)
{
	Buffer_Struct rx_buf;
	Buffer_Struct msg_buf;
	Buffer_Struct tx_msg_buf = {0,0,0};
	int result, i;
	uint32_t ip;
	uint16_t port;
	uint16_t len;
	switch(event)
	{
	case Sn_IR_SEND_OK:
		w5500->last_udp_send_ok = 1;
		break;
	case Sn_IR_RECV:
		OS_InitBuffer(&rx_buf, 2048);
		result = w5500_socket_rx(w5500, SYS_SOCK_ID, rx_buf.Data, rx_buf.MaxLen);
		if (result > 0)
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
					ip4_dhcp_run(w5500, &msg_buf, &tx_msg_buf, &ip);
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
					break;
				}
				rx_buf.Pos += 8 + len;
			}
		}

		break;
	case Sn_IR_TIMEOUT:
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
	int i;
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

		if (socket_irqs[0])
		{
			for(i = 0; i < 5; i++)
			{
				if (socket_irqs[0] & (1 << i))
				{
					w5500_sys_socket_callback(w5500, (1 << i));
				}
			}
		}
		for(i = 1; i < MAX_SOCK_NUM; i++)
		{
			if (socket_irqs[i])
			{
				DBG("%d,0x%x", i, socket_irqs[i]);
			}
		}

	}

}



static void w5500_task(void *param)
{
	w5500_ctrl_t *w5500 = (w5500_ctrl_t *)param;
	OS_EVENT event;
	int result;
	Buffer_Struct tx_msg_buf = {0,0,0};
	uint32_t remote_ip, sleep_time;
	w5500_init_reg(w5500);
	while(1)
	{
		if (w5500->inter_error >= 2)
		{
			DBG("w5500 error too much, reboot");
			w5500_init_reg(w5500);
		}
		sleep_time = 100;
		if (w5500->network_ready)
		{
			sleep_time = 1000;
		}
		else if (w5500->link_ready)
		{
			sleep_time = 500;
		}
		else if (w5500->link_pin != 0xff)
		{
			sleep_time = 0;
		}
		result = luat_wait_event_from_task(w5500->task_handle, 0, &event, NULL, sleep_time);

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

		if (result && w5500->link_ready)
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
			break;
		case EV_W5500_SOCKET_CONNECT:
			break;
		case EV_W5500_SOCKET_CLOSE:
			break;
		case EV_W5500_SOCKET_CONFIG:
			break;
		case EV_W5500_SOCKET_LISTEN:
			break;
		case EV_W5500_SOCKET_ACCEPT:
			break;
		case EV_W5500_SOCKET_DNS:
			break;
		case EV_W5500_RE_INIT:
			w5500_init_reg(w5500);
			break;
		case EV_W5500_REG_OP:
			break;
		case EV_W5500_LINK:
			w5500_link_state(w5500, !luat_gpio_get(w5500->link_pin));
			break;
		}
	}
}

uint32_t w5500_string_to_ip(const char *string, uint32_t len)
{
	int i;
	int8_t Buf[4][4];
	CmdParam CP;
	PV_Union uIP;
	char temp[32];
	memset(Buf, 0, sizeof(Buf));
	CP.param_max_len = 4;
	CP.param_max_num = 4;
	CP.param_num = 0;
	CP.param_str = (int8_t *)Buf;
	memcpy(temp, string, len);
	temp[len] = 0;
	CmdParseParam(temp, &CP, '.');
	for(i = 0; i < 4; i++)
	{
		uIP.u8[i] = strtol(Buf[i], NULL, 10);
	}
//	DBG("%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
	return uIP.u32;
}

int w5500_set_static_ip(uint32_t ipv4, uint32_t submask, uint32_t gateway)
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

int w5500_request(uint32_t cmd, uint32_t param1, uint32_t param2, uint32_t param3)
{
	if (prv_w5500_ctrl && prv_w5500_ctrl->device_on)
	{
		luat_send_event_to_task(prv_w5500_ctrl->task_handle, cmd + EV_W5500_SOCKET_TX, param1, param2, param3);
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
	size_t t;
	if (!prv_w5500_ctrl)
	{
		w5500_ctrl_t *w5500 = luat_heap_malloc(sizeof(w5500_ctrl_t));
		memset(w5500, 0, sizeof(w5500_ctrl_t));
		w5500->socket_cb = w5500_dummy_callback;
		w5500->RCR = 8;
		w5500->RTR = 2000;
		w5500->spi_id = spi->id;
		w5500->cs_pin = spi->cs;
		w5500->irq_pin = irq_pin;
		w5500->rst_pin = rst_pin;
		w5500->link_pin = link_pin;
		spi->cs = 0xff;
		luat_spi_setup(spi);
		luat_spi_config_dma(w5500->spi_id, 0xffff, 0xffff);
		luat_gpio_t gpio = {0};
		gpio.pin = w5500->cs_pin;
		gpio.mode = Luat_GPIO_OUTPUT;
		gpio.pull = Luat_GPIO_DEFAULT;
		luat_gpio_setup(&gpio);
		luat_gpio_set(w5500->cs_pin, 1);

		gpio.pin = w5500->rst_pin;
		luat_gpio_setup(&gpio);
		luat_gpio_set(w5500->rst_pin, 0);


		char rands[16];
		luat_crypto_trng(rands, 16);

		w5500->dhcp_client.xid = BytesGetBe32(rands);
		w5500->dhcp_client.state = DHCP_STATE_NOT_WORK;
		uid = luat_mcu_unique_id(&t);
		memcpy(w5500->mac, &uid[10], 6);
		luat_thread_t thread;
		thread.task_fun = w5500_task;
		thread.name = "w5500";
		thread.stack_size = 2 * 1024;
		thread.priority = 3;
		thread.userdata = w5500;
		luat_thread_start(&thread);
		prv_w5500_ctrl = w5500;
		w5500->task_handle = thread.handle;
		prv_w5500_ctrl->device_on = 1;
	}
}

uint8_t w5500_ready(void)
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
//创建一个socket，func作为socket工作时相关event的回调函数，并设置成非阻塞模式，user_data传入对应适配器
static int w5500_create_soceket(uint8_t is_tcp, uint32_t param, uint8_t is_ipv6, void *user_data)
{
	return -1;
}
//检查这个socket是否正常可以用
static int w5500_check_socket_vaild(int socket_id, void *user_data)
{
	return -1;
}
//作为client绑定一个port，并连接remote_ip和remote_port对应的server
static int w5500_socket_connect_ex(int socket_id, uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	return -1;
}
//作为server绑定一个port，开始监听
static int w5500_socket_listen(int socket_id, uint16_t local_port, void *user_data)
{
	return -1;
}
//作为server接受一个client
static int w5500_socket_accept(int socket_id, luat_ip_addr_t *remote_ip, void *user_data)
{
	return -1;
}
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
static int w5500_socket_disconnect_ex(int socket_id, void *user_data)
{
	return -1;
}
static int w5500_socket_receive(int socket_id, uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	return -1;
}
static int w5500_socket_send(int socket_id, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	return -1;
}
static int w5500_getsockopt(int s, int level, int optname, void *optval, uint32_t *optlen, void *user_data)
{
	return -1;
}
static int w5500_setsockopt(int s, int level, int optname, const void *optval, uint32_t optlen, void *user_data)
{
	return -1;
}
static int w5500_dns(const char *url, void *user_data)
{
	return -1;
}
static int w5500_set_dns_server(int id, luat_ip_addr_t *ip, void *user_data)
{
	return -1;
}
static int w5500_socket_set_callback(CBFuncEx_t cb_fun, void *user_data)
{
	w5500_ctrl_t *w5500 = (w5500_ctrl_t *)user_data;
	w5500->socket_cb = cb_fun;
}

static network_adapter_info prv_w5500_adapter =
{
		.create_soceket = w5500_create_soceket,
		.check_socket_vaild = w5500_check_socket_vaild,
		.socket_connect = w5500_socket_connect_ex,
		.socket_listen = w5500_socket_listen,
		.socket_accept = w5500_socket_accept,
		.socket_disconnect = w5500_socket_disconnect_ex,
		.socket_receive = w5500_socket_receive,
		.socket_send = w5500_socket_send,
		.setsockopt = w5500_getsockopt,
		.setsockopt = w5500_getsockopt,
		.dns = w5500_dns,
		.set_dns_server = w5500_set_dns_server,
		.socket_set_callback = w5500_socket_set_callback,
		.name = "w5500",
		.socket_num = MAX_SOCK_NUM - 1,
		.no_accept = 1,
		.auto_tcp_heart = 1,
};

void w5500_register_adapter(int index)
{
	if (prv_w5500_ctrl)
	{
		network_register_adapter(index, &prv_w5500_adapter, prv_w5500_ctrl);
	}
}
#else
void w5500_init(luat_spi_t* spi, uint8_t irq_pin, uint8_t rst_pin) {;}
void w5500_set_static_ip(uint32_t ipv4, uint32_t submask, uint32_t gateway) {;}
void w5500_set_mac(uint8_t mac[6])  {;}
void w5500_set_param(uint16_t timeout, uint8_t retry, uint8_t auto_speed, uint8_t force_arp) {;}
int w5500_request(uint32_t cmd, uint32_t param1, uint32_t param2, uint32_t param3) {return -1;}
uint32_t w5500_string_to_ip(const char *string, uint32_t len) {return 0}
void w5500_array_to_mac(uint8_t *array, uint32_t *mac1, uint16_t *mac2) {return;}
uint8_t w5500_ready(void) {return 0;}
void w5500_register_adapter(int index) {;}
#endif
