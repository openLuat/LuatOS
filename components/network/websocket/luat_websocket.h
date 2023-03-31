#ifndef LUAT_WEBSOCKET_H
#define LUAT_WEBSOCKET_H

enum
{
	WEBSOCKET_MSG_RELEASE = 0,
	WEBSOCKET_MSG_PUBLISH = 1,
	WEBSOCKET_MSG_TIMER_PING = 2,
	WEBSOCKET_MSG_CONNACK = 3,
	WEBSOCKET_MSG_RECONNECT = 4,
	WEBSOCKET_MSG_SENT = 5,
	WEBSOCKET_MSG_DISCONNECT = 6
};

#define WEBSOCKET_RECV_BUF_LEN_MAX 4096

typedef struct
{
	// http_parser parser;// websocket broker
	network_ctrl_t *netc;	// websocket netc
	luat_ip_addr_t ip_addr; // websocket ip
	char host[192]; // websocket host
	char uri[256];
	uint8_t is_tls;
	uint16_t remote_port; // 远程端口号
	uint16_t buffer_offset; // 用于标识pkg_buff当前有多少数据
	uint8_t pkg_buff[WEBSOCKET_RECV_BUF_LEN_MAX + 4];
	int websocket_cb;		 // websocket lua回调函数
	uint32_t keepalive;		 // 心跳时长 单位s
	uint8_t adapter_index;	 // 适配器索引号, 似乎并没有什么用
	uint8_t websocket_state; // websocket状态
	uint8_t reconnect;		 // websocket是否重连
	uint32_t reconnect_time; // websocket重连时间 单位ms
	void *reconnect_timer;	 // websocket重连定时器
	void *ping_timer;		 // websocket_ping定时器
	int websocket_ref;		 // 强制引用自身避免被GC
	char* headers;
	int frame_wait;
} luat_websocket_ctrl_t;

typedef struct luat_websocket_connopts
{
	const char *url;
	uint16_t is_tls;
} luat_websocket_connopts_t;

typedef struct luat_websocket_pkg
{
	uint8_t FIN;
	uint8_t OPT_CODE;
	uint8_t R;
	uint8_t mark;
	uint16_t plen; // 最多支持64k
	char *payload;
} luat_websocket_pkg_t;

#define WebSocket_OP_CONTINUE 0x0 /* 0000 - continue frame */
#define WebSocket_OP_TEXT 0x1	  /* 0001 - text frame */
#define WebSocket_OP_BINARY 0x2	  /* 0010 - binary frame */
#define WebSocket_OP_CLOSE 0x8	  /* 1000 - close frame */
#define WebSocket_OP_PING 0x9	  /* 1001 - ping frame */
#define WebSocket_OP_PONG 0xA	  /* 1010 - pong frame */

int luat_websocket_connect(luat_websocket_ctrl_t *websocket_ctrl);
int l_luat_websocket_msg_cb(luat_websocket_ctrl_t *ctrl, int arg1, int arg2);
int32_t luat_websocket_callback(void *data, void *param);
int luat_websocket_send_packet(void *socket_info, const void *buf, unsigned int count);
void luat_websocket_close_socket(luat_websocket_ctrl_t *websocket_ctrl);
void luat_websocket_release_socket(luat_websocket_ctrl_t *websocket_ctrl);
void luat_websocket_ping(luat_websocket_ctrl_t *websocket_ctrl);
void luat_websocket_reconnect(luat_websocket_ctrl_t *websocket_ctrl);
int luat_websocket_init(luat_websocket_ctrl_t *websocket_ctrl, int adapter_index);
int luat_websocket_set_connopts(luat_websocket_ctrl_t *websocket_ctrl, const char *url);
int luat_websocket_payload(char *buff, luat_websocket_pkg_t *pkg, size_t limit);
int luat_websocket_send_frame(luat_websocket_ctrl_t *websocket_ctrl, luat_websocket_pkg_t *pkg);
int luat_websocket_set_headers(luat_websocket_ctrl_t *websocket_ctrl, const char *headers);
#endif
