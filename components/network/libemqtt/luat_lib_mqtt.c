
#include "luat_base.h"

#include "luat_network_adapter.h"
#include "libemqtt.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "mqtt"
#include "luat_log.h"

#define LUAT_MQTT_CTRL_TYPE "MQTTCTRL*"

#define MQTT_RECV_BUF_LEN_MAX 4096
typedef struct
{
	mqtt_broker_handle_t *broker;
	network_ctrl_t *netc;
	luat_ip_addr_t *ip_addr;
	const char *ip;
	uint8_t mqtt_packet_buffer[MQTT_RECV_BUF_LEN_MAX];
	uint16_t remote_port;
	uint16_t keepalive;
	uint8_t adapter_index;
	uint8_t mqtt_state;
}luat_mqtt_ctrl_t;

typedef struct
{
	uint16_t topic_len;
    uint16_t payload_len;
	uint8_t topic[255];
	uint8_t payload[1000];
}luat_mqtt_msg_t;

static int luat_mqtt_connect(luat_mqtt_ctrl_t *mqtt_ctrl, const char *hostname, uint16_t port, uint16_t keepalive);

static int mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl)
{
	network_close(mqtt_ctrl->netc, 0);

}

static int mqtt_read_packet(luat_mqtt_ctrl_t *mqtt_ctrl)
{
	memset(mqtt_ctrl->mqtt_packet_buffer, 0, MQTT_RECV_BUF_LEN_MAX);
	int total_len;
	int rx_len;
	int result = network_rx(mqtt_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
	result = network_rx(mqtt_ctrl->netc, mqtt_ctrl->mqtt_packet_buffer, total_len, 0, NULL, NULL, &rx_len);
	return rx_len;
}


static int32_t l_mqtt_callback(lua_State *L, void* ptr)
{
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_mqtt_ctrl_t *mqtt_ctrl =(luat_mqtt_ctrl_t *)msg->ptr;
    switch (msg->arg1) {
		case MQTT_MSG_PUBLISH : {
			luat_mqtt_msg_t *mqtt_msg =(luat_mqtt_msg_t *)msg->arg2;
			lua_getglobal(L, "sys_pub");
			if (lua_isfunction(L, -1)) {
				lua_pushstring(L, "MQTT_MSG_PUBLISH");
				lua_pushlightuserdata(L, mqtt_ctrl);
				lua_pushlstring(L, mqtt_msg->topic,mqtt_msg->topic_len);
				lua_pushlstring(L, mqtt_msg->payload,mqtt_msg->payload_len);
				lua_call(L, 4, 0);
				luat_heap_free(mqtt_msg);
			}
            break;
        }
        case MQTT_MSG_CONNACK: {
			lua_getglobal(L, "sys_pub");
			if (lua_isfunction(L, -1)) {
				lua_pushstring(L, "MQTT_MSG_CONNACK");
				lua_pushlightuserdata(L, mqtt_ctrl);
				lua_call(L, 2, 0);
			}
            break;
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}


static int mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl) {
	rtos_msg_t msg;
    msg.handler = l_mqtt_callback;
    uint8_t msg_tp = MQTTParseMessageType(mqtt_ctrl->mqtt_packet_buffer);
    switch (msg_tp) {
        case MQTT_MSG_PUBLISH : {
			luat_mqtt_msg_t *mqtt_msg = (luat_mqtt_msg_t *)luat_heap_malloc(sizeof(luat_mqtt_msg_t));
			mqtt_msg->topic_len = mqtt_parse_pub_topic(mqtt_ctrl->mqtt_packet_buffer, mqtt_msg->topic);
            mqtt_msg->payload_len = mqtt_parse_publish_msg(mqtt_ctrl->mqtt_packet_buffer, mqtt_msg->payload);
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_PUBLISH;
			msg.arg2 = mqtt_msg;
			luat_msgbus_put(&msg, 0);
            break;
        }
        case MQTT_MSG_CONNACK: {
			mqtt_ctrl->mqtt_state = 1;
			msg.ptr = mqtt_ctrl;
			msg.arg1 = MQTT_MSG_CONNACK;
			luat_msgbus_put(&msg, 0);
            break;
        }
        case MQTT_MSG_PINGRESP : {
			LLOGD("MQTT_MSG_PINGRESP");
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
        case MQTT_MSG_UNSUBACK : {
			LLOGD("MQTT_MSG_UNSUBACK");
            break;
        }
        default : {
			LLOGD("mqtt_msg_cb no");
            break;
        }
    }
    return 0;
}

static int32_t luat_lib_mqtt_callback(void *data, void *param)
{
	OS_EVENT *event = (OS_EVENT *)data;
	luat_mqtt_ctrl_t *mqtt_ctrl =(luat_mqtt_ctrl_t *)param;
	int ret = 0;
	LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	LLOGD("luat_lib_mqtt_callback %d %d",event->ID & 0x0fffffff,event->Param1);
	if (event->ID == EV_NW_RESULT_LINK)
	{
		int ret = luat_mqtt_connect(mqtt_ctrl, mqtt_ctrl->ip, mqtt_ctrl->remote_port, mqtt_ctrl->keepalive);
		if(ret){
			LLOGD("init_socket ret=%d\n", ret);
		}
	}else if(event->ID == EV_NW_RESULT_CONNECT){
		mqtt_connect(mqtt_ctrl->broker);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		ret = mqtt_read_packet(mqtt_ctrl);
		if (ret > 0)
		{
			ret = mqtt_msg_cb(mqtt_ctrl);
		}
		
	}else if(event->ID == EV_NW_RESULT_TX){

	}else if(event->ID == EV_NW_RESULT_CLOSE){

	}
	network_wait_event(mqtt_ctrl->netc, NULL, 0, NULL);
    return 0;
}


static int l_mqtt_client(lua_State *L) {
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY){
		lua_pushnil(L);
		return 1;
	}

	luat_mqtt_ctrl_t *mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_newuserdata(L, sizeof(luat_mqtt_ctrl_t));
	if (!mqtt_ctrl){
		lua_pushnil(L);
		return 1;
	}
	mqtt_ctrl->mqtt_state = 0;
	mqtt_ctrl->adapter_index = adapter_index;
	mqtt_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!mqtt_ctrl->netc){
		LLOGD("create fail");
		lua_pushnil(L);
		return 1;
	}
	network_init_ctrl(mqtt_ctrl->netc, NULL, luat_lib_mqtt_callback, mqtt_ctrl);

	mqtt_ctrl->netc->is_debug = 1;

	network_set_base_mode(mqtt_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(mqtt_ctrl->netc, 0);
	network_deinit_tls(mqtt_ctrl->netc);
	
	const char* client_id = luaL_optstring(L, 2, "");
	int keep_alive = luaL_optinteger(L, 3, 300);
	const char* username = luaL_optstring(L, 4, "");
	const char* password = luaL_optstring(L, 5, "");
	int packet_length;
	uint16_t msg_id, msg_id_rcv;
	mqtt_ctrl->broker = (mqtt_broker_handle_t *)luat_heap_malloc(sizeof(mqtt_broker_handle_t));
	mqtt_init(mqtt_ctrl->broker, client_id);
	mqtt_init_auth(mqtt_ctrl->broker, username, password);
	

	luaL_setmetatable(L, LUAT_MQTT_CTRL_TYPE);
	return 1;
}

static int mqtt_send_packet(void* socket_info, const void* buf, unsigned int count){
    luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)socket_info;
	uint32_t tx_len;
	network_tx(mqtt_ctrl->netc, buf, count, 0, mqtt_ctrl->ip_addr->type?NULL:&(mqtt_ctrl->ip_addr), NULL, &tx_len, 0);
}

static int luat_mqtt_connect(luat_mqtt_ctrl_t *mqtt_ctrl, const char *hostname, uint16_t port, uint16_t keepalive){
	if(network_connect(mqtt_ctrl->netc, hostname, strlen(hostname), mqtt_ctrl->ip_addr->type?NULL:&(mqtt_ctrl->ip_addr), port, 0) < 0){
        network_close(mqtt_ctrl->netc, 0);
        return -1;
    }
    mqtt_set_alive(mqtt_ctrl->broker, keepalive);
    mqtt_ctrl->broker->socket_info = mqtt_ctrl;
    mqtt_ctrl->broker->send = mqtt_send_packet;
    return 0;
}

static int l_mqtt_connect(lua_State *L) {
	int ret = 0;
	const char *ip;
	size_t ip_len;
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	mqtt_ctrl->ip_addr = (luat_ip_addr_t *)luat_heap_malloc(sizeof(luat_ip_addr_t));
	mqtt_ctrl->ip_addr->type = 0xff;
	if (lua_isinteger(L, 2)){
		mqtt_ctrl->ip_addr->type = IPADDR_TYPE_V4;
		mqtt_ctrl->ip_addr->u_addr.ip4.addr = lua_tointeger(L, 2);
		ip = NULL;
		ip_len = 0;
	}else{
		ip_len = 0;
		ip = luaL_checklstring(L, 2, &ip_len);
	}
	mqtt_ctrl->ip = luat_heap_malloc(ip_len + 1);
	memset(mqtt_ctrl->ip, 0, ip_len + 1);
	memcpy(mqtt_ctrl->ip, ip, ip_len);
	mqtt_ctrl->remote_port = luaL_checkinteger(L, 3);
	mqtt_ctrl->keepalive = luaL_optinteger(L, 4, 240);
	int result = network_wait_link_up(mqtt_ctrl->netc, 0);
	if (result < 0)
	{
		/* code */
	}
	
	LLOGD("network_wait_link_up result %d",result);

	return 0;
}

static int l_mqtt_subscribe(lua_State *L) {
	size_t len;
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	const char * topic = luaL_checklstring(L, 2, &len);
	int subscribe_state = mqtt_subscribe(mqtt_ctrl->broker, topic, NULL);
	return 0;
}

static int l_mqtt_unsubscribe(lua_State *L) {
	size_t len;
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	const char * topic = luaL_checklstring(L, 2, &len);
	int subscribe_state = mqtt_unsubscribe(mqtt_ctrl->broker, topic, NULL);
	return 0;
}

static int l_mqtt_publish(lua_State *L) {
	size_t len;
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	const char * topic = luaL_checklstring(L, 2, &len);
	const char * payload = luaL_checklstring(L, 3, &len);
	uint8_t qos = luaL_optinteger(L, 4, 0);
	uint8_t retain = luaL_optinteger(L, 5, 0);
	mqtt_publish_with_qos(mqtt_ctrl->broker, topic, payload, retain, qos, NULL);
	return 0;
}

static int l_mqtt_disconnect(lua_State *L) {
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)lua_touserdata(L, 1);
	mqtt_close_socket(mqtt_ctrl);
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mqtt[] =
{
	{"client",			ROREG_FUNC(l_mqtt_client)},
	{"connect",			ROREG_FUNC(l_mqtt_connect)},
	{"subscribe",		ROREG_FUNC(l_mqtt_subscribe)},
	{"unsubscribe",		ROREG_FUNC(l_mqtt_unsubscribe)},
	{"publish",			ROREG_FUNC(l_mqtt_publish)},
	{"disconnect",		ROREG_FUNC(l_mqtt_disconnect)},
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_mqtt( lua_State *L ) {
    luat_newlib2(L, reg_mqtt);
    return 1;
}
