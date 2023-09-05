#ifndef LUAT_MQTT_H
#define LUAT_MQTT_H
/**
 * @defgroup luatos_MQTT  MQTT相关接口
 * @{
 */
#define MQTT_MSG_RELEASE 		0
#define MQTT_MSG_TIMER_PING 	2
#define MQTT_MSG_RECONNECT  	3
#define MQTT_MSG_CLOSE 			4

#ifdef CHIP_EC618
#define MQTT_RECV_BUF_LEN_MAX 8192 ///< MQTT 接收BUFF大小
#else
#define MQTT_RECV_BUF_LEN_MAX 4096 ///< MQTT 接收BUFF大小
#endif

/**
 * @brief 设置MQTT客户端的配置参数
*/
typedef struct{
	mqtt_broker_handle_t broker;/**< mqtt broker*/
	network_ctrl_t *netc;		/**< mqtt netc*/
	luat_ip_addr_t ip_addr;		/**<mqtt ip*/
	char host[192]; 			/**<mqtt host*/
	uint16_t buffer_offset; 	/**< 用于标识mqtt_packet_buffer当前有多少数据*/
	uint8_t mqtt_packet_buffer[MQTT_RECV_BUF_LEN_MAX + 4];/**< 接收BUFF*/
	int mqtt_cb;			/**< mqtt 回调函数*/
	uint16_t remote_port; 		/**< 远程端口号*/
	uint32_t keepalive;   		/**< 心跳时长 单位s*/
	uint8_t adapter_index; 		/**< 适配器索引号, 似乎并没有什么用*/
	uint8_t mqtt_state;    		/**< mqtt状态*/
	uint8_t reconnect;    		/**< mqtt是否重连*/
	uint32_t reconnect_time;    /**< mqtt重连时间 单位ms*/
	void* reconnect_timer;		/**< mqtt重连定时器*/
	void* ping_timer;			/**< mqtt_ping定时器*/
	int mqtt_ref;				/**<  强制引用自身避免被GC*/
	void* userdata;				/**< userdata */
}luat_mqtt_ctrl_t;

typedef struct{
	uint16_t topic_len;
    uint16_t payload_len;
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
}luat_mqtt_connopts_t;

typedef void (*luat_mqtt_cb_t)(luat_mqtt_ctrl_t *luat_mqtt_ctrl, uint16_t event);
/**
 *@brief 发起MQTT连接
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return 成功为0，其他值失败
 */
int luat_mqtt_connect(luat_mqtt_ctrl_t *mqtt_ctrl);
// static int luat_mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl);
// int l_mqtt_callback(lua_State *L, void* ptr);
int l_luat_mqtt_msg_cb(luat_mqtt_ctrl_t * ctrl, int arg1, int arg2);
int32_t luat_mqtt_callback(void *data, void *param);
LUAT_RT_RET_TYPE luat_mqtt_timer_callback(LUAT_RT_CB_PARAM);
// int luat_mqtt_read_packet(luat_mqtt_ctrl_t *mqtt_ctrl);
int luat_mqtt_send_packet(void* socket_info, const void* buf, unsigned int count);
/**
 *@brief 关闭MQTT连接，如果设置了自动重连，回重新自动连接
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return 成功为0，其他值失败
 */
void luat_mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl);
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
 *@brief 设置MQTT服务器信息、加密信息函数
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@param opts 结构体MQTT服务器信息、加密信息函数
 *@return 成功为0，其他值失败
 */

/**
 *@brief 手动发起重连
 *@param mqtt_ctrl luatos_mqtt对象实例
 *@return 成功为0，其他值失败
 */
int luat_mqtt_reconnect(luat_mqtt_ctrl_t *mqtt_ctrl);
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
