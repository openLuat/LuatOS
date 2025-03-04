#ifndef LUAT_ONEWIRE_H
#define LUAT_ONEWIRE_H

typedef struct
{
	uint32_t reset_keep_low_time;//reset低电平时间
	uint32_t reset_wait_ack_time;//reset恢复高电平到reset结束时间
	uint32_t reset_read_ack_before_time;//reset恢复高电平到可以读ACK的时间
	uint32_t reset_read_ack_time;//reset读ACK的时间
	uint32_t wr_slot_time;//整个slot时间。不包括起始信号
	uint32_t wr_start_time;//起始信号时间
	uint32_t wr_write_start_time;//slot开始到可以写的时间
	uint32_t wr_read_start_time;//slot开始到可以读的时间
	uint32_t wr_recovery_time;//slot读写完后恢复时间
}onewire_timing_us_t;

typedef struct
{
	uint32_t clock_div;//分频系数，默认0情况下自适应到1us1个tick
	uint32_t reset_keep_low_tick;
	uint32_t reset_wait_ack_tick;
	uint32_t reset_read_ack_before_tick;
	uint32_t reset_read_ack_tick;
	uint32_t wr_slot_tick;
	uint32_t wr_start_tick;
	uint32_t wr_write_start_tick;
	uint32_t wr_read_start_tick;
	uint32_t wr_recovery_tick;
}onewire_timing_tick_t;

typedef struct
{
	union
	{
		onewire_timing_us_t timing_us;
		onewire_timing_tick_t timing_tick;
	};
	uint8_t type; //0 timing_us, 1 timing_tick
}onewire_timing_t;

void luat_onewire_init(void);
void luat_onewire_setup_timing(int id, onewire_timing_t *timing);
void luat_onewire_reset(int id);
void luat_onewire_write_bit(int id, uint8_t level);
uint8_t luat_onewire_read_bit(int id);
void luat_onewire_write_byte(int id, const uint8_t *data, uint32_t len, uint8_t is_msb);
void luat_onewire_read_byte(int id, uint8_t *data, uint32_t len, uint8_t is_msb);
void luat_onewire_read_byte_with_cmd(int id, const uint8_t cmd, uint8_t *data, uint32_t len, uint8_t is_msb);
#endif
