#include "csdk.h"
#include "airtalk_def.h"
#include "airtalk_api.h"
#include "luat_airtalk.h"

#include "libemqtt.h"
#include "luat_mqtt.h"

typedef struct
{
	uint8_t save_data[RECORD_DATA_MAX + 28];
	uint8_t in_use;
}airtalk_net_data_cache_t;

typedef struct
{
	airtalk_network_ctrl_t *net_ctrl;
	luat_mqtt_ctrl_t *mqtt_ctrl;
	Buffer_Struct topic;
	airtalk_net_data_cache_t *net_data_cache;
	volatile uint32_t cache_cnt;
}airtalk_mqtt_ctrl_t;

static airtalk_mqtt_ctrl_t prv_mqtt;

static void luat_airtalk_mqtt_send_function(uint8_t *data, uint32_t len)
{
	mqtt_publish(&(prv_mqtt.mqtt_ctrl->broker), prv_mqtt.topic.Data, data, len, 0);
}

static void luat_airtalk_mqtt_recv_function(uint8_t *data, uint32_t len)
{
	if (len >= DOWNLOAD_CACHE_MAX)
	{
		LUAT_DEBUG_PRINT("mqtt data cache cnt error %d", len);
	}
	if (!prv_mqtt.net_data_cache[len].in_use)
	{
		LUAT_DEBUG_PRINT("mqtt data cache not used %d", len);
	}
	prv_mqtt.net_data_cache[len].in_use = 0;
}

static int airtalk_mqtt_cb(luat_mqtt_ctrl_t *mqtt_ctrl, uint16_t event)
{
	int ret;
	if (event != MQTT_MSG_PUBLISH)
	{
		return 0;
	}
	else
	{
		const uint8_t* ptr;
		uint32_t len;
		len = mqtt_parse_pub_topic_ptr(prv_mqtt.mqtt_ctrl->mqtt_packet_buffer, &ptr);
		if (!memcmp(prv_mqtt.topic.Data, ptr, len))
		{
			len = mqtt_parse_pub_msg_ptr(prv_mqtt.mqtt_ctrl->mqtt_packet_buffer, &ptr);
			if (len && (len <= RECORD_DATA_MAX + 28))
			{
				if (prv_mqtt.net_data_cache[prv_mqtt.cache_cnt].in_use)
				{
					LUAT_DEBUG_PRINT("mqtt data cache full!!!");
				}
				else
				{
					memcpy(prv_mqtt.net_data_cache[prv_mqtt.cache_cnt].save_data, ptr, len);
					luat_rtos_event_send(prv_mqtt.net_ctrl->task_handle, NULL, AIRTALK_EVENT_NETWORK_DOWNLINK_DATA, (uint32_t)prv_mqtt.net_data_cache[prv_mqtt.cache_cnt].save_data, len, prv_mqtt.cache_cnt);
					return 1;
				}

			}
		}
	}
	return 0;
}


void luat_airtalk_net_mqtt_init(void)
{
	prv_mqtt.net_data_cache = luat_heap_calloc(DOWNLOAD_CACHE_MAX, sizeof(airtalk_net_data_cache_t));
	prv_mqtt.net_ctrl = luat_airtalk_net_common_init(luat_airtalk_mqtt_send_function, luat_airtalk_mqtt_recv_function);
}

void luat_airtalk_net_set_mqtt_ctrl(void *ctrl)
{
	prv_mqtt.mqtt_ctrl = ctrl;
	prv_mqtt.mqtt_ctrl->app_cb = airtalk_mqtt_cb;
}

void luat_airtalk_net_set_mqtt_topic(const void *data, uint32_t len)
{
	OS_ReInitBuffer(&prv_mqtt.topic, len);
	OS_BufferWrite(&prv_mqtt.topic, data, len);
}
