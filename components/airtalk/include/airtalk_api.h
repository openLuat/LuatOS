/*
 * airtalk_api.h
 *
 *  Created on: 2025年6月26日
 *      Author: Administrator
 */

#ifndef AIRTALK_INCLUDE_AIRTALK_API_H_
#define AIRTALK_INCLUDE_AIRTALK_API_H_
#include "luat_network_adapter.h"
#include "luat_rtos.h"

void luat_airtalk_net_init(void);
void *luat_airtalk_net_common_init(CBDataFun_t send_function, CBDataFun_t recv_function);
void luat_airtalk_net_param_config(uint8_t audio_data_protocl, uint32_t download_cache_time);
void luat_airtalk_net_debug_switch(uint8_t on_off);
void luat_airtalk_net_transfer_start(void);
void luat_airtalk_net_transfer_stop(void);
void luat_airtalk_net_save_uplink_head(uint64_t record_time);
void luat_airtalk_net_save_uplink_data(uint8_t *data, uint32_t len);
void luat_airtalk_net_uplink_once(void);
void luat_airtalk_net_uplink_end(void);

void luat_airtalk_net_force_sync_downlink(void);

void luat_airtalk_net_mqtt_init(void);
void luat_airtalk_net_set_mqtt_ctrl(void *ctrl);
void luat_airtalk_net_set_mqtt_topic(const void *data, uint32_t len);

void luat_airtalk_speech_init(void);
void luat_airtalk_speech_audio_param_config(int multimedia_id, uint8_t audio_sleep_mode);
void luat_airtalk_speech_debug_switch(uint8_t on_off);
int luat_airtalk_speech_set_one_block_frame_cnt(uint8_t decode_frame_cnt, uint8_t encode_frame_cnt);
void luat_airtalk_speech_start_play(uint8_t is_16k);
void luat_airtalk_speech_stop_play(void);
void luat_airtalk_speech_record_switch(uint8_t on_off);
void luat_airtalk_speech_sync_ok(void);
void luat_airtalk_speech_save_downlink_data(uint8_t *data, uint32_t len);

void luat_airtalk_use_16k(uint8_t on_off);
uint8_t luat_airtalk_is_16k(void);
#endif /* AIRTALK_INCLUDE_AIRTALK_API_H_ */
