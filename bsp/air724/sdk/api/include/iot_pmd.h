#ifndef __IOT_PMD_H__
#define __IOT_PMD_H__

#include "iot_os.h"

/**
 * @defgroup iot_sdk_pmd 电源管理接口
 * @{
 */

/**充电初始化
*@param		chrMode:		充电方式
*@param		cfg:		    配置信息
*@param		pPmMessage:		消息回调函数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_pmd_init(     
                    E_AMOPENAT_PM_CHR_MODE chrMode,     
                    T_AMOPENAT_PMD_CFG*    cfg,       
                    PPM_MESSAGE            pPmMessage  
            );


/**获取电池状态
*@param		batStatus:		电池状态
**/
VOID iot_pmd_get_batteryStatus(
                    T_AMOPENAT_BAT_STATUS* batStatus    
                     );

/**获取充电器状态
*@param		chrStatus:		充电器状态
**/
VOID iot_pmd_get_chargerStatus(
                    T_AMOPENAT_CHARGER_STATUS* chrStatus
                     );

/**查询充电器HW状态接口
*@return	E_AMOPENAT_CHR_HW_STATUS: 充电器HW状态接口
**/
E_AMOPENAT_CHR_HW_STATUS iot_pmd_get_chargerHwStatus(
                    VOID
                    );

/**查询充电器HW状态接口
*@param		battStatus:		    电池状态
*@param		battVolt:		    电压值
*@param		battLevel:		    电压等级
*@param		chargerStatus:		充电器状态
*@param		chargeState:		充电状态
*@return	int:  返回0成功其余失败
**/
int iot_pmd_get_chg_param(BOOL *battStatus, u16 *battVolt, u8 *battLevel, BOOL *chargerStatus, u8 *chargeState);


/**正常开机
*@param		simStartUpMode:		开启SIM卡方式
*@param		nwStartupMode:		开启协议栈方式
*@return	TRUE: 	            成功
*           FALSE:              失败
**/
BOOL iot_pmd_poweron_system(                                     
                    E_AMOPENAT_STARTUP_MODE simStartUpMode,
                    E_AMOPENAT_STARTUP_MODE nwStartupMode
                  );

/**正常关机
*@note 正常关机 包括关闭协议栈和供电
**/
VOID iot_pmd_poweroff_system(VOID);

/**打开LDO
*@param		ldo:		    ldo通道
*@param		level:		    0-7 0:关闭 1~7电压等级
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_pmd_poweron_ldo(                                       
                    E_AMOPENAT_PM_LDO    ldo,
                    UINT8                level          
               );

/**进入睡眠
**/
VOID iot_pmd_enter_deepsleep(VOID);

/**退出睡眠
**/
VOID iot_pmd_exit_deepsleep(VOID);                               

/**获取开机原因值
*@return	E_AMOPENAT_POWERON_REASON: 	   返回开机原因值
**/
E_AMOPENAT_POWERON_REASON iot_pmd_get_poweronCasue(VOID);

/** @}*/

#endif

