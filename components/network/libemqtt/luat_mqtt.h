#ifndef LUAT_MQTT_H
#define LUAT_MQTT_H
#include "luat_network_adapter.h"
/**
 * @defgroup luatos_MQTT  MQTT相关接口
 * @{
 */
#define MQTT_MSG_RELEASE 		0	/**< mqtt 释放资源前回调消息 */
#define MQTT_MSG_TCP_TX_DONE 	1	/**< mqtt tcp发送完成*/
#define MQTT_MSG_TIMER_PING 	2	/**< mqtt ping前回调消息 */
#define MQTT_MSG_RECONNECT  	3	/**< mqtt 重连前回调消息 */
#define MQTT_MSG_CLOSE 			4	/**< mqtt 关闭回调消息(不会再重连) */
#define MQTT_MSG_CON_ERROR 		5
#define MQTT_MSG_TX_ERROR 		6
#define MQTT_MSG_CONACK_ERROR 	7
#define MQTT_MSG_NET_ERROR 		8
#define MQTT_MSG_CONN_TIMEOUT   9	/**< mqtt 连接超时回调消息 */

#define MQTT_ERROR_STATE_SOCKET		-1
#define MQTT_ERROR_STATE_DISCONNECT	-2

#ifndef MQTT_RECV_BUF_LEN_MAX
#if defined(CHIP_EC618) || defined(CHIP_EC718)|| defined(CHIP_EC716)
#define MQTT_RECV_BUF_LEN_MAX (32*1024) ///< MQTT 接收BUFF大小
#else
#define MQTT_RECV_BUF_LEN_MAX 4096 ///< MQTT 接收BUFF大小
#endif
#endif


/**
 * @brief mqtt状态
 */
typedef enum {
	MQTT_STATE_DISCONNECT 			,	/**< mqtt 断开 */
	MQTT_STATE_SCONNECT 			,	/**< mqtt socket连接中 */
	MQTT_STATE_MQTT					,	/**< mqtt socket已连接 mqtt连接中 */
	MQTT_STATE_READY 					/**< mqtt mqtt已连接 */
}LUAT_MQTT_STATE_E;

/**
 * @brief 设置MQTT客户端的配置参数
*/
typedef struct{
	mqtt_broker_handle_t broker;/**< mqtt broker*/
	network_ctrl_t *netc;		/**< mqtt netc*/
	luat_ip_addr_t ip_addr;		/**<mqtt ip*/
	char host[192]; 			/**<mqtt host*/
	uint32_t buffer_offset; 	/**< 用于标识mqtt_packet_buffer当前有多少数据*/
	uint32_t rxbuff_size; 		/**< mqtt_packet_buffer的长度*/
	uint8_t *mqtt_packet_buffer;/**< 接收BUFF*/
	void* mqtt_cb;			/**< mqtt 回调函数*/
	void* app_cb;				/**< mqtt 特殊应用回调，数据收发不再会调用到lua层*/
	int8_t error_state;    		/**< mqtt 错误状态*/
	uint16_t remote_port; 		/**< 远程端口号*/
	uint32_t keepalive;   		/**< 心跳时长 单位s*/
	uint8_t adapter_index; 		/**< 适配器索引号, 似乎并没有什么用*/
	LUAT_MQTT_STATE_E mqtt_state;    		/**< mqtt状态*/
	uint8_t reconnect;    		/**< mqtt是否重连*/
	uint32_t reconnect_time;    /**< mqtt重连时间 单位ms*/
	void* reconnect_timer;		/**< mqtt重连定时器*/
	void* ping_timer;			/**< mqtt_ping定时器*/
	void* conn_timer;			/**< mqtt连接超时定时器*/
	int mqtt_ref;				/**<  强制引用自身避免被GC*/
	uint16_t conn_timeout;		/**< 连接超时时间，单位秒，默认15秒*/
	void* userdata;				/**< userdata */
}luat_mqtt_ctrl_t;

typedef struct{
	uint16_t topic_len;
	uint16_t message_id;
    uint32_t payload_len;
    uint8_t flags;
	uint8_t data[];
}luat_mqtt_msg_t;

/**
 * @brief 设置MQTT服务端服务器信息、加密信息
*/
typedef struct luat_mqtt_connopts
{
    const char* host;/**< 服务器HOST*/
    uint16_t port;/**< 服务器端口*/
    uint8_t is_tls;/**< 是否采用tls加密*/
	uint8_t is_ipv6;
	uint8_t verify;
    const char* server_cert;
    size_t server_cert_len;
    const char* client_cert;
    size_t client_cert_len;
    const char* client_key;
    size_t client_key_len;
    const char* client_password;
    size_t client_password_len;
	uint16_t conn_timeout; /**< 连接超时时间，单位秒，默认15秒*/
}luat_mqtt_connopts_t;

typedef void (*luat_mqtt_cb_t)(luat_mqtt_ctrl_t *luat_mqtt_ctrl, uint16_t event);
typedef int (*luat_mqtt_app_cb_t)(luat_mqtt_ctrl_t *luat_mqtt_ctrl, uint16_t event);

/**
 *@brief 发起MQTT连接
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return 成功为0，其他值失败
 */
int luat_mqtt_connect(luat_mqtt_ctrl_t *mqtt_ctrl);
// static int luat_mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl);
// int l_mqtt_callback(lua_State *L, void* ptr);
/**
 *@brief MQTT内部回调(用户无需关心)
 *@param ctrl luatos_mqtt对象实例
 *@param arg1 参数1
 *@param arg2 参数2
 *@return 成功为0，其他值失败
 */
int l_luat_mqtt_msg_cb(luat_mqtt_ctrl_t * ctrl, int arg1, int arg2);
/**
 *@brief MQTT报文解析内部回调(用户无需关心)
 *@param data 数据
 *@param param 参数
 *@return 成功为0，其他值失败
 */
int32_t luat_mqtt_callback(void *data, void *param);
/**
 *@brief MQTT定时器内部回调(用户无需关心)
 */
// LUAT_RT_RET_TYPE ping_timer_callback(LUAT_RT_CB_PARAM);
// int luat_mqtt_read_packet(luat_mqtt_ctrl_t *mqtt_ctrl);
/**
 *@brief MQTT报文发送(用户无需关心)
 *@param socket_info socket
 *@param buf 数据
 *@param count 数据大小
 *@return 成功为0，其他值失败
 */
int luat_mqtt_send_packet(void* socket_info, const void* buf, unsigned int count);

/**
 *@brief 关闭MQTT连接，如果设置了自动重连，回重新自动连接
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return 成功为0，其他值失败
 */
void luat_mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl);

/**
 *@brief 获取MQTT连接状态
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return LUAT_MQTT_STATE_E
 */
LUAT_MQTT_STATE_E luat_mqtt_state_get(luat_mqtt_ctrl_t *mqtt_ctrl);

/**
 *@brief 释放MQTT资源，释放后luatos_mqtt对象不可用
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return 成功为0，其他值失败
 */
void luat_mqtt_release_socket(luat_mqtt_ctrl_t *mqtt_ctrl);

/**
 *@brief 初始化luatos_mqtt(初始化MQTT)
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param adapter_index 网卡类型(唯一值 NW_ADAPTER_INDEX_LWIP_GPRS)
 *@return 成功为0，其他值失败
 */
int luat_mqtt_init(luat_mqtt_ctrl_t *mqtt_ctrl, int adapter_index);

/**
 *@brief 设置MQTT服务器信息、加密信息函数
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param opts 结构体MQTT服务器信息、加密信息函数
 *@return 成功为0，其他值失败
 */
int luat_mqtt_set_connopts(luat_mqtt_ctrl_t *mqtt_ctrl, luat_mqtt_connopts_t *opts);

/**
 *@brief 设置MQTT服务器三元组信息
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param clientid clientid
 *@param username username
 *@param password password
 *@return 成功为0，其他值失败
 */
int luat_mqtt_set_triad(luat_mqtt_ctrl_t *mqtt_ctrl, const char* clientid, const char* username, const char* password);

/**
 *@brief 设置MQTT服务器接收buff大小
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param rxbuff_size 接收buff大小
 *@return 成功为0，其他值失败
 */
int luat_mqtt_set_rxbuff_size(luat_mqtt_ctrl_t *mqtt_ctrl, uint32_t rxbuff_size);

/**
 *@brief 设置MQTT服务器 心跳时长 
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param keepalive keepalive 单位s
 *@return 成功为0，其他值失败
 */
int luat_mqtt_set_keepalive(luat_mqtt_ctrl_t *mqtt_ctrl, uint32_t keepalive);

/**
 *@brief 设置MQTT服务器 是否自动重连
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param auto_connect 是否自动重连
 *@param reconnect_time 自动重连时间 单位ms
 *@return 成功为0，其他值失败
 */
int luat_mqtt_set_auto_connect(luat_mqtt_ctrl_t *mqtt_ctrl, uint8_t auto_connect,uint32_t reconnect_time);

/**
 *@brief 手动发起重连
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return 成功为0，其他值失败
 */
int luat_mqtt_reconnect(luat_mqtt_ctrl_t *mqtt_ctrl);

/**
 *@brief 发送ping包
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return 成功为0，其他值失败
 */
int luat_mqtt_ping(luat_mqtt_ctrl_t *mqtt_ctrl);

/**
 *@brief 设置遗嘱消息
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param topic 遗嘱消息的topic
 *@param payload 遗嘱消息的payload
 *@param payload_len 遗嘱消息payload的长度
 *@param qos  遗嘱消息的qos
 *@param retain 遗嘱消息的retain
 *@return 成功为0，其他值失败
 */
int luat_mqtt_set_will(luat_mqtt_ctrl_t *mqtt_ctrl, const char* topic, const char* payload, size_t payload_len, uint8_t qos, size_t retain);
/**
 *@brief 设置MQTT事件回调函数
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param mqtt_cb 回调函数
 *@return 成功为0，其他值失败
 */
int luat_mqtt_set_cb(luat_mqtt_ctrl_t *mqtt_ctrl, luat_mqtt_cb_t mqtt_cb);
/** @}*/
#endif
