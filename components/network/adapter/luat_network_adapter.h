#ifndef __LUAT_NW_ADAPTER_H__
#define __LUAT_NW_ADAPTER_H__
#include "luat_base.h"
// #ifdef LUAT_USE_NETWORK
#if defined(LUAT_EC7XX_CSDK) || defined(CHIP_EC618) || defined(__AIR105_BSP__) || defined(CONFIG_SOC_8910) || defined(CONFIG_SOC_8850)
#include "bsp_common.h"
#endif
#include "luat_rtos.h"
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif
#ifdef LUAT_USE_TLS
#include "mbedtls/ssl.h"
#include "mbedtls/platform.h"
#include "mbedtls/debug.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/base64.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/sha1.h"
#endif
#ifdef LUAT_USE_LWIP
#include "lwip/opt.h"
#include "lwip/netif.h"
#include "lwip/timeouts.h"
#include "lwip/priv/tcp_priv.h"

#include "lwip/def.h"
#include "lwip/memp.h"
#include "lwip/priv/tcpip_priv.h"

#include "lwip/ip4_frag.h"
#include "lwip/etharp.h"
#include "lwip/dhcp.h"
#include "lwip/prot/dhcp.h"
#include "lwip/autoip.h"
#include "lwip/igmp.h"
#include "lwip/dns.h"
#include "lwip/nd6.h"
#include "lwip/ip6_frag.h"
#include "lwip/mld6.h"
#include "lwip/dhcp6.h"
#include "lwip/sys.h"
#include "lwip/pbuf.h"
#include "lwip/inet.h"
#endif
#define MAX_DNS_IP		(4)	//每个URL最多保留4个IP

enum
{
	EV_NW_RESET = USER_EVENT_ID_START + 0x1000000,
	EV_NW_STATE,
	EV_NW_TIMEOUT,
	EV_NW_DNS_RESULT,
	EV_NW_SOCKET_TX_OK,
	EV_NW_SOCKET_RX_NEW,
	EV_NW_SOCKET_RX_FULL,
	EV_NW_SOCKET_CLOSE_OK,
	EV_NW_SOCKET_REMOTE_CLOSE,
	EV_NW_SOCKET_CONNECT_OK,

	EV_NW_SOCKET_ERROR,
	EV_NW_SOCKET_LISTEN,
	EV_NW_SOCKET_NEW_CONNECT,	//作为server接收到新的connect，只有允许accept操作的才有，否则直接上报CONNECT_OK
	EV_NW_BREAK_WAIT,
	EV_NW_END,

	NW_STATE_LINK_OFF = 0,
	NW_STATE_OFF_LINE,
	NW_STATE_WAIT_DNS,
	NW_STATE_CONNECTING,
	NW_STATE_SHAKEHAND,
	NW_STATE_ONLINE,
	NW_STATE_LISTEN,
	NW_STATE_DISCONNECTING,

	NW_WAIT_NONE = 0,
	NW_WAIT_LINK_UP,
	NW_WAIT_ON_LINE,
	NW_WAIT_TX_OK,
	NW_WAIT_OFF_LINE,
	NW_WAIT_EVENT,

	//一旦使用高级API，回调会改为下面的，param1 = 0成功，其他失败
	EV_NW_RESULT_BASE = EV_NW_END + 1,
	EV_NW_RESULT_LINK = EV_NW_RESULT_BASE + NW_WAIT_LINK_UP,
	EV_NW_RESULT_CONNECT = EV_NW_RESULT_BASE + NW_WAIT_ON_LINE,
	EV_NW_RESULT_CLOSE = EV_NW_RESULT_BASE + NW_WAIT_OFF_LINE,
	EV_NW_RESULT_TX = EV_NW_RESULT_BASE + NW_WAIT_TX_OK,
	EV_NW_RESULT_EVENT = EV_NW_RESULT_BASE + NW_WAIT_EVENT,

	NW_ADAPTER_INDEX_LWIP_NONE = 0,
	NW_ADAPTER_INDEX_LWIP_GPRS,	//蜂窝网络模块
	NW_ADAPTER_INDEX_LWIP_WIFI_STA,	//WIFI SOC
	NW_ADAPTER_INDEX_LWIP_WIFI_AP,	//WIFI SOC
	NW_ADAPTER_INDEX_LWIP_ETH,		//自带以太网控制器的SOC
	NW_ADAPTER_INDEX_LWIP_SPI,		// SPI协议的网卡,无MAC,纯IP包
	NW_ADAPTER_INDEX_LWIP_UART,     // UART协议的网卡,无MAC,纯IP包
	NW_ADAPTER_INDEX_LWIP_USER0,
	NW_ADAPTER_INDEX_LWIP_USER1,
	NW_ADAPTER_INDEX_LWIP_USER2,
	NW_ADAPTER_INDEX_LWIP_USER3,
	NW_ADAPTER_INDEX_LWIP_USER4,
	NW_ADAPTER_INDEX_LWIP_USER5,
	NW_ADAPTER_INDEX_LWIP_USER6,
	NW_ADAPTER_INDEX_LWIP_USER7,
	NW_ADAPTER_INDEX_LWIP_NETIF_QTY,
	NW_ADAPTER_INDEX_HW_PS_DEVICE = NW_ADAPTER_INDEX_LWIP_NETIF_QTY,
	NW_ADAPTER_INDEX_ETH0 = NW_ADAPTER_INDEX_HW_PS_DEVICE,	//外挂以太网+硬件协议栈
	NW_ADAPTER_INDEX_USB,			//USB网卡
	NW_ADAPTER_INDEX_POSIX,         // 对接POSIX
	NW_ADAPTER_INDEX_LUAPROXY,      // 代理到Lua层
	NW_ADAPTER_INDEX_CUSTOM,        // 对接到自定义适配器
	NW_ADAPTER_QTY,

	NW_CMD_AUTO_HEART_TIME = 0,



};

#ifdef LUAT_USE_LWIP
#define luat_ip_addr_t ip_addr_t
#else
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
uint8_t network_string_is_ipv4(const char *string, uint32_t len);
uint32_t network_string_to_ipv4(const char *string, uint32_t len);
int network_string_to_ipv6(const char *string, luat_ip_addr_t *ip_addr);
#endif

typedef struct
{
	uint64_t tag;
	void *param;
}luat_network_cb_param_t;

typedef struct
{
	uint32_t ttl_end;
	luat_ip_addr_t ip;
}luat_dns_ip_result;


typedef struct
{
	/* data */
	llist_head node;
	Buffer_Struct uri;
	luat_dns_ip_result result[MAX_DNS_IP];
	uint8_t ip_nums;
}luat_dns_cache_t;

typedef struct
{
	uint64_t tx_size;
	uint64_t ack_size;
	uint64_t tag;
#ifdef LUAT_USE_TLS
	//SSL相关数据均为动态生成的，需要在close的时候释放
    mbedtls_ssl_context *ssl;          /**< mbed TLS control context. */
    mbedtls_ssl_config *config;          /**< mbed TLS configuration context. */
    mbedtls_x509_crt *ca_cert;
#endif

	CBFuncEx_t user_callback;
	void *user_data;			//传递给user_callback的pParam
	void *socket_param;			//一般用来存放network_ctrl本身，用于快速查找
	HANDLE	task_handle;
	HANDLE timer;
	HANDLE tls_short_timer;
	HANDLE tls_long_timer;
	HANDLE mutex;
	uint32_t tcp_keep_idle;
	int socket_id;
	char *domain_name;			//动态生成的，需要在close的时候释放
	uint32_t domain_name_len;
	luat_ip_addr_t remote_ip;
	luat_dns_ip_result *dns_ip;	//动态生成的，需要在close的时候释放
	luat_ip_addr_t *online_ip;	//指向某个ip，无需释放
	uint16_t remote_port;
	uint16_t local_port;
	uint8_t *cache_data;	//动态生成的，需要在close的时候释放
	uint32_t cache_len;
	int tls_timer_state;
	uint32_t tcp_timeout_ms;
	uint8_t tls_mode;
    uint8_t tls_need_reshakehand;
    uint8_t need_close;
    uint8_t new_rx_flag;
    uint8_t dns_ip_cnt;
    uint8_t dns_ip_nums;
    uint8_t tcp_keep_alive;
	uint8_t tcp_keep_interval;
	uint8_t tcp_keep_cnt;
    uint8_t adapter_index;
    uint8_t is_tcp;
    uint8_t is_server_mode;
    uint8_t auto_mode;
    uint8_t wait_target_state;
    uint8_t state;
    uint8_t is_debug;
    uint8_t domain_ipv6;
}network_ctrl_t;

typedef struct
{
	uint64_t tag;
#ifdef LUAT_USE_LWIP
	llist_head wait_ack_head;
#endif
	llist_head tx_head;
	llist_head rx_head;
	uint32_t rx_wait_size;
	uint32_t tx_wait_size;
#ifdef LUAT_USE_LWIP
	union {
		struct ip_pcb  *ip;
		struct tcp_pcb *tcp;
		struct udp_pcb *udp;
		struct raw_pcb *raw;
	} pcb;
	struct tcp_pcb_listen *listen_tcp;
	HANDLE mutex;
	uint16_t local_port;
	uint16_t remote_port;
#endif
	void *param;
	uint8_t state;
	uint8_t is_tcp;
	uint8_t is_ipv6;
	uint8_t in_use;
	uint8_t rx_waiting;
	uint8_t remote_close;
	uint8_t fast_rx_ack;	//TCP快速应答
}socket_ctrl_t;		//推荐底层协议栈适配用的socket状态结构

/*
 * info内的api必须全部是非阻塞的及任务的，并且对socket_id和tag做合法性检查
 * 目前只支持tcp和udp，不支持raw
 * 如果没有特殊说明，成功返回=0，失败返回<0
 */
typedef struct
{
	//检查网络是否准备好，返回非0准备好，user_data是注册时的user_data，传入给底层api
	uint8_t (*check_ready)(void *user_data);
	//创建一个socket，并设置成非阻塞模式，user_data传入对应适配器, tag作为socket的合法依据，给check_socket_vaild比对用
	//成功返回socketid，失败 < 0
	int (*create_soceket)(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data);
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
	//释放掉socket的控制权，除了tag异常外，必须立刻生效
	//成功返回0，失败 < 0
	int (*socket_close)(int socket_id, uint64_t tag, void *user_data);
	//强行释放掉socket的控制权，必须立刻生效
	//成功返回0，失败 < 0
	int (*socket_force_close)(int socket_id, void *user_data);
	//tcp时，不需要remote_ip和remote_port，如果buf为NULL，则返回当前缓存区的数据量，当返回值小于len时说明已经读完了
	//udp时，只返回1个block数据，需要多次读直到没有数据为止
	//成功返回实际读取的值，失败 < 0
	int (*socket_receive)(int socket_id, uint64_t tag, uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data);
	//tcp时，不需要remote_ip和remote_port
	//成功返回>0的len，缓冲区满了=0，失败 < 0，如果发送了len=0的空包，也是返回0，注意判断
	int (*socket_send)(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data);
	//检查socket合法性，成功返回0，失败 < 0
	int (*socket_check)(int socket_id, uint64_t tag, void *user_data);
	//保留有效的socket，将无效的socket关闭
	void (*socket_clean)(int *vaild_socket_list, uint32_t num, void *user_data);
	int (*getsockopt)(int socket_id, uint64_t tag, int level, int optname, void *optval, uint32_t *optlen, void *user_data);
	int (*setsockopt)(int socket_id, uint64_t tag, int level, int optname, const void *optval, uint32_t optlen, void *user_data);
	//非posix的socket，用这个根据实际硬件设置参数
	int (*user_cmd)(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data);

	int (*dns)(const char *domain_name, uint32_t len, void *param,  void *user_data);
	int (*dns_ipv6)(const char *domain_name, uint32_t len, void *param,  void *user_data);
	int (*set_dns_server)(uint8_t server_index, luat_ip_addr_t *ip, void *user_data);
	int (*set_mac)(uint8_t *mac, void *user_data);
	int (*set_static_ip)(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data);
	int (*get_full_ip_info)(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data);
	int (*get_local_ip_info)(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data);
	//所有网络消息都是通过cb_fun回调
	//cb_fun回调时第一个参数为OS_EVENT，包含了socket的必要信息，第二个是luat_network_cb_param_t，其中的param是这里传入的param(就是适配器序号)
	//OS_EVENT ID为EV_NW_XXX，param1是socket id param2是各自参数 param3是create_soceket传入的socket_param(就是network_ctrl *)
	//dns结果是特别的，ID为EV_NW_SOCKET_DNS_RESULT，param1是获取到的IP数据量，0就是失败了，param2是ip组，动态分配的， param3是dns传入的param(就是network_ctrl *)
	void (*socket_set_callback)(CBFuncEx_t cb_fun, void *param, void *user_data);
	int (*check_ack)(uint8_t adapter_index, int socket_id); // 2024.4.11新增

	char *name;
	int max_socket_num;//最大socket数量，也是最大network_ctrl申请数量的基础值
	uint8_t no_accept;
	uint8_t is_posix;
}network_adapter_info;
/*
 * api有可能涉及到任务安全要求，不可以在中断里运行，只能在task中运行
 */

/**
 * 获取最后一个注册的网卡适配器序号
 * @return 注册的网卡适配器序号 NW_ADAPTER_INDEX_XXX
 */
int network_get_last_register_adapter(void);
/****************************以下是通用基础api********************************************************/

/**
 * 注册网卡适配器相关的协议栈接口
 * @param adapter_index 网卡适配器序号 NW_ADAPTER_INDEX_XXX
 * @param info 协议栈接口
 * @param user_data 用户数据
 * @return 0成功，其他失败
 */
int network_register_adapter(uint8_t adapter_index, network_adapter_info *info, void *user_data);

/**
 * 将某个网卡适配器配置成默认适配器
 * @param adapter_index 网卡适配器序号 NW_ADAPTER_INDEX_XXX
 */
void network_register_set_default(uint8_t adapter_index);

/**
 * 设置某个网卡适配器的DNS服务器地址
 * @param adapter_index 网卡适配器序号 NW_ADAPTER_INDEX_XXX
 * @param server_index DNS服务器序号
 * @param ip DNS服务器地址
 */
void network_set_dns_server(uint8_t adapter_index, uint8_t server_index, luat_ip_addr_t *ip);

/**
 * 在某个网卡适配器上申请一个网络资源
 * @param adapter_index 适配器序号 NW_ADAPTER_INDEX_XXX
 * @return 网络资源，network_ctrl_t结构类型
 */
network_ctrl_t *network_alloc_ctrl(uint8_t adapter_index);

/**
 * 归还一个网络资源
 * @param ctrl 网络资源
 */
void network_release_ctrl(network_ctrl_t *ctrl);

/**
 * 初始化网络资源
 * lua调用c时，必须使用非阻塞接口，task_handle不需要
 * 在纯c调用时，如果不需要则塞应用，必须有callback和param
 * 在纯c调用时，如果需要阻塞应用，则必须有task_handle，建议有callback，param，可以等待消息时，同时在callback中处理其他类型的消息
 * @param ctrl 网络资源
 * @param task_handle socket阻塞应用时所在的task，可以是空的
 * @param callback socket非阻塞应用时回调函数
 * @param param	socket非阻塞应用时回调时的用户自定义参数
 */
void network_init_ctrl(network_ctrl_t *ctrl, HANDLE task_handle, CBFuncEx_t callback, void *param);

/**
 * 网络资源基本配置
 * 设置是tcp还是udp模式及TCP自动保活相关参数，也可以直接改network_ctrl_t中的is_tcp参数
 * 设置必须在socket处于close状态，在进行connect和tls初始之前
 * @param ctrl 网络资源
 * @param is_tcp 0UDP 其他TCP，默认是UDP
 * @param tcp_timeout_ms tcp超时时间，目前未启用
 * @param keep_alive	tcp自动保活是否启用，0不启用，其他启用
 * @param keep_idle		tcp自动保活空闲时间，单位秒
 * @param keep_interval	tcp自动保活启动时，tcp探针发送时间间隔，单位秒
 * @param keep_cnt  tcp自动保活启动时，tcp探针发送总次数
 */
void network_set_base_mode(network_ctrl_t *ctrl, uint8_t is_tcp, uint32_t tcp_timeout_ms, uint8_t keep_alive, uint32_t keep_idle, uint8_t keep_interval, uint8_t keep_cnt);
/**
 * 是否开启debug功能
 * @param ctrl 网络资源
 * @param on_off 0关，其他开，默认是关
 */
void network_set_debug_onoff(network_ctrl_t *ctrl, uint8_t on_off);


/**
 * 使用域名时是否选择IPV6地址
 * @param ctrl 网络资源
 * @param onoff 0关，其他开，默认是关
 */
void network_connect_ipv6_domain(network_ctrl_t *ctrl, uint8_t onoff);


/**
 * 检测某个网卡是否能上网
 * 具体哪个网卡，看socket或者适配器序号
 * @param ctrl 网络资源，如果为NULL，则看下面的适配器序号
 * @param adapter_index 适配器序号 NW_ADAPTER_INDEX_XXX
 * @return 0不能上网 其他能
 */
uint8_t network_check_ready(network_ctrl_t *ctrl, uint8_t adapter_index);

/**
 * 设置本地port，注意不要用60000及以上，如果local_port为0，系统从60000开始随机抽一个
 * 默认就是0，一般不需要配置，由系统去分配
 * @param ctrl 网络资源
 * @param local_port 本地端口号
 * @return local_port不为0，且重复了，则返回-1，其他返回0
 */
int network_set_local_port(network_ctrl_t *ctrl, uint16_t local_port);

/**
 * 创建一个socket
 * @param ctrl 网络资源
 * @param is_ipv6 是否是IPV6，0否 1是，默认是0
 * @return 成功返回0，失败 < 0
 */
int network_create_socket(network_ctrl_t *ctrl, uint8_t is_ipv6);

/**
 * 连接服务器，在连接前，需要配置好网络资源中的remote_port
 * @param ctrl 网络资源
 * @param remote_ip 服务器地址
 * @return 成功返回0，失败 < 0
 */
int network_socket_connect(network_ctrl_t *ctrl, luat_ip_addr_t *remote_ip);

/**
 * 作为服务器监听
 * @param ctrl 网络资源 用于监听的网络资源
 * @return 成功返回0，失败 < 0
 */
int network_socket_listen(network_ctrl_t *ctrl);

/**
 * 查询网络资源对应的网卡是否有服务器功能
 * @param ctrl 网络资源 用于监听的网络资源
 * @return 1有 0无
 */
uint8_t network_accept_enable(network_ctrl_t *ctrl);

/**
 * 作为服务器接受一个客户端的接入请求
 * @param ctrl 网络资源 用于监听的网络资源
 * @param accept_ctrl 用于和客户端通讯的网络资源
 * @return 成功返回0，失败 < 0
 */
int network_socket_accept(network_ctrl_t *ctrl, network_ctrl_t *accept_ctrl);

/**
 * 主动断开一个tcp连接，需要走完整个tcp挥手流程，用户需要接收到close ok回调才能确认彻底断开
 * @param ctrl 网络资源
 * @return 均为0
 */
int network_socket_disconnect(network_ctrl_t *ctrl);

/**
 * 释放掉socket的控制权
 * @param ctrl 网络资源
 * @return 均为0
 */
int network_socket_close(network_ctrl_t *ctrl);

/**
 * 强行释放掉socket的控制权
 * @param ctrl 网络资源
 * @return 均为0
 */
int network_socket_force_close(network_ctrl_t *ctrl);

/**
 * 读取对端发送过来的数据
 * tcp时，不需要remote_ip和remote_port，如果buf为NULL，则返回当前缓存区的数据量，当返回值小于len时说明已经读完了
 * udp时，只返回1个block数据，需要多次读直到没有数据为止
 * @param ctrl 网络资源
 * @param buf 数据读取后缓存的地址
 * @param len 期望读取的长度
 * @param flags 读取时的标志，一般为0
 * @param remote_ip 存放对端IP，UDP才有
 * @param remote_port 存放对端端口，UDP才有
 * @return 成功返回实际读取的值，失败 < 0
 */
int network_socket_receive(network_ctrl_t *ctrl,uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port);

/**
 * 缓存发送数据，准备发送给对端
 * tcp时，不需要remote_ip和remote_port
 * @param ctrl 网络资源
 * @param buf 缓存发送数据的地址
 * @param len 发送长度
 * @param flags 发送标志，一般为0
 * @param remote_ip 对端IP，UDP才有
 * @param remote_port 对端端口，UDP才有
 * @return 存入发送缓存返回0，失败 < 0
 */
int network_socket_send(network_ctrl_t *ctrl,const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port);

/**
 * 获取socket一个配置，和POSIX socket一致，非POSIX的网卡(比如w5500的硬件协议栈)不支持
 * @param ctrl 网络资源
 * @param level 配置参数级别
 * @param optname 参数名称
 * @param optval 参数指针
 * @param optlen 参数长度
 * @return 成功返回0，其他失败
 */
int network_getsockopt(network_ctrl_t *ctrl, int level, int optname, void *optval, uint32_t *optlen);

/**
 * 设置socket一个配置，和POSIX socket一致，非POSIX的网卡(比如w5500的硬件协议栈)不支持
 * @param ctrl 网络资源
 * @param level 配置参数级别
 * @param optname 参数名称
 * @param optval 参数指针
 * @param optlen 参数长度
 * @return 成功返回0，其他失败
 */
int network_setsockopt(network_ctrl_t *ctrl, int level, int optname, const void *optval, uint32_t optlen);

/**
 * 设置socket一个配置，仅支持非POSIX的网卡(比如w5500的硬件协议栈)
 * @param ctrl 网络资源
 * @param cmd 配置命令
 * @param value 配置值
 * @return 成功返回0，其他失败
 */
int network_user_cmd(network_ctrl_t *ctrl,  uint32_t cmd, uint32_t value);
#ifdef LUAT_USE_LWIP
/**
 * 设置网卡的MAC
 * @param adapter_index 网卡适配器序号 NW_ADAPTER_INDEX_XXX
 * @param mac MAC地址
 * @return 成功返回0，其他失败
 */
int network_set_mac(uint8_t adapter_index, uint8_t *mac);
/**
 * 设置网卡的静态地址
 * @param adapter_index 网卡适配器序号 NW_ADAPTER_INDEX_XXX
 * @param ip IPV4地址
 * @param submask 子网掩码
 * @param gateway 网关
 * @param ipv6 IPV6地址
 * @return 成功返回0，其他失败
 */
int network_set_static_ip_info(uint8_t adapter_index, luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6);
#endif
/**
 * 获取网卡的地址信息
 * @param ctrl 网络资源
 * @param ip IPV4地址
 * @param submask 子网掩码
 * @param gateway 网关
 * @return 成功返回0，其他失败
 */
int network_get_local_ip_info(network_ctrl_t *ctrl, luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway);
/**
 * 强制释放socket资源，同时也释放部分网络资源
 * @param ctrl 网络资源
 */
void network_force_close_socket(network_ctrl_t *ctrl);

/**
 * 启动DNS解析，启动前，需要设置好domain_name和domain_name_len
 * domain_name已经是ip形式了，返回1，并且填充remote_ip
 * @param ctrl 网络资源
 * @return domain_name已经是ip形式了返回1， DNS开始返回0，失败 < 0
 */
int network_dns(network_ctrl_t *ctrl);
/**
 * 查询网卡下所有网络资源是否需要释放，需要释放的立刻释放掉
 * @param adapter_index 网卡适配器序号 NW_ADAPTER_INDEX_XXX
 */
void network_clean_invaild_socket(uint8_t adapter_index);

//下列API仅内部调试使用，用户不用
const char *network_ctrl_state_string(uint8_t state);
const char *network_ctrl_wait_state_string(uint8_t state);
const char *network_ctrl_callback_event_string(uint32_t event);
/****************************通用基础api结束********************************************************/

/****************************tls相关api************************************************************/

/**
 * 给DTLS设置PSK，给UDP加密传输时用的
 * @param ctrl 网络资源
 * @param psk psk数据
 * @param psk_len psk数据长度
 * @param psk_identity psk_identity数据
 * @param psk_identity_len psk_identity数据长度
 * @return 成功返回0，其他失败
 */
int network_set_psk_info(network_ctrl_t *ctrl,
		const unsigned char *psk, size_t psk_len,
		const unsigned char *psk_identity, size_t psk_identity_len);

/**
 * TLS设置验证服务器的证书，可以不用
 * @param ctrl 网络资源
 * @param cert 服务器证书数据
 * @param cert_len 服务器证书数据长度
 * @return 成功返回0，其他失败
 */
int network_set_server_cert(network_ctrl_t *ctrl, const unsigned char *cert, size_t cert_len);

/**
 * TLS设置验证客户端的证书，只有双向认证才需要，而且一般只有金融领域才需要
 * @param ctrl 网络资源
 * @param cert 客户端证书数据
 * @param certLen客户端证书数据长度
 * @param key 客户端证书私钥数据
 * @param keylen 客户端证书私钥数据长度
 * @param pwd 客户端证书私钥的密码数据
 * @param pwdlen 客户端证书私钥的密码数据长度
 * @return 成功返回0，其他失败
 */
int network_set_client_cert(network_ctrl_t *ctrl,
		const unsigned char *cert, size_t certLen,
        const unsigned char *key, size_t keylen,
        const unsigned char *pwd, size_t pwdlen);

/**
 * 获取证书验证结果
 * @param ctrl 网络资源
 * @return 成功返回0，其他失败
 */
int network_cert_verify_result(network_ctrl_t *ctrl);

/**
 * 初始化加密传输
 * @param ctrl 网络资源
 * @param verify_mode 参考MBEDTLS_SSL_VERIFY_XXX
 * @return 成功返回0，其他失败
 */
int network_init_tls(network_ctrl_t *ctrl, int verify_mode);

/**
 * 结束加密传输模式，恢复成正常模式，必须在socket关闭情况下才可以修改
 * @param ctrl 网络资源
 */
void network_deinit_tls(network_ctrl_t *ctrl);
/*
 * 加密传输其他非阻塞api和通用api共用，阻塞api和rtos环境相关阻塞api通用，均由api内部做相关处理
 */
/****************************tls相关api结束************************************************************/


/****************************高级api，用于实现一个完整功能***********************/
//一旦使用下面的api，将由network内部自动判断状态并进行下一步操作，中间处理过程除了主动强制关闭socket，其他用户不能干预，直到达到目标状态，即使非阻塞回调也只回调最终结果。
//所有阻塞状态接口，一旦收到link down，socket close, error之类的消息就会返回错误，如果是timeout，只有wait event会返回成功，其他返回失败
//以下api是阻塞和非则塞均可，当network_ctrl中设置了task_handle 而且 timeout_ms > 0时为阻塞接口，timeout_ms = 0xffffffff 为永远等待

/**
 * 等待网络环境准备好
 * @param ctrl 网络资源
 * @param timeout_ms 超时时间
 * @return 成功返回0，失败 < 0，非阻塞需要等待返回1
 */
int network_wait_link_up(network_ctrl_t *ctrl, uint32_t timeout_ms);

/**
 * 作为客户端去连接服务器
 * 域名或者IP至少写1个，如果写了有效IP，则不会去连接域名
 * 会自动等待网络环境准备好，无需network_wait_link_up
 * 如果是加密模式，自动进行握手
 * 使用前必须确保是在close状态，建议先用network_close
 * @param ctrl 网络资源
 * @param domain_name 服务器域名
 * @param domain_name_len 服务器域名长度
 * @param remote_ip 服务器IP
 * @param remote_port 服务器端口
 * @param timeout_ms 超时时间
 * @return 成功返回0，失败 < 0，非阻塞需要等待返回1
 */
int network_connect(network_ctrl_t *ctrl, const char *domain_name, uint32_t domain_name_len, luat_ip_addr_t *remote_ip, uint16_t remote_port, uint32_t timeout_ms);

/**
 * 作为服务器监听
 * @param ctrl 网络资源
 * @param timeout_ms 超时时间
 * @return 成功返回0，失败 < 0，非阻塞需要等待返回1
 */
int network_listen(network_ctrl_t *ctrl, uint32_t timeout_ms);

/**
 * 关闭连接
 * @param ctrl 网络资源
 * @param timeout_ms 超时时间
 * @return 成功返回0，失败 < 0，非阻塞需要等待返回1
 */
int network_close(network_ctrl_t *ctrl, uint32_t timeout_ms);

/**
 * 发送数据给对端
 * UDP的时候，remote_ip和remote_port和connect不一致的时候才需要remote_ip和remote_port
 * TCP不看remote_ip和remote_port
 * 阻塞模式，*tx_len不需要看，非阻塞模式需要看*tx_len的实际长度是不是和len一致
 * @param ctrl 网络资源
 * @param data 需要发送的数据
 * @param len 需要发送的数据长度
 * @param flags 发送标志，一般写0
 * @param remote_ip 对端IP
 * @param remote_port 对端端口
 * @param tx_len 实际存入缓存区的长度
 * @param timeout_ms 超时时间
 * @return 成功返回0，失败 < 0，非阻塞需要等待返回1
 */
int network_tx(network_ctrl_t *ctrl, const uint8_t *data, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, uint32_t *tx_len, uint32_t timeout_ms);

/**
 * 读取接收到的数据
 * 实际读到的数据量在read_len里，如果是UDP模式且为server时，需要看remote_ip和remote_port
 * @param ctrl 网络资源
 * @param data 存放读取数据的地址
 * @param len 期望读取的长度
 * @param flags 接收标志，一般写0
 * @param remote_ip 对端IP
 * @param remote_port 对端端口
 * @param rx_len 实际读出的长度
 * @return 成功返回0，失败或者socket已经断开 < 0
 */
int network_rx(network_ctrl_t *ctrl, uint8_t *data, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, uint32_t *rx_len);

/**
 * 等待网络状态变化
 * 接收到socket异常消息均会返回
 * 如果为阻塞接口，out_event保存消息（拷贝，非引用），is_timeout保存是否超时
 * 返回0表示有数据接收或者超时返回，返回1表示切换到非阻塞等待，其他为网络异常
 * @param ctrl 网络资源
 * @param out_event 网络消息
 * @param timeout_ms 超时时间
 * @param is_timeout 是否超时
 * @return 成功返回0，失败 < 0，非阻塞需要等待返回1
 */
int network_wait_event(network_ctrl_t *ctrl, OS_EVENT *out_event, uint32_t timeout_ms, uint8_t *is_timeout);

/*

 */
/**
 * 等待有数据接收
 * 接收到socket异常，用户发送EV_NW_BREAK_WAIT，或者有新数据都会退出，如果是其他消息，通过network_init_ctrl里输入的回调函数使用，如果没有回调函数，就直接抛弃了
 * timeout_ms=0时，依然为阻塞接口，而且是永远等待
 * 返回0表示有数据接收，用户打断或者超时返回，其他为网络异常
 * 用户打断，is_break = 1，超时 is_timeout = 1
 * @param ctrl 网络资源
 * @param timeout_ms 超时时间
 * @param is_break 是否是用户打断
 * @param is_timeout 是否超时
 * @return 成功返回0，失败 < 0
 */
int network_wait_rx(network_ctrl_t *ctrl, uint32_t timeout_ms, uint8_t *is_break, uint8_t *is_timeout);
/****************************高级api结束********************************************************************/

/**
 * 获取网卡完整的地址信息
 * @param ctrl 网络资源，如果写NULL，则看下面的adapter_index
 * @param adapter_index 网卡适配器序号 NW_ADAPTER_INDEX_XXX
 * @param ip IPV4地址
 * @param submask 子网掩码
 * @param gateway 网关
 * @param ipv6 IPV6地址
 * @return 成功返回0，其他失败
 */
int network_get_full_local_ip_info(network_ctrl_t *ctrl, uint8_t adapter_index, luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6);

/**
 * 将IP设置成无效状态
 * @param ip
 */
void network_set_ip_invaild(luat_ip_addr_t *ip);

/**
 * 检测IP是不是无效的
 * @param ip
 * @return 无效返回0，其他有效
 */
uint8_t network_ip_is_vaild(luat_ip_addr_t *ip);

/**
 * 检测IP是不是IPV6类型
 * @param ip
 * @return 不是返回0
 */
uint8_t network_ip_is_ipv6(luat_ip_addr_t *ip);

/**
 * 检测IP是不是有效的IPV4类型
 * @param ip
 * @return 不是返回0
 */
uint8_t network_ip_is_vaild_ipv4(luat_ip_addr_t *ip);
/**
 * 将IP设置成IPV4
 * @param 需要设置的ip地址
 * @param ipv4 ipv4
 */
void network_set_ip_ipv4(luat_ip_addr_t *ip, uint32_t ipv4);
#endif
// #endif
