#ifndef __LUAT_NW_ADAPTER_H__
#define __LUAT_NW_ADAPTER_H__
#include "luat_base.h"
#ifdef LUAT_USE_NETWORK
#include "luat_rtos.h"
#include "bsp_common.h"
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
enum
{
	EV_NW_RESET = USER_EVENT_ID_START + 0x1000000,
	EV_NW_SOCKET_TX_OK,
	EV_NW_SOCKET_RX_NEW,
	EV_NW_SOCKET_RX_FULL,
	EV_NW_SOCKET_CLOSE_OK,
	EV_NW_SOCKET_REMOTE_CLOSE,
	EV_NW_SOCKET_CONNECT_OK,
	EV_NW_SOCKET_DNS_RESULT,
	EV_NW_SOCKET_ERROR,
	EV_NW_SOCKET_LISTEN,
	EV_NW_SOCKET_NEW_CONNECT,	//作为server接收到新的connect，只有允许accept操作的才有，否则直接上报CONNECT_OK
	EV_NW_STATE,

	NW_ADAPTER_INDEX_ETH0 = 0,		//以太网
	NW_ADAPTER_INDEX_STA,			//wifi sta和蜂窝
	NW_ADAPTER_INDEX_AP,			//wifi ap
	NW_ADAPTER_QTY,
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
	uint64_t tx_size;
	uint64_t ack_size;
	uint64_t tag;
#ifdef LUAT_USE_TLS
    mbedtls_ssl_context ssl;          /**< mbed TLS control context. */
    mbedtls_ssl_config config;          /**< mbed TLS configuration context. */
    mbedtls_x509_crt ca_cert;
#endif

	CBFuncEx_t user_callback;
	void *user_data;			//传递给user_callback的pParam
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
    uint8_t adapter_index;
    uint8_t is_tcp;
    uint8_t is_server_mode;
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

/*
 * info内的api必须全部是非阻塞的，并且对socket_id和tag做合法性检查
 * 目前只支持tcp和udp，不支持raw
 */
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

	int (*getsockopt)(int socket_id, uint64_t tag, int level, int optname, void *optval, uint32_t *optlen, void *user_data);
	int (*setsockopt)(int socket_id, uint64_t tag, int level, int optname, const void *optval, uint32_t optlen, void *user_data);
	//非posix的socket，用这个根据实际硬件设置参数
	int (*user_cmd)(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data);

	int (*dns)(const char *url, void *user_data);
	int (*set_dns_server)(uint8_t server_index, luat_ip_addr_t *ip, void *user_data);
	//所有网络消息都是通过cb_fun回调
	void (*socket_set_callback)(CBFuncEx_t cb_fun, void *param, void *user_data);

	char *name;
	int socket_num;
	uint8_t no_accept;
	uint8_t is_posix;
}network_adapter_info;

/****************************以下是通用基础api********************************************************/
/*
 * 在使用任意API前，必须先注册相关的协议栈接口
 */
int network_register_adapter(uint8_t adapter_index, network_adapter_info *info, void *user_data);
/*
 * 注册socket回调接口，调用socket_set_callback传入cb_fun和param
 * 网络消息回调时，第一个参数具体消息，第二个是这里传入的param
 */
void network_set_user_callback(uint8_t adapter_index, CBFuncEx_t cb_fun, void *param);

int network_set_dns_server(uint8_t adapter_index, uint8_t server_index, luat_ip_addr_t *ip);

/*
 * 在使用network_ctrl前，必须先初始化
 * lua调用c时，必须使用非阻塞接口，task_handle，callback，param都不需要
 * 在纯c调用时，如果需要阻塞应用，则必须有task_handle，建议有callback，param，可以等待消息时，同时在callback中处理其他类型的消息
 */
int network_init_ctrl(network_ctrl_t *ctrl, uint8_t adapter_index, HANDLE task_handle, CBFuncEx_t callback, void *param);

/*
 * 设置是tcp还是udp模式，也可以直接改network_ctrl_t中的is_tcp参数
 * 设置必须在socket处于close状态，在进行connect和tls初始之前
 */
int network_set_base_mode(network_ctrl_t *ctrl, uint8_t is_tcp);
/*
 * 检查网络是否已经连接，注意不是socket
 * 返回非0是已连接，可以开始socket操作
 */
uint8_t network_check_ready(network_ctrl_t *ctrl);


//创建一个socket
//成功返回0，失败 < 0
int network_create_soceket(network_ctrl_t *ctrl, uint8_t is_tcp, uint8_t is_ipv6);

//作为client绑定一个port，并连接remote_ip和remote_port对应的server
//成功返回0，失败 < 0
int network_socket_connect(network_ctrl_t *ctrl,uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port);
//作为server绑定一个port，开始监听
//成功返回0，失败 < 0
int network_socket_listen(network_ctrl_t *ctrl,uint16_t local_port);
//作为server接受一个client
//成功返回0，失败 < 0
int network_socket_accept(network_ctrl_t *ctrl,luat_ip_addr_t *remote_ip, uint16_t *remote_port);
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
//成功返回0，失败 < 0
int network_socket_disconnect(network_ctrl_t *ctrl);
//释放掉socket的控制权
//成功返回0，失败 < 0
int network_socket_close(network_ctrl_t *ctrl);
//强行释放掉socket的控制权
//成功返回0，失败 < 0
int network_socket_force_close(network_ctrl_t *ctrl);
//tcp时，不需要remote_ip和remote_port，如果buf为NULL，则返回当前缓存区的数据量，当返回值小于len时说明已经读完了
//udp时，只返回1个block数据，需要多次读直到没有数据为止
//成功返回实际读取的值，失败 < 0
int network_socket_receive(network_ctrl_t *ctrl,uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port);
//tcp时，不需要remote_ip和remote_port
//成功返回0，失败 < 0
int network_socket_send(network_ctrl_t *ctrl,const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port);

int network_getsockopt(network_ctrl_t *ctrl, int level, int optname, void *optval, uint32_t *optlen);
int network_setsockopt(network_ctrl_t *ctrl, int level, int optname, const void *optval, uint32_t optlen);
//非posix的socket，用这个根据实际硬件设置参数
int network_user_cmd(network_ctrl_t *ctrl,  uint32_t cmd, uint32_t value);

int network_dns(network_ctrl_t *ctrl, const char *url);

/****************************通用基础api结束********************************************************/

/****************************tls相关api************************************************************/
/*
 * 给DTLS设置PSK，给UDP加密传输时用的
 */
int network_set_psk_info(network_ctrl_t *ctrl,
		const unsigned char *psk, size_t psk_len,
		const unsigned char *psk_identity, size_t psk_identity_len);

/*
 * TLS设置验证服务器的证书，可以不用
 */
int network_set_server_cert(network_ctrl_t *ctrl, const unsigned char *cert, size_t certLen);
/*
 * TLS设置验证客户端的证书，只有双向认证才需要，而且一般只有金融领域才需要
 */
int network_set_client_cert(network_ctrl_t *ctrl,
		const unsigned char *cert, size_t certLen,
        const unsigned char *pkey, size_t pkeylen,
        const unsigned char *pwd, size_t pwdlen);
/*
 * 获取证书验证结果
 */
int network_cert_verify_result(network_ctrl_t *ctrl);
/*
 * 初始化加密传输
 * verify_mode参考MBEDTLS_SSL_VERIFY_XXX
 */
void network_init_tls(network_ctrl_t *ctrl, int verify_mode);
/*
 * 结束加密传输模式，恢复成正常模式
 */
void network_deinit_tls(network_ctrl_t *ctrl);
/*
 * 加密传输其他非阻塞api和通用api共用，阻塞api和rtos环境相关阻塞api通用，均由api内部做相关处理
 */
/****************************tls相关api结束************************************************************/

/****************************rtos环境相关阻塞api************************************************************/
//所有阻塞状态接口，一旦收到link down，socket close, error之类的消息就会返回错误，如果是timeout，只有wait event会返回成功，其他返回失败

int network_wait_link_up(network_ctrl_t *ctrl, uint32_t timeout_ms);
/*
 * 1.进行ready检测和等待ready
 * 2.有remote_ip则开始连接服务器并等待连接结果
 * 3.没有remote_ip则开始对url进行dns解析，解析完成后对所有ip进行尝试连接直到有个成功或者全部失败
 * 4.如果是加密模式，还要走握手环节，等到握手环节完成后才能返回结果
 * local_port如果为0则api内部自动生成一个
 */
int network_connect(network_ctrl_t *ctrl, uint16_t local_port, const char *url, luat_ip_addr_t *remote_ip, uint16_t remote_port, uint32_t timeout_ms);

int network_listen(network_ctrl_t *ctrl, uint16_t local_port);

void network_close(network_ctrl_t *ctrl);
/*
 * timeout_ms=0时，为非阻塞接口
 */
int network_tx(network_ctrl_t *ctrl, const uint8_t *data, uint32_t len, uint32_t timeout_ms);
/*
 * timeout_ms=0时，为非阻塞接口
 * 实际读到的数据量在read_len里，如果是UDP模式且为server时，需要看remote_ip和remote_port
 */
int network_rx(network_ctrl_t *ctrl, uint8_t *data, uint32_t len, uint32_t *read_len, luat_ip_addr_t *remote_ip, uint16_t *remote_port, uint32_t timeout_ms);

/*
 * 如果event为NULL，则自动处理掉接收到的非socket的event，直到超时，否则收到非socket的event或者正常的socket rx，就返回成功
 */
int network_wait_event(network_ctrl_t *ctrl, OS_EVENT *event, uint32_t timeout_ms, uint8_t *is_timeout);

/****************************rtos环境相关阻塞api结束********************************************************/
#endif
#endif
