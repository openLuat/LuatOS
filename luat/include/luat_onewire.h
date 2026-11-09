#ifndef LUAT_ONEWIRE_H
#define LUAT_ONEWIRE_H
#include "luat_base.h"
#define LUAT_ONEWIRE_VIRTUAL_MASK	(0x80)

enum {
	LUAT_ONEWIRE_EVENT_RESET_DONE,
	LUAT_ONEWIRE_EVENT_OP_DONE,
	LUAT_ONEWIRE_EVENT_FIND_ID_DONE,
};

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

typedef void (*luat_onewire_callback_t)(int id, uint8_t event, uint8_t is_ack, uint8_t is_error, uint8_t rx_len, uint8_t *rx_data, void *user_data);
/**
 * @brief 单总线初始化
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 */
void luat_onewire_init(int id);

/**
 * @brief 单总线关闭
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 */
void luat_onewire_deinit(int id);
/**
 * @brief 单总线调试开关
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param on_off 1打开，0关闭
 */
void luat_onewire_debug(int id, uint8_t on_off);
/**
 * @brief 单总线时序设置
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param timing 时序设置
 */
void luat_onewire_setup_timing(int id, onewire_timing_t *timing);
/**
 * @brief 单总线复位
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param check_ack 是否检测ACK信号，1检测，0不检测
 * @return 0成功，其他没有读到ACK信号
 */
int luat_onewire_reset(int id, uint8_t check_ack);
/**
 * @brief 单总线写1个bit
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param level 电平
 */
void luat_onewire_write_bit(int id, uint8_t level);
/**
 * @brief 单总线读1个bit
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @return 1 高 0 低
 */
uint8_t luat_onewire_read_bit(int id);
/**
 * @brief 单总线写N字节
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
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
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
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
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param cmd 命令
 * @param data 需要读出的数据
 * @param len 需要读出的长度
 * @param is_msb 是否MSB优先，默认是0，一般都是LSB先
 * @param need_reset 是否需要先reset，1是，0否
 * @param check_ack 是否在reset过程中检测ACK信号，1检测，0不检测，如果需要reset并且检测ACK，一旦没用检测到ACK直接停止
 * @return 0成功，其他没有读到ACK信号
 */
int luat_onewire_read_byte_with_cmd(int id, const uint8_t cmd, uint8_t *data, uint32_t len, uint8_t is_msb, uint8_t need_reset, uint8_t check_ack);

/**
 * @brief 通过硬件定时器和gpio创建一条虚拟单总线
 * 
 * @param hwtimer_id 硬件定时器
 * @param gpio gpio编号
 * @return >0 成功返回虚拟总线ID，其他失败 
 */
int luat_onewire_create_virtual(int hwtimer_id, int gpio);

/**
 * @brief 释放一条虚拟单总线
 * 
 * @param id 虚拟单总线id
 */
void luat_onewire_destroy_virtual(int id);

void luat_onewire_set_callback(int id, luat_onewire_callback_t callback, void *user_data);

/**
 * @brief 单总线复位
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param is_sync 是否同步方式
 * @param is_ack 如果是同步方式，返回是否读到ACK信号
 * @return 0无异常 其他失败
 */
int luat_onewire_reset_v2(int id, uint8_t is_sync, uint8_t *is_ack);

/**
 * @brief 单总线写N字节
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param data 需要写入数据
 * @param len 需要写入长度
 * @param is_msb 是否MSB优先发送，默认是0，一般都是LSB先发送
 * @param need_reset 是否需要先reset，1是，0否
 * @param check_ack 是否在reset过程中检测ACK信号，1检测，0不检测，如果需要reset并且检测ACK，一旦没用检测到ACK直接停止
 * @param is_sync 是否同步方式
 * @param is_ack 如果是同步方式，返回是否读到ACK信号
 * @return 0无异常 其他失败
 */
int luat_onewire_write_byte_v2(int id, const uint8_t *data, uint32_t len, uint8_t is_msb, uint8_t need_reset, uint8_t check_ack, uint8_t is_sync, uint8_t *is_ack);
/**
 * @brief 单总线读N字节
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param data 需要读出的数据
 * @param len 需要读出的长度
 * @param is_msb 是否MSB优先，默认是0，一般都是LSB先
 * @param need_reset 是否需要先reset，1是，0否
 * @param check_ack 是否在reset过程中检测ACK信号，1检测，0不检测，如果需要reset并且检测ACK，一旦没用检测到ACK直接停止
 * @param is_sync 是否同步方式
 * @param is_ack 如果是同步方式，返回是否读到ACK信号
 * @return 0无异常 其他失败
 */
int luat_onewire_read_byte_v2(int id, uint8_t *data, uint32_t len, uint8_t is_msb, uint8_t need_reset, uint8_t check_ack, uint8_t is_sync, uint8_t *is_ack);

/**
 * @brief 单总线先发一个命令，再读N字节
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param cmd 命令
 * @param data 需要读出的数据
 * @param len 需要读出的长度
 * @param is_msb 是否MSB优先，默认是0，一般都是LSB先
 * @param need_reset 是否需要先reset，1是，0否
 * @param check_ack 是否在reset过程中检测ACK信号，1检测，0不检测，如果需要reset并且检测ACK，一旦没用检测到ACK直接停止
 * @param is_sync 是否同步方式
 * @param is_ack 如果是同步方式，返回是否读到ACK信号
 * @return 0无异常 其他失败
 */
int luat_onewire_read_byte_with_cmd_v2(int id, const uint8_t cmd, uint8_t *data, uint32_t len, uint8_t is_msb, uint8_t need_reset, uint8_t check_ack, uint8_t is_sync, uint8_t *is_ack);

/**
 * @brief 单总线发出2个read bit+1个write bit操作来搜索ID
 * 
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @param is_all_done 是否已经全部搜索完成，如果返回1，则无法再搜索，需要luat_onewire_find_id_stop重置搜索
 * @return 0无异常 其他失败
 */
int luat_onewire_find_id(int id, uint8_t *is_all_done);
/**
 * @brief 单总线停止搜索所有ID，并且清空内置搜索状态
 * 
 * @param id id, 硬件单总线编号或者虚拟总线编号,如果只有一条硬件单总线则写0,使用虚拟总线必须填写luat_onewire_create_virtual创建的虚拟总线编号
 * @return 0无异常 其他失败
 */
int luat_onewire_find_id_stop(int id);
#endif
