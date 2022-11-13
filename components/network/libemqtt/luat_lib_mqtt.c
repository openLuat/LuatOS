/*
@module  mqtt
@summary mqtt客户端
@version 1.0
@date    2022.08.25
@demo network
*/

#include "luat_base.h"

#include "luat_network_adapter.h"
#include "libemqtt.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "mqtt"
#include "luat_log.h"

#define LUAT_MQTT_CTRL_TYPE "MQTTCTRL*"

#define MQTT_MSG_RELEASE 0
#define MQTT_MSG_TIMER_PING 2

#define MQTT_RECV_BUF_LEN_MAX 4096
typedef struct{
	mqtt_broker_handle_t broker;// mqtt broker
	network_ctrl_t *netc;		// mqtt netc
	luat_ip_addr_t ip_addr;		// mqtt ip
	const char *host; 			// mqtt host
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

static int luat_socket_connect(luat_mqtt_ctrl_t *mqtt_ctrl, const char *hostname, uint16_t port, uint16_t keepalive);
static void mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl);
static int mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl);
static int32_t l_mqtt_callback(lua_State *L, void* ptr);

static luat_mqtt_ctrl_t * get_mqtt_ctrl(lua_State *L){
	if (luaL_testudata(L, 1, LUAT_MQTT_CTRL_TYPE)){
		return ((luat_mqtt_ctrl_t *)luaL_checkudata(L, 1, LUAT_MQTT_CTRL_TYPE));
	}else{
		return ((luat_mqtt_ctrl_t *)lua_touserdata(L, 1));
	}
}

static LUAT_RT_RET_TYPE mqtt_timer_callback(LUAT_RT_CB_PARAM){
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)param;
	rtos_msg_t msg = {0};
	msg.handler = l_mqtt_callback;
	msg.ptr = mqtt_ctrl;
	msg.arg1 = MQTT_MSG_TIMER_PING;
	luat_msgbus_put(&msg, 0);

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
		mqtt_ctrl->buffer_offset = 0;
		mqtt_ctrl->reconnect_timer = luat_create_rtos_timer(reconnect_timer_cb, mqtt_ctrl, NULL);
		luat_start_rtos_timer(mqtt_ctrl->reconnect_timer, mqtt_ctrl->reconnect_time, 0);
	}
}

static void mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl){
	if (mqtt_ctrl->netc){
		network_force_close_socket(mqtt_ctrl->netc);
	}
	luat_stop_rtos_timer(mqtt_ctrl->ping_timer);
	mqtt_ctrl->mqtt_state = 0;
	mqtt_reconnect(mqtt_ctrl);
}

static void mqtt_release_socket(luat_mqtt_ctrl_t *mqtt_ctrl){
	rtos_msg_t msg = {0};
	msg.handler = l_mqtt_callback;
	msg.ptr = mqtt_ctrl;
	msg.arg1 = MQTT_MSG_RELEASE;
	luat_msgbus_put(&msg, 0);
	if (mqtt_ctrl->netc){
		network_release_ctrl(mqtt_ctrl->netc);
    	mqtt_ctrl->netc = NULL;
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
	int result = network_rx(mqtt_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
	if (total_len > 0xFFF) {
		LLOGE("too many data wait for recv %d", total_len);
		mqtt_close_socket(mqtt_ctrl);
		return -1;
	}
	if (total_len == 0) {
		LLOGD("rx event but NO data wait for recv");
		return 0;
	}
	if (MQTT_RECV_BUF_LEN_MAX - mqtt_ctrl->buffer_offset <= 0) {
		LLOGD("buff is FULL, mqtt packet too big");
		mqtt_close_socket(mqtt_ctrl);
		return -1;
	}
	#define MAX_READ (1024)
	int recv_want = 0;

	while (MQTT_RECV_BUF_LEN_MAX - mqtt_ctrl->buffer_offset > 0) {
		if (MAX_READ > (MQTT_RECV_BUF_LEN_MAX - mqtt_ctrl->buffer_offset)) {
			recv_want = MQTT_RECV_BUF_LEN_MAX - mqtt_ctrl->buffer_offset;
		}
		else {
			recv_want = MAX_READ;
		}
		// 从网络接收数据
		result = network_rx(mqtt_ctrl->netc, mqtt_ctrl->mqtt_packet_buffer + mqtt_ctrl->buffer_offset, recv_want, 0, NULL, NULL, &rx_len);
		if (rx_len == 0||result!=0) {
			break;
		}
		// 收到数据了, 传给处理函数继续处理
		// 数据的长度变更, 触发传递
		mqtt_ctrl->buffer_offset += rx_len;
further:
		result = mqtt_parse(mqtt_ctrl);
		if (result == 0) {
			// OK
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
		case MQTT_MSG_TIMER_PING : {
			mqtt_ping(&(mqtt_ctrl->broker));
			break;
		}
		case MQTT_MSG_PUBLISH : {
			luat_mqtt_msg_t *mqtt_msg =(luat_mqtt_msg_t *)msg->arg2;
			if (mqtt_ctrl->mqtt_cb) {
				luat_mqtt_msg_t *mqtt_msg =(luat_mqtt_msg_t *)msg->arg2;
				lua_geti(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_cb);
				if (lua_isfunction(L, -1)) {
					lua_geti(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_ref);
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
			if (mqtt_ctrl->mqtt_cb) {
				lua_geti(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_cb);
				if (lua_isfunction(L, -1)) {
					lua_geti(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_ref);
					lua_pushstring(L, "conack");
					lua_call(L, 2, 0);
				}
				lua_getglobal(L, "sys_pub");
				if (lua_isfunction(L, -1)) {
					lua_pushstring(L, "MQTT_CONNACK");
					lua_geti(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_ref);
					lua_call(L, 2, 0);
				}
            }
            break;
        }
		case MQTT_MSG_PUBACK:
		case MQTT_MSG_PUBCOMP: {
			if (mqtt_ctrl->mqtt_cb) {
				lua_geti(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_cb);
				if (lua_isfunction(L, -1)) {
					lua_geti(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_ref);
					lua_pushstring(L, "sent");
					lua_pushinteger(L, msg->arg2);
					lua_call(L, 3, 0);
				}
            }
            break;
        }
		case MQTT_MSG_RELEASE: {
			if (mqtt_ctrl->mqtt_ref) {
				luaL_unref(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_ref);
				mqtt_ctrl->mqtt_ref = 0;
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
			// LLOGD("MQTT_MSG_CONNECT");
			break;
		}
		case MQTT_MSG_CONNACK: {
			// LLOGD("MQTT_MSG_CONNACK");
			if(mqtt_ctrl->mqtt_packet_buffer[3] != 0x00){
				LLOGE("MQTT_MSG_CONNACK mqtt_ctrl->mqtt_packet_buffer[3]:0x%02x",mqtt_ctrl->mqtt_packet_buffer[3]);
                mqtt_close_socket(mqtt_ctrl);
                return -1;
            }
			mqtt_ctrl->mqtt_state = 1;
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_CONNACK;
			luat_msgbus_put(&msg, 0);
            break;
        }
        case MQTT_MSG_PUBLISH : {
			// LLOGD("MQTT_MSG_PUBLISH");
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
			// LLOGD("MQTT_MSG_PUBACK");
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_PUBACK;
			msg.arg2 = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			luat_msgbus_put(&msg, 0);
			break;
		}
		case MQTT_MSG_PUBREC : {
			uint16_t msg_id=mqtt_parse_msg_id(&(mqtt_ctrl->broker));
			mqtt_pubrel(&(mqtt_ctrl->broker), msg_id);
			// LLOGD("MQTT_MSG_PUBREC");
			break;
		}
		case MQTT_MSG_PUBCOMP : {
			// LLOGD("MQTT_MSG_PUBCOMP");
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_PUBCOMP;
			msg.arg2 = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			luat_msgbus_put(&msg, 0);
			break;
		}
		case MQTT_MSG_SUBSCRIBE : {
			// LLOGD("MQTT_MSG_SUBSCRIBE");
            break;
        }
        case MQTT_MSG_SUBACK : {
			// LLOGD("MQTT_MSG_SUBACK");
            break;
        }
		case MQTT_MSG_UNSUBSCRIBE : {
			// LLOGD("MQTT_MSG_UNSUBSCRIBE");
            break;
        }
		case MQTT_MSG_UNSUBACK : {
			// LLOGD("MQTT_MSG_UNSUBACK");
            break;
        }
		case MQTT_MSG_PINGREQ : {
			// LLOGD("MQTT_MSG_PINGREQ");
            break;
        }
        case MQTT_MSG_PINGRESP : {
			// LLOGD("MQTT_MSG_PINGRESP");
            break;
        }
		case MQTT_MSG_DISCONNECT : {
			// LLOGD("MQTT_MSG_DISCONNECT");
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
			LLOGE("init_socket ret=%d\n", ret);
			mqtt_close_socket(mqtt_ctrl);
		}
	}else if(event->ID == EV_NW_RESULT_CONNECT){
		ret = mqtt_connect(&(mqtt_ctrl->broker));
		if(ret==1){
			luat_start_rtos_timer(mqtt_ctrl->ping_timer, mqtt_ctrl->keepalive*1000*0.75, 1);
		}
	}else if(event->ID == EV_NW_RESULT_EVENT){
		if (event->Param1==0){
			ret = mqtt_read_packet(mqtt_ctrl);
			// LLOGD("mqtt_read_packet ret:%d",ret);
			luat_stop_rtos_timer(mqtt_ctrl->ping_timer);
			luat_start_rtos_timer(mqtt_ctrl->ping_timer, mqtt_ctrl->keepalive*1000*0.75, 1);
		}
	}else if(event->ID == EV_NW_RESULT_TX){
		luat_stop_rtos_timer(mqtt_ctrl->ping_timer);
		luat_start_rtos_timer(mqtt_ctrl->ping_timer, mqtt_ctrl->keepalive*1000*0.75, 1);
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
#ifdef LUAT_USE_LWIP
	return network_tx(mqtt_ctrl->netc, buf, count, 0, NULL, 0, &tx_len, 0);
#else
	return network_tx(mqtt_ctrl->netc, buf, count, 0, NULL, 0, &tx_len, 0);
#endif
}

static int luat_socket_connect(luat_mqtt_ctrl_t *mqtt_ctrl, const char *hostname, uint16_t port, uint16_t keepalive){
#ifdef LUAT_USE_LWIP
	if(network_connect(mqtt_ctrl->netc, hostname, strlen(hostname), (0xff == mqtt_ctrl->ip_addr.type)?NULL:&(mqtt_ctrl->ip_addr), port, 0) < 0){
#else
	if(network_connect(mqtt_ctrl->netc, hostname, strlen(hostname), (0xff == mqtt_ctrl->ip_addr.is_ipv6)?NULL:&(mqtt_ctrl->ip_addr), port, 0) < 0){
#endif
        network_close(mqtt_ctrl->netc, 0);
        return -1;
    }
    mqtt_set_alive(&(mqtt_ctrl->broker), keepalive);
    mqtt_ctrl->broker.socket_info = mqtt_ctrl;
    mqtt_ctrl->broker.send = mqtt_send_packet;
    return 0;
}

/*
订阅主题
@api mqttc:subscribe(topic, qos)
@string/table 主题
@int topic为string时生效 0/1/2 默认0
@usage 
mqttc:subscribe("/luatos/123456")
mqttc:subscribe({["/luatos/1234567"]=1,["/luatos/12345678"]=2})
*/
static int l_mqtt_subscribe(lua_State *L) {
	size_t len = 0;
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	if (lua_isstring(L, 2)){
		const char * topic = luaL_checklstring(L, 2, &len);
		uint8_t qos = luaL_optinteger(L, 3, 0);
		int subscribe_state = mqtt_subscribe(&(mqtt_ctrl->broker), topic, NULL,qos);
	}else if(lua_istable(L, 2)){
		lua_pushnil(L);
		while (lua_next(L, 2) != 0) {
			mqtt_subscribe(&(mqtt_ctrl->broker), lua_tostring(L, -2), NULL,luaL_optinteger(L, -1, 0));
			lua_pop(L, 1);
		}
	}
	return 0;
}

/*
取消订阅主题
@api mqttc:unsubscribe(topic)
@string/table 主题
@usage 
mqttc:unsubscribe("/luatos/123456")
mqttc:unsubscribe({"/luatos/1234567","/luatos/12345678"})
*/
static int l_mqtt_unsubscribe(lua_State *L) {
	size_t len = 0;
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	if (lua_isstring(L, 2)){
		const char * topic = luaL_checklstring(L, 2, &len);
		int subscribe_state = mqtt_unsubscribe(&(mqtt_ctrl->broker), topic, NULL);
	}else if(lua_istable(L, 2)){
		size_t count = lua_rawlen(L, 2);
		for (size_t i = 1; i <= count; i++){
			lua_geti(L, 2, i);
			const char * topic = luaL_checklstring(L, -1, &len);
			mqtt_unsubscribe(&(mqtt_ctrl->broker), topic, NULL);
			lua_pop(L, 1);
		}
	}
	return 0;
}

/*
mqtt客户端创建
@api mqttc:create(adapter,host,port,isssl,ca_file)
@int 适配器序号, 只能是network.ETH0,network.STA,network.AP,如果不填,会选择最后一个注册的适配器
@string 服务器地址
@int  	端口号
@bool  	是否为ssl加密连接,默认不加密
@string 证书
@usage 
mqttc = mqtt.create(nil,"120.55.137.106", 1884)
*/
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

	mqtt_ctrl->mqtt_state = 0;
	mqtt_ctrl->netc->is_debug = 0;
	mqtt_ctrl->keepalive = 240;
	network_set_base_mode(mqtt_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(mqtt_ctrl->netc, 0);

	const char *ip;
	size_t ip_len = 0;
#ifdef LUAT_USE_LWIP
	mqtt_ctrl->ip_addr.type = 0xff;
#else
	mqtt_ctrl->ip_addr.is_ipv6 = 0xff;
#endif
	if (lua_isinteger(L, 2)){
#ifdef LUAT_USE_LWIP
		mqtt_ctrl->ip_addr.type = IPADDR_TYPE_V4;
		mqtt_ctrl->ip_addr.u_addr.ip4.addr = lua_tointeger(L, 2);
#else
		mqtt_ctrl->ip_addr.is_ipv6 = 0;
		mqtt_ctrl->ip_addr.ipv4 = lua_tointeger(L, 2);
#endif
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
	mqtt_ctrl->ping_timer = luat_create_rtos_timer(mqtt_timer_callback, mqtt_ctrl, NULL);
	
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

	luaL_setmetatable(L, LUAT_MQTT_CTRL_TYPE);
	lua_pushvalue(L, -1);
	mqtt_ctrl->mqtt_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	return 1;
}

/*
mqtt三元组配置
@api mqttc:auth(client_id,username,password)
@string client_id
@string 账号 可选
@string 密码 可选
@usage 
mqttc:auth("123456789","username","password")
*/
static int l_mqtt_auth(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	const char *client_id = luaL_checkstring(L, 2);
	const char *username = luaL_optstring(L, 3, "");
	const char *password = luaL_optstring(L, 4, "");
	mqtt_init(&(mqtt_ctrl->broker), client_id);
	mqtt_init_auth(&(mqtt_ctrl->broker), username, password);
	return 0;
}

/*
mqtt心跳设置
@api mqttc:keepalive(time)
@int 可选 单位s 默认240s
@usage 
mqttc:keepalive(30)
*/
static int l_mqtt_keepalive(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	mqtt_ctrl->keepalive = luaL_optinteger(L, 2, 240);
	return 0;
}

/*
mqtt回调注册
@api mqttc:on(cb)
@function cb mqtt回调,参数包括mqtt_client, event, data, payload
@usage 
mqttc:on(function(mqtt_client, event, data, payload)
	-- 用户自定义代码
	log.info("mqtt", "event", event, mqtt_client, data, payload)
end)
*/
static int l_mqtt_on(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	if (mqtt_ctrl->mqtt_cb != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_cb);
		mqtt_ctrl->mqtt_cb = 0;
	}
	if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		mqtt_ctrl->mqtt_cb = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	return 0;
}

/*
连接服务器
@api mqttc:connect()
@usage 
mqttc:connect()
*/
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

/*
自动重连
@api mqttc:autoreconn(reconnect, reconnect_time)
@bool 是否自动重连
@int 自动重连周期 单位ms 默认3s
@usage 
mqttc:autoreconn(true)
*/
static int l_mqtt_autoreconn(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	if (lua_isboolean(L, 2)){
		mqtt_ctrl->reconnect = lua_toboolean(L, 2);
	}
	mqtt_ctrl->reconnect_time = luaL_optinteger(L, 3, 3000);
	return 0;
}

/*
发布消息
@api mqttc:publish(topic, data, qos)
@string topic 主题
@string data  消息
@int qos 0/1/2 默认0
@return int message_id
@usage 
mqttc:publish("/luatos/123456", "123")
*/
static int l_mqtt_publish(lua_State *L) {
	uint16_t message_id ,payload_len= 0;
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	const char * topic = luaL_checkstring(L, 2);
	const char * payload = luaL_checklstring(L, 3, &payload_len);
	uint8_t qos = luaL_optinteger(L, 4, 0);
	uint8_t retain = luaL_optinteger(L, 5, 0);
	int ret = mqtt_publish_with_qos(&(mqtt_ctrl->broker), topic, payload,payload_len, retain, qos, &message_id);
	if (ret!=1){
		return 0;
	}
	if (qos == 0){
		rtos_msg_t msg = {0};
    	msg.handler = l_mqtt_callback;
		msg.ptr = mqtt_ctrl;
		msg.arg1 = MQTT_MSG_PUBACK;
		msg.arg2 = message_id;
		luat_msgbus_put(&msg, 0);
	}
	lua_pushinteger(L, message_id);
	return 1;
}

/*
mqtt客户端关闭(关闭后资源释放无法再使用)
@api mqttc:close()
@usage 
mqttc:close()
*/
static int l_mqtt_close(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = get_mqtt_ctrl(L);
	mqtt_disconnect(&(mqtt_ctrl->broker));
	mqtt_close_socket(mqtt_ctrl);
	if (mqtt_ctrl->mqtt_cb != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, mqtt_ctrl->mqtt_cb);
		mqtt_ctrl->mqtt_cb = 0;
	}
	mqtt_release_socket(mqtt_ctrl);
	return 0;
}

/*
mqtt客户端是否就绪
@api mqttc:ready()
@return bool 客户端是否就绪
@usage 
local error = mqttc:ready()
*/
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
	{"autoreconn",		ROREG_FUNC(l_mqtt_autoreconn)},
	{"publish",			ROREG_FUNC(l_mqtt_publish)},
	{"subscribe",		ROREG_FUNC(l_mqtt_subscribe)},
	{"unsubscribe",		ROREG_FUNC(l_mqtt_unsubscribe)},
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
static const rotable_Reg_t reg_mqtt_emtry[] =
{
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_mqtt( lua_State *L ) {

#ifdef LUAT_USE_NETWORK
    luat_newlib2(L, reg_mqtt);
	luat_mqtt_struct_init(L);
    return 1;
#else
	luat_newlib2(L, reg_mqtt_emtry);
    return 1;
	LLOGE("mqtt require network enable!!");
#endif
}
