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

/**
 * @brief 单总线初始化
 * @param id 总线ID，如果只有1条，随便写
 */
void luat_onewire_init(int id);
/**
 * @brief 单总线调试开关
 * @param id 总线ID，如果只有1条，随便写
 * @param on_off 1打开，0关闭
 */
void luat_onewire_debug(int id, uint8_t on_off);
/**
 * @brief 单总线时序设置
 * @param id 总线ID，如果只有1条，随便写
 * @param timing 时序设置
 */
void luat_onewire_setup_timing(int id, onewire_timing_t *timing);
/**
 * @brief 单总线复位
 * @param id 总线ID，如果只有1条，随便写
 * @param check_ack 是否检测ACK信号，1检测，0不检测
 * @return 0成功，其他没有读到ACK信号
 */
int luat_onewire_reset(int id, uint8_t check_ack);
/**
 * @brief 单总线写1个bit
 * @param id 总线ID，如果只有1条，随便写
 * @param level 电平
 */
void luat_onewire_write_bit(int id, uint8_t level);
/**
 * @brief 单总线读1个bit
 * @param id 总线ID，如果只有1条，随便写
 * @return 1 高 0 低
 */
uint8_t luat_onewire_read_bit(int id);
/**
 * @brief 单总线写N字节
 * @param id 总线ID，如果只有1条，随便写
 * @param data 需要写入数据
 * @param len 需要写入长度
 * @param is_msb 是否MSB优先发送，默认是0，一般都是LSB先发送
 * @param need_reset 是否需要先reset，1是，0否
 * @param check_ack 是否在reset过程中检测ACK信号，1检测，0不检测，如果需要reset并且检测ACK，一旦没用检测到ACK直接停止
 * @return 0成功，其他没有读到ACK信号
 */
int luat_onewire_write_byte(int id, const uint8_t *data, uint32_t len, uint8_t is_msb, uint8_t need_reset, uint8_t check_ack);
/**
 * @brief 单总线读N字节
 * @param id 总线ID，如果只有1条，随便写
 * @param data 需要读出的数据
 * @param len 需要读出的长度
 * @param is_msb 是否MSB优先，默认是0，一般都是LSB先
 * @param need_reset 是否需要先reset，1是，0否
 * @param check_ack 是否在reset过程中检测ACK信号，1检测，0不检测，如果需要reset并且检测ACK，一旦没用检测到ACK直接停止
 * @return 0成功，其他没有读到ACK信号
 */
int luat_onewire_read_byte(int id, uint8_t *data, uint32_t len, uint8_t is_msb, uint8_t need_reset, uint8_t check_ack);

/**
 * @brief 单总线先发一个命令，再读N字节
 * @param id 总线ID，如果只有1条，随便写
 * @param cmd 命令
 * @param data 需要读出的数据
 * @param len 需要读出的长度
 * @param is_msb 是否MSB优先，默认是0，一般都是LSB先
 * @param need_reset 是否需要先reset，1是，0否
 * @param check_ack 是否在reset过程中检测ACK信号，1检测，0不检测，如果需要reset并且检测ACK，一旦没用检测到ACK直接停止
 * @return 0成功，其他没有读到ACK信号
 */
int luat_onewire_read_byte_with_cmd(int id, const uint8_t cmd, uint8_t *data, uint32_t len, uint8_t is_msb, uint8_t need_reset, uint8_t check_ack);

#endif
