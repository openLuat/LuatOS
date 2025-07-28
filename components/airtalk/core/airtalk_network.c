#include "csdk.h"
#include "luat_airtalk.h"
#include "airtalk_def.h"
#include "airtalk_api.h"
#include "luat_rtp.h"

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
	uint32_t tamp_high;
	uint32_t tamp_low;
	union
	{
		struct
		{
			uint32_t amr_data_len:16;
			uint32_t encode_type:4;
			uint32_t unused:12;
		};
		uint32_t fin_param;
	};
}airtalk_extern_head_data_t;


static airtalk_network_ctrl_t prv_network;

//播放完成
static void airtalk_full_stop(void)
{
	net_data_struct *net_cache;
	luat_airtalk_speech_stop_play();
	luat_stop_rtos_timer(prv_network.download_check_timer);
	while(!llist_empty(&prv_network.download_cache_head))
	{
		net_cache = (net_data_struct *)prv_network.download_cache_head.next;
		llist_del(&net_cache->node);
		luat_heap_free(net_cache);
	}
}

static void download_check_timer(void *param)
{
	LUAT_DEBUG_PRINT("broadcast long time no data!");
	luat_rtos_event_send(prv_network.task_handle, AIRTALK_EVENT_NETWORK_FORCE_STOP, 0, 0, 0, 0);
}


static void airtalk_network_task(void *param)
{
	uint64_t tamp;
	airtalk_extern_head_data_t extern_data;
	rtp_base_head_t *remote_rtp_head = luat_heap_malloc(sizeof(rtp_base_head_t));
	rtp_extern_head_t *remote_rtp_extern = luat_heap_malloc(sizeof(rtp_extern_head_t));
	rtp_base_head_t *local_rtp_head = luat_heap_malloc(sizeof(rtp_base_head_t));
	rtp_extern_head_t *local_rtp_extern = luat_heap_malloc(sizeof(rtp_extern_head_t) + sizeof(airtalk_extern_head_data_t));
	uint32_t local_time_diff, remote_time_diff, *remote_rtp_extern_data;
	luat_event_t event;
	net_data_struct *net_cache;
	record_data_struct *record_cache = luat_heap_calloc(UPLOAD_CACHE_MAX, sizeof(record_data_struct));

	int ret = -1;
	uint16_t local_sn = 0;
	uint8_t *p;
	uint8_t *out = luat_heap_malloc(RECORD_DATA_MAX + 28);
	uint8_t sync_lost = 1;

	memset(local_rtp_head, 0, sizeof(rtp_base_head_t));
	memset(local_rtp_extern, 0, sizeof(rtp_extern_head_t) + sizeof(airtalk_extern_head_data_t));
	local_rtp_head->version = 2;
	local_rtp_head->extension = 1;
	local_rtp_extern->profile_id = 1;
	local_rtp_extern->length = sizeof(airtalk_extern_head_data_t) >> 2;
	INIT_LLIST_HEAD(&prv_network.download_cache_head);
	INIT_LLIST_HEAD(&prv_network.upload_cache_head);
	INIT_LLIST_HEAD(&prv_network.free_cache_head);
	for(int i = 0; i < UPLOAD_CACHE_MAX; i++)
	{
		llist_add(&record_cache[i].node, &prv_network.free_cache_head);
	}
	prv_network.download_check_timer = luat_create_rtos_timer(download_check_timer, NULL, NULL);
	if (!prv_network.download_cache_time)
	{
		prv_network.download_cache_time = 500;
	}
	prv_network.record_cache_locker = luat_mutex_create();
	while(1){
		luat_rtos_event_recv(prv_network.task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
		switch(event.id)
		{
		case AIRTALK_EVENT_NETWORK_DOWNLINK_DATA:
			p = (uint8_t *)event.param1;
			ret = luat_unpack_rtp_head(p, event.param2, remote_rtp_head, &remote_rtp_extern_data);
			if (ret <= 0)
			{
				goto RX_DATA_DONE;
			}
			p += ret;
			event.param2 -= ret;
			ret = luat_unpack_rtp_extern_head(p, event.param2, remote_rtp_extern, &remote_rtp_extern_data);
			if (ret <= 0)
			{
				goto RX_DATA_DONE;
			}
			if (remote_rtp_extern->profile_id != 1)
			{
				LUAT_DEBUG_PRINT("profile id failed!");
				goto RX_DATA_DONE;
			}
			if (remote_rtp_extern->length != 3)
			{
				LUAT_DEBUG_PRINT("profile length failed!");
				goto RX_DATA_DONE;
			}
			extern_data.tamp_high = BytesGetBe32(remote_rtp_extern_data);
			extern_data.tamp_low = BytesGetBe32(&remote_rtp_extern_data[1]);
			extern_data.fin_param = BytesGetBe32(&remote_rtp_extern_data[2]);
			tamp = extern_data.tamp_high;
			tamp = (tamp << 32) + extern_data.tamp_low;
			p += ret;
			event.param2 -= ret;
			if (extern_data.amr_data_len != event.param2)
			{
				LUAT_DEBUG_PRINT("amr data len error %d,%d", extern_data.amr_data_len, event.param2);
				goto RX_DATA_DONE;
			}
			if ((uint32_t)p != event.param1 + 28)
			{
				LUAT_DEBUG_PRINT("head len error %x,%x", p, event.param1 + 28);
				goto RX_DATA_DONE;
			}
			if (sync_lost)
			{
				prv_network.data_sync_ok = 0;
				sync_lost = 0;
				prv_network.remote_ssrc_exsit = 0;
				LUAT_DEBUG_PRINT("wait fisrt rtp for sync");
			}
			if (!prv_network.remote_ssrc_exsit)
			{
				prv_network.data_sync_ok = 0;
				net_cache = luat_heap_malloc(sizeof(net_data_struct) + event.param3);
				net_cache->total_len = extern_data.amr_data_len;
				net_cache->remote_tamp = tamp;
				net_cache->local_tamp = luat_mcu_tick64_ms();
				memcpy(net_cache->amr_save_data, p, net_cache->total_len);
				llist_add_tail(&net_cache->node, &prv_network.download_cache_head);
				prv_network.remote_ssrc = remote_rtp_head->ssrc;
				LUAT_DEBUG_PRINT("sync start remote %llu %llu", net_cache->remote_tamp, net_cache->local_tamp);
			}
			else
			{
				if (prv_network.remote_ssrc != remote_rtp_head->ssrc)
				{
					LUAT_DEBUG_PRINT("ssrc error drop %x,%x", prv_network.remote_ssrc, remote_rtp_head->ssrc);
					goto RX_DATA_DONE;
				}
			}
			if (prv_network.data_sync_ok)
			{
				luat_airtalk_speech_save_downlink_data(p, extern_data.amr_data_len);
			}
			else
			{
				net_cache = luat_heap_malloc(sizeof(net_data_struct) + event.param3);
				net_cache->total_len = extern_data.amr_data_len;
				net_cache->remote_tamp = tamp;
				net_cache->local_tamp = luat_mcu_tick64_ms();
				memcpy(net_cache->amr_save_data, p, net_cache->total_len);
				llist_add_tail(&net_cache->node, &prv_network.download_cache_head);

				net_cache = (net_data_struct *)prv_network.download_cache_head.next;
				remote_time_diff = (uint32_t)(tamp - net_cache->remote_tamp);
				if (remote_time_diff >= (prv_network.download_cache_time - 20))
				{
					local_time_diff = (uint32_t)(luat_mcu_tick64_ms() - net_cache->local_tamp);
					if (local_time_diff >= (prv_network.download_cache_time - 20))
					{
						LUAT_DEBUG_PRINT("sync ok");
						prv_network.data_sync_ok = 1;
						while(!llist_empty(&prv_network.download_cache_head))
						{
							net_cache = (net_data_struct *)prv_network.download_cache_head.next;
							llist_del(&net_cache->node);
							luat_airtalk_speech_save_downlink_data(net_cache->amr_save_data, net_cache->total_len);
							luat_heap_free(net_cache);
						}
						luat_airtalk_speech_sync_ok();
					}
					else
					{
						LUAT_DEBUG_PRINT("sync failed %u, %u", remote_time_diff, local_time_diff);
						net_cache = (net_data_struct *)prv_network.download_cache_head.next;
						llist_del(&net_cache->node);
						luat_heap_free(net_cache);
						net_cache = (net_data_struct *)prv_network.download_cache_head.next;
						LUAT_DEBUG_PRINT("resync start remote %llu %llu", net_cache->remote_tamp, net_cache->local_tamp);
					}
				}
			}
			luat_airtalk_speech_start_play(prv_network.is_16k);
			luat_start_rtos_timer(prv_network.download_check_timer, 3000, 0);
RX_DATA_DONE:
			prv_network.recv_function((uint8_t *)event.param1, event.param3);
			break;
		case AIRTALK_EVENT_NETWORK_UPLINK_DATA:
			if (prv_network.is_ready)
			{
TX_DATA_START:
				record_cache = NULL;
				luat_rtos_mutex_lock(prv_network.record_cache_locker, LUAT_WAIT_FOREVER);
				if(!llist_empty(&prv_network.upload_cache_head))
				{
					record_cache = (record_data_struct *)prv_network.upload_cache_head.next;
					llist_del(&record_cache->node);

					local_rtp_head->sn = local_sn;
					local_sn++;
					extern_data.tamp_high = (uint32_t)(record_cache->local_tamp >> 32);
					extern_data.tamp_low = (uint32_t)(record_cache->local_tamp & 0x00000000ffffffff);
					extern_data.amr_data_len = record_cache->total_len;
					memcpy(local_rtp_extern->data, &extern_data, sizeof(extern_data));
					ret = luat_pack_rtp(local_rtp_head, local_rtp_extern, record_cache->save_data, record_cache->total_len, out, RECORD_DATA_MAX + 28);

					llist_add_tail(&record_cache->node, &prv_network.free_cache_head);
				}
				luat_rtos_mutex_unlock(prv_network.record_cache_locker);
				if (!record_cache)
				{
					goto TX_DATA_DONE;
				}
				if (ret > 0)
				{
					prv_network.send_function(out, ret);
				}
				else
				{
					LUAT_DEBUG_PRINT("rtp pack error");
				}
			}
			else
			{
				luat_rtos_mutex_lock(prv_network.record_cache_locker, LUAT_WAIT_FOREVER);
				while(!llist_empty(&prv_network.upload_cache_head))
				{
					record_cache = (record_data_struct *)prv_network.upload_cache_head.next;
					llist_del(&record_cache->node);
					llist_add_tail(&record_cache->node, &prv_network.free_cache_head);
				}
				LUAT_DEBUG_PRINT("upload %d, free %d", llist_num(&prv_network.upload_cache_head), llist_num(&prv_network.free_cache_head));
				luat_rtos_mutex_unlock(prv_network.record_cache_locker);
			}
TX_DATA_DONE:
			record_cache = NULL;
			break;
		case AIRTALK_EVENT_NETWORK_UPLINK_END:
			if (prv_network.is_ready)
			{
				local_rtp_head->sn = local_sn;
				local_sn++;
				extern_data.amr_data_len = 0;
				memcpy(local_rtp_extern->data, &extern_data, sizeof(extern_data));
				ret = luat_pack_rtp(local_rtp_head, local_rtp_extern, NULL, 0, out, RECORD_DATA_MAX + 28);
				if (ret > 0)
				{
					prv_network.send_function(out, ret);
				}
				else
				{
					LUAT_DEBUG_PRINT("rtp pack error");
				}
			}
			break;
		case AIRTALK_EVENT_NETWORK_READY_START:
			local_rtp_head->ssrc = prv_network.local_ssrc;
			luat_rtos_mutex_lock(prv_network.record_cache_locker, LUAT_WAIT_FOREVER);
			prv_network.is_ready = 1;
			while(!llist_empty(&prv_network.upload_cache_head))
			{
				record_cache = (record_data_struct *)prv_network.upload_cache_head.next;
				llist_del(&record_cache->node);
				llist_add_tail(&record_cache->node, &prv_network.free_cache_head);
			}
			LUAT_DEBUG_PRINT("upload %d, free %d", llist_num(&prv_network.upload_cache_head), llist_num(&prv_network.free_cache_head));
			luat_rtos_mutex_unlock(prv_network.record_cache_locker);
			break;
		case AIRTALK_EVENT_NETWORK_FORCE_SYNC:
			LUAT_DEBUG_PRINT("sync lost resync!");
			sync_lost = 1;
			break;
		case AIRTALK_EVENT_NETWORK_FORCE_STOP:
			if (prv_network.is_ready)
			{
				sync_lost = 1;
				prv_network.is_ready = 0;
				airtalk_full_stop();
			}
			break;
		case AIRTALK_EVENT_NETWORK_MSG:
			break;
		}
	}
}

void *luat_airtalk_net_common_init(CBDataFun_t send_function, CBDataFun_t recv_function)
{
	prv_network.send_function = send_function;
	prv_network.recv_function = recv_function;
	luat_rtos_task_create(&prv_network.task_handle, 6 * 1024, 90, "airtalk_net", airtalk_network_task, NULL, 0);
	return (void *)&prv_network;
}

void luat_airtalk_net_param_config(uint8_t audio_data_protocl, uint32_t download_cache_time)
{
	prv_network.audio_data_protocl = audio_data_protocl;
	prv_network.download_cache_time = download_cache_time;
}

void luat_airtalk_net_set_ssrc(uint32_t ssrc)
{
	prv_network.local_ssrc = ssrc;
}

void luat_airtalk_net_transfer_start(uint8_t work_mode)
{
	prv_network.work_mode = work_mode;
	luat_rtos_event_send(prv_network.task_handle, AIRTALK_EVENT_NETWORK_READY_START, 0, 0, 0, 0);
}

void luat_airtalk_net_transfer_stop(void)
{
	luat_rtos_event_send(prv_network.task_handle, AIRTALK_EVENT_NETWORK_FORCE_STOP, 0, 0, 0, 0);
}

void luat_airtalk_net_force_sync_downlink(void)
{
	if (prv_network.data_sync_ok)
	{
		luat_rtos_event_send(prv_network.task_handle, AIRTALK_EVENT_NETWORK_FORCE_SYNC, 0, 0, 0, 0);
	}
}

void luat_airtalk_net_save_uplink_head(uint64_t record_time)
{
	if (!prv_network.is_ready) return;
	luat_rtos_mutex_lock(prv_network.record_cache_locker, LUAT_WAIT_FOREVER);
	if (!prv_network.cur_record_node)
	{
		if (llist_empty(&prv_network.free_cache_head))
		{
			LUAT_DEBUG_PRINT("no cache for upload!");
			luat_rtos_mutex_unlock(prv_network.record_cache_locker);
			return;
		}
		prv_network.cur_record_node = (record_data_struct *)prv_network.free_cache_head.next;
		llist_del(&prv_network.cur_record_node->node);
	}
	prv_network.cur_record_node->local_tamp = record_time;
	prv_network.cur_record_node->total_len = 0;
	luat_rtos_mutex_unlock(prv_network.record_cache_locker);
}

void luat_airtalk_net_save_uplink_data(uint8_t *data, uint32_t len)
{
	if (!prv_network.is_ready) return;
	luat_rtos_mutex_lock(prv_network.record_cache_locker, LUAT_WAIT_FOREVER);
	if (!prv_network.cur_record_node)
	{
		luat_rtos_mutex_unlock(prv_network.record_cache_locker);
		LUAT_DEBUG_PRINT("no head!");
		return;
	}
	if (prv_network.cur_record_node->total_len + len <= RECORD_DATA_MAX)
	{
		memcpy(prv_network.cur_record_node->save_data + prv_network.cur_record_node->total_len, data, len);
		prv_network.cur_record_node->total_len += len;
	}
	else
	{
		LUAT_DEBUG_PRINT("no mem!");
	}
	luat_rtos_mutex_unlock(prv_network.record_cache_locker);
}

void luat_airtalk_net_uplink_once(void)
{
	if (!prv_network.is_ready) return;
	luat_rtos_mutex_lock(prv_network.record_cache_locker, LUAT_WAIT_FOREVER);
	if (!prv_network.cur_record_node)
	{
		luat_rtos_mutex_unlock(prv_network.record_cache_locker);
		LUAT_DEBUG_PRINT("no head!");
		return;
	}
	llist_add_tail(&prv_network.cur_record_node->node, &prv_network.upload_cache_head);
	prv_network.cur_record_node = NULL;
	luat_rtos_mutex_unlock(prv_network.record_cache_locker);
	luat_rtos_event_send(prv_network.task_handle, AIRTALK_EVENT_NETWORK_UPLINK_DATA, 0, 0, 0, 0);
}

void luat_airtalk_net_uplink_end(void)
{
	if (!prv_network.is_ready) return;
	luat_rtos_event_send(prv_network.task_handle, AIRTALK_EVENT_NETWORK_UPLINK_END, 0, 0, 0, 0);
}

void luat_airtalk_net_debug_switch(uint8_t on_off)
{
	prv_network.debug_on_off = on_off;
}

void luat_airtalk_net_init(void)
{
	switch(prv_network.audio_data_protocl)
	{
	case LUAT_AIRTALK_PROTOCOL_MQTT:
		luat_airtalk_net_mqtt_init();
		break;
	}
}

void luat_airtalk_use_16k(uint8_t on_off)
{
	prv_network.is_16k = on_off;
}

uint8_t luat_airtalk_is_16k(void)
{
	return prv_network.is_16k;
}
