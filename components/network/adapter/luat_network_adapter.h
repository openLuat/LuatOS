#ifndef __LUAT_NW_ADAPTER_H__
#define __LUAT_NW_ADAPTER_H__
#include "luat_base.h"
#ifdef LUAT_USE_NETWORK
#include "luat_rtos.h"
#include "bsp_common.h"
enum
{
	EV_NW_RESET = USER_EVENT_ID_START + 0x1000000,
	EV_NW_SOCKET_TX_OK,
	EV_NW_SOCKET_RX_NEW,
	EV_NW_SOCKET_RX_FULL,
	EV_NW_SOCKET_TCP_CLOSE_OK,
	EV_NW_SOCKET_TCP_REMOTE_CLOSE,
	EV_NW_SOCKET_TCP_CONNECT_OK,
	EV_NW_SOCKET_DNS_RESULT,
	EV_NW_SOCKET_ERROR,
	EV_NW_SOCKET_TCP_LISTEN,
	EV_NW_SOCKET_TCP_NEW_CONNECT,	//作为server接收到新的connect，只有允许accept操作的才有，否则直接上报CONNECT_OK
	EV_NW_STATE,

	NW_ADAPTER_ETH0 = 0,
	NW_ADAPTER_ETH1,
	NW_ADAPTER_STA,
	NW_ADAPTER_AP,

	NW_CMD_W5500_AUTO_HEART_TIME = 0,

};

typedef struct
{
	union
	{
		uint32_t ipv4;
		uint32_t ipv6_u32_addr[4];
	    uint8_t  ipv6_u8_addr[16];
	};
	uint8_t is_ipv6;
}luat_ip_addr_t;

typedef struct
{
#ifdef LUAT_USE_TLS
    mbedtls_ssl_context ssl;          /**< mbed TLS control context. */
    mbedtls_ssl_config config;          /**< mbed TLS configuration context. */
    mbedtls_x509_crt ca_cert;
#endif
	uint64_t tx_size;
	uint64_t ack_size;
	CBFuncEx_t user_callback;
	HANDLE	task_handle;
	HANDLE timer;
#ifdef LUAT_USE_TLS
	HANDLE tls_short_timer;
	HANDLE tls_long_timer;
#endif
	int socket_id;
	luat_ip_addr_t remote_ip;
	luat_ip_addr_t *dns_ip;
	uint16_t remote_port;
	uint16_t local_port;
#ifdef LUAT_USE_TLS
	int tls_timer_state;
	uint32_t tls_send_timeout_ms;
	uint8_t tls_mode;
    uint8_t tls_need_reshakehand;
    uint8_t tls_init_done;
#endif
}network_ctrl_t;

typedef struct
{
	uint64_t tag;
	llist_head tx_head;
	llist_head rx_head;
	uint32_t rx_wait_size;
	uint32_t tx_wait_size;
	uint8_t state;
	uint8_t is_tcp;
	uint8_t is_ipv6;
	uint8_t in_use;
}socket_ctrl_t;		//推荐底层协议栈适配用的socket状态结构

typedef struct
{
	//检查网络是否准备好，返回非0准备好，user_data是注册时的user_data，传入给底层api
	uint8_t (*check_ready)(void *user_data);
	//创建一个socket，并设置成非阻塞模式，user_data传入对应适配器, tag作为socket的合法依据，给check_socket_vaild比对用
	//成功返回socketid，失败 < 0
	int (*create_soceket)(uint8_t is_tcp, uint64_t *tag, uint8_t is_ipv6, void *user_data);
	//作为client绑定一个port，并连接remote_ip和remote_port对应的server
	//成功返回0，失败 < 0
	int (*socket_connect)(int socket_id, uint64_t tag, uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data);
	//作为server绑定一个port，开始监听
	//成功返回0，失败 < 0
	int (*socket_listen)(int socket_id, uint64_t tag, uint16_t local_port, void *user_data);
	//作为server接受一个client
	//成功返回0，失败 < 0
	int (*socket_accept)(int socket_id, uint64_t tag, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data);
	//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
	//成功返回0，失败 < 0
	int (*socket_disconnect)(int socket_id, uint64_t tag, void *user_data);
	//释放掉socket的控制权
	//成功返回0，失败 < 0
	int (*socket_close)(int socket_id, uint64_t tag, void *user_data);
	//强行释放掉socket的控制权
	//成功返回0，失败 < 0
	int (*socket_force_close)(int socket_id, void *user_data);
	//tcp时，不需要remote_ip和remote_port，如果buf为NULL，则返回当前缓存区的数据量，当返回值小于len时说明已经读完了
	//udp时，只返回1个block数据，需要多次读直到没有数据为止
	//成功返回实际读取的值，失败 < 0
	int (*socket_receive)(int socket_id, uint64_t tag, uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data);
	//tcp时，不需要remote_ip和remote_port
	//成功返回0，失败 < 0
	int (*socket_send)(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data);

	int (*getsockopt)(int s, uint64_t tag, int level, int optname, void *optval, uint32_t *optlen, void *user_data);
	int (*setsockopt)(int s, uint64_t tag, int level, int optname, const void *optval, uint32_t optlen, void *user_data);
	//非posix的socket，用这个根据实际硬件设置参数
	int (*user_cmd)(int s, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data);

	int (*dns)(const char *url, void *user_data);
	int (*set_dns_server)(int id, luat_ip_addr_t *ip, void *user_data);

	int (*socket_set_callback)(CBFuncEx_t cb_fun, void *param, void *user_data);

	char *name;
	int socket_num;
	uint8_t no_accept;
	uint8_t is_posix;
}network_adapter_info;

int network_register_adapter(int index, network_adapter_info *info, void *user_data);
#endif
#endif
