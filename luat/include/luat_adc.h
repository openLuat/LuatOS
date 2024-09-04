/******************************************************************************
 *  ADC设备操作抽象层
 *  @author wendal
 *  @since 0.1.5
 *****************************************************************************/
#ifndef Luat_ADC_H
#define Luat_ADC_H

#include "luat_base.h"
/**
 * @defgroup luatos_device_adc ADC接口
 * @{
*/
#define LUAT_ADC_CH_CPU		(-1)
#define LUAT_ADC_CH_VBAT	(-2)

typedef enum
{
	ADC_SET_GLOBAL_RANGE = 0x80,
}ADC_SET_CMD_ENUM;

/**
 * @brief ADC控制命令
*/
typedef enum LUAT_ADC_CTRL_CMD
{
	LUAT_ADC_SET_GLOBAL_RANGE,/**< 量程 */
}LUAT_ADC_CTRL_CMD_E;

/// @brief ADC量程
typedef enum LUAT_ADC_RANGE
{
	LUAT_ADC_AIO_RANGE_1_2,
	LUAT_ADC_AIO_RANGE_1_4,
	LUAT_ADC_AIO_RANGE_1_6,
	LUAT_ADC_AIO_RANGE_1_9,
	LUAT_ADC_AIO_RANGE_2_4,
	LUAT_ADC_AIO_RANGE_2_6,
	LUAT_ADC_AIO_RANGE_2_7,
	LUAT_ADC_AIO_RANGE_3_2,
	LUAT_ADC_AIO_RANGE_3_8,
	LUAT_ADC_AIO_RANGE_4_0,
	LUAT_ADC_AIO_RANGE_4_8,
	LUAT_ADC_AIO_RANGE_6_4,
	LUAT_ADC_AIO_RANGE_9_6,
	LUAT_ADC_AIO_RANGE_19_2,
	LUAT_ADC_AIO_RANGE_MAX,
	
	LUAT_ADC_VBAT_RANGE_2_0_RATIO,
	LUAT_ADC_VBAT_RANGE_2_2_RATIO,
	LUAT_ADC_VBAT_RANGE_2_6_RATIO,
	LUAT_ADC_VBAT_RANGE_3_2_RATIO,
	LUAT_ADC_VBAT_RANGE_4_0_RATIO,
	LUAT_ADC_VBAT_RANGE_5_3_RATIO,
	LUAT_ADC_VBAT_RANGE_8_0_RATIO,
	LUAT_ADC_VBAT_RANGE_16_0_RATIO,
}LUAT_ADC_RANGE_E;

/**
 * @brief ADC控制参数
*/
typedef union luat_adc_ctrl_param
{	
	LUAT_ADC_RANGE_E range;/**< adc量程*/
	void *userdata;/**< 预留 */
} luat_adc_ctrl_param_t;

/**
 * luat_adc_open
 * Description: 打开一个adc通道
 * @param pin[in] adc通道的序号
 * @param args[in] 保留用,传NULL
 * @return 0 成功, 其他值为失败
 */
int luat_adc_open(int pin, void* args);

/**
 * luat_adc_read
 * Description: 读取adc通道的值
 * @param pin[in] adc通道的序号
 * @param val[out] adc通道的原始值
 * @param val2[out] adc通道的计算值,与具体通道有关
 * @return 0 成功, 其他值为失败
 */
int luat_adc_read(int pin, int* val, int* val2);

/**
 * luat_adc_close
 * Description: 关闭adc通道
 * @param pin[in] adc通道的序号
 * @return 0 成功, 其他值为失败
 */
int luat_adc_close(int pin);

/**
 * luat_adc_global_config
 * Description: 设置adc全局参数
 * @param tp[in]  参数类型
 * @param val[in] 参数值
 * @return 0 成功, 其他值为失败
 */
int luat_adc_global_config(int tp, int val);

/**
 * luat_adc_ctrl
 * Description: 设置ADC参数，部分功能会与luat_adc_global_config有相同的想过
 * @param id[in] adc通道的序号
 * @param cmd[in]  参数类型
 * @param param[in] 参数值
 * @return 0 成功, 其他值为失败
 */
int luat_adc_ctrl(int id, LUAT_ADC_CTRL_CMD_E cmd, luat_adc_ctrl_param_t param);
/**
 * luat_adc_open_and_disable_lowpower
 * Description: 打开一个adc通道，并且阻止系统进入休眠
 * @param pin[in] adc通道的序号
 * @return 0 成功, 其他值为失败
 */
int luat_adc_open_and_disable_lowpower(int id);
/**
 * luat_adc_read_fast
 * Description: 读取adc通道的值，必须由luat_adc_open_and_disable_lowpower初始化过的通道
 * @param pin[in] adc通道的序号
 * @param val[out] adc通道的原始值
 * @param val2[out] adc通道的计算值,与具体通道有关
 * @return 0 成功, 其他值为失败
 */
int luat_adc_read_fast(int id, int* val, int* val2);
/**
 * luat_adc_close_and_enable_lowpower
 * Description: 关闭adc通道，并且允许系统进入休眠
 * @param pin[in] adc通道的序号
 * @return 0 成功, 其他值为失败
 */
int luat_adc_close_and_enable_lowpower(int id);
/** @}*/
#endif
