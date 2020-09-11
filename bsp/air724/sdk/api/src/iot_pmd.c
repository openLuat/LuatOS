#include "iot_pmd.h"


/****************************** PMD ******************************/

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
            )
{
    return OPENAT_init_pmd(chrMode, cfg, pPmMessage);
}

/**获取电池状态
*@param		batStatus:		电池状态
**/
VOID iot_pmd_get_batteryStatus(
                    T_AMOPENAT_BAT_STATUS* batStatus    
                     )
{
    IVTBL(get_batteryStatus)(batStatus);    
}

/**获取充电器状态
*@param		chrStatus:		充电器状态
**/
VOID iot_pmd_get_chargerStatus(
                    T_AMOPENAT_CHARGER_STATUS* chrStatus
                     )
{
    IVTBL(get_chargerStatus)(chrStatus); 
}

/**查询充电器HW状态接口
*@return	E_AMOPENAT_CHR_HW_STATUS: 充电器HW状态接口
**/
E_AMOPENAT_CHR_HW_STATUS iot_pmd_get_chargerHwStatus(
                    VOID
                    )
{
    return IVTBL(get_chargerHwStatus)();
}

/**查询充电器HW状态接口
*@param		battStatus:		    电池状态
*@param		battVolt:		    电压值
*@param		battLevel:		    电压等级
*@param		chargerStatus:		充电器状态
*@param		chargeState:		充电状态
*@return	int:  返回0成功其余失败
**/
int iot_pmd_get_chg_param(BOOL *battStatus, u16 *battVolt, u8 *battLevel, BOOL *chargerStatus, u8 *chargeState)
{
    return IVTBL(get_chg_param)(battStatus, battVolt, battLevel, chargerStatus, chargeState);
}

/**正常开机
*@param		simStartUpMode:		开启SIM卡方式
*@param		nwStartupMode:		开启协议栈方式
*@return	TRUE: 	            成功
*           FALSE:              失败
**/
BOOL iot_pmd_poweron_system(        
                    E_AMOPENAT_STARTUP_MODE simStartUpMode,
                    E_AMOPENAT_STARTUP_MODE nwStartupMode
                  )
{
    return OPENAT_poweron_system(simStartUpMode, nwStartupMode);
}

/**正常关机
*@note 正常关机 包括关闭协议栈和供电
**/
VOID iot_pmd_poweroff_system(void)           

{
    OPENAT_poweroff_system();
}

/**打开LDO
*@param		ldo:		    ldo通道
*@param		level:		    0-7 0:关闭 1~7电压等级
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_pmd_poweron_ldo(                   
                    E_AMOPENAT_PM_LDO    ldo,
                    UINT8                level        
               )
{
    return OPENAT_poweron_ldo(ldo, level);
}

/**进入睡眠
**/
VOID iot_pmd_enter_deepsleep(VOID) 
{
    OPENAT_enter_deepsleep();
}

/**退出睡眠
**/
VOID iot_pmd_exit_deepsleep(VOID)
{
    OPENAT_exit_deepsleep();
}

/**获取开机原因值
*@return	E_AMOPENAT_POWERON_REASON: 	   返回开机原因值
**/
E_AMOPENAT_POWERON_REASON iot_pmd_get_poweronCasue (void)
{
    return OPENAT_get_poweronCause();
}
