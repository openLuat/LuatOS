
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
}luat_mqtt_ctrl_t;

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

static int mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl) {
    const uint8_t *topic;
    const uint8_t *payload;

    uint16_t topic_len;
    uint16_t payload_len;
    uint8_t msg_tp = MQTTParseMessageType(mqtt_ctrl->mqtt_packet_buffer);
    LLOGD("mqtt msg %02X", msg_tp);
    switch (msg_tp) {
        case MQTT_MSG_PUBLISH : {
			LLOGD("MQTT_MSG_PUBLISH");
            break;
        }
        case MQTT_MSG_CONNACK: {
			LLOGD("MQTT_MSG_CONNACK");
            break;
        }
        case MQTT_MSG_PINGRESP : {
			LLOGD("MQTT_MSG_PINGRESP");
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
	LLOGD("network_wait_link_up result %d",result);


	// ret = luat_mqtt_connect(mqtt_ctrl, ip, remote_port, keepalive);
    // if(ret){
    //     LLOGD("init_socket ret=%d\n", ret);
    // }

	// int packet_length = 0;
	// packet_length = mqtt_read_packet();
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mqtt[] =
{
	{"client",			ROREG_FUNC(l_mqtt_client)},
	{"connect",			ROREG_FUNC(l_mqtt_connect)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_mqtt( lua_State *L ) {
    luat_newlib2(L, reg_mqtt);
    return 1;
}
