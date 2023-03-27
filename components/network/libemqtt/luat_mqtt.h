#ifndef LUAT_MQTT_H
#define LUAT_MQTT_H

#define MQTT_MSG_RELEASE 0
#define MQTT_MSG_TIMER_PING 2
#define MQTT_MSG_RECONNECT  3

#define MQTT_RECV_BUF_LEN_MAX 4096


typedef struct{
	mqtt_broker_handle_t broker;// mqtt broker
	network_ctrl_t *netc;		// mqtt netc
	luat_ip_addr_t ip_addr;		// mqtt ip
	char host[192]; 			// mqtt host
	uint16_t buffer_offset; 	// 用于标识mqtt_packet_buffer当前有多少数据
	uint8_t mqtt_packet_buffer[MQTT_RECV_BUF_LEN_MAX + 4];
	int mqtt_cb;				// mqtt lua回调函数
	uint16_t remote_port; 		// 远程端口号
	uint32_t keepalive;   		// 心跳时长 单位s
	uint8_t adapter_index; 		// 适配器索引号, 似乎并没有什么用
	uint8_t mqtt_state;    		// mqtt状态
	uint8_t reconnect;    		// mqtt是否重连
	uint32_t reconnect_time;    // mqtt重连时间 单位ms
	void* reconnect_timer;		// mqtt重连定时器
	void* ping_timer;			// mqtt_ping定时器
	int mqtt_ref;				// 强制引用自身避免被GC
}luat_mqtt_ctrl_t;

typedef struct{
	uint16_t topic_len;
    uint16_t payload_len;
	uint8_t data[];
}luat_mqtt_msg_t;

typedef struct luat_mqtt_connopts
{
    const char* host;
    uint16_t port;
    uint8_t is_tls;
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


int luat_mqtt_connect(luat_mqtt_ctrl_t *mqtt_ctrl);
// static int luat_mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl);
// int l_mqtt_callback(lua_State *L, void* ptr);
int l_luat_mqtt_msg_cb(luat_mqtt_ctrl_t * ctrl, int arg1, int arg2);
int32_t luat_mqtt_callback(void *data, void *param);
LUAT_RT_RET_TYPE luat_mqtt_timer_callback(LUAT_RT_CB_PARAM);
// int luat_mqtt_read_packet(luat_mqtt_ctrl_t *mqtt_ctrl);
int luat_mqtt_send_packet(void* socket_info, const void* buf, unsigned int count);
void luat_mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl);
void luat_mqtt_release_socket(luat_mqtt_ctrl_t *mqtt_ctrl);

int luat_mqtt_init(luat_mqtt_ctrl_t *mqtt_ctrl, int adapter_index);
int luat_mqtt_set_connopts(luat_mqtt_ctrl_t *mqtt_ctrl, luat_mqtt_connopts_t *opts);

int luat_mqtt_reconnect(luat_mqtt_ctrl_t *mqtt_ctrl);
int luat_mqtt_ping(luat_mqtt_ctrl_t *mqtt_ctrl);
int luat_mqtt_set_will(luat_mqtt_ctrl_t *mqtt_ctrl, const char* topic, 
						const char* payload, size_t payload_len, 
						uint8_t qos, size_t retain);
#endif
