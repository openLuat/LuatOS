#include "csdk.h"
#include "airtalk_def.h"
#include "airtalk_api.h"
#include "luat_airtalk.h"

#include "libemqtt.h"
#include "luat_mqtt.h"
#if 0
typedef struct
{
	llist_head node;
	uint64_t remote_tamp;
	uint64_t local_tamp;
	uint32_t total_len;
	uint8_t amr_save_data[];
}net_data_struct;

typedef struct
{
	luat_mqtt_ctrl_t *mqtt_ctrl;
	luat_rtos_task_handle mqtt_task_handle;
	luat_rtos_timer_t download_check_timer;
	Buffer_Struct uplink;
	llist_head download_cache_head;				//下行数据接收缓存队列
	uint32_t download_cache_time;
	Buffer_Struct topic;
	char self_id[15];
	uint8_t data_sync_ok;
	uint8_t uplink_ready;
	uint8_t speech_on;
	uint8_t is_16k;
	uint8_t debug_on_off;
}demo_mqtt_ctrl_t;

static demo_mqtt_ctrl_t prv_demo_mqtt;


//播放完成
static void end_broadcast_play(void)
{
	net_data_struct *net_cache;
	luat_airtalk_speech_stop_play();
	luat_stop_rtos_timer(prv_demo_mqtt.download_check_timer);
	while(!llist_empty(&prv_demo_mqtt.download_cache_head))
	{
		net_cache = (net_data_struct *)prv_demo_mqtt.download_cache_head.next;
		llist_del(&net_cache->node);
		luat_heap_free(net_cache);
	}
	prv_demo_mqtt.speech_on = 0;
}

static void download_check_timer(void *param)
{
	luat_rtos_event_send(prv_demo_mqtt.mqtt_task_handle, AIRTALK_EVENT_MQTT_FORCE_STOP, 0, 0, 0, 0);
}


static void airtalk_mqtt_cb(luat_mqtt_ctrl_t *mqtt_ctrl, uint16_t event)
{
	int ret;
	if (event != MQTT_MSG_PUBLISH)
	{
		luat_rtos_event_send(prv_demo_mqtt.mqtt_task_handle, AIRTALK_EVENT_MQTT_MSG, event, 0, 0, 0);
	}
	else
	{
		const uint8_t* ptr;
		uint32_t len;
		uint8_t *topic = NULL;
		uint8_t *payload = NULL;
		len = mqtt_parse_pub_topic_ptr(prv_demo_mqtt.mqtt_ctrl->mqtt_packet_buffer, &ptr);
		topic = luat_heap_calloc(len + 1, 1);
		memcpy(topic, ptr, len);
		len = mqtt_parse_pub_msg_ptr(prv_demo_mqtt.mqtt_ctrl->mqtt_packet_buffer, &ptr);
		if (len)
		{
			payload = luat_heap_malloc(len);
			memcpy(payload, ptr, len);
		}
		luat_rtos_event_send(prv_demo_mqtt.mqtt_task_handle, AIRTALK_EVENT_MQTT_DOWNLINK_DATA, (uint32_t)topic, (uint32_t)payload, len, 0);
	}
	return;
}

static void airtalk_demo_mqtt_task(void *param)
{
	uint64_t tamp;
	uint32_t local_time_diff, remote_time_diff;
	luat_event_t event;
	net_data_struct *net_cache;
	int ret = -1;
	uint8_t *p;
	char *packet_id;
	int i;
	uint16_t msgid = 0;
	char remote_client[16] = {0};
	INIT_LLIST_HEAD(&prv_demo_mqtt.download_cache_head);
	prv_demo_mqtt.download_check_timer = luat_create_rtos_timer(download_check_timer, NULL, NULL);
	if (!prv_demo_mqtt.download_cache_time)
	{
		prv_demo_mqtt.download_cache_time = 500;
	}
	if (!prv_demo_mqtt.topic.Data)
	{
		OS_BufferWrite(&prv_demo_mqtt.topic, "speech_demo/all", 16);
	}
	LUAT_DEBUG_PRINT("device id, %.*s topic %s", sizeof(prv_demo_mqtt.self_id), prv_demo_mqtt.self_id, prv_demo_mqtt.topic.Data);
	while(1){
		luat_rtos_event_recv(prv_demo_mqtt.mqtt_task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
		switch(event.id)
		{
		case AIRTALK_EVENT_MQTT_DOWNLINK_DATA:
			if (memcmp(prv_demo_mqtt.topic.Data, (char *)event.param1, prv_demo_mqtt.topic.Pos - 1))
			{
				LUAT_DEBUG_PRINT("topic %s", (char *)event.param1);
			}
			else
			{
				packet_id = (char *)event.param2;
				p = (uint8_t *)event.param2;
				if (packet_id[15] > 1)
				{
					goto RX_DATA_DONE;
				}
				if (!memcmp(packet_id, prv_demo_mqtt.self_id, 15))
				{
#ifdef SELF_TEST
#else
					goto RX_DATA_DONE;
#endif
				}
				if (packet_id[15])
				{
					if (prv_demo_mqtt.speech_on)
					{
						remote_client[0] = 0;
						end_broadcast_play();
						goto RX_DATA_DONE;
					}
					else
					{
						LUAT_DEBUG_PRINT("speech already stop!");
						goto RX_DATA_DONE;
					}
				}
				memcpy(&tamp, p + 16, 8);
				if (!remote_client[0])
				{
					prv_demo_mqtt.speech_on = 1;
					prv_demo_mqtt.data_sync_ok = 0;
					net_cache = luat_heap_malloc(sizeof(net_data_struct) + event.param3);
					net_cache->total_len = event.param3 - 24;
					net_cache->remote_tamp = tamp;
					net_cache->local_tamp = luat_mcu_tick64_ms();
					memcpy(net_cache->amr_save_data, p + 24, net_cache->total_len);
					llist_add_tail(&net_cache->node, &prv_demo_mqtt.download_cache_head);
					memcpy(remote_client, packet_id, 15);
					LUAT_DEBUG_PRINT("sync start remote %s %llu %llu", remote_client, net_cache->remote_tamp, net_cache->local_tamp);
				}
				else
				{
					if (memcmp(remote_client, packet_id, 15))
					{
						goto RX_DATA_DONE;
					}
				}
				{
					event.param3 -= 24;	//data_len
					p += 24; //data
					if (prv_demo_mqtt.data_sync_ok)
					{
						luat_airtalk_speech_save_downlink_data(p, event.param3);
					}
					else
					{
						net_cache = luat_heap_malloc(sizeof(net_data_struct) + event.param3);
						net_cache->total_len = event.param3;
						net_cache->remote_tamp = tamp;
						net_cache->local_tamp = luat_mcu_tick64_ms();
						memcpy(net_cache->amr_save_data, p, net_cache->total_len);
						llist_add_tail(&net_cache->node, &prv_demo_mqtt.download_cache_head);

						net_cache = (net_data_struct *)prv_demo_mqtt.download_cache_head.next;
						remote_time_diff = (uint32_t)(tamp - net_cache->remote_tamp);
						if (remote_time_diff >= (prv_demo_mqtt.download_cache_time - 20))
						{
							local_time_diff = (uint32_t)(luat_mcu_tick64_ms() - net_cache->local_tamp);
							if (local_time_diff >= (prv_demo_mqtt.download_cache_time - 20))
							{
								LUAT_DEBUG_PRINT("sync ok");
								prv_demo_mqtt.data_sync_ok = 1;
								while(!llist_empty(&prv_demo_mqtt.download_cache_head))
								{
									net_cache = (net_data_struct *)prv_demo_mqtt.download_cache_head.next;
									llist_del(&net_cache->node);
									luat_airtalk_speech_save_downlink_data(net_cache->amr_save_data, net_cache->total_len);
									luat_heap_free(net_cache);
								}
								luat_airtalk_speech_sync_ok();
							}
							else
							{
								LUAT_DEBUG_PRINT("sync failed %u, %u", remote_time_diff, local_time_diff);
								net_cache = (net_data_struct *)prv_demo_mqtt.download_cache_head.next;
								llist_del(&net_cache->node);
								luat_heap_free(net_cache);
								net_cache = (net_data_struct *)prv_demo_mqtt.download_cache_head.next;
								LUAT_DEBUG_PRINT("resync start remote %s %llu %llu", remote_client, net_cache->remote_tamp, net_cache->local_tamp);
							}
						}
					}
					luat_airtalk_speech_start_play(prv_demo_mqtt.is_16k);
					luat_start_rtos_timer(prv_demo_mqtt.download_check_timer, 3000, 0);
				}
			}
RX_DATA_DONE:
			luat_heap_free((char *)event.param1);
			luat_heap_free((char *)event.param2);
			break;
		case AIRTALK_EVENT_MQTT_UPLINK_DATA:
			if (prv_demo_mqtt.uplink_ready)
			{
				mqtt_publish(&(prv_demo_mqtt.mqtt_ctrl->broker), (char *)prv_demo_mqtt.topic.Data, prv_demo_mqtt.uplink.Data, prv_demo_mqtt.uplink.Pos, 0);
			}
			break;
		case AIRTALK_EVENT_MQTT_UPLINK_END:
			if (prv_demo_mqtt.uplink_ready)
			{
				prv_demo_mqtt.uplink.Pos = 16;
				prv_demo_mqtt.uplink.Data[15] = 1;
				mqtt_publish(&(prv_demo_mqtt.mqtt_ctrl->broker), (char *)prv_demo_mqtt.topic.Data, prv_demo_mqtt.uplink.Data, prv_demo_mqtt.uplink.Pos, 0);
			}
			break;
		case AIRTALK_EVENT_MQTT_FORCE_SYNC:
			LUAT_DEBUG_PRINT("sync lost resync!");
			remote_client[0] = 0;
			break;
		case AIRTALK_EVENT_MQTT_FORCE_STOP:
			LUAT_DEBUG_PRINT("broadcast long time no data!");
			remote_client[0] = 0;
			end_broadcast_play();
			break;
		case AIRTALK_EVENT_MQTT_MSG:
			switch(event.param1)
			{
			case MQTT_MSG_TCP_TX_DONE:
				//如果用QOS0发送，可以作为发送成功的初步判断依据
				break;
			case MQTT_MSG_CONNACK:
				if(prv_demo_mqtt.mqtt_ctrl->mqtt_packet_buffer[3] != 0x00){
					LUAT_DEBUG_PRINT("CONACK 0x%02x",prv_demo_mqtt.mqtt_ctrl->mqtt_packet_buffer[3]);
					prv_demo_mqtt.mqtt_ctrl->error_state = prv_demo_mqtt.mqtt_ctrl->mqtt_packet_buffer[3];
	                luat_mqtt_close_socket(prv_demo_mqtt.mqtt_ctrl);
	                break;
	            }
				mqtt_subscribe(&(prv_demo_mqtt.mqtt_ctrl->broker), (char *)prv_demo_mqtt.topic.Data, &msgid, 0);
				msgid++;
				break;
			case MQTT_MSG_SUBACK:
				if(prv_demo_mqtt.mqtt_ctrl->mqtt_packet_buffer[4] > 0x02){
					LUAT_DEBUG_PRINT("SUBACK 0x%02x",prv_demo_mqtt.mqtt_ctrl->mqtt_packet_buffer[4]);
	                luat_mqtt_close_socket(prv_demo_mqtt.mqtt_ctrl);
	                break;
	            }
				LUAT_DEBUG_PRINT("mqtt_subscribe ok");
				OS_ReInitBuffer(&prv_demo_mqtt.uplink, 1024);
				OS_BufferWrite(&prv_demo_mqtt.uplink, prv_demo_mqtt.self_id, 15);
				prv_demo_mqtt.data_sync_ok = 0;
				prv_demo_mqtt.uplink_ready = 1;
				luat_airtalk_callback(LUAT_AIRTALK_CB_ON_LINE_IDLE, NULL, 0);
				break;
			case MQTT_MSG_DISCONNECT:
				LUAT_DEBUG_PRINT("airtalk_mqtt_cb mqtt disconnect");
				prv_demo_mqtt.uplink_ready = 0;
				end_broadcast_play();
				luat_airtalk_callback(LUAT_AIRTALK_CB_OFF_LINE, NULL, 0);
				break;
			case MQTT_MSG_TIMER_PING:
				break;
			case MQTT_MSG_RECONNECT:
				break;
			case MQTT_MSG_CLOSE :
				prv_demo_mqtt.uplink_ready = 0;
				luat_airtalk_callback(LUAT_AIRTALK_CB_OFF_LINE, NULL, 0);
				break;
			}
			break;
		}
	}
}

void luat_airtalk_net_demo_mqtt_init(uint8_t is_16k)
{
	prv_demo_mqtt.is_16k = is_16k;
	OS_InitBuffer(&prv_demo_mqtt.uplink, 1024);
	luat_rtos_task_create(&prv_demo_mqtt.mqtt_task_handle, 8 * 1024, 90, "airtalk_mqtt", airtalk_demo_mqtt_task, NULL, 0);
}

void luat_airtalk_net_param_config(uint32_t download_cache_time)
{
	prv_demo_mqtt.download_cache_time = download_cache_time;
}

void luat_airtalk_net_uplink_start(void)
{
	prv_demo_mqtt.data_sync_ok = 0;
}

void luat_airtalk_net_force_sync_downlink(void)
{
	if (prv_demo_mqtt.data_sync_ok)
	{
		luat_rtos_event_send(prv_demo_mqtt.mqtt_task_handle, AIRTALK_EVENT_MQTT_FORCE_SYNC, 0, 0, 0, 0);
	}
}

void luat_airtalk_net_save_uplink_head(uint64_t record_time)
{
	if (!prv_demo_mqtt.uplink_ready) return;
	prv_demo_mqtt.uplink.Pos = 16;
	if (record_time)
	{
		prv_demo_mqtt.uplink.Data[15] = 0;
		OS_BufferWrite(&prv_demo_mqtt.uplink, &record_time, 8);
	}
	else
	{
		prv_demo_mqtt.uplink.Data[15] = 1;
	}
}

void luat_airtalk_net_save_uplink_data(uint8_t *data, uint32_t len)
{
	if (!prv_demo_mqtt.uplink_ready) return;
	OS_BufferWrite(&prv_demo_mqtt.uplink, data, len);
}

void luat_airtalk_net_uplink_once(void)
{
	if (!prv_demo_mqtt.uplink_ready) return;
	luat_rtos_event_send(prv_demo_mqtt.mqtt_task_handle, AIRTALK_EVENT_MQTT_UPLINK_DATA, 0, 0, 0, 0);
}

void luat_airtalk_net_uplink_end(void)
{
	if (!prv_demo_mqtt.uplink_ready) return;
	luat_rtos_event_send(prv_demo_mqtt.mqtt_task_handle, AIRTALK_EVENT_MQTT_UPLINK_END, 0, 0, 0, 0);
}

int luat_airtalk_net_set_device_id(char *id, uint32_t len)
{
	if (prv_demo_mqtt.uplink_ready) return -ERROR_DEVICE_BUSY;
	if (len > 15) len = 15;
	memset(prv_demo_mqtt.self_id, 0, sizeof(prv_demo_mqtt.self_id));
	memcpy(prv_demo_mqtt.self_id, id, len);
	return 0;
}

void luat_airtalk_net_set_mqtt_ctrl(void *ctrl)
{
	prv_demo_mqtt.mqtt_ctrl = ctrl;
	prv_demo_mqtt.mqtt_ctrl->app_cb = airtalk_mqtt_cb;
}

void luat_airtalk_net_set_mqtt_topic(const void *data, uint32_t len)
{
	OS_ReInitBuffer(&prv_demo_mqtt.topic, len);
	OS_BufferWrite(&prv_demo_mqtt.topic, data, len);
}

void luat_airtalk_net_debug_switch(uint8_t on_off)
{
	prv_demo_mqtt.debug_on_off = on_off;
}

#endif
