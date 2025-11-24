#include "luat_base.h"
#include "luat_sys.h"
#include "luat_can.h"

#define LUAT_LOG_TAG "can"


int luat_can_base_init(uint8_t can_id, uint32_t rx_msg_cache_max)
{
	return 0;
}

int luat_can_set_callback(uint8_t can_id, luat_can_callback_t callback)
{
	return 0;
}

int luat_can_set_work_mode(uint8_t can_id, LUAT_CAN_WORK_MODE_E mode)
{
	return 0;
}

int luat_can_set_timing(uint8_t can_id, uint32_t bit_rate, uint8_t PTS, uint8_t PBS1, uint8_t PBS2, uint8_t SJW)
{
	return 0;
}

int luat_can_set_node(uint8_t can_id, uint32_t node_id, uint8_t is_extend_id)
{
	return 0;
}

int luat_can_set_filter(uint8_t can_id, uint8_t is_dual_mode, uint8_t ACR[4], uint8_t AMR[4])
{
	return 0;
}

int luat_can_tx_message(uint8_t can_id, uint32_t message_id, uint8_t is_extend_id, uint8_t is_RTR, uint8_t need_ack, uint8_t data_len, const void *data)
{
	return 0;
}

int luat_can_tx_stop(uint8_t can_id)
{
	return 0;
}


int luat_can_rx_message_from_cache(uint8_t can_id, luat_can_message_t *message)
{
	return 0;
}

int luat_can_reset(uint8_t can_id)
{
	return 0;
}

int luat_can_close(uint8_t can_id)
{
	return 0;
}

int luat_can_get_state(uint8_t can_id)
{
	return 0;
}

int luat_can_set_stb_io_level(uint8_t can_id, uint8_t on_off)
{
	return 0;
}

int luat_can_bus_off(uint8_t can_id)
{
	return 0;
}

int luat_can_get_capacity(uint8_t can_id, uint32_t *clk, uint32_t *div_min, uint32_t *div_max, uint32_t *div_step)
{
	return 0;
}

uint32_t luat_can_get_last_error(uint8_t can_id)
{
	return 0;
}

void luat_can_set_debug(uint8_t on_off)
{

}
