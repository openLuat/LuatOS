#include "iot_adc.h"

/**ADC初始化 
*@param		channel:		adc通道
*@param     mode:       adc模式
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_adc_init(
                        E_AMOPENAT_ADC_CHANNEL channel  /* ADC编号 */,
    					E_AMOPENAT_ADC_CFG_MODE mode
                )
{
    return OPENAT_InitADC(channel,mode);
}

/**读取ADC数据
*@note ADC值，可以为空, 电压值，可以为空
*@param		channel:		adc通道
*@param		adcValue:	ADC值，可以为空
*@param		voltage:	电压值，可以为空
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_adc_read(
                        E_AMOPENAT_ADC_CHANNEL channel,     
                        UINT32* adcValue,                  
                        UINT32* voltage                   
                )
{
    return OPENAT_ReadADC(channel, adcValue, voltage);
}
