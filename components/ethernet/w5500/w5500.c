#include "luat_base.h"
#ifdef LUAT_USE_W5500
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "bsp_common.h"
#include "w5500_def.h"
#include "dhcp_def.h"
#include "dns_def.h"
extern void DBG_Printf(const char* format, ...);
extern void DBG_HexPrintf(void *Data, unsigned int len);
#define DBG(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)

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
	EV_W5500_SOCKET_TX,
	EV_W5500_SOCKET_CONNECT,
	EV_W5500_SOCKET_CLOSE,
	EV_W5500_SOCKET_CONFIG,
	EV_W5500_SOCKET_LISTEN,
	EV_W5500_SOCKET_ACCEPT,
	EV_W5500_SOCKET_DNS,
	EV_W5500_SET_IP,
	EV_W5500_SET_MAC,
	EV_W5500_SET_TO_PARAM,
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
	CBFuncEx_t socket_cb;
	void *user_data;
	void *task_handle;
	void *period_timer;
	void *dhcp_timer;
	uint32_t static_ip; //大端格式存放
	uint32_t static_submask; //大端格式存放
	uint32_t static_gateway; //大端格式存放
	uint32_t mac1;
	uint16_t mac2;
	uint16_t RTR;
	uint8_t RCR;
	uint8_t spi_id;
	uint8_t cs_pin;
	uint8_t rst_pin;
	uint8_t irq_pin;
	uint8_t link_pin;
	uint8_t link_ready;
	uint8_t ip_ready;
	uint8_t network_ready;
	uint8_t inter_error;
	uint8_t device_on;
	uint8_t socket_irq[MAX_SOCK_NUM];
	uint8_t data_buf[2048 + 8];
	uint8_t socket_state[MAX_SOCK_NUM];
}w5500_ctrl_t;

static w5500_ctrl_t *prv_w5500_ctrl;

static void w5500_ip_state(w5500_ctrl_t *w5500, uint8_t check_state);

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

static void w5500_xfer(w5500_ctrl_t *w5500, uint16_t address, uint8_t ctrl, uint8_t *data, uint32_t len, uint8_t *buf)
{
	BytesPutBe16(buf, address);
	buf[2] = ctrl;
	if (data && len)
	{
		memcpy(buf + 3, data, len);
	}
	luat_gpio_set(w5500->cs_pin, 0);
	luat_spi_transfer(w5500->spi_id, buf, len + 3, buf, len + 3);
	luat_gpio_set(w5500->cs_pin, 1);
}


static uint8_t w5500_socket_state(w5500_ctrl_t *w5500, uint8_t socket_id)
{
	uint8_t retry = 0;
	do
	{
		w5500_xfer(w5500, 0, socket_index(socket_id)|socket_reg, NULL, 4, w5500->data_buf);
		if (w5500->data_buf[3 + W5500_SOCKET_MR] == 0xff)	//模块读不到了
		{
			w5500->device_on = 0;
			return 0;
		}
		retry++;
	}while(w5500->data_buf[3 + W5500_SOCKET_CR] && (retry < 10));
	if (retry >= 10)
	{
		DBG("!");
		w5500->inter_error = 1;
	}
	return w5500->data_buf[3 + W5500_SOCKET_SR];
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
	if ((temp >= SOCK_FIN_WAIT) && (temp <= SOCK_LAST_ACK))
	{
		w5500->socket_state[socket_id] = W5500_SOCKET_CLOSING;
		DBG("socket %d is closing");
		return;

	}
	temp = Sn_CR_DISCON;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, &temp, 1, w5500->data_buf);
	w5500->socket_state[socket_id] = W5500_SOCKET_CLOSING;
}


static int w5500_socket_config(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t is_tcp, uint16_t local_port)
{
	uint8_t delay_cnt;
	uint8_t temp;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if (SOCK_CLOSED != temp)
	{
		DBG("socket %d not closed state %x", temp);
		return -1;
	}
	uint8_t cmd[32];
	uint16_t wtemp;
	for(temp = 0; temp < 3; temp++)
	{
		cmd[W5500_SOCKET_MR] = is_tcp?Sn_MR_TCP:Sn_MR_UDP;
		cmd[W5500_SOCKET_CR] = Sn_CR_OPEN;
		cmd[W5500_SOCKET_IR] = 0xff;
		BytesPutBe16(&cmd[W5500_SOCKET_SOURCE_PORT0], local_port);
		BytesPutLe32(&cmd[W5500_SOCKET_DEST_IP0], 0);
		BytesPutBe16(&cmd[W5500_SOCKET_DEST_PORT0], 0);
		BytesPutBe16(&cmd[W5500_SOCKET_SEGMENT0], is_tcp?1460:1472);
		w5500_xfer(w5500, W5500_SOCKET_MR, socket_index(socket_id)|socket_reg|is_write, cmd, W5500_SOCKET_TOS - 1, w5500->data_buf);
		w5500_xfer(w5500, W5500_SOCKET_MR, socket_index(socket_id)|socket_reg, cmd, W5500_SOCKET_TOS - 1, w5500->data_buf);
		wtemp = BytesGetBe16(&cmd[W5500_SOCKET_SOURCE_PORT0]);
		if (wtemp != local_port)
		{
			DBG("error port %u %u", wtemp, local_port);
		}
		else
		{
			goto W5500_SOCKET_CONFIG_START;
		}
	}
	return -1;
W5500_SOCKET_CONFIG_START:
	do
	{
		luat_timer_mdelay(1);
		temp = w5500_socket_state(w5500, socket_id);
		if (!w5500->device_on) return -1;
		if (SOCK_CLOSED != temp)
		{
			DBG("socket %d not closed");
			return -1;
		}
		delay_cnt++;
	}while((temp != SOCK_INIT) && (temp != SOCK_UDP) && (delay_cnt < 100));

	if (delay_cnt >= 100)
	{
		DBG("socket %d config timeout");
		return -1;
	}

	w5500->socket_state[socket_id] = is_tcp?W5500_SOCKET_CONFIG:W5500_SOCKET_ONLINE;
	return 0;
}

static int w5500_socket_connect(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t is_listen, uint32_t remote_ip, uint16_t remote_port)
{
	uint8_t delay_cnt;
	uint8_t temp;
	uint8_t cmd[32];
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if ((temp != SOCK_INIT) && (temp != SOCK_UDP))
	{
		DBG("socket %d not config state %x", temp);
		return -1;
	}

	if (!is_listen)
	{
		uint16_t wtemp;
		uint32_t ip;
		for(temp = 0; temp < 3; temp++)
		{
			BytesPutLe32(&cmd[0], remote_ip);
			BytesPutBe16(&cmd[W5500_SOCKET_DEST_PORT0 - W5500_SOCKET_DEST_IP0], remote_port);
			w5500_xfer(w5500, W5500_SOCKET_DEST_IP0, socket_index(socket_id)|socket_reg|is_write, cmd, 6, w5500->data_buf);
			w5500_xfer(w5500, W5500_SOCKET_DEST_IP0, socket_index(socket_id)|socket_reg, cmd, 6, w5500->data_buf);
			wtemp = BytesGetBe16(&cmd[W5500_SOCKET_DEST_PORT0 - W5500_SOCKET_DEST_IP0]);
			ip = BytesGetLe32(&cmd[0]);
			if ((wtemp != remote_port) || (ip != remote_ip))
			{
				DBG("error ip port %u,%u,%x,%x", wtemp, remote_port, ip, remote_ip);
			}
			else
			{
				goto W5500_SOCKET_CONNECT_START;
			}
		}
		return -1;
	}
W5500_SOCKET_CONNECT_START:
	if (temp != SOCK_UDP)
	{

		uint8_t temp = is_listen?Sn_CR_LISTEN:Sn_CR_CONNECT;
		w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, &temp, 1, w5500->data_buf);
		w5500->socket_state[socket_id] = W5500_SOCKET_CONNECT;
	}
	return 0;
}

static int w5500_socket_auto_heart(w5500_ctrl_t *w5500, uint8_t socket_id, uint8_t time)
{
	uint8_t temp;
	uint8_t point[6];
	uint16_t tx_free, tx_point;
	temp = w5500_socket_state(w5500, socket_id);
	if (!w5500->device_on) return -1;
	if ((temp != SOCK_ESTABLISHED))
	{
		DBG("socket %d not online tcp state %x", temp);
		return -1;
	}
	point[0] = time;
	w5500_xfer(w5500, W5500_SOCKET_KEEP_TIME, socket_index(socket_id)|socket_reg|is_write, point, 1, w5500->data_buf);
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
		DBG("socket %d not online state %x", temp);
		return -1;
	}
	w5500->socket_state[socket_id] = W5500_SOCKET_ONLINE;
	if (!data || !len)
	{
		point[0] = Sn_CR_SEND_KEEP;
		w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, point, 1, w5500->data_buf);
	}

	w5500_xfer(w5500, W5500_SOCKET_TX_FREE_SIZE0, socket_index(socket_id)|socket_reg, point, 6, w5500->data_buf);
	tx_free = BytesGetBe16(point);
	tx_point = BytesGetBe16(point + 4);
	if (len > tx_free)
	{
		len = tx_free;
	}
	w5500_xfer(w5500, tx_point, socket_index(socket_id)|socket_tx|is_write, data, len, w5500->data_buf);
	tx_point += len;
	BytesPutBe16(point, tx_point);
	w5500_xfer(w5500, W5500_SOCKET_TX_WRITE_POINT0, socket_index(socket_id)|socket_reg|is_write, point, 2, w5500->data_buf);
	point[0] = Sn_CR_SEND;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, point, 1, w5500->data_buf);
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
		DBG("socket %d not config state %x", temp);
		return -1;
	}
	w5500->socket_state[socket_id] = W5500_SOCKET_ONLINE;
	w5500_xfer(w5500, W5500_SOCKET_RX_SIZE0, socket_index(socket_id)|socket_reg, point, 4, w5500->data_buf);

	rx_size = BytesGetBe16(point);
	rx_point = BytesGetBe16(point + 2);

	if (!rx_size) return 0;
	if (rx_size < len)
	{
		len = rx_size;
	}
	w5500_xfer(w5500, rx_point, socket_index(socket_id)|socket_rx, NULL, len, w5500->data_buf);
	memcpy(data, &w5500->data_buf[3], len);
	rx_point += len;
	BytesPutBe16(point, rx_point);
	w5500_xfer(w5500, W5500_SOCKET_RX_READ_POINT0, socket_index(socket_id)|socket_reg|is_write, point, 2, w5500->data_buf);
	point[0] = Sn_CR_RECV;
	w5500_xfer(w5500, W5500_SOCKET_CR, socket_index(socket_id)|socket_reg|is_write, point, 1, w5500->data_buf);
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

static void w5500_link_state(w5500_ctrl_t *w5500, uint8_t check_state)
{
	if (w5500->link_ready != check_state)
	{
		DBG("link %d -> %d", w5500->link_ready, check_state);
		w5500->link_ready = check_state;
		if (w5500->link_ready && !w5500->static_ip)
		{
			w5500->dhcp_client.state = DHCP_STATE_REQUEST;
			w5500_socket_connect(w5500, SYS_SOCK_ID, 0, 0xffffffff, DHCP_SERVER_PORT);

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
	uint8_t *uid;
	size_t t;
	w5500->ip_ready = 0;
	w5500->network_ready = 0;
	w5500->dhcp_client.state = w5500->static_ip ? DHCP_STATE_NOT_WORK : DHCP_STATE_WAIT_LINK_READY;
	w5500_callback_to_nw_task(w5500, 0, 0, 0, 0);

	luat_gpio_close(w5500->link_pin);
	luat_gpio_close(w5500->irq_pin);

	w5500_xfer(w5500, W5500_COMMON_MR, 0, NULL, W5500_COMMON_QTY, w5500->data_buf);
	w5500->device_on = (0x04 == w5500->data_buf[3 + W5500_COMMON_VERSIONR])?1:0;
	w5500_link_state(w5500, w5500->device_on?(w5500->data_buf[3 + W5500_COMMON_PHY] & 0x01):0);

	memcpy(temp, w5500->data_buf + 3, W5500_COMMON_QTY);
	temp[W5500_COMMON_MR] = MR_WOL;
	BytesPutLe32(&temp[W5500_COMMON_GAR0], w5500->static_gateway);	//已经是大端格式了不需要转换
	BytesPutLe32(&temp[W5500_COMMON_SUBR0], w5500->static_submask); //已经是大端格式了不需要转换
	BytesPutLe32(&temp[W5500_COMMON_IP0], w5500->static_ip); //已经是大端格式了不需要转换

	if (w5500->mac1 || w5500->mac2)
	{
		BytesPutBe32(&temp[W5500_COMMON_MAC0], w5500->mac1);
		BytesPutBe16(&temp[W5500_COMMON_MAC0 + 4], w5500->mac2);
	}
	else
	{
		uid = luat_mcu_unique_id(&t);
		memcpy(&temp[W5500_COMMON_MAC0], &uid[10], 6);
	}
	BytesPutBe16(&temp[W5500_COMMON_SOCKET_RTR0], w5500->RTR);
	temp[W5500_COMMON_IMR] = IR_CONFLICT|IR_UNREACH|IR_MAGIC;
	temp[W5500_COMMON_SOCKET_IMR] = 0xff;
	temp[W5500_COMMON_PHY] = 0xf8;
	temp[W5500_COMMON_SOCKET_RCR] = w5500->RCR;
//	DBG_HexPrintf(temp, W5500_COMMON_QTY);
	w5500_xfer(w5500, W5500_COMMON_MR, is_write, temp, W5500_COMMON_QTY, w5500->data_buf);

	w5500_ip_state(w5500, w5500->static_ip?1:0);
	w5500->common_irq = 0;
	memset(w5500->socket_irq, 0, MAX_SOCK_NUM);

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
	w5500_socket_config(w5500, SYS_SOCK_ID, 0, DHCP_CLIENT_PORT);
}


static void w5500_dhcp_run(w5500_ctrl_t *w5500)
{

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
	Buffer_Struct dhcp_msg_buf;
	switch(event)
	{
	case NW_EVENT_RECV:
		break;
	case NW_EVENT_ERR:
		break;
	default:
		break;
	}
}

static void w5500_read_irq(w5500_ctrl_t *w5500)
{
	OS_EVENT socket_event;
	uint8_t temp[64];
	uint8_t socket_irq, common_irq;
	int i, j;
	w5500_xfer(w5500, W5500_COMMON_IR, 0, NULL, W5500_COMMON_QTY - W5500_COMMON_IR, w5500->data_buf);
	memcpy(temp, w5500->data_buf + 3, W5500_COMMON_QTY - W5500_COMMON_IR);
	common_irq = temp[0] & 0xf0;
	socket_irq = temp[W5500_COMMON_SOCKET_IR - W5500_COMMON_IR];
	w5500->device_on = (0x04 == w5500->data_buf[3 + W5500_COMMON_VERSIONR])?1:0;
	w5500_link_state(w5500, w5500->device_on?(w5500->data_buf[W5500_COMMON_PHY - W5500_COMMON_IR] & 0x01):0);
	temp[0] = 0;
	temp[W5500_COMMON_IMR - W5500_COMMON_IR] = IR_CONFLICT|IR_UNREACH|IR_MAGIC;
	temp[W5500_COMMON_SOCKET_IR - W5500_COMMON_IR] = 0;
	w5500_xfer(w5500, W5500_COMMON_IR, is_write, temp, 3, w5500->data_buf);

	if (!w5500->device_on)
	{
		luat_gpio_close(w5500->link_pin);
		luat_gpio_close(w5500->irq_pin);

		return;
	}
	if (common_irq & IR_CONFLICT)
	{
		DBG("!");
	}
	if (socket_irq)
	{
		if (socket_irq & 0x01)
		{
			for(j = 0; j < 5; j++)
			{
				if (socket_irq & (1 << j))
				{
					w5500_sys_socket_callback(w5500, j);
				}
			}
		}
		for(i = 1; i < MAX_SOCK_NUM; i++)
		{
			if (socket_irq & (1 << i))
			{
				w5500_xfer(w5500, W5500_SOCKET_IR, socket_index(i)|socket_reg, temp, 1, w5500->data_buf);
				if (temp[0] != 0xff)
				{
					for(j = 0; j < 5; j++)
					{
						if (socket_irq & (1 << j))
						{
							socket_event.ID = j;
							socket_event.Param1 = i;
							w5500->socket_cb(&socket_event, w5500->user_data);
						}
					}
				}
			}
		}
	}
}



static void w5500_task(void *param)
{
	w5500_ctrl_t *w5500 = (w5500_ctrl_t *)param;
	OS_EVENT event;
	int result;

	luat_timer_mdelay(1);
	luat_gpio_set(w5500->rst_pin, 1);
	luat_timer_mdelay(1);
	w5500_init_reg(w5500);
	while(1)
	{
		result = luat_wait_event_from_task(w5500->task_handle, 0, &event, NULL, (w5500->link_pin != 0xff)?0:1000);

		w5500_xfer(w5500, W5500_COMMON_MR, 0, NULL, W5500_COMMON_QTY, w5500->data_buf);
		w5500->device_on = (0x04 == w5500->data_buf[3 + W5500_COMMON_VERSIONR])?1:0;
		if (w5500->device_on && w5500->data_buf[3 + W5500_COMMON_IMR] != (IR_CONFLICT|IR_UNREACH|IR_MAGIC))
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
			w5500_link_state(w5500, w5500->data_buf[3 + W5500_COMMON_PHY] & 0x01);
		}

		if (result)
		{
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
			if (!w5500->static_ip)
			{
				//尝试DHCP
			}
			break;
		case EV_W5500_SET_IP:
			w5500->static_ip = event.Param1;
			w5500->static_submask = event.Param2;
			w5500->static_gateway = event.Param3;
			break;
		case EV_W5500_SET_MAC:
			w5500->mac1 = event.Param1;
			w5500->mac2 = event.Param2;
			break;
		case EV_W5500_SET_TO_PARAM:
			w5500->RTR = event.Param1;
			w5500->RCR = event.Param2;
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
	DBG("%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
	return uIP.u32;
}

void w5500_array_to_mac(uint8_t *array, uint32_t *mac1, uint16_t *mac2)
{
	*mac1 = BytesGetBe32(array);
	*mac2 = BytesGetBe16(array + 4);
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
//		luat_spi_config_dma(w5500->spi_id, 0xffff, 0xffff);
		luat_gpio_t gpio = {0};
		gpio.pin = w5500->cs_pin;
		gpio.mode = Luat_GPIO_OUTPUT;
		gpio.pull = Luat_GPIO_DEFAULT;
		luat_gpio_setup(&gpio);
		luat_gpio_set(w5500->cs_pin, 1);

		gpio.pin = w5500->rst_pin;
		luat_gpio_setup(&gpio);
		luat_gpio_set(w5500->rst_pin, 0);

		luat_thread_t thread;
		thread.task_fun = w5500_task;
		thread.name = "w5500";
		thread.stack_size = 1024;
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
#else
void w5500_init(luat_spi_t* spi, uint8_t irq_pin, uint8_t rst_pin) {;}
int w5500_request(uint32_t cmd, uint32_t param1, uint32_t param2, uint32_t param3) {return -1;}
uint32_t w5500_string_to_ip(const char *string, uint32_t len) {return 0}
void w5500_array_to_mac(uint8_t *array, uint32_t *mac1, uint16_t *mac2) {return;}
uint8_t w5500_ready(void) {return 0;}
#endif
