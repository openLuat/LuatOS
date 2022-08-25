
#include "luat_base.h"

#include "luat_network_adapter.h"
#include "libemqtt.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "mqtt"
#include "luat_log.h"

#define MQTT_RECV_BUF_LEN_MAX 4096
typedef struct
{
	mqtt_broker_handle_t *broker; // TODO 这里没必要分开malloc
	network_ctrl_t *netc;
	luat_ip_addr_t *ip_addr;
	const char *host; 
	uint16_t buffer_offset; // 用于标识mqtt_packet_buffer当前有多少数据
	uint8_t mqtt_packet_buffer[MQTT_RECV_BUF_LEN_MAX + 4];
	uint8_t mqtt_id; // 对应mqtt_cbs的索引, TODO, 既然要存function的ref_id, 为啥不直接存呢
	uint16_t remote_port; // 远程端口号
	uint32_t keepalive;   // 心跳时长 单位s
	uint8_t adapter_index; // 适配器索引号, 似乎并没有什么用
	uint8_t mqtt_state;    // mqtt状态
	uint8_t reconnect;    // mqtt是否重连
	uint8_t reconnect_time;    // mqtt重连时间 单位ms
	void* reconnect_timer;		// mqtt重连定时器
	// TODO 记录最后一次数据交互的时间,方便判断是否真的发送ping请求
}luat_mqtt_ctrl_t;

#define MAX_MQTT_COUNT 32
static int mqtt_cbs[MAX_MQTT_COUNT];
static uint8_t mqtt_id = 0;

#define LUAT_MQTT_CTRL_TYPE "MQTTCTRL*"

typedef struct
{
	uint16_t topic_len;
    uint16_t payload_len;
	uint8_t data[];
}luat_mqtt_msg_t;

static int luat_socket_connect(luat_mqtt_ctrl_t *mqtt_ctrl, const char *hostname, uint16_t port, uint16_t keepalive);
static void mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl);
static int mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl);

static luat_mqtt_ctrl_t * get_mqtt_ctrl(lua_State *L){
	if (luaL_testudata(L, 1, LUAT_MQTT_CTRL_TYPE)){
		return ((luat_mqtt_ctrl_t *)luaL_checkudata(L, 1, LUAT_MQTT_CTRL_TYPE));
	}else{
		return ((luat_mqtt_ctrl_t *)lua_touserdata(L, 1));
	}
}

static void reconnect_timer_cb(void *data, void *param){
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)param;
	int ret = network_wait_link_up(mqtt_ctrl->netc, 0);
	if (ret == 0){
		int ret = luat_socket_connect(mqtt_ctrl, mqtt_ctrl->host, mqtt_ctrl->remote_port, mqtt_ctrl->keepalive);
		if(ret){
			LLOGD("init_socket ret=%d\n", ret);
			mqtt_close_socket(mqtt_ctrl);
		}
	}
}

static void mqtt_reconnect(luat_mqtt_ctrl_t *mqtt_ctrl){
	if (mqtt_ctrl->reconnect){
		mqtt_ctrl->reconnect_timer = luat_create_rtos_timer(reconnect_timer_cb, mqtt_ctrl, NULL);
		luat_start_rtos_timer(mqtt_ctrl->reconnect_timer, mqtt_ctrl->reconnect_time, 0);
	}
}

static void mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl){
	if (mqtt_ctrl->netc){
		network_force_close_socket(mqtt_ctrl->netc);
	}
	mqtt_reconnect(mqtt_ctrl);
}

static void mqtt_release_socket(luat_mqtt_ctrl_t *mqtt_ctrl){
	if (mqtt_ctrl->netc){
		network_release_ctrl(mqtt_ctrl->netc);
    	mqtt_ctrl->netc = NULL;
	}
	if (mqtt_ctrl->broker){
		luat_heap_free(mqtt_ctrl->broker);
	}
	if (mqtt_ctrl->ip_addr){
		luat_heap_free(mqtt_ctrl->ip_addr);
	}
	if (mqtt_ctrl->host){
		luat_heap_free(mqtt_ctrl->host);
	}
}

static int mqtt_parse(luat_mqtt_ctrl_t *mqtt_ctrl) {
	if (mqtt_ctrl->buffer_offset < 2) {
		LLOGD("wait more data");
		return 0;
	}
	mqtt_ctrl->mqtt_packet_buffer[mqtt_ctrl->buffer_offset] = 0x00;
	// 判断数据长度, 前几个字节能判断出够不够读出mqtt的头
	uint8_t rem_len_bytes = mqtt_num_rem_len_bytes(mqtt_ctrl->mqtt_packet_buffer);
	if (rem_len_bytes > mqtt_ctrl->buffer_offset - 1) {
		LLOGD("wait more data for mqtt head");
		return 0;
	}
	// 判断数据总长, 这里rem_len只包含mqtt头部之外的数据
	uint16_t rem_len = mqtt_parse_rem_len(mqtt_ctrl->mqtt_packet_buffer);
	if (rem_len > mqtt_ctrl->buffer_offset - rem_len_bytes - 1) {
		LLOGD("wait more data for mqtt head");
		return 0;
	}
	// 至此, mqtt包是完整的 解析类型, 处理之
	int ret = mqtt_msg_cb(mqtt_ctrl);
	if (ret!=0){
		return -1;
	}
	// 处理完成后, 如果还有数据, 移动数据, 继续处理
	mqtt_ctrl->buffer_offset -= (1 + rem_len_bytes + rem_len);
	memmove(mqtt_ctrl->mqtt_packet_buffer, mqtt_ctrl->mqtt_packet_buffer+1 + rem_len_bytes + rem_len, mqtt_ctrl->buffer_offset);
	return 1;
}

static int mqtt_read_packet(luat_mqtt_ctrl_t *mqtt_ctrl){
	// LLOGD("mqtt_read_packet mqtt_ctrl->buffer_offset:%d",mqtt_ctrl->buffer_offset);
	int ret = -1;
	uint8_t *read_buff = NULL;
	uint32_t total_len = 0;
	uint32_t rx_len = 0;
	// 这里获取长度的逻辑貌似没有用了, 还是说network需要先读一次呢?
	int result = network_rx(mqtt_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
	if (total_len > 0xFFF) {
		LLOGE("too many data wait for recv %d", total_len);
		// TODO close socket, clean up mqtt context
		return 0;
	}
	if (total_len == 0) {
		LLOGD("rx event but NO data wait for recv");
		return 0;
	}
	if (MQTT_RECV_BUF_LEN_MAX - mqtt_ctrl->buffer_offset <= 0) {
		LLOGD("buff is FULL, mqtt packet too big");
		// TODO 关闭socket
		return 0;
	}
	#define MAX_READ (1024)
	int recv_want = 0;

	// 读取数据, 直至没有数据可读
	while (MQTT_RECV_BUF_LEN_MAX - mqtt_ctrl->buffer_offset > 0) {
		if (MAX_READ > (MQTT_RECV_BUF_LEN_MAX - mqtt_ctrl->buffer_offset)) {
			recv_want = MQTT_RECV_BUF_LEN_MAX - mqtt_ctrl->buffer_offset;
		}
		else {
			// 
			recv_want = MAX_READ;
		}
		// 从网络接收数据
		result = network_rx(mqtt_ctrl->netc, mqtt_ctrl->mqtt_packet_buffer + mqtt_ctrl->buffer_offset, recv_want, 0, NULL, NULL, &rx_len);
		// TODO 判断 result, 虽然通常没问题
		if (rx_len == 0) {
			break;
		}
		// LLOGD("mqtt_read_packet 1 mqtt_ctrl->buffer_offset:%d",mqtt_ctrl->buffer_offset);
		// 收到数据了, 传给处理函数继续处理
		// 数据的长度变更, 触发传递
		mqtt_ctrl->buffer_offset += rx_len;
further:
		result = mqtt_parse(mqtt_ctrl);
		// LLOGD("mqtt_read_packet 1 mqtt_ctrl->buffer_offset:%d",mqtt_ctrl->buffer_offset);
		if (result == 0) {
			// 处理OK
		}else if(result == 1){
			goto further;
		}
		else {
			mqtt_close_socket(mqtt_ctrl);
			break;
		}
	}
	return 0;
}

static int32_t l_mqtt_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_mqtt_ctrl_t *mqtt_ctrl =(luat_mqtt_ctrl_t *)msg->ptr;
    switch (msg->arg1) {
		case MQTT_MSG_PUBLISH : {
			luat_mqtt_msg_t *mqtt_msg =(luat_mqtt_msg_t *)msg->arg2;
			if (mqtt_cbs[mqtt_ctrl->mqtt_id]) {
				luat_mqtt_msg_t *mqtt_msg =(luat_mqtt_msg_t *)msg->arg2;
				lua_geti(L, LUA_REGISTRYINDEX, mqtt_cbs[mqtt_ctrl->mqtt_id]);
				if (lua_isfunction(L, -1)) {
					lua_pushlightuserdata(L, mqtt_ctrl);
					lua_pushstring(L, "recv");
					lua_pushlstring(L, mqtt_msg->data,mqtt_msg->topic_len);
					lua_pushlstring(L, mqtt_msg->data+mqtt_msg->topic_len,mqtt_msg->payload_len);
					lua_call(L, 4, 0);
				}
            }
			luat_heap_free(mqtt_msg);
            break;
        }
        case MQTT_MSG_CONNACK: {
			if (mqtt_cbs[mqtt_ctrl->mqtt_id]) {
				lua_geti(L, LUA_REGISTRYINDEX, mqtt_cbs[mqtt_ctrl->mqtt_id]);
				if (lua_isfunction(L, -1)) {
					lua_pushlightuserdata(L, mqtt_ctrl);
					lua_pushstring(L, "conack");
					lua_call(L, 2, 0);
				}
				lua_getglobal(L, "sys_pub");
				if (lua_isfunction(L, -1)) {
					lua_pushstring(L, "MQTT_CONNACK");
					lua_pushlightuserdata(L, mqtt_ctrl);
					lua_call(L, 2, 0);
				}
            }
            break;
        }
		case MQTT_MSG_PUBACK:
		case MQTT_MSG_PUBCOMP: {
			if (mqtt_cbs[mqtt_ctrl->mqtt_id]) {
				lua_geti(L, LUA_REGISTRYINDEX, mqtt_cbs[mqtt_ctrl->mqtt_id]);
				if (lua_isfunction(L, -1)) {
					lua_pushlightuserdata(L, mqtt_ctrl);
					lua_pushstring(L, "sent");
					// TODO 需要解出pkgid,作为参数传过去
					lua_call(L, 2, 0);
				}
            }
            break;
        }
		default : {
			LLOGD("l_mqtt_callback error arg1:%d",msg->arg1);
            break;
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}

static int mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl) {
	rtos_msg_t msg = {0};
    msg.handler = l_mqtt_callback;
    uint8_t msg_tp = MQTTParseMessageType(mqtt_ctrl->mqtt_packet_buffer);
    switch (msg_tp) {
		case MQTT_MSG_CONNECT : {
			LLOGD("MQTT_MSG_CONNECT");
			break;
		}
		case MQTT_MSG_CONNACK: {
			LLOGD("MQTT_MSG_CONNACK");
			if(mqtt_ctrl->mqtt_packet_buffer[3] != 0x00){
                mqtt_close_socket(mqtt_ctrl);
                return -2;
            }
			mqtt_ctrl->mqtt_state = 1;
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_CONNACK;
			luat_msgbus_put(&msg, 0);
            break;
        }
        case MQTT_MSG_PUBLISH : {
			LLOGD("MQTT_MSG_PUBLISH");
			const uint8_t* ptr;
			uint16_t topic_len = mqtt_parse_pub_topic_ptr(mqtt_ctrl->mqtt_packet_buffer, &ptr);
			uint16_t payload_len = mqtt_parse_pub_msg_ptr(mqtt_ctrl->mqtt_packet_buffer, &ptr);
			luat_mqtt_msg_t *mqtt_msg = (luat_mqtt_msg_t *)luat_heap_malloc(sizeof(luat_mqtt_msg_t)+topic_len+payload_len);
			mqtt_msg->topic_len = mqtt_parse_pub_topic(mqtt_ctrl->mqtt_packet_buffer, mqtt_msg->data);
            mqtt_msg->payload_len = mqtt_parse_publish_msg(mqtt_ctrl->mqtt_packet_buffer, mqtt_msg->data+topic_len);
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_PUBLISH;
			msg.arg2 = mqtt_msg;
			luat_msgbus_put(&msg, 0);
            break;
        }
        case MQTT_MSG_PUBACK : {
			LLOGD("MQTT_MSG_PUBACK");
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_PUBACK;
			luat_msgbus_put(&msg, 0);
			break;
		}
		case MQTT_MSG_PUBREC : {
			uint16_t msg_id=mqtt_parse_msg_id(mqtt_ctrl->broker);
			mqtt_pubrel(mqtt_ctrl->broker, msg_id);
			LLOGD("MQTT_MSG_PUBREC");
			break;
		}
		case MQTT_MSG_PUBCOMP : {
			LLOGD("MQTT_MSG_PUBCOMP");
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_PUBCOMP;
			luat_msgbus_put(&msg, 0);
			break;
		}
		case MQTT_MSG_SUBSCRIBE : {
			LLOGD("MQTT_MSG_SUBSCRIBE");
            break;
        }
        case MQTT_MSG_SUBACK : {
			LLOGD("MQTT_MSG_SUBACK");
            break;
        }
		case MQTT_MSG_UNSUBSCRIBE : {
			LLOGD("MQTT_MSG_UNSUBSCRIBE");
            break;
        }
		case MQTT_MSG_UNSUBACK : {
			LLOGD("MQTT_MSG_UNSUBACK");
            break;
        }
		case MQTT_MSG_PINGREQ : {
			LLOGD("MQTT_MSG_PINGREQ");
            break;
        }
        case MQTT_MSG_PINGRESP : {
			LLOGD("MQTT_MSG_PINGRESP");
            break;
        }
		case MQTT_MSG_DISCONNECT : {
			LLOGD("MQTT_MSG_DISCONNECT");
            break;
        }
        default : {
			LLOGD("mqtt_msg_cb error msg_tp:%d",msg_tp);
            break;
        }
    }
    return 0;
}

static int32_t luat_lib_mqtt_callback(void *data, void *param){
	OS_EVENT *event = (OS_EVENT *)data;
	luat_mqtt_ctrl_t *mqtt_ctrl =(luat_mqtt_ctrl_t *)param;
	int ret = 0;
	LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	LLOGD("luat_lib_mqtt_callback %d %d",event->ID & 0x0fffffff,event->Param1);
	if (event->ID == EV_NW_RESULT_LINK){
		int ret = luat_socket_connect(mqtt_ctrl, mqtt_ctrl->host, mqtt_ctrl->remote_port, mqtt_ctrl->keepalive);
		if(ret){
			LLOGD("init_socket ret=%d\n", ret);
		}
	}else if(event->ID == EV_NW_RESULT_CONNECT){
		mqtt_connect(mqtt_ctrl->broker);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		if (event->Param1==0){
			ret = mqtt_read_packet(mqtt_ctrl);
			LLOGD("mqtt_read_packet ret:%d",ret);
		}
	}else if(event->ID == EV_NW_RESULT_TX){
		
	}else if(event->ID == EV_NW_RESULT_CLOSE){

	}
	if (event->Param1){
		mqtt_close_socket(mqtt_ctrl);
	}
	network_wait_event(mqtt_ctrl->netc, NULL, 0, NULL);
    return 0;
}

static int mqtt_send_packet(void* socket_info, const void* buf, unsigned int count){
    luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)socket_info;
	uint32_t tx_len = 0;
	network_tx(mqtt_ctrl->netc, buf, count, 0, mqtt_ctrl->ip_addr->is_ipv6?NULL:&(mqtt_ctrl->ip_addr), NULL, &tx_len, 0);
	// TODO 判断network_tx的返回值
	return 0;
}

static int luat_socket_connect(luat_mqtt_ctrl_t *mqtt_ctrl, const char *hostname, uint16_t port, uint16_t keepalive){
	if(network_connect(mqtt_ctrl->netc, hostname, strlen(hostname), mqtt_ctrl->ip_addr->is_ipv6?NULL:&(mqtt_ctrl->ip_addr), port, 0) < 0){
        network_close(mqtt_ctrl->netc, 0);
        return -1;
    }
    mqtt_set_alive(mqtt_ctrl->broker, keepalive);
    mqtt_ctrl->broker->socket_info = mqtt_ctrl;
    mqtt_ctrl->broker->send = mqtt_send_packet;
    return 0;
}

static int l_mqtt_subscribe(lua_State *L) {
	size_t len = 0;
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	if (lua_isstring(L, 2)){
		const char * topic = luaL_checklstring(L, 2, &len);
		uint8_t qos = luaL_optinteger(L, 3, 0);
		int subscribe_state = mqtt_subscribe(mqtt_ctrl->broker, topic, NULL,qos);
	}else if(lua_istable(L, 2)){
		lua_pushnil(L);
		while (lua_next(L, 2) != 0) {
		mqtt_subscribe(mqtt_ctrl->broker, lua_tostring(L, -2), NULL,luaL_optinteger(L, -1, 0));
		lua_pop(L, 1);
		}
	}
	return 0;
}

static int l_mqtt_unsubscribe(lua_State *L) {
	size_t len = 0;
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	if (lua_isstring(L, 2)){
		const char * topic = luaL_checklstring(L, 2, &len);
		int subscribe_state = mqtt_unsubscribe(mqtt_ctrl->broker, topic, NULL);
	}else if(lua_istable(L, 2)){
		size_t count = lua_rawlen(L, 2);
		for (size_t i = 1; i <= count; i++){
			lua_geti(L, 2, i);
			const char * topic = luaL_checklstring(L, -1, &len);
			mqtt_unsubscribe(mqtt_ctrl->broker, topic, NULL);
			lua_pop(L, 1);
		}
	}
	return 0;
}

static int l_mqtt_create(lua_State *L) {
	size_t client_cert_len, client_key_len, client_password_len;
	const char *client_cert = NULL;
	const char *client_key = NULL;
	const char *client_password = NULL;
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY){
		return 0;
	}
	luat_mqtt_ctrl_t *mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_newuserdata(L, sizeof(luat_mqtt_ctrl_t));
	if (!mqtt_ctrl){
		return 0;
	}
	memset(mqtt_ctrl, 0, sizeof(luat_mqtt_ctrl_t));
	mqtt_ctrl->adapter_index = adapter_index;
	mqtt_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!mqtt_ctrl->netc){
		LLOGD("create fail");
		return 0;
	}
	network_init_ctrl(mqtt_ctrl->netc, NULL, luat_lib_mqtt_callback, mqtt_ctrl);

	mqtt_ctrl->mqtt_id = mqtt_id++;

	mqtt_ctrl->mqtt_state = 0;
	mqtt_ctrl->netc->is_debug = 1;
	mqtt_ctrl->keepalive = 240;
	network_set_base_mode(mqtt_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(mqtt_ctrl->netc, 0);
	uint8_t is_tls = 0;
	if (lua_isboolean(L, 4)){
		is_tls = lua_toboolean(L, 4);
	}
	if (lua_isstring(L, 5)){
		client_cert = luaL_checklstring(L, 5, &client_cert_len);
	}
	if (lua_isstring(L, 6)){
		client_key = luaL_checklstring(L, 6, &client_key_len);
	}
	if (lua_isstring(L, 7)){
		client_password = luaL_checklstring(L, 7, &client_password_len);
	}
	if (is_tls){
		network_init_tls(mqtt_ctrl->netc, client_cert?2:0);
		if (client_cert){
			network_set_client_cert(mqtt_ctrl->netc, client_cert, client_cert_len,
					client_key, client_key_len,
					client_password, client_password_len);
		}
	}else{
		network_deinit_tls(mqtt_ctrl->netc);
	}
	int packet_length = 0;
	uint16_t msg_id = 0, msg_id_rcv = 0;
	mqtt_ctrl->broker = (mqtt_broker_handle_t *)luat_heap_malloc(sizeof(mqtt_broker_handle_t));
	const char *ip;
	size_t ip_len = 0;
	mqtt_ctrl->ip_addr = (luat_ip_addr_t *)luat_heap_malloc(sizeof(luat_ip_addr_t));
	mqtt_ctrl->ip_addr->is_ipv6 = 0xff;
	if (lua_isinteger(L, 2)){
		mqtt_ctrl->ip_addr->is_ipv6 = 0;
		mqtt_ctrl->ip_addr->ipv4 = lua_tointeger(L, 2);
		ip = NULL;
		ip_len = 0;
	}else{
		ip_len = 0;
		ip = luaL_checklstring(L, 2, &ip_len);
	}
	mqtt_ctrl->host = luat_heap_malloc(ip_len + 1);
	memset(mqtt_ctrl->host, 0, ip_len + 1);
	memcpy(mqtt_ctrl->host, ip, ip_len);
	mqtt_ctrl->remote_port = luaL_checkinteger(L, 3);
	luaL_setmetatable(L, LUAT_MQTT_CTRL_TYPE);
	return 1;
}

static int l_mqtt_auth(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	const char *client_id = luaL_checkstring(L, 2);
	const char *username = luaL_optstring(L, 3, "");
	const char *password = luaL_optstring(L, 4, "");
	mqtt_init(mqtt_ctrl->broker, client_id);
	mqtt_init_auth(mqtt_ctrl->broker, username, password);
	return 0;
}

static int l_mqtt_keepalive(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	mqtt_ctrl->keepalive = luaL_optinteger(L, 2, 240);
	return 0;
}

static int l_mqtt_on(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	if (mqtt_cbs[mqtt_ctrl->mqtt_id] != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, mqtt_cbs[mqtt_ctrl->mqtt_id]);
		mqtt_cbs[mqtt_ctrl->mqtt_id] = 0;
	}
	if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		mqtt_cbs[mqtt_ctrl->mqtt_id] = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	return 0;
}

static int l_mqtt_connect(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	int ret = network_wait_link_up(mqtt_ctrl->netc, 0);
	if (ret == 0){
		int ret = luat_socket_connect(mqtt_ctrl, mqtt_ctrl->host, mqtt_ctrl->remote_port, mqtt_ctrl->keepalive);
		if(ret){
			LLOGD("init_socket ret=%d\n", ret);
			mqtt_close_socket(mqtt_ctrl);
		}
	}
	return 0;
}

static int l_mqtt_reconnect(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	if (lua_isboolean(L, 2)){
		mqtt_ctrl->reconnect = lua_toboolean(L, 2);
	}
	mqtt_ctrl->reconnect_time = luaL_optinteger(L, 3, 3000);
	return 0;
}

static int l_mqtt_publish(lua_State *L) {
	uint16_t message_id = 0;
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	const char * topic = luaL_checkstring(L, 2);
	const char * payload = luaL_checkstring(L, 3);
	uint8_t qos = luaL_optinteger(L, 4, 0);
	uint8_t retain = luaL_optinteger(L, 5, 0);
	int ret = mqtt_publish_with_qos(mqtt_ctrl->broker, topic, payload, retain, qos, &message_id);
	if (ret!=1){
		return 0;
	}
	if (qos == 0){
		rtos_msg_t msg = {0};
    	msg.handler = l_mqtt_callback;
		msg.ptr = mqtt_ctrl;
		msg.arg1 = MQTT_MSG_PUBACK;
		luat_msgbus_put(&msg, 0);
	}
	lua_pushinteger(L, message_id);
	return 1;
}

static int l_mqtt_ping(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	mqtt_ping(mqtt_ctrl->broker);
	return 0;
}

static int l_mqtt_close(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	mqtt_disconnect(mqtt_ctrl->broker);
	mqtt_close_socket(mqtt_ctrl);
	mqtt_release_socket(mqtt_ctrl);
	return 0;
}

static int l_mqtt_ready(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	lua_pushboolean(L, mqtt_ctrl->mqtt_state);
	return 1;
}
static int _mqtt_struct_newindex(lua_State *L);


void luat_mqtt_struct_init(lua_State *L) {
    luaL_newmetatable(L, LUAT_MQTT_CTRL_TYPE);
    lua_pushcfunction(L, _mqtt_struct_newindex);
    lua_setfield( L, -2, "__index" );
    lua_pop(L, 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_mqtt[] =
{
	{"create",			ROREG_FUNC(l_mqtt_create)},
	{"auth",			ROREG_FUNC(l_mqtt_auth)},
	{"keepalive",		ROREG_FUNC(l_mqtt_keepalive)},
	{"on",				ROREG_FUNC(l_mqtt_on)},
	{"connect",			ROREG_FUNC(l_mqtt_connect)},
	{"reconnect",		ROREG_FUNC(l_mqtt_reconnect)},
	{"publish",			ROREG_FUNC(l_mqtt_publish)},
	{"subscribe",		ROREG_FUNC(l_mqtt_subscribe)},
	{"unsubscribe",		ROREG_FUNC(l_mqtt_unsubscribe)},
	{"ping",			ROREG_FUNC(l_mqtt_ping)},
	{"close",			ROREG_FUNC(l_mqtt_close)},
	{"ready",			ROREG_FUNC(l_mqtt_ready)},

	{ NULL,             ROREG_INT(0)}
};

static int _mqtt_struct_newindex(lua_State *L) {
	rotable_Reg_t* reg = reg_mqtt;
    const char* key = luaL_checkstring(L, 2);
	while (1) {
		if (reg->name == NULL)
			return 0;
		if (!strcmp(reg->name, key)) {
			lua_pushcfunction(L, reg->value.value.func);
			return 1;
		}
		reg ++;
	}
    //return 0;
}

LUAMOD_API int luaopen_mqtt( lua_State *L ) {
    luat_newlib2(L, reg_mqtt);
	luat_mqtt_struct_init(L);
    return 1;
}
