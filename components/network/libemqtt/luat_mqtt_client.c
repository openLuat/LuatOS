#include "luat_base.h"

#include "luat_network_adapter.h"
#include "libemqtt.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_mqtt.h"

#define LUAT_LOG_TAG "mqtt"
#include "luat_log.h"

#ifndef LUAT_MQTT_DEBUG
#define LUAT_MQTT_DEBUG 0
#endif

#if LUAT_MQTT_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif

static int luat_mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl);

#ifdef __LUATOS__
#include "luat_msgbus.h"
int32_t luatos_mqtt_callback(lua_State *L, void* ptr);
#endif

int l_luat_mqtt_msg_cb(luat_mqtt_ctrl_t * ptr, int arg1, int arg2) {
#ifdef __LUATOS__
	luat_mqtt_ctrl_t *mqtt_ctrl =(luat_mqtt_ctrl_t *)ptr;
	rtos_msg_t msg = {
		.handler = luatos_mqtt_callback,
		.ptr = ptr,
		.arg1 = arg1,
		.arg2 = arg2
	};
	if (mqtt_ctrl->app_cb)
	{
		luat_mqtt_app_cb_t mqtt_cb = mqtt_ctrl->app_cb;
		if (mqtt_cb(mqtt_ctrl, arg1))
		{
			return 0;
		}
	}
	luat_msgbus_put(&msg, 0);
#else
	luat_mqtt_ctrl_t *mqtt_ctrl =(luat_mqtt_ctrl_t *)ptr;
	if (mqtt_ctrl->mqtt_cb){
		luat_mqtt_cb_t mqtt_cb = mqtt_ctrl->mqtt_cb;
		mqtt_cb(mqtt_ctrl, arg1);
	}

#endif
	return 0;
}

static LUAT_RT_RET_TYPE ping_timer_callback(LUAT_RT_CB_PARAM){
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)param;
    l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_TIMER_PING, 0);
}

static LUAT_RT_RET_TYPE reconnect_timer_cb(LUAT_RT_CB_PARAM){
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)param;
	l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_RECONNECT, 0);
}

static LUAT_RT_RET_TYPE conn_timer_callback(LUAT_RT_CB_PARAM){
	luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)param;
	l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_CONN_TIMEOUT, 0);
}

int luat_mqtt_reconnect(luat_mqtt_ctrl_t *mqtt_ctrl) {
	mqtt_ctrl->buffer_offset = 0;
	int ret = luat_mqtt_connect(mqtt_ctrl);
	if(ret){
		LLOGI("reconnect init socket ret=%d\n", ret);
		luat_mqtt_close_socket(mqtt_ctrl);
	}
	return ret;
}



int luat_mqtt_ping(luat_mqtt_ctrl_t *mqtt_ctrl) {
	mqtt_ping(&mqtt_ctrl->broker);
	return 0;
}

int luat_mqtt_init(luat_mqtt_ctrl_t *mqtt_ctrl, int adapter_index) {
	memset(mqtt_ctrl, 0, sizeof(luat_mqtt_ctrl_t));
	mqtt_ctrl->rxbuff_size = MQTT_RECV_BUF_LEN_MAX+4;
	mqtt_ctrl->adapter_index = adapter_index;
	mqtt_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!mqtt_ctrl->netc){
		LLOGW("network_alloc_ctrl fail");
		return -1;
	}
	network_init_ctrl(mqtt_ctrl->netc, NULL, luat_mqtt_callback, mqtt_ctrl);

	mqtt_ctrl->mqtt_state = MQTT_STATE_DISCONNECT;
	mqtt_ctrl->netc->is_debug = 0;
	mqtt_ctrl->keepalive = 240;
	network_set_base_mode(mqtt_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(mqtt_ctrl->netc, 0);
	mqtt_ctrl->reconnect_timer = luat_create_rtos_timer(reconnect_timer_cb, mqtt_ctrl, NULL);
	mqtt_ctrl->ping_timer = luat_create_rtos_timer(ping_timer_callback, mqtt_ctrl, NULL);
	mqtt_ctrl->conn_timer = luat_create_rtos_timer(conn_timer_callback, mqtt_ctrl, NULL);
    return 0;
}

int luat_mqtt_set_rxbuff_size(luat_mqtt_ctrl_t *mqtt_ctrl, uint32_t rxbuff_size){
	mqtt_ctrl->rxbuff_size = rxbuff_size;
	return 0;
}

int luat_mqtt_set_keepalive(luat_mqtt_ctrl_t *mqtt_ctrl, uint32_t keepalive){
    mqtt_ctrl->keepalive = keepalive;
    return 0;
}

int luat_mqtt_set_auto_connect(luat_mqtt_ctrl_t *mqtt_ctrl, uint8_t auto_connect,uint32_t reconnect_time){
    mqtt_ctrl->reconnect = auto_connect;
    mqtt_ctrl->reconnect_time = reconnect_time;
    return 0;
}

int luat_mqtt_set_connopts(luat_mqtt_ctrl_t *mqtt_ctrl, luat_mqtt_connopts_t *opts) {
    memcpy(mqtt_ctrl->host, opts->host, strlen(opts->host) + 1);
    mqtt_ctrl->remote_port = opts->port;
	if (opts->is_tls){
		if (network_init_tls(mqtt_ctrl->netc, opts->verify)){
			LLOGE("初始化tls失败");
			return -1;
		}
		if (opts->server_cert){
			if (network_set_server_cert(mqtt_ctrl->netc, (const unsigned char *)opts->server_cert, opts->server_cert_len+1)){
				LLOGE("network_set_server_cert error");
				return -1;
			}
		}
		if (opts->client_cert){
			if (network_set_client_cert(mqtt_ctrl->netc, (const unsigned char*)opts->client_cert, opts->client_cert_len+1,
					(const unsigned char*)opts->client_key, opts->client_key_len+1,
					(const unsigned char*)opts->client_password, opts->client_password_len+1)){
				LLOGE("network_set_client_cert error");
				return -1;
			}
		}
	} else {
		network_deinit_tls(mqtt_ctrl->netc);
	}

	if (opts->is_ipv6) {
		network_connect_ipv6_domain(mqtt_ctrl->netc, 1);
	}

    mqtt_ctrl->broker.socket_info = mqtt_ctrl;
    mqtt_ctrl->broker.send = luat_mqtt_send_packet;
	mqtt_ctrl->conn_timeout = opts->conn_timeout ? opts->conn_timeout : 30;
    return 0;
}

int luat_mqtt_set_triad(luat_mqtt_ctrl_t *mqtt_ctrl, const char* clientid, const char* username, const char* password){
    mqtt_init(&(mqtt_ctrl->broker), clientid);
	mqtt_init_auth(&(mqtt_ctrl->broker), username, password);
    return 0;
}


void luat_mqtt_close_socket(luat_mqtt_ctrl_t *mqtt_ctrl){
	LLOGI("mqtt closing socket netc:%p mqtt_state:%d",mqtt_ctrl->netc,mqtt_ctrl->mqtt_state);
	if (mqtt_ctrl->mqtt_state){
		mqtt_ctrl->mqtt_state = 0;
		mqtt_ctrl->buffer_offset = 0;
		luat_stop_rtos_timer(mqtt_ctrl->ping_timer);
		luat_stop_rtos_timer(mqtt_ctrl->conn_timer);
		if (mqtt_ctrl->netc){
			network_force_close_socket(mqtt_ctrl->netc);
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_DISCONNECT, mqtt_ctrl->error_state==0?MQTT_ERROR_STATE_SOCKET:mqtt_ctrl->error_state);
		}
		if (mqtt_ctrl->reconnect && mqtt_ctrl->reconnect_time > 0){
			luat_start_rtos_timer(mqtt_ctrl->reconnect_timer, mqtt_ctrl->reconnect_time, 0);
		}else{
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_CLOSE, 0);
		}
	}
	mqtt_ctrl->buffer_offset = 0;
}

void luat_mqtt_release_socket(luat_mqtt_ctrl_t *mqtt_ctrl){
    l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_RELEASE, 0);
	if (mqtt_ctrl->ping_timer){
		luat_release_rtos_timer(mqtt_ctrl->ping_timer);
    	mqtt_ctrl->ping_timer = NULL;
	}
	if (mqtt_ctrl->conn_timer){
		luat_release_rtos_timer(mqtt_ctrl->conn_timer);
		mqtt_ctrl->conn_timer = NULL;
	}
	if (mqtt_ctrl->reconnect_timer){
		luat_release_rtos_timer(mqtt_ctrl->reconnect_timer);
    	mqtt_ctrl->reconnect_timer = NULL;
	}
	if (mqtt_ctrl->broker.will_data) {
		mqtt_ctrl->broker.will_len = 0;
		luat_heap_free(mqtt_ctrl->broker.will_data);
		mqtt_ctrl->broker.will_data = NULL;
	}
	if (mqtt_ctrl->netc){
		network_release_ctrl(mqtt_ctrl->netc);
    	mqtt_ctrl->netc = NULL;
	}
	if (mqtt_ctrl->mqtt_packet_buffer) {
		luat_heap_free(mqtt_ctrl->mqtt_packet_buffer);
		mqtt_ctrl->mqtt_packet_buffer = NULL;
	}
}

static int mqtt_parse(luat_mqtt_ctrl_t *mqtt_ctrl) {
	LLOGD("mqtt_parse offset %d", mqtt_ctrl->buffer_offset);
	if (mqtt_ctrl->buffer_offset < 2) {
		LLOGD("wait more data");
		return 0;
	}
	// 判断数据长度, 前几个字节能判断出够不够读出mqtt的头
	char* buf = (char*)mqtt_ctrl->mqtt_packet_buffer;
	int num_bytes = 1;
	if ((buf[1] & 0x80) == 0x80) {
		num_bytes++;
		if (mqtt_ctrl->buffer_offset < 3) {
			LLOGD("wait more data for mqtt head");
			return 0;
		}
		if ((buf[2] & 0x80) == 0x80) {
			num_bytes ++;
			if (mqtt_ctrl->buffer_offset < 4) {
				LLOGD("wait more data for mqtt head");
				return 0;
			}
			if ((buf[3] & 0x80) == 0x80) {
				num_bytes ++;
			}
		}
	}
	// 判断数据总长, 这里rem_len只包含mqtt头部之外的数据
	uint32_t rem_len = mqtt_parse_rem_len(mqtt_ctrl->mqtt_packet_buffer);
	if (rem_len > mqtt_ctrl->buffer_offset - num_bytes - 1) {
		LLOGD("wait more data for mqtt head");
		return 0;
	}
	// 至此, mqtt包是完整的 解析类型, 处理之
	int ret = luat_mqtt_msg_cb(mqtt_ctrl);
	if (ret != 0){
		LLOGW("bad mqtt packet!! ret %d", ret);
		return -1;
	}
	// 处理完成后, 如果还有数据, 移动数据, 继续处理
	mqtt_ctrl->buffer_offset -= (1 + num_bytes + rem_len);
	memmove(mqtt_ctrl->mqtt_packet_buffer, mqtt_ctrl->mqtt_packet_buffer+1 + num_bytes + rem_len, mqtt_ctrl->buffer_offset);
	return 1;
}

int luat_mqtt_read_packet(luat_mqtt_ctrl_t *mqtt_ctrl){
	LLOGD("luat_mqtt_read_packet mqtt_ctrl->buffer_offset:%d",mqtt_ctrl->buffer_offset);
	uint32_t total_len = 0;
	uint32_t rx_len = 0;
	int result = network_rx(mqtt_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
	if (total_len > mqtt_ctrl->rxbuff_size - mqtt_ctrl->buffer_offset) {
		LLOGE("too many data wait for recv %d", total_len);
		luat_mqtt_close_socket(mqtt_ctrl);
		return -1;
	}
	if (total_len == 0 && !mqtt_ctrl->netc->tls_mode) {
		LLOGW("rx event but NO data wait for recv");
		return 0;
	}
	if (mqtt_ctrl->rxbuff_size - mqtt_ctrl->buffer_offset <= 0) {
		LLOGE("buff is FULL, mqtt packet too big");
		luat_mqtt_close_socket(mqtt_ctrl);
		return -1;
	}
	#define MAX_READ (1024)
	int recv_want = 0;

	while (mqtt_ctrl->rxbuff_size - mqtt_ctrl->buffer_offset > 0) {
		if (MAX_READ > (mqtt_ctrl->rxbuff_size - mqtt_ctrl->buffer_offset)) {
			recv_want = mqtt_ctrl->rxbuff_size - mqtt_ctrl->buffer_offset;
		}
		else {
			recv_want = MAX_READ;
		}
		// 从网络接收数据
		result = network_rx(mqtt_ctrl->netc, mqtt_ctrl->mqtt_packet_buffer + mqtt_ctrl->buffer_offset, recv_want, 0, NULL, NULL, &rx_len);
		if (rx_len == 0 || result != 0 ) {
			LLOGD("rx_len %d result %d", rx_len, result);
			break;
		}
		// 收到数据了, 传给处理函数继续处理
		// 数据的长度变更, 触发传递
		mqtt_ctrl->buffer_offset += rx_len;
		LLOGD("data recv %d offset %d", rx_len, mqtt_ctrl->buffer_offset);
further:
		result = mqtt_parse(mqtt_ctrl);
		if (result == 0) {
			// OK
		}else if(result == 1){
			if (mqtt_ctrl->buffer_offset > 0)
				goto further;
			else {
				continue;
			}
		}
		else {
			LLOGW("mqtt_parse ret %d, closing socket",result);
			luat_mqtt_close_socket(mqtt_ctrl);
			return -1;
		}
	}
	return 0;
}


static int luat_mqtt_msg_cb(luat_mqtt_ctrl_t *mqtt_ctrl) {
    uint8_t msg_tp = MQTTParseMessageType(mqtt_ctrl->mqtt_packet_buffer);
	uint16_t msg_id = 0;
	uint8_t qos = 0;
    switch (msg_tp) {
		case MQTT_MSG_CONNACK: {
			LLOGD("MQTT_MSG_CONNACK");
			if(mqtt_ctrl->mqtt_packet_buffer[3] != 0x00){
				LLOGW("CONACK 0x%02x",mqtt_ctrl->mqtt_packet_buffer[3]);
				mqtt_ctrl->error_state = mqtt_ctrl->mqtt_packet_buffer[3];
                luat_mqtt_close_socket(mqtt_ctrl);
                l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_CONACK_ERROR, mqtt_ctrl->mqtt_packet_buffer[3]);
                return -1;
            }
			mqtt_ctrl->mqtt_state = MQTT_STATE_READY;
            l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_CONNACK, 0);
			luat_stop_rtos_timer(mqtt_ctrl->reconnect_timer);
			luat_stop_rtos_timer(mqtt_ctrl->ping_timer);
			luat_stop_rtos_timer(mqtt_ctrl->conn_timer);
			luat_start_rtos_timer(mqtt_ctrl->ping_timer, mqtt_ctrl->keepalive*1000*3/4, 1);
            break;
        }
        case MQTT_MSG_PUBLISH : {
			LLOGD("MQTT_MSG_PUBLISH");
			qos = MQTTParseMessageQos(mqtt_ctrl->mqtt_packet_buffer);
#ifdef __LUATOS__
			if (mqtt_ctrl->app_cb)
			{
				luat_mqtt_app_cb_t mqtt_cb = mqtt_ctrl->app_cb;
				if (mqtt_cb(mqtt_ctrl, MQTT_MSG_PUBLISH))
				{
					goto MQTT_MSG_PUBLISH_DONE;
				}
			}
			const uint8_t* ptr;
			uint16_t topic_len = mqtt_parse_pub_topic_ptr(mqtt_ctrl->mqtt_packet_buffer, &ptr);
			uint32_t payload_len = mqtt_parse_pub_msg_ptr(mqtt_ctrl->mqtt_packet_buffer, &ptr);
			luat_mqtt_msg_t *mqtt_msg = (luat_mqtt_msg_t *)luat_heap_malloc(sizeof(luat_mqtt_msg_t)+topic_len+payload_len);
			mqtt_msg->topic_len = mqtt_parse_pub_topic(mqtt_ctrl->mqtt_packet_buffer, mqtt_msg->data);
            mqtt_msg->payload_len = mqtt_parse_publish_msg(mqtt_ctrl->mqtt_packet_buffer, mqtt_msg->data+topic_len);
            mqtt_msg->message_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
            mqtt_msg->flags = mqtt_ctrl->mqtt_packet_buffer[0];
            l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_PUBLISH, (int)mqtt_msg);
#else
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_PUBLISH, 0);
#endif
MQTT_MSG_PUBLISH_DONE:
			msg_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			LLOGD("msg %d qos %d", msg_id, qos);
			// 还要回复puback
			if (qos == 1) {
				LLOGD("reply puback %d", msg_id);
				mqtt_puback(&(mqtt_ctrl->broker), msg_id);
			}
			else if (qos == 2) {
				LLOGD("reply pubrec %d", msg_id);
				mqtt_pubrec(&(mqtt_ctrl->broker), msg_id);
			}
            break;
        }
        case MQTT_MSG_PUBACK : {
			msg_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
            l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_PUBACK, msg_id);
			break;
		}
		case MQTT_MSG_PUBREC : {
			msg_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			mqtt_pubrel(&(mqtt_ctrl->broker), msg_id);
			LLOGD("MQTT_MSG_PUBREC %d", msg_id);
			break;
		}
		case MQTT_MSG_PUBCOMP : {
			msg_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			LLOGD("MQTT_MSG_PUBCOMP %d", msg_id);
            l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_PUBCOMP, msg_id);
			break;
		}
		case MQTT_MSG_PUBREL : {
			msg_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			LLOGD("MQTT_MSG_PUBREL %d", msg_id);
            mqtt_pubcomp(&(mqtt_ctrl->broker), msg_id);
			break;
		}
        case MQTT_MSG_SUBACK : {
			LLOGD("MQTT_MSG_SUBACK");
			msg_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_SUBACK, mqtt_ctrl->mqtt_packet_buffer[4]);
            break;
        }
		case MQTT_MSG_UNSUBACK : {
			LLOGD("MQTT_MSG_UNSUBACK");
			msg_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_UNSUBACK, msg_id);
            break;
        }
        case MQTT_MSG_PINGRESP : {
			LLOGD("MQTT_MSG_PINGRESP");
			msg_id = mqtt_parse_msg_id(mqtt_ctrl->mqtt_packet_buffer);
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_PINGRESP, msg_id);
            break;
        }
		case MQTT_MSG_DISCONNECT : {
			LLOGD("MQTT_MSG_DISCONNECT");
			mqtt_ctrl->error_state = MQTT_ERROR_STATE_DISCONNECT;
            break;
        }
        default : {
			LLOGD("luat_mqtt_msg_cb error msg_tp:%d",msg_tp);
            break;
        }
    }
    return 0;
}

int32_t luat_mqtt_callback(void *data, void *param) {
	OS_EVENT *event = (OS_EVENT *)data;
	luat_mqtt_ctrl_t *mqtt_ctrl =(luat_mqtt_ctrl_t *)param;
	int ret = 0;
	// LLOGD("LINK %08X ON_LINE %08X EVENT %08X TX_OK %08X CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	LLOGD("network mqtt cb %8X %08X",event->ID & 0x0ffffffff, event->Param1);
	if (event->Param1){
		LLOGE("mqtt_callback param1 %d, event %d closing socket", event->Param1, event->ID - EV_NW_RESULT_BASE);

		switch(event->ID)
		{
		case EV_NW_RESULT_CONNECT:
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_CON_ERROR, 0);
			break;
		case EV_NW_RESULT_TX:
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_TX_ERROR, 0);
			break;
		default:
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_NET_ERROR, 0);
			break;
		}
		luat_mqtt_close_socket(mqtt_ctrl);
		return -1;
	}
	if (event->ID == EV_NW_RESULT_LINK){
		return 0; // 这里应该直接返回, 不能往下调用network_wait_event
	}else if(event->ID == EV_NW_RESULT_CONNECT){
		mqtt_ctrl->mqtt_state = MQTT_STATE_MQTT;
		ret = mqtt_connect(&(mqtt_ctrl->broker));
		if(ret==1){
			// luat_start_rtos_timer(mqtt_ctrl->ping_timer, mqtt_ctrl->keepalive*1000*3/4, 1);
		}
		else {
			LLOGI("mqtt_connect ret=%d\n", ret);
			luat_mqtt_close_socket(mqtt_ctrl);
		}
	}else if(event->ID == EV_NW_RESULT_EVENT){
		if (event->Param1==0){
			ret = luat_mqtt_read_packet(mqtt_ctrl);
			if (ret){
				return -1;
			}
			// LLOGD("luat_mqtt_read_packet ret:%d",ret);
			// luat_stop_rtos_timer(mqtt_ctrl->ping_timer);
			// luat_start_rtos_timer(mqtt_ctrl->ping_timer, mqtt_ctrl->keepalive*1000*0.75, 1);
		}
	}else if(event->ID == EV_NW_RESULT_TX){
#ifdef __LUATOS__
#else
		if (MQTT_STATE_READY == mqtt_ctrl->mqtt_state) {
			l_luat_mqtt_msg_cb(mqtt_ctrl, MQTT_MSG_TCP_TX_DONE, 0);
		}
#endif
		// luat_stop_rtos_timer(mqtt_ctrl->ping_timer);
		// luat_start_rtos_timer(mqtt_ctrl->ping_timer, mqtt_ctrl->keepalive*1000*0.75, 1);
	}else if(event->ID == EV_NW_RESULT_CLOSE){

	}
	ret = network_wait_event(mqtt_ctrl->netc, NULL, 0, NULL);
	if (ret < 0){
		LLOGW("network_wait_event ret %d, closing socket", ret);
		luat_mqtt_close_socket(mqtt_ctrl);
		return -1;
	}
	
    return 0;
}

int luat_mqtt_send_packet(void* socket_info, const void* buf, unsigned int count){
    luat_mqtt_ctrl_t * mqtt_ctrl = (luat_mqtt_ctrl_t *)socket_info;
	uint32_t tx_len = 0;
	int ret = network_tx(mqtt_ctrl->netc, buf, count, 0, NULL, 0, &tx_len, 0);
	if (ret < 0) {
		LLOGW("network_tx ret %d, closing socket", ret);
		luat_mqtt_close_socket(mqtt_ctrl);
		return 0;
	}
	if (tx_len != count) {
		LLOGW("network_tx expect %d but %d", count, tx_len);
		luat_mqtt_close_socket(mqtt_ctrl);
		return 0;
	}
	return count;
}

int luat_mqtt_connect(luat_mqtt_ctrl_t *mqtt_ctrl) {
	int ret = 0;
	mqtt_ctrl->error_state=0;
	if (!mqtt_ctrl->mqtt_packet_buffer) {
		mqtt_ctrl->mqtt_packet_buffer = luat_heap_malloc(mqtt_ctrl->rxbuff_size+4);
	}

	if (mqtt_ctrl->mqtt_packet_buffer == NULL){
		return -1;
	}
	memset(mqtt_ctrl->mqtt_packet_buffer, 0, mqtt_ctrl->rxbuff_size+4);
    const char *hostname = mqtt_ctrl->host;
    uint16_t port = mqtt_ctrl->remote_port;
    uint16_t keepalive = mqtt_ctrl->keepalive;
    LLOGD("host %s port %d keepalive %d", hostname, port, keepalive);
    mqtt_set_alive(&(mqtt_ctrl->broker), keepalive);
	ret = network_connect(mqtt_ctrl->netc, hostname, strlen(hostname), NULL, port, 0) < 0;
	LLOGD("network_connect ret %d", ret);
	if (ret < 0) {
        network_close(mqtt_ctrl->netc, 0);
        return -1;
    }
	mqtt_ctrl->mqtt_state = MQTT_STATE_SCONNECT;
	// 启动连接超时定时器
	luat_start_rtos_timer(mqtt_ctrl->conn_timer, mqtt_ctrl->conn_timeout * 1000, 0);
    return 0;
}

int luat_mqtt_set_will(luat_mqtt_ctrl_t *mqtt_ctrl, const char* topic, 
						const char* payload, size_t payload_len, 
						uint8_t qos, size_t retain) {
	if (mqtt_ctrl == NULL || mqtt_ctrl->netc == NULL)
		return -1;
	return mqtt_set_will(&mqtt_ctrl->broker, topic, payload, payload_len, qos, retain);
}

int luat_mqtt_set_cb(luat_mqtt_ctrl_t *mqtt_ctrl, luat_mqtt_cb_t mqtt_cb){
	if (mqtt_ctrl == NULL || mqtt_ctrl->netc == NULL)
		return -1;
	mqtt_ctrl->mqtt_cb = mqtt_cb;
	return 0;
}

LUAT_MQTT_STATE_E luat_mqtt_state_get(luat_mqtt_ctrl_t *mqtt_ctrl){
	return mqtt_ctrl->mqtt_state;
}
