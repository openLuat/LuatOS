/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: brezen
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2012.09.24  brezen    创建文件
    V0.2      2012.12.17  brezen    添加UART部分
    V0.3      2012.12.27  brezen    添加pmd部分
    V0.4      2012.12.27  brezen    添加spi部分 
    V0.5      2013.01.08  brezen    添加触摸屏驱动
    V0.6      2013.01.11  brezen    添加spi部分 
    V0.7      2013.01.15  brezen    修改lcd frequence为uint32
    V0.8      2013.01.15  brezen    1、添加gpo 2、添加lcd gpio 参数
    V0.9      2013.01.17  brezen    添加ldo
    V1.0      2013.01.28  brezen    添加psam
    V1.1      2013.02.06  Jack.li   添加camera接口
    V1.2      2013.02.09  Jack.li   添加视频录制接口
    V1.3      2013.03.01  brezen    添加串口OPENAT_UART_3
	V1.4      2014.1.17   brezen    添加蓝牙HFP功能
	V1.5      2014.5.22   brezen    增加蓝牙工程测试模式
	V1.6      2014.6.9    brezen    设置蓝牙睡眠模式
	V1.7      2014.6.26   brezen    添加蓝牙spp接口
	V1.8      2015.08.27  panjun    Simplify MMI's frame for Video.
	V1.9      2016.03.26  panjun    Add TTSPLY's API.
*********************************************************/

#ifndef __AM_OPENAT_DRV_H__
#define __AM_OPENAT_DRV_H__

#ifdef __cplusplus
#if __cplusplus
extern "C"{
#endif
#endif /* __cplusplus */
/*----------------------------------------------*
 * 包含头文件                                   *
 *----------------------------------------------*/
#include <am_openat_common.h> 
/*----------------------------------------------*
 * 宏定义                                       *
 *----------------------------------------------*/
/*+\NEW\RUFEI\2015.8.27\Add adc fuction*/
#define DEFAULT_VALUE 0xffff
/*-\NEW\RUFEI\2015.8.27\Add adc fuction*/ 


#if defined(A9188S_VER_A11) || defined (AM_A9189_VER_A10)
#define OPENAT_LCD_RST_GPIO 50
#elif defined (A9188S_VER_A10)
#define OPENAT_LCD_RST_GPIO 41
#else
#define OPENAT_LCD_RST_GPIO 50
#endif


typedef enum
{
  OPENAT_DRV_EVT_INVALID,
  /* charge plug in/out */
  OPENAT_DRV_EVT_CHR_PRESENT_IND,

  /* battery status */
  OPENAT_DRV_EVT_BAT_PRESENT_IND, //暂时不支持
  OPENAT_DRV_EVT_BAT_LEVEL_IND,
  OPENAT_DRV_EVT_BAT_VOLT_LOW,
  OPENAT_DRV_EVT_BAT_OVERVOLT,    //暂时不支持

  /* charging status */
  OPENAT_DRV_EVT_BAT_CHARGING,
  OPENAT_DRV_EVT_BAT_CHR_FULL,
/*+\BUG WM-1016\rufei\2013.11.19\ 修改平台充电控制*/
  OPENAT_DRV_EVT_BAT_RECHARGING,
  OPENAT_DRV_EVT_BAT_RECHR_FULL,
/*-\BUG WM-1016\rufei\2013.11.19\ 修改平台充电控制*/
  OPENAT_DRV_EVT_BAT_CHR_STOP,
  OPENAT_DRV_EVT_BAT_CHR_ERR,

  /* power on cause */
  OPENAT_DRV_EVT_PM_POWERON_ON_IND,

  /* GPIO interrupt */
  OPENAT_DRV_EVT_GPIO_INT_IND,
  
  /* LCD event */
  OPENAT_DRV_EVT_LCD_REFRESH_REQ,
  
  /* CAMERA event */
  OPENAT_DRV_EVT_VIDEORECORD_FINISH_IND,

  /*CAMERA DATA event*/
  /*+\NEW\zhuwangbin\2020.4.26\添加openat cam接口*/
  OPENAT_DRV_EVT_CAMERA_DATA_IND,
  /*-\NEW\zhuwangbin\2020.4.26\添加openat cam接口*/
  
  /* VIDEO event */
  OPENAT_DRV_EVT_VIDEO_PLAY_FINISH_IND,
  OPENAT_DRV_EVT_VIDEO_CURRENT_TIME_IND,

  /* UART event */
  OPENAT_DRV_EVT_UART_RX_DATA_IND,
/*+\NEW\zhuwangbin\2018.8.10\添加OPENAT_DRV_EVT_UART_TX_DONE_IND上报*/
  OPENAT_DRV_EVT_UART_TX_DONE_IND,
/*-\NEW\zhuwangbin\2018.8.10\添加OPENAT_DRV_EVT_UART_TX_DONE_IND上报*/
  /* ALARM event */
  OPENAT_DRV_EVT_ALARM_IND,

  /*app 程序自动校验*/
  OPENAT_SW_AUTO_VERIFY_IND,
  
}E_OPENAT_DRV_EVT;

/*************************************************
* GPIO
*************************************************/
typedef UINT8 E_AMOPENAT_GPIO_PORT;

/*********************************************
* 描述: GPIO中断方式
* 功能: 
*********************************************/
typedef enum
{
    OPENAT_GPIO_NO_INT,
    OPENAT_GPIO_INT_HIGH_LEVEL,
    OPENAT_GPIO_INT_LOW_LEVEL,
    OPENAT_GPIO_INT_BOTH_EDGE,
    OPENAT_GPIO_INT_FALLING_EDGE,
    OPENAT_GPIO_INT_RAISING_EDGE,
}T_OPENAT_GPIO_INT_TYPE;


/*********************************************
* 描述: PIN功能模式
* 功能: 
*********************************************/
typedef enum
{
  OPENAT_GPIO_INVALID_MODE,
  OPENAT_GPIO_INPUT, //as gpio or gpo
  OPENAT_GPIO_OUTPUT,
  OPENAT_GPIO_INPUT_INT,
  OPENAT_GPIO_MODE_UNKNOWN
}T_OPENAT_GPIO_MODE;

/*+\BUG\AMOPENAT-13\brezen\2013.4.13\修改Openat和驱动api层数据类型强转*/
typedef void (*OPENAT_GPIO_EVT_HANDLE)(E_OPENAT_DRV_EVT evt, E_AMOPENAT_GPIO_PORT gpioPort,unsigned char state);
/*-\BUG\AMOPENAT-13\brezen\2013.4.13\修改Openat和驱动api层数据类型强转*/

/*********************************************
* 描述: GPIO中断参数
* 功能: 
*********************************************/
typedef struct
{
  unsigned int            debounce; //ms
  T_OPENAT_GPIO_INT_TYPE     intType;
  OPENAT_GPIO_EVT_HANDLE     intCb;
}T_OPENAT_GPIO_INT_CFG;

/*********************************************
* 描述: GPIO参数
* 功能: 
*********************************************/
typedef struct
{
  unsigned char      defaultState;
  T_OPENAT_GPIO_INT_CFG   intCfg;
}T_OPENAT_GPIO_PARAM;

typedef struct T_AMOPENAT_GPIO_CFG_TAG
{
    /// Direction of the GPIO
    T_OPENAT_GPIO_MODE    mode;
    T_OPENAT_GPIO_PARAM   param;
}T_AMOPENAT_GPIO_CFG;

/*+\NEW \lijiaodi\2018.08.16\添加GPIO中断的软防抖功能*/
typedef struct  GpioInterruptConfigTag
{
    T_OPENAT_GPIO_INT_TYPE intType;
    BOOL             ignoreFirstInterrupt;
}
GpioInterruptConfig;

typedef struct GpioIntDebounceTag
{
    INT16           debouncePrd;
    BOOL         oldLineState;
/*+:\BUG\AMOPENAT-24\brezen\2013.05.17\GPIO4在打电话时出现中断无效现象*/		
    INT16           debounceCount; /*debouncePrd/10*/
    INT16           checkedCount;  /*已经防抖的个数*/
    INT16           sucCheckCount; /*防抖成功的个数*/

    INT16           debounceFaildCount; /*防抖失败记录，调试使用*/
    INT16           debounceSuccCount; /*防抖成功记录，调试使用*/
    INT16           intCount;

    /***************
    checkedCount  每次防抖++,最大为debounceCount*2;
    
    sucCheckCount 如果防抖失败就将sucCheck清0
    ***/
/*-:\BUG\AMOPENAT-24\brezen\2013.05.17\GPIO4在打电话时出现中断无效现象*/	    
}GpioIntDebounce;

typedef struct GpioIntTmrInfoTag
{
   const INT32       timerId;
   INT32             gpioNum;
   HANDLE            hTimer;
}
GpioIntTmrInfo;

typedef struct GpioIntConfigTag
{
    INT32                gpioNum;
    GpioInterruptConfig  intCfg;
    GpioIntDebounce      debounce;
    OPENAT_GPIO_EVT_HANDLE  gpiointcb;
    struct GpioIntConfigTag* prev;
    struct GpioIntConfigTag* next;
}
GpioIntConfig;

typedef struct gpioIntConfigQueue
{
  GpioIntConfig* head;
  GpioIntConfig* tail;
}GpioIntConfigQueue;


/*Internal Signal To The GPIO Module*/
typedef struct PdGpioStartIntTimerReqTag
{
  INT32       timerId;
  INT16           period;
}
PdGpioStartIntTimerReq;

typedef struct pdgpioTimerExpiryTag
{
    INT32                timerId;
    INT32                userValue;
}pdgpioTimerExpiry;
/*-\NEW \lijiaodi\2018.08.16\添加GPIO中断的软防抖功能*/

/*************************************************
* ADC
*************************************************/
/*+\NEW\RUFEI\2015.8.27\Add adc fuction*/
typedef enum E_AMOPENAT_ADC_CHANNEL_TAG
{
	/*+\NEW\zhuwangbin\2020.2.11\添加openat adc接口*/
    OPENAT_ADC_0,
    OPENAT_ADC_1,
    OPENAT_ADC_2,
	OPENAT_ADC_3,
	OPENAT_ADC_4,
	OPENAT_ADC_5,
	OPENAT_ADC_6,
	OPENAT_ADC_7,
	OPENAT_ADC_8,
	OPENAT_ADC_9,
	OPENAT_ADC_10,
	OPENAT_ADC_11,
	OPENAT_ADC_12,
	OPENAT_ADC_13,
    OPENAT_ADC_14,
    OPENAT_ADC_15,
    OPENAT_ADC_16,
    OPENAT_ADC_17,
    OPENAT_ADC_18,
    OPENAT_ADC_19,
    OPENAT_ADC_20,
    OPENAT_ADC_21,
	OPENAT_ADC_22,
	OPENAT_ADC_23,
    OPENAT_ADC_24,
    OPENAT_ADC_25,
    OPENAT_ADC_26,
    OPENAT_ADC_27,
    OPENAT_ADC_28,
    OPENAT_ADC_29,
    OPENAT_ADC_30,
    OPENAT_ADC_31,
    OPENAT_ADC_QTY
    /*-\NEW\zhuwangbin\2020.2.11\添加openat adc接口*/
}E_AMOPENAT_ADC_CHANNEL;
typedef enum E_AMOPENAT_ADC_CFG_MODE_TAG
{
    OPENAT_ADC_MODE_NULL = 0,/*默认值*/
    OPENAT_ADC_MODE_1 = 1,  /*更新1次*/
    /*其他值可以直接强转*/

    OPENAT_ADC_MODE_MAX = 0xff /*永久更新，对功耗有一定影响*/
}E_AMOPENAT_ADC_CFG_MODE;

typedef enum E_AMOPENAT_ADC_STATUS_TAG
{
    OPENAT_ADC_STATUS_NULL, /*默认状态*/
    OPENAT_ADC_STATUS_INIT, /*初始化*/
    OPENAT_ADC_STATUS_READING,/*已更新值，仍继续更新  */ 
    OPENAT_ADC_STATUS_READ_COMPLETE,/*完成读值*/
    
    OPENAT_ADC_STATUS_QTY
}E_AMOPENAT_ADC_STATUS;

typedef struct E_AMOPENAT_ADC_CONTEXT_TAG
{
    E_AMOPENAT_ADC_STATUS status;
    E_AMOPENAT_ADC_CFG_MODE adc_mode;
    E_AMOPENAT_ADC_CHANNEL channel;
    kal_uint32 adc_value;
    kal_uint32 volt;
    kal_uint32 adc_handle;
}E_AMOPENAT_ADC_CONTEXT;
/*-\NEW\RUFEI\2015.8.27\Add adc fuction*/

/*************************************************
* PM
*************************************************/
typedef enum
{
  OPENAT_PM_CHR_BY_DEFAULT, /* 系统自动控制充电 */
  OPENAT_PM_CHR_BY_CUST,    /* 用户自己控制充电 */
/*+\NEW WM-746\rufei\2013.3.30\增加芯片IC充电*/
  OPENAT_PM_CHR_BY_IC,
/*-\NEW WM-746\rufei\2013.3.30\增加芯片IC充电*/
  OPENAT_PM_CHR_INVALID_MODE
}E_AMOPENAT_PM_CHR_MODE;

/*+\BUG WM-771\rufei\2013.4.11\完善充电流程*/
typedef enum
{
  OPENAT_PM_LI_BAT,
  OPENAT_PM_NICD_BAT
}E_AMOPENAT_BAT_TYPE;
/*-\BUG WM-771\rufei\2013.4.11\完善充电流程*/

/*+\BUG WM-771\rufei\2013.5.20\完善充电流程*/
typedef enum
{
    /// Charge is forced OFF
/*+\NEW\RUFEI\2015.5.8\完善充电控制*/
    OPENAT_PM_CHARGER_00MA,  /* 不支持该功能*/
    OPENAT_PM_CHARGER_20MA,  /*只用于充满电流使用*/
    OPENAT_PM_CHARGER_30MA,  /*只用于充满电流使用*/
    OPENAT_PM_CHARGER_40MA,  /*只用于充满电流使用*/
    OPENAT_PM_CHARGER_50MA,
    OPENAT_PM_CHARGER_60MA,
    /// Charge with a  70 mA current
    OPENAT_PM_CHARGER_70MA,
    /// Charge with a 200 mA current
    OPENAT_PM_CHARGER_200MA,
    /// Charge with a 300 mA current
    OPENAT_PM_CHARGER_300MA,
    /// Charge with a 400 mA current
    OPENAT_PM_CHARGER_400MA,
    /// Charge with a 500 mA current
    OPENAT_PM_CHARGER_500MA,
    /// Charge with a 600 mA current
    OPENAT_PM_CHARGER_600MA,
    /// Charge with a 700 mA current
    OPENAT_PM_CHARGER_700MA,
    /// Charge with a 800 mA current
    OPENAT_PM_CHARGER_800MA,
    OPENAT_PM_CHARGER_900MA,
    OPENAT_PM_CHARGER_1000MA,
    OPENAT_PM_CHARGER_1100MA,
    OPENAT_PM_CHARGER_1200MA,
    OPENAT_PM_CHARGER_1300MA,
    OPENAT_PM_CHARGER_1400MA,
    OPENAT_PM_CHARGER_1500MA,
/*-\NEW\RUFEI\2015.5.8\完善充电控制*/

    OPENAT_PM_CHARGE_CURRENT_QTY
} E_OPENAT_CHARGE_CURRENT;
/*-\BUG WM-771\rufei\2013.5.20\完善充电流程*/

/*+\NEW\RUFEI\2015.5.8\完善充电控制*/
typedef enum
{
    OPENAT_PM_VOLT_00_000V,
    OPENAT_PM_VOLT_01_800V,
    OPENAT_PM_VOLT_02_800V,
    OPENAT_PM_VOLT_03_000V,
    OPENAT_PM_VOLT_03_200V,
    OPENAT_PM_VOLT_03_400V,
    OPENAT_PM_VOLT_03_600V,
    OPENAT_PM_VOLT_03_800V,
    OPENAT_PM_VOLT_03_850V,
    OPENAT_PM_VOLT_03_900V,
    OPENAT_PM_VOLT_04_000V,
    OPENAT_PM_VOLT_04_050V,
    OPENAT_PM_VOLT_04_100V,
    OPENAT_PM_VOLT_04_120V,
    OPENAT_PM_VOLT_04_130V,
    OPENAT_PM_VOLT_04_150V,
    OPENAT_PM_VOLT_04_160V,
    OPENAT_PM_VOLT_04_170V,
    OPENAT_PM_VOLT_04_180V,
    OPENAT_PM_VOLT_04_200V,
    OPENAT_PM_VOLT_04_210V,
    OPENAT_PM_VOLT_04_220V,
    OPENAT_PM_VOLT_04_230V,
    OPENAT_PM_VOLT_04_250V,
    OPENAT_PM_VOLT_04_260V,
    OPENAT_PM_VOLT_04_270V,
    OPENAT_PM_VOLT_04_300V,
    OPENAT_PM_VOLT_04_320V,
    OPENAT_PM_VOLT_04_350V,
    OPENAT_PM_VOLT_04_370V,
    OPENAT_PM_VOLT_04_400V,
    OPENAT_PM_VOLT_04_420V,

    OPENAT_PM_VOLT_QTY
} E_OPENAT_PM_VOLT;
/*-\NEW\RUFEI\2015.5.8\完善充电控制*/

typedef union T_AMOPENAT_PMD_CFG_TAG
{
  struct{
  UINT8 pad;   /*无意义，目前不支持这种充电*/
/*+\BUG WM-771\rufei\2013.4.11\完善充电流程*/
  E_AMOPENAT_BAT_TYPE batType; /*保留扩展使用*/
  UINT16 batfullLevel;/*保留扩展使用，mv*/
/*+\BUG WM-771\rufei\2013.5.20\完善充电流程*/
  UINT16 batPreChargLevel;
/*-\BUG WM-771\rufei\2013.5.20\完善充电流程*/
  UINT16 poweronLevel;/*保留以后扩展使用，mv*/
  UINT16 poweroffLevel;/*保留以后扩展使用，mv*/
/*-\BUG WM-771\rufei\2013.4.11\完善充电流程*/
  }cust;/*目前不支持这种充电*/
  struct{
/*+\NEW\RUFEI\2015.5.8\完善充电控制*/
  BOOL batdetectEnable;/*暂不支持*/

  BOOL tempdetectEnable;/*暂不支持*/
  UINT16 templowLevel;
  UINT16 temphighLevel;

  E_AMOPENAT_BAT_TYPE batType;

  BOOL batLevelEnable;
  E_OPENAT_PM_VOLT ccLevel;/*恒流充电阶段*/
  E_OPENAT_PM_VOLT cvLevel;/*恒压充电阶段，充满电压点*/
  E_OPENAT_PM_VOLT ovLevel;/*充电限制电压*/
  E_OPENAT_PM_VOLT pvLevel;/*回充电压*/
  E_OPENAT_PM_VOLT poweroffLevel;
  E_AMOPENAT_ADC_CHANNEL batAdc;/*暂不支持*/
  E_AMOPENAT_ADC_CHANNEL tempAdc;/*暂不支持*/
  
  BOOL currentControlEnable;
  E_OPENAT_CHARGE_CURRENT ccCurrent;
  E_OPENAT_CHARGE_CURRENT fullCurrent;/*当测量出来的电流值小于该值时，认为充满*/
  UINT16 ccOnTime;/*单位s,暂不支持*/
  UINT16 ccOffTime;/*单位s,暂不支持*/
    
  BOOL  chargTimeOutEnable;
  UINT16 TimeOutMinutes; /*超时分钟数*/

  BOOL disableCharginCall;/*暂不支持*/
/*-\NEW\RUFEI\2015.5.8\完善充电控制*/

  }deFault;
}T_AMOPENAT_PMD_CFG;


typedef enum
{
  PMD_MODULE_GPIO,
  PMD_MODULE_SPI,
  PMD_MODULE_UART,
  PMD_MODULE_I2C,
  PMD_MODULE_AUDIO,
  PMD_MODULE_TRACE,
  PMD_MODULE_APP,
  PMD_MOUDLE_MAX
}E_AMOPENAT_PMD_M;

typedef enum
{
  OPENAT_PM_BATT_NORMAL,
  OPENAT_PM_BATT_CHARGING,
  OPENAT_PM_BATT_ERR,
  OPENAT_PM_BATT_INVALID
}E_AMOPENAT_BAT_STATUS;

typedef enum
{
  OPENAT_PM_CHARGER_STATUS_ERR,
  OPENAT_PM_CHARGER_PLUG_IN,
  OPENAT_PM_CHARGER_PLUG_OUT,
  OPENAT_PM_CHARGER_STATUS_INVALID
}E_AMOPENAT_CHARGER_STATUS;

typedef enum
{
  OPENAT_PM_CHARGER_WALL,
  OPENAT_PM_CHARGER_USB,
  OPENAT_PM_CHARGER_INVALID
}E_AMOPENAT_CHARGER_TYPE;

typedef enum
{ 
	OPENAT_LDO_POWER_VLCD,
	OPENAT_LDO_POWER_MMC,
	/*+\new\wj\2020.4.14\添加电压域VSIM1控制gpio29，30，31*/
	OPENAT_LDO_POWER_VSIM1,
	/*-\new\wj\2020.4.14\添加电压域VSIM1控制gpio29，30，31*/
	/*+\new\shenyuanyuan\2020.5.21\模块无VCAM输出*/
	OPENAT_LDO_POWER_VCAMA,
	OPENAT_LDO_POWER_VCAMD,
	/*-\new\shenyuanyuan\2020.5.21\模块无VCAM输出*/
	/*+\BUG\wangyuan\2020.08.22\BUG_2883:lua开发820GPS供电引脚设置*/
	OPENAT_LDO_POWER_VIBR,
	/*-\BUG\wangyuan\2020.08.22\BUG_2883:lua开发820GPS供电引脚设置*/
	OPENAT_LDO_POWER_INVALID
}E_AMOPENAT_PM_LDO;

typedef struct
{
  uint16              batteryTemp;        /* 电池温度ADC值*/
  uint16              batteryVolt;
/*+\BUG WM-771\rufei\2013.5.22\完善充电流程3*/
  E_AMOPENAT_ADC_CHANNEL tempChannel;  
  E_AMOPENAT_ADC_CHANNEL batteryChannel;
/*-\BUG WM-771\rufei\2013.5.22\完善充电流程3*/
  E_AMOPENAT_BAT_STATUS  batteryState;
}T_AMOPENAT_BAT_STATUS;

typedef struct
{
/*+\BUG WM-771\rufei\2013.5.22\完善充电流程3*/
  uint16                    chargerVolt;
  E_AMOPENAT_ADC_CHANNEL    chargerChannel;
/*-\BUG WM-771\rufei\2013.5.22\完善充电流程3*/
  E_AMOPENAT_CHARGER_TYPE   chargerType;   /* TODO 暂时不支持 */
  E_AMOPENAT_CHARGER_STATUS chargerStatus;
}T_AMOPENAT_CHARGER_STATUS;

typedef enum
{
  OPENAT_PM_CHR_STOP_NO_REASON,
  OPENAT_PM_CHR_STOP_BAT_FULL,
  OPENAT_PM_CHR_STOP_BAT_ERR,
  OPENAT_PM_CHR_STOP_TIMEOUT,
/*+\BUG WM-771\rufei\2013.8.2\完善充电流程*/
  OPENAT_PM_CHR_STOP_TEMP,
  OPENAT_PM_CHR_STOP_CHARGER_ERR,
/*-\BUG WM-771\rufei\2013.8.2\完善充电流程*/
  OPENAT_PM_CHR_STOP_NO_CHARGER,
  OPENAT_PM_CHR_STOP_OTER_REASON,
/*+\BUG WM-1016\rufei\2013.11.19\ 修改平台充电控制*/
  OPENAT_PM_RECHR_STOP_BAT_FULL,
/*-\BUG WM-1016\rufei\2013.11.19\ 修改平台充电控制*/
  OPENAT_PM_CHR_STOP_INVALID_REASON
}E_AMOPENAT_CHR_STOP_REASON;

typedef enum
{
  OPENAT_PM_POWERON_BY_KEY,     /* 按键开机 */
  OPENAT_PM_POWERON_BY_CHARGER, /* 充电开机 */
  OPENAT_PM_POWERON_BY_ALARM,   /* 闹钟开机 */
  OPENAT_PM_POWERON_BY_RESET,   /* 软件重启开机 */ 
  OPENAT_PM_POWERON_BY_EXCEPTION, /* 异常重启 */ 
  OPENAT_PM_POWERON_BY_PIN_RESET, /* reset 键重启 */ 
  OPENAT_PM_POWERON_BY_UNKOWN = 0xff
	
}E_AMOPENAT_POWERON_REASON;

/*+\NEW\lijiaodi\2019.12.29\task_087:开机原因值的获取 */
typedef enum
{
	RESET_BY_ERR,
	RESET_BY_SW,
	RESET_BY_UNKOWN,
}reset_cause;
/*-\NEW\lijiaodi\2019.12.29\task_087:开机原因值的获取 */

typedef enum
{
  OPENAT_PM_STARTUP_MODE_DEFAULT,              /* 由系统决定 */
  OPENAT_PM_STARTUP_MODE_ON,                   /* 强制开启 */
  OPENAT_PM_STARTUP_MODE_OFF                   /* 强制不开启 */
}E_AMOPENAT_STARTUP_MODE;

/*+\NEW\RUFEI\2014.2.13\增加OPENAT查询充电器HW状态接口*/
typedef enum
{
    OPENAT_PM_CHR_HW_STATUS_UNKNOWN,
    OPENAT_PM_CHR_HW_STATUS_AC_OFF,
    OPENAT_PM_CHR_HW_STATUS_AC_ON
}E_AMOPENAT_CHR_HW_STATUS;
/*-\NEW\RUFEI\2014.2.13\增加OPENAT查询充电器HW状态接口*/

typedef struct 
{
  E_OPENAT_DRV_EVT evtId;
  union
  {
/*+\BUG WM-771\rufei\2013.4.11\完善充电流程*/
    struct{
    BOOL present;
    }batpresentind,chrpresentind;
    struct{
    UINT8 pad; /*空，无意义*/
    }chrstartind,chargererrind;
/*+\BUG WM-1016\rufei\2013.11.19\ 修改平台充电控制*/
    struct{
    UINT8 batteryLevel;  /*0-100 %*/
    }batlevelind,batovervoltind,chargingind,chrfullind,rechargingind,rechrfullind;
/*-\BUG WM-1016\rufei\2013.11.19\ 修改平台充电控制*/
    struct{
    E_AMOPENAT_CHR_STOP_REASON chrStopReason;
    }chrstopind;
    struct{
    E_AMOPENAT_POWERON_REASON powerOnReason;
    }poweronind;
    struct
    {
     BOOL start;  //true :start false:end
     UINT8 mask;  //bit0:sw bit1:key bit2:pw1 bit3:pw2 
    }swAutoVerifyInd;
/*-\BUG WM-771\rufei\2013.4.11\完善充电流程*/
  }param;

}T_AMOPENAT_PM_MSG;

typedef void (*PPM_MESSAGE)(T_AMOPENAT_PM_MSG* pmMessage);

/*************************************************
* KEYPAD
*************************************************/
typedef enum E_AMOPENAT_KEYPAD_TYPE_TAG
{
    OPENAT_KEYPAD_TYPE_MATRIX,      /* 阵列键盘 */
    OPENAT_KEYPAD_TYPE_ADC,         /* ADC键盘 */
    OPENAT_KEYPAD_TYPE_GPIO,        /* GPIO键盘 */
    OPENAT_KEYPAD_TYPE_MAX
}E_AMOPENAT_KEYPAD_TYPE;

#define OPENAT_KEYPAD_ENABLE_DEBOUNCE (1 << ((OPENAT_KEYPAD_TYPE_MAX >> 1) + 1))

/*+\NEW WM-718\rufei\2013.3.21\ 增加gpio键盘加密模式*/
typedef enum E_AMOPENAT_GPIOKEY_MODE_TAG
{
    OPENAT_GPIOKEY_IRQ, /*普通模式*/
    OPENAT_GPIOKEY_ENCRYPT, /*加密模式*/
        
    OPENAT_GPIOKEY_MAX
}E_AMOPENAT_GPIOKEY_MODE;
/*-\NEW WM-718\rufei\2013.3.21\ 增加gpio键盘加密模式*/

typedef struct T_AMOPENAT_TOUCH_MESSAGE_TAG
{
    UINT8 type; /**/
    UINT16 x;
    UINT16 y;
}T_AMOPENAT_TOUCH_MESSAGE;

typedef VOID (*TOUCH_MESSAGE)(T_AMOPENAT_TOUCH_MESSAGE *pTouchMessage);


typedef struct T_AMOPENAT_KEYPAD_MESSAGE_TAG
{
    UINT8 nType; /**/
    BOOL bPressed; /* 是否是按下消息 */
    union {
        struct {
            UINT8 r;
            UINT8 c;
        }matrix, gpio;

/*+\NEW OPENAT-771\rufei\2013.8.8\上报ADC键盘采样数据*/
        struct{
            UINT16  adcValue;
            UINT16* adcList; /*在T_AMOPENAT_KEYPAD_CONFIG 中打开isreportData，则需要free  adcList*/
            UINT16  adcCount;
        }adc;
/*-\NEW OPENAT-771\rufei\2013.8.8\上报ADC键盘采样数据*/
    }data;
}T_AMOPENAT_KEYPAD_MESSAGE;

typedef VOID (*PKEYPAD_MESSAGE)(T_AMOPENAT_KEYPAD_MESSAGE *pKeypadMessage);

typedef struct T_AMOPENAT_KEYPAD_CONFIG_TAG
{
    E_AMOPENAT_KEYPAD_TYPE type;
    PKEYPAD_MESSAGE pKeypadMessageCallback;
    union {
        struct {
/*+\NEW WM-718\rufei\2013.3.21\ 增加gpio键盘加密模式*/
            UINT8 keyInMask;
            UINT8 keyOutMask;
/*-\NEW WM-718\rufei\2013.3.21\ 增加gpio键盘加密模式*/
        }matrix;
/*+\NEW WM-718\rufei\2013.3.21\ 增加gpio键盘加密模式*/
        struct {
            UINT32 gpioInMask;
            UINT32 gpioOutMask;
            BOOL   gpiofirstcfg;
            E_AMOPENAT_GPIOKEY_MODE mode;
        }gpio;
/*-\NEW WM-718\rufei\2013.3.21\ 增加gpio键盘加密模式*/

/*+\NEW OPENAT-771\rufei\2013.8.8\上报ADC键盘采样数据*/
        struct{
            BOOL isreportData; /*在开启后，需在按键按下的处理中free  adcList*/
        }adc;
/*-\NEW OPENAT-771\rufei\2013.8.8\上报ADC键盘采样数据*/
    }config;
	UINT8 debounceTime;
}T_AMOPENAT_KEYPAD_CONFIG;

/*************************************************
* TOUCHSCREEN
*************************************************/
typedef enum E_AMOPENAT_TOUCHSCREEN_PEN_STATE_TAG
{
    OPENAT_TOUCHSCREEN_PEN_DOWN,    
    OPENAT_TOUCHSCREEN_PEN_RESSED,  
    OPENAT_TOUCHSCREEN_PEN_UP,

    NumOfOpenatTouchScreenStates
}E_AMOPENAT_TOUCHSCREEN_PEN_STATE;

typedef struct T_AMOPENAT_TOUCHSCREEN_MESSAGE_TAG
{
    UINT8 penState;  //当前触摸状态
    UINT16 x;
    UINT16 y;
}T_AMOPENAT_TOUCHSCREEN_MESSAGE;

typedef VOID (*PTOUCHSCREEN_MESSAGE)(T_AMOPENAT_TOUCHSCREEN_MESSAGE *pTouchScreenMessage);


/*************************************************
* UART
*************************************************/
typedef enum
{
  OPENAT_UART_1,
  OPENAT_UART_2,
  OPENAT_UART_3,
  OPENAT_UART_USB,
  OPENAT_UART_QTY
}E_AMOPENAT_UART_PORT;

typedef enum
{
/*后面必须要赋值，否则在MTK平台上，编译器会自动把这个枚举量的长度设置为2字节*/
  OPENAT_UART_BAUD_1200 = 1200,
  OPENAT_UART_BAUD_2400 = 2400,
  OPENAT_UART_BAUD_4800 = 4800,
  OPENAT_UART_BAUD_9600 = 9600,
  OPENAT_UART_BAUD_14400 = 14400,
  OPENAT_UART_BAUD_19200 = 19200,
  OPENAT_UART_BAUD_28800 = 28800,
  OPENAT_UART_BAUD_38400 = 38400,
  OPENAT_UART_BAUD_57600 = 57600,
  OPENAT_UART_BAUD_76800 = 76800,
  OPENAT_UART_BAUD_115200 = 115200,
  OPENAT_UART_BAUD_230400 = 230400,
  OPENAT_UART_BAUD_460800 = 460800,
  OPENAT_UART_BAUD_576000 = 576000,
  OPENAT_UART_BAUD_921600 = 921600,
  OPENAT_UART_BAUD_1152000 = 1152000,
  OPENAT_UART_BAUD_4000000 = 4000000,
  OPENAT_UART_NUM_OF_BAUD_RATES
}E_AMOPENAT_UART_BAUD;

typedef enum
{
  OPENAT_UART_NO_PARITY,
  OPENAT_UART_ODD_PARITY,
  OPENAT_UART_EVEN_PARITY
}E_AMOPENAT_UART_PARITY;

typedef enum
{
 /*与MTK平台的保持一致*/
  OPENAT_UART_FLOWCONTROL_NONE = 1,
  OPENAT_UART_FLOWCONTROL_HW,
  OPENAT_UART_FLOWCONTROL_SW,
  OPENAT_UART_FLOWCONTROL_INVALID
} E_AMOPENAT_UART_FLOWCTL;

#define AMOPENAT_UART_READ_FOREVER  (0xFFFFFFFF)
#define AMOPENAT_UART_READ_TRY      (0)

typedef struct 
{
  E_OPENAT_DRV_EVT evtId;
  union
  {
    uint32  dataLen;
  }param;
  
}T_AMOPENAT_UART_MESSAGE;

typedef void (*PUART_MESSAGE)(T_AMOPENAT_UART_MESSAGE* evt);

typedef struct
{
  E_AMOPENAT_UART_BAUD     baud; 
  uint32                   dataBits; /*6-8*/
  uint32                   stopBits; /*1-2*/
  E_AMOPENAT_UART_PARITY   parity;
  E_AMOPENAT_UART_FLOWCTL  flowControl;
  PUART_MESSAGE            uartMsgHande; /*串口接受到数据主动上报。可以为NULL，即使用阻塞方式读取*/
/*+\NEW\zhuwangbin\2018.8.31\添加参数判断是否上报UART TXDONE*/
  BOOL                     txDoneReport;
/*-\NEW\zhuwangbin\2018.8.31\添加参数判断是否上报UART TXDONE*/
}T_AMOPENAT_UART_PARAM;

/*+\NEW\liweiqiang\2013.12.25\添加host uart发送数据功能 */
/************************************************
* HOST
************************************************/
typedef void (*PHOST_MESSAGE)(UINT8 *pData, UINT32 length);
/*-\NEW\liweiqiang\2013.12.25\添加host uart发送数据功能 */

/************************************************
* LCD
************************************************/
/*+\NEW\liweiqiang\2013.3.28\增加串口彩屏接口 */
typedef enum 
{
    OPENAT_LCD_SPI4LINE,
    OPENAT_LCD_PARALLEL_8800,

    OPENAT_LCD_BUS_QTY
}E_AMOPENAT_LCD_BUS;
/*-\NEW\liweiqiang\2013.3.28\增加串口彩屏接口 */

typedef struct
{
  short  ltX;
  short  ltY;
  short  rbX;
  short  rbY;
}T_AMOPENAT_LCD_RECT_T;


#define OPENAT_COLOR_FORMAT_16         2       /* 16-bit, rgb 565 */
#define OPENAT_COLOR_FORMAT_24         3       /* 24-bit, B,G,R       8,8,8 */
#define OPENAT_COLOR_FORMAT_32         4       /* 32-bit, B,G,R,A  8,8,8,8 */


typedef struct OPENAT_LAYER_INFO_TAG
{
    U8  color_format;
    T_AMOPENAT_LCD_RECT_T clip_rect;        /* 需要刷新的区域 */
    T_AMOPENAT_LCD_RECT_T disp_rect;        /* 需要刷新的区域 */
    T_AMOPENAT_LCD_RECT_T src_rect;         /* 需要刷新的区域 */
    U8 *buffer;              /* 刷新的缓冲区 */
}OPENAT_LAYER_INFO;


typedef struct
{
  uint16     height;
  uint16     width;
  uint16     xoffset;   /* 刷屏的偏移量 */
  uint16     yoffset;   /* 一般配置为0或0x20，用来半屏对调显示时使用 */
  uint32     frequence; /* SPI工作频率 */
  UINT8*     fameBuffer;
  E_AMOPENAT_GPIO_PORT   csPort;  /* LCD片选GPIO口 */
  E_AMOPENAT_GPIO_PORT   rstPort; /* LCD复位GPIO口 */
  
  /*+\BUG WM-822\WZQ\2013.5.25\兼容128*128的4级灰度屏*/
  uint16     pixelBits;
  /*-\BUG WM-822\WZQ\2013.5.25\兼容128*128的4级灰度屏*/
}T_AMOPENAT_MONO_LCD_PARAM;

typedef struct T_AMOPENAT_LCD_REFRESH_REQ_TAG
{
    T_AMOPENAT_LCD_RECT_T rect;
    UINT16 *pFrameBuffer;
}T_AMOPENAT_LCD_REFRESH_REQ;

typedef struct 
{
  E_OPENAT_DRV_EVT evtId;
  union
  {
    T_AMOPENAT_LCD_REFRESH_REQ      refreshReq;
  }param;
}T_AMOPENAT_LCD_MESSAGE;

typedef void (*PLCD_MESSAGE)(T_AMOPENAT_LCD_MESSAGE *pMsg);

typedef struct 
{
    uint16     height;
    uint16     width;
    PLCD_MESSAGE    msgCallback; // 针对camera 视频功能的刷新回调处理等
/*+\NEW\liweiqiang\2013.3.28\增加串口彩屏接口 */
    E_AMOPENAT_LCD_BUS bus;
    union{
        struct{
            uint32     frequence; /* SPI工作频率 */
            E_AMOPENAT_GPIO_PORT   csPort;  /* LCD片选GPIO口 */
            E_AMOPENAT_GPIO_PORT   rstPort; /* LCD复位GPIO口 */
        }spi;
    /*+\NEW\liweiqiang\2013.10.12\增加并口彩屏cs,rst管脚配置*/
        struct{
            E_AMOPENAT_GPIO_PORT   csPort;  /* LCD片选GPIO口 */
            E_AMOPENAT_GPIO_PORT   rstPort; /* LCD复位GPIO口 */
        }parallel;
    /*-\NEW\liweiqiang\2013.10.12\增加并口彩屏cs,rst管脚配置*/
    }lcdItf;
/*-\NEW\liweiqiang\2013.3.28\增加串口彩屏接口 */

    uint8 lcd_bpp;
}T_AMOPENAT_COLOR_LCD_PARAM;

// +panjun, 2015.04.21, Define some GPIOs for OLED.
extern const char gpio_oled_backlight_en;
extern const char gpio_oled_cs_pin;
extern const char gpio_oled_rs_pin;
extern const char gpio_oled_clk_pin;
extern const char gpio_oled_data_pin;

#define LCD_SPI_RS 		gpio_oled_rs_pin
#define LCD_SPI_CS0  	gpio_oled_cs_pin
#define LCD_SPI_SCLK 	gpio_oled_clk_pin
#define LCD_SPI_SDA 	gpio_oled_data_pin
#define LCD_SPI_RESET 	OPENAT_LCD_RST_GPIO
#define LCD_BACKLIGHT_EN 	gpio_oled_backlight_en

#define LCD_SPI_RS_DELAY 	10
#define LCD_SPI_CS1_DELAY  	10
#define LCD_SPI_SCLK_DELAY 	18
#define LCD_SPI_SDA_DELAY 	10

#define LCD_SPI_RS_LOW \
{\
	volatile kal_uint32 i;\
	GPIO_WriteIO(0,LCD_SPI_RS); \
	for (i=0; i<LCD_SPI_RS_DELAY; i++); \
}
#define LCD_SPI_RS_HIGH \
{\
	volatile kal_uint32 i;\
	GPIO_WriteIO(1,LCD_SPI_RS); \
	for (i=0; i<LCD_SPI_RS_DELAY; i++); \
}


#define LCD_SPI_CS1_LOW \
{\
	volatile kal_uint32 i;\
	GPIO_WriteIO(0,LCD_SPI_CS0); \
	for (i=0; i<LCD_SPI_CS1_DELAY; i++); \
}
#define LCD_SPI_CS1_HIGH \
{\
	volatile kal_uint32 i;\
	GPIO_WriteIO(1,LCD_SPI_CS0); \
	for (i=0; i<LCD_SPI_CS1_DELAY; i++); \
}

#define LCD_SPI_SCLK_LOW \
{\
	volatile kal_uint32 i;\
	GPIO_WriteIO(0,LCD_SPI_SCLK); \
	for (i=0; i<LCD_SPI_SCLK_DELAY; i++); \
}
#define LCD_SPI_SCLK_HIGH \
{\
	volatile kal_uint32 i;\
	GPIO_WriteIO(1,LCD_SPI_SCLK); \
	for (i=0; i<LCD_SPI_SCLK_DELAY; i++); \
}

#define LCD_SPI_SDA_LOW \
{\
	volatile kal_uint32 i;\
	GPIO_WriteIO(0,LCD_SPI_SDA); \
	for (i=0; i<LCD_SPI_SDA_DELAY; i++); \
}
#define LCD_SPI_SDA_HIGH \
{\
	volatile kal_uint32 i;\
	GPIO_WriteIO(1,LCD_SPI_SDA); \
	for (i=0; i<LCD_SPI_SDA_DELAY; i++); \
}
// -panjun, 2015.04.21, Define some GPIOs for OLED.

/************************************************
* SPI
*************************************************/
typedef enum
{
  OPENAT_SPI_1,
  OPENAT_SPI_QTY
}E_AMOPENAT_SPI_PORT;

typedef struct T_AMOPENAT_SPI_MESSAGE_TAG
{
  E_OPENAT_DRV_EVT evtId;
  uint32    dataLen;
}T_AMOPENAT_SPI_MESSAGE;

typedef VOID (*PSPI_MESSAGE)(T_AMOPENAT_SPI_MESSAGE* spiMessage);

typedef struct
{
  BOOL          fullDuplex;                  /*TRUE: DI/DO FALSE: DO only*/
  BOOL          cpol;                        /*FALSE: spi_clk idle状态为0 TRUE: spi_clk idle状态为 1*/
  uint8         cpha;                        /*0~1 0:第一个clk的跳变沿传输数据，1:第二个clk跳变沿传输数据 ...*/
  uint8         dataBits;                    /*4~32*/
  uint32        clock;                       /*110k~13M*/
  PSPI_MESSAGE  spiMessage;                  /*暂时不支持*/
  BOOL          withCS;                      /*CS引脚支持*/
}T_AMOPENAT_SPI_PARAM;

/************************************************
* I2C
*************************************************/
typedef enum E_AMOPENAT_I2C_PORT_TAG
{
/*+\NEW\zhuwangbin\2020.2.11\添加openat i2c接口*/
    OPENAT_I2C_1,
    OPENAT_I2C_2,
    OPENAT_I2C_3,
    OPENAT_I2C_4,
/*-\NEW\zhuwangbin\2020.2.11\添加openat i2c接口*/
    OPENAT_I2C_QTY
}E_AMOPENAT_I2C_PORT;

typedef struct T_AMOPENAT_I2C_MESSAGE_TAG
{
    E_OPENAT_DRV_EVT evtId;
    uint32    dataLen;
}T_AMOPENAT_I2C_MESSAGE;

typedef VOID (*PI2C_MESSAGE)(T_AMOPENAT_I2C_MESSAGE* i2cMessage);

typedef struct
{
    uint32          freq;           /*i2c传输速率 100KHz\400KHz*/
    //uint8           slaveAddr;      /*i2c从设备地址 (7bit) 在read write的时候传入从设备地址*/
    uint8           regAddrBytes;    /*i2c外设寄存器地址字节数*/ //暂不支持请设置为0 = 1字节
    BOOL            noAck;          /*是否确认ack*/      //暂不支持请设置为FALSE
    BOOL            noStop;         /*是否确认发停止位*/ //暂不支持请设置为FALSE
    PI2C_MESSAGE    i2cMessage;     /*暂时不支持*/
}T_AMOPENAT_I2C_PARAM;


typedef struct
{
    E_AMOPENAT_I2C_PORT   scl_port; 
    E_AMOPENAT_I2C_PORT   sda_port;
    u16                   slaveAddr;
}T_AMOPENAT_GPIO_I2C_PARAM;

/************************************************
* camera
*************************************************/
#define AMOPENAT_CAMERA_DELAY_CMD 0xffff /* 0xffff表示这条这是一条延时指令 */

#define AMOPENAT_CAMERA_REG_ADDR_8BITS      (0<<0)
#define AMOPENAT_CAMERA_REG_ADDR_16BITS     (1<<0)
#define AMOPENAT_CAMERA_REG_DATA_8BITS      (0<<1)
#define AMOPENAT_CAMERA_REG_DATA_16BITS     (1<<1)

typedef struct T_AMOPENAT_CAMERA_REG_TAG
{
    UINT16      addr;
    UINT16      value;
}AMOPENAT_CAMERA_REG, *PAMOPENAT_CAMERA_REG;

typedef enum E_AMOPENAT_CAMERA_IMAGE_FORMAT_TAG
{
    CAMERA_IMAGE_FORMAT_YUV422,

    NumOfOpenatCameraImageFormats
}E_AMOPENAT_CAMERA_IMAGE_FORMAT;

/*+\NEW\zhuwangbin\2020.4.26\添加openat cam接口*/
typedef struct 
{
    E_AMOPENAT_GPIO_PORT camPdn;
    E_AMOPENAT_GPIO_PORT camRst;
    BOOL enable;
}OPENAT_CAMERA_PIN_CONFIG;

typedef enum
{
    OPENAT_SPI_MODE_NO = 0,         // parallel sensor in use
    OPENAT_SPI_MODE_SLAVE ,        // SPI sensor as SPI slave
    OPENAT_SPI_MODE_MASTER1,     // SPI sensor as SPI master, 1 sdo output with SSN 
    OPENAT_SPI_MODE_MASTER2_1, // SPI sensor as SPI master, 1 sdo output without SSN
    OPENAT_SPI_MODE_MASTER2_2, // SPI sensor as SPI master, 2 sdos output 
    OPENAT_SPI_MODE_MASTER2_4, // SPI sensor as SPI master, 4 sdos output
    OPENAT_SPI_MODE_UNDEF,
} OPENAT_CAMERA_SPI_MODE_E;

typedef enum
{
    OPENAT_SPI_OUT_Y0_U0_Y1_V0 = 0,
    OPENAT_SPI_OUT_Y0_V0_Y1_U0,
    OPENAT_SPI_OUT_U0_Y0_V0_Y1,
    OPENAT_SPI_OUT_U0_Y1_V0_Y0,
    OPENAT_SPI_OUT_V0_Y1_U0_Y0,
    OPENAT_SPI_OUT_V0_Y0_U0_Y1,
    OPENAT_SPI_OUT_Y1_V0_Y0_U0,
    OPENAT_SPI_OUT_Y1_U0_Y0_V0,
} OPENAT_CAMERA_SPI_YUV_OUT_E;

typedef struct 
{
    UINT16 *data; 
    int dataLen;
    BOOL isDataChannel;
}T_AMOPENAT_CAMERA_DATA_PARAM;

/*+\NEW\zhuwangbin\2020.7.11\添加cam spi speed模式配置*/
typedef enum
{
	OPENAT_SPI_SPEED_DEFAULT,
	OPENAT_SPI_SPEED_SDR, /*单倍速率*/
	OPENAT_SPI_SPEED_DDR, /*双倍速率*/
	OPENAT_SPI_SPEED_QDR, /*四倍速率 暂不支持*/
}OPENAT_SPI_SPEED_MODE_E;
/*-\NEW\zhuwangbin\2020.7.11\添加cam spi speed模式配置*/
	
typedef struct 
{
  E_OPENAT_DRV_EVT evtId;
  union
  {
    UINT16 videorecordFinishResult;  //OPENAT_DRV_EVT_VIDEORECORD_FINISH_IND 录制结果上报
  }param;

  T_AMOPENAT_CAMERA_DATA_PARAM dataParam; // OPENAT_DRV_EVT_CAMERA_DATA_IND camera数据上报
}T_AMOPENAT_CAMERA_MESSAGE;
/*-\NEW\zhuwangbin\2020.4.26\添加openat cam接口*/
typedef void (*PCAMERA_MESSAGE)(T_AMOPENAT_CAMERA_MESSAGE *pMsg);

typedef struct T_AMOPENAT_CAMERA_PARAM_TAG
{
    /* 摄像头/视频消息处理函数 */
    PCAMERA_MESSAGE messageCallback;
    
    /* 摄像头I2C设置 */
    E_AMOPENAT_I2C_PORT i2cPort;            /* 摄像头使用的i2c总线id */
    UINT8       i2cSlaveAddr;               /* 摄像头i2c访问地址 */
    UINT8       i2cAddrDataBits;            /* 摄像头寄存器地址以及数据位数 */

    /* 摄像头主要信号线有效极性配置 */
    BOOL        RSTBActiveLow;              /* pin RSTB 低有效 */
    BOOL        PWDNActiveLow;              /* pin PWDN 低有效 */
    BOOL        VSYNCActiveLow;             /* pin VSYNC 低有效 */

    /* 摄像头图像宽高 */
    UINT16      sensorWidth;
    UINT16      sensorHeight;

    E_AMOPENAT_CAMERA_IMAGE_FORMAT imageFormat; /* 摄像头图像格式 */
    
    PAMOPENAT_CAMERA_REG initRegTable_p;  /* 摄像头初始化指令表 */
    UINT16 initRegTableCount;          /* 摄像头初始化指令数 */

    AMOPENAT_CAMERA_REG idReg;          /* 摄像头ID寄存器与值 */
/*+\NEW\zhuwangbin\2020.4.26\添加openat cam接口*/
    OPENAT_CAMERA_PIN_CONFIG cameraPin;
    UINT8 camClkDiv;
    OPENAT_CAMERA_SPI_MODE_E       spi_mode;
    OPENAT_CAMERA_SPI_YUV_OUT_E  spi_yuv_out;
    /*+\new\zhuwangbin\2018.9.6\支持camera各行隔列输出使能*/
    BOOL jumpEnable;
    /*-\new\zhuwangbin\2018.9.6\支持camera各行隔列输出使能*/
	OPENAT_SPI_SPEED_MODE_E spi_speed;
/*-\NEW\zhuwangbin\2020.4.26\添加openat cam接口*/
}T_AMOPENAT_CAMERA_PARAM;

// T_AMOPENAT_CAM_PREVIEW_PARAM.encodeQuality video encoding quality
#define OPENAT_VID_REC_QTY_LOW          0
#define OPENAT_VID_REC_QTY_NORMAL       1
#define OPENAT_VID_REC_QTY_HIGH         2
#define OPENAT_VID_REC_QTY_FINE         3

typedef struct T_AMOPENAT_CAM_PREVIEW_PARAM_TAG
{
    UINT16      startX;
    UINT16      startY;
    UINT16      endX;
    UINT16      endY;

    /* 视频录制的参数,拍照预览不用设置这些参数 */
    UINT16      recordAudio;  /* 是否录音 */
    UINT16      filesizePermit;  //以K为单位
    UINT16      timePermit;
    UINT16      encodeQuality;
	/*+\NEW\zhuwangbin\2020.7.20\添加camera 翻转放缩功能*/
	int 		rotation; //反转角度设置 暂时只支持0和90度
	int 		zoom; //放缩设置, 正数放大负数缩小，最大4倍，0不放缩
	/*-\NEW\zhuwangbin\2020.7.20\添加camera 翻转放缩功能*/
}T_AMOPENAT_CAM_PREVIEW_PARAM;

typedef struct T_AMOPENAT_CAM_CAPTURE_PARAM_TAG
{
    UINT16      imageWidth;
    UINT16      imageHeight;
	UINT16      quality;
}T_AMOPENAT_CAM_CAPTURE_PARAM;

/************************************************
* video
*************************************************/
typedef enum E_AMOPENAT_VIDEO_TYPE_TAG
{
    OPENAT_VIDEO_TYPE_MJPG,
    OPENAT_VIDEO_TYPE_RM,
    OPENAT_VIDEO_TYPE_MP4,
    OPENAT_VIDEO_TYPE_3GP,
    OPENAT_VIDEO_TYPE_AVSTRM,

    NumOfOpenatVideoTypes
}E_AMOPENAT_VIDEO_TYPE;

typedef struct T_AMOPENAT_VIDEO_MESSAGE_TAG
{
    E_OPENAT_DRV_EVT evtId;
    union
    {
      UINT32 playFinishResult;
      UINT32 currentTime;  // 以ms为单位
    }param;
}T_AMOPENAT_VIDEO_MESSAGE;

typedef void (*PVIDEO_MESSAGE)(T_AMOPENAT_VIDEO_MESSAGE *pMsg); 

typedef struct T_AMOPENAT_VIDEO_INFO_TAG
{
    UINT16 imageWidth;
    UINT16 imageHeight;
    UINT32 totalTime;
}T_AMOPENAT_VIDEO_INFO;

typedef struct T_AMOPENAT_VIDEO_PARAM_TAG
{
    PVIDEO_MESSAGE                  msgCallback;    /* 视频消息回调处理 */    
    INT32                           iFd;            /* 视频文件句柄 */
    E_AMOPENAT_VIDEO_TYPE           videoType;
}T_AMOPENAT_VIDEO_PARAM;

/************************************************
* AUDIO
*************************************************/
typedef enum
{
  OPENAT_AUD_TONE_DTMF_0,
  OPENAT_AUD_TONE_DTMF_1,
  OPENAT_AUD_TONE_DTMF_2,
  OPENAT_AUD_TONE_DTMF_3,
  OPENAT_AUD_TONE_DTMF_4,
  OPENAT_AUD_TONE_DTMF_5,
  OPENAT_AUD_TONE_DTMF_6,
  OPENAT_AUD_TONE_DTMF_7,
  OPENAT_AUD_TONE_DTMF_8,
  OPENAT_AUD_TONE_DTMF_9,
  OPENAT_AUD_TONE_DTMF_A,
  OPENAT_AUD_TONE_DTMF_B,
  OPENAT_AUD_TONE_DTMF_C,
  OPENAT_AUD_TONE_DTMF_D,
  OPENAT_AUD_TONE_DTMF_HASH,
  OPENAT_AUD_TONE_DTMF_STAR,
  OPENAT_AUD_TONE_DTMF_END
}E_AMOPENAT_DTMF_TYPE;

/*+\BUG\wangyuan\2020.06.08\BUG_2163:CSDK提供audio音频播放接口*/
typedef enum
{
  OPENAT_AUD_TONE_DIAL,
  OPENAT_AUD_TONE_BUSY,
  
  OPENAT_AUD_TONE_PATH_ACKNOWLEGEMENT,
  OPENAT_AUD_TONE_CALL_DROPPED,
  OPENAT_AUD_TONE_SPECIAL_INFO,
  OPENAT_AUD_TONE_CALL_WAITING,
  OPENAT_AUD_TONE_RINGING,
  OPENAT_AUD_TONE_END,
}E_AMOPENAT_TONE_TYPE;
/*-\BUG\wangyuan\2020.06.08\BUG_2163:CSDK提供audio音频播放接口*/

typedef enum {
    OPENAT_AUD_SPK_GAIN_MUTE = 0,     /// MUTE
    OPENAT_AUD_SPK_GAIN_0dB,    
    OPENAT_AUD_SPK_GAIN_3dB,    
    OPENAT_AUD_SPK_GAIN_6dB,   
    OPENAT_AUD_SPK_GAIN_9dB,   
    OPENAT_AUD_SPK_GAIN_12dB,
    OPENAT_AUD_SPK_GAIN_15dB,
    OPENAT_AUD_SPK_GAIN_18dB,
    /*+\BUG\wangyuan\2020.08.10\扩充选项，不去设置音量*/
    OPENAT_AUD_SPK_GAIN_NOT_SET,
    /*-\BUG\wangyuan\2020.08.10\扩充选项，不去设置音量*/
    OPENAT_AUD_SPK_GAIN_END,
}E_AMOPENAT_SPEAKER_GAIN;


/*+\NEW\xiongjunqun\2015.05.28\增加通话中调节音量接口*/
typedef enum {
    OPENAT_AUD_SPH_VOL0,
    OPENAT_AUD_SPH_VOL1,
    OPENAT_AUD_SPH_VOL2,
    OPENAT_AUD_SPH_VOL3,
    OPENAT_AUD_SPH_VOL4,
    OPENAT_AUD_SPH_VOL5,
    OPENAT_AUD_SPH_VOL6,
    NumOfAMOPENATAudSPHVols
}E_AMOPENAT_AUD_SPH_VOL;
/*-\NEW\xiongjunqun\2015.05.28\增加通话中调节音量接口*/

/*+\NEW\zhuwangbin\2020.8.11\添加耳机插拔配置*/
typedef enum
{
    OPENAT_AUD_HEADSET_PLUGOUT,
    OPENAT_AUD_HEADSET_INSERT4P,
    OPENAT_AUD_HEADSET_INSERT3P,
    OPENAT_AUD_HEADSET_TYPE_QTY
} E_OPENAT_AUD_HEADSET_TYPE;
/*-\NEW\zhuwangbin\2020.8.11\添加耳机插拔配置*/

typedef enum 
{
    OPENAT_AUD_PLAY_ERR_NO,
    OPENAT_AUD_PLAY_ERR_UNKNOWN_FORMAT,
    OPENAT_AUD_PLAY_ERR_BUSY,
    OPENAT_AUD_PLAY_ERR_INVALID_PARAMETER,
    OPENAT_AUD_PLAY_ERR_ACTION_NOT_ALLOWED,
    OPENAT_AUD_PLAY_ERR_OUT_OF_MEMORY,
    OPENAT_AUD_PLAY_ERR_CANNOT_OPEN_FILE,         		           
    OPENAT_AUD_PLAY_ERR_END_OF_FILE,	     
    OPENAT_AUD_PLAY_ERR_TERMINATED,		   
    OPENAT_AUD_PLAY_ERR_BAD_FORMAT,	      
    OPENAT_AUD_PLAY_ERR_INVALID_FORMAT,   
    OPENAT_AUD_PLAY_ERR_ERROR,
	/*+\NEW\zhuwangbin\2020.05.15\增加speex格式的录音和播放*/
    OPENAT_AUD_SPX_ERR_DATA_LONG,
    OPENAT_AUD_SPX_ERR_DATA_FORMAT,
	/*-\NEW\zhuwangbin\2020.05.15\增加speex格式的录音和播放*/
} E_AMOPENAT_PLAY_ERROR;


typedef enum 
{
    OPENAT_AUD_REC_ERR_NONE = 0,
	OPENAT_AUD_REC_ERR_NOT_ALLOW ,
	OPENAT_AUD_REC_ERR_NO_MEMORY,
	OPENAT_AUD_REC_ERR_EXE_FAIL,
	OPENAT_AUD_REC_ERR_PARAM,	               
} E_AMOPENAT_RECORD_ERROR;

typedef enum
{
    OPENAT_AUD_PLAY_MODE_AMR475,
    OPENAT_AUD_PLAY_MODE_AMR515,
    OPENAT_AUD_PLAY_MODE_AMR59,
    OPENAT_AUD_PLAY_MODE_AMR67,
    OPENAT_AUD_PLAY_MODE_AMR74,
    OPENAT_AUD_PLAY_MODE_AMR795,
    OPENAT_AUD_PLAY_MODE_AMR102,
    OPENAT_AUD_PLAY_MODE_AMR122,
    OPENAT_AUD_PLAY_MODE_FR,
    OPENAT_AUD_PLAY_MODE_HR,
    OPENAT_AUD_PLAY_MODE_EFR,
    OPENAT_AUD_PLAY_MODE_PCM,
    OPENAT_AUD_PLAY_MODE_AMR_RING,
    OPENAT_AUD_PLAY_MODE_MP3,
    OPENAT_AUD_PLAY_MODE_AAC,
    OPENAT_AUD_PLAY_MODE_WAV,
    OPENAT_AUD_PLAY_MODE_STREAM_PCM, //for TTS stream play
    /*+\BUG WM-669\lifei\2013.06.09\[OpenAT] 支持MIDI播放*/
    OPENAT_AUD_PLAY_MODE_MIDI,
    /*-\BUG WM-669\lifei\2013.06.09\[OpenAT] 支持MIDI播放*/
    OPENAT_AUD_PLAY_MODE_QTY,
} E_AMOPENAT_PLAY_MODE;

typedef enum
{
    OPENAT_AUDIOHAL_ITF_RECEIVER =0,     
    OPENAT_AUDIOHAL_ITF_EARPIECE,    
	/*+\new\wj\2020.4.22\支持音频通道切换接口*/
    OPENAT_AUDIOHAL_ITF_LOUDSPEAKER, 
    OPENAT_AUD_CHANNEL_DUMMY_AUX_HANDSET
    #if 0
	OPENAT_AUDIOHAL_ITF_LOUDSPEAKER,   
	OPENAT_ITF_LOUDSPEAKER_AND_HEADPHONE, 
	
	OPENAT_AUDIOHAL_ITF_BLUETOOTH,       
	OPENAT_AUDIOHAL_ITF_FM,          
    OPENAT_AUDIOHAL_ITF_FM2SPK,    
    OPENAT_AUDIOHAL_ITF_TV, 
    
    OPENAT_AUDIOHAL_ITF_QTY,    												
	OPENAT_AUDIOHAL_ITF_NONE = 255,         
	OPENAT_AUD_CHANNEL_DUMMY_AUX_HANDSET,     
	#endif
	/*-\new\wj\2020.4.22\支持音频通道切换接口*/
}E_AMOPENAT_AUDIO_CHANNEL;

/*+\new\zhuwangbin\2020.6.2\添加音频功放类型设置接口*/
typedef enum
{
    OPENAT_SPKPA_TYPE_CLASSAB,
    OPENAT_INPUT_TYPE_CLASSD,
    OPENAT_INPUT_TYPE_CLASSK,
    OPENAT_SPKPA_INPUT_TYPE_QTY = 0xFF000000
} OPENAT_SPKPA_TYPE_T;
/*-\new\zhuwangbin\2020.6.2\添加音频功放类型设置接口*/

/*+\bug2767\zhuwangbin\2020.8.5\添加外部pa设置接口*/
typedef struct 
{
	BOOL enable;
	UINT16 gpio;
	UINT16 count;
	UINT16 us;
	E_AMOPENAT_AUDIO_CHANNEL outDev;
}OPENAT_EXPA_T;
/*-\bug2767\zhuwangbin\2020.8.5\添加外部pa设置接口*/

typedef void (*AUD_PLAY_CALLBACK_T)(E_AMOPENAT_PLAY_ERROR result);

typedef void (*AUD_RECORD_CALLBACK_T)(E_AMOPENAT_RECORD_ERROR result);

/*+\NEW\shenyuanyuan\2019.12.11\添加MP3播放AT+PLAY，AT+STOP ，AT+SOUNDLVL指令*/
typedef void (*MUSIC_PLAY_CALLBACK_T)(const char *file_name, int ret);
/*-\NEW\shenyuanyuan\2019.12.11\添加MP3播放AT+PLAY，AT+STOP ，AT+SOUNDLVL指令*/
/*+\new\wj\2020.4.26\实现录音接口*/
/*+\BUG\wangyuan\2020.07.31\BUG_2736:CSDK 大唐对讲机需求 支持流录音*/
typedef void (*AUD_STREAM_RECORD_CALLBACK_T)(int ret, char *data, int len);
/*-\BUG\wangyuan\2020.07.31\BUG_2736:CSDK 大唐对讲机需求 支持流录音*/
/*-\new\wj\2020.4.26\实现录音接口*/
/*+\NewReq WM-702\maliang\2013.3.15\播放音频文件的接口增加一个参数，用来表示文件类型*/
typedef enum E_AMOPENAT_AUD_FORMAT_TAG
{
    OPENAT_AUD_FORMAT_UNKNOWN, ///< placeholder for unknown format
    OPENAT_AUD_FORMAT_PCM,     ///< raw PCM data
    OPENAT_AUD_FORMAT_WAVPCM,  ///< WAV, PCM inside
    OPENAT_AUD_FORMAT_MP3,     ///< MP3
    OPENAT_AUD_FORMAT_AMRNB,   ///< AMR-NB
    OPENAT_AUD_FORMAT_AMRWB,   ///< AMR_WB
	/*+\NEW\zhuwangbin\2020.05.15\增加speex格式的录音和播放*/
    OPENAT_AUD_FORMAT_SPEEX,
	/*-\NEW\zhuwangbin\2020.05.15\增加speex格式的录音和播放*/
    OPENAT_AUD_FORMAT_QTY,
}E_AMOPENAT_AUD_FORMAT;
/*-\NewReq WM-702\maliang\2013.3.15\播放音频文件的接口增加一个参数，用来表示文件类型*/

typedef enum E_AMOPENAT_RECORD_TYPE_TAG
{
    OPENAT_RECORD_TYPE_NONE, ///< placeholder for unknown format
    OPENAT_RECORD_TYPE_MIC,     ///Record from microphone.
    OPENAT_RECORD_TYPE_VOICE,  ///
    OPENAT_RECORD_TYPE_VOICE_DUAL,     ///
    OPENAT_RECORD_TYPE_DEBUG_DUMP, 
}E_AMOPENAT_RECORD_TYPE;

typedef enum E_AMOPENAT_RECORD_QUALITY_TAG
{
    OPENAT_RECORD_QUALITY_LOW,    ///< quality low
    OPENAT_RECORD_QUALITY_MEDIUM, ///< quality medium
    OPENAT_RECORD_QUALITY_HIGH,   ///< quality high
    OPENAT_RECORD_QUALITY_BEST,   ///< quality best
} E_AMOPENAT_RECORD_QUALITY;

typedef enum 
{
	OPENAT_RECORD_FILE,
	OPENAT_RECORD_STREAM,
}OpenatRecordMode_t;

typedef struct
{
	char *fileName;
	int time_sec;
	OpenatRecordMode_t record_mode;
	E_AMOPENAT_RECORD_QUALITY quality;
	E_AMOPENAT_RECORD_TYPE type;
	E_AMOPENAT_AUD_FORMAT format;
	AUD_STREAM_RECORD_CALLBACK_T stream_record_cb;
	/*+\bug2241\zhuwangbin\2020.6.20\流录音可配置回调长度阀值*/
	int thresholdLength; //录音数据达到一定的长度就上报
	/*-\bug2241\zhuwangbin\2020.6.20\流录音可配置回调长度阀值*/
}E_AMOPENAT_RECORD_PARAM;

typedef enum
{
    OPENAT_AUDEV_OUTPUT_RECEIVER = 0,  ///< receiver
    OPENAT_AUDEV_OUTPUT_HEADPHONE = 1, ///< headphone
    OPENAT_AUDEV_OUTPUT_SPEAKER = 2,   ///< speaker
} E_AMOPENAT_AUDIO_OUTPUT_T;

typedef struct T_AMOPENAT_PLAY_BUFFER_PARAM_TAG
{
    char *pBuffer;
    UINT32 len;
    UINT8 loop;
    AUD_PLAY_CALLBACK_T callback;
    E_AMOPENAT_AUD_FORMAT  format;
}T_AMOPENAT_PLAY_BUFFER_PARAM;


typedef struct T_AMOPENAT_PLAY_FILE_PARAM_TAG
{
/*+\BUG WM-719\maliang\2013.3.21\文件系统接口和播放音频文件接口的文件名改为unicode little ending类型*/
    char* fileName;        /* 文件名使用unicode编码 little endian方式表示 */
/*-\BUG WM-719\maliang\2013.3.21\文件系统接口和播放音频文件接口的文件名改为unicode little ending类型*/
/*+\NewReq WM-702\maliang\2013.3.15\播放音频文件的接口增加一个参数，用来表示文件类型*/
    E_AMOPENAT_AUD_FORMAT  fileFormat;
/*-\NewReq WM-702\maliang\2013.3.15\播放音频文件的接口增加一个参数，用来表示文件类型*/
    AUD_PLAY_CALLBACK_T callback;
}T_AMOPENAT_PLAY_FILE_PARAM;

typedef struct  T_AMOPENAT_PLAY_PARAM_TAG
{
      BOOL  playBuffer;/*是播放buffer还是播放文件*/
      union
      {
           T_AMOPENAT_PLAY_BUFFER_PARAM       playBufferParam;
           T_AMOPENAT_PLAY_FILE_PARAM        playFileParam;
      };
}T_AMOPENAT_PLAY_PARAM;
/*-\NewReq WM-584\maliang\2013.2.21\[OpenAt]支持T卡播放MP3*/

/*+\NewReq WM-710\maliang\2013.3.18\ [OpenAt]增加接口设置MP3播放的音效*/
typedef enum  E_AMOPENAT_AUDIO_SET_EQ_TAG
{
    OPENAT_AUD_EQ_NORMAL,     
    OPENAT_AUD_EQ_BASS,    
    OPENAT_AUD_EQ_DANCE,
    OPENAT_AUD_EQ_CLASSICAL,
    OPENAT_AUD_EQ_TREBLE,
    OPENAT_AUD_EQ_PARTY,
    OPENAT_AUD_EQ_POP,
    OPENAT_AUD_EQ_ROCK
}E_AMOPENAT_AUDIO_SET_EQ;
/*-\NewReq WM-710\maliang\2013.3.18\ [OpenAt]增加接口设置MP3播放的音效*/

/*+\NewReq WM-711\maliang\2013.3.18\[OpenAt]增加接口打开或关闭音频回环测试*/
typedef enum  E_AMOPENAT_AUDIO_LOOPBACK_TYPE_TAG
{
    OPENAT_AUD_LOOPBACK_HANDSET,
    OPENAT_AUD_LOOPBACK_EARPIECE,
    OPENAT_AUD_LOOPBACK_LOUDSPEAKER,
/*+\NewReq WM-862\maliang\2013.7.2\ 增加at+audlb测试音频回环*/
    OPENAT_AUD_LOOPBACK_AUX_HANDSET,
    OPENAT_AUD_LOOPBACK_AUX_LOUDSPEAKER
/*-\NewReq WM-862\maliang\2013.7.2\ 增加at+audlb测试音频回环*/
}E_AMOPENAT_AUDIO_LOOPBACK_TYPE;
/*-\NewReq WM-711\maliang\2013.3.18\[OpenAt]增加接口打开或关闭音频回环测试*/

/*************************************************
* PSAM
*************************************************/
typedef enum
{
  OPENAT_PSAM_SUCCESS,                      /*操作成功*/
  OPENAT_PSAM_ERR_EXTRA_RXATA,              /*接收到多余数据*/
  OPENAT_PSAM_ERR_BAT_ATR,                  /*复位ATR错误*/
  OPENAT_PSAM_ERR_RESET_TIMEOUT,            /*复位应答超时*/
  OPENAT_PSAM_ERR_PARITY,                   /*数据奇偶校验错误*/
  OPENAT_PSAM_ERR_WWT_TIMEOUT,              /*数据传输失败*/
  OPENAT_PSAM_ERR_RCV_TIMEOUT,              /*数据接收超时*/
  OPENAT_PSAM_ERR_INVALID_PARAM,            /*接口参数错误*/
  OPENAT_PSAM_ERR_DEV_BUSY,                 /*设备忙*/
  OPENAT_PSAM_ERR_HW_SWITCH,                /*硬件已经切换到别的卡上访问*/
  OPENAT_PSAM_ERR_OTHER                     /*其他错误*/
}E_AMOPENAT_PSAM_OPER_RESULT;
typedef enum
{
  OPENAT_PSAM_ID_1,                         /* 利用SIM0作为PSAM卡接口 */
  OPENAT_PSAM_ID_2,                         /* 利用SIM2作为PSAM卡接口 */
  OPENAT_PSAM_ID_INVALID
}E_AMOPENAT_PSAM_ID;
typedef enum
{
  OPENAT_PSAM_VOLT_1_8V,                    /* 1.8V */
  OPENAT_PSAM_VOLT_3V,                      /* 3V */
  OPENAT_PSAM_VOLT_5V,                      /* 5V */
  OPENAT_PSAM_VOLT_INVALID
}E_AMOPENAT_PSAM_VOLT_CLASS;

/*+\BUG WM-690\rufei\2013.3.18\AT+SPWM没有实现PWM1和PWM2*/
/*************************************************
* PWM
*************************************************/
/*+\bug\wj\2020.4.30\lua添加pwm接口*/
typedef enum
{
    PWM_LGP_PER_125MS,
    PWM_LGP_PER_250MS,
    PWM_LGP_PER_500MS,
    PWM_LGP_PER_1000MS,
    PWM_LGP_PER_1500MS,
    PWM_LGP_PER_2000MS,
    PWM_LGP_PER_2500MS,
    PWM_LGP_PER_3000MS,
    OPENAT_PWM_LPG_PER_QTY
}E_OPENAT_PWM_LPG_PERIOD;

typedef enum 
{
    PWM_LGP_ONTIME_UNDEFINE,
    PWM_LGP_ONTIME_15_6MS,
    PWM_LGP_ONTIME_31_2MS,
    PWM_LGP_ONTIME_46_8MS,
    PWM_LGP_ONTIME_62MS,
    PWM_LGP_ONTIME_78MS,
    PWM_LGP_ONTIME_94MS,
    PWM_LGP_ONTIME_110MS,
    PWM_LGP_ONTIME_125MS,
    PWM_LGP_ONTIME_140MS,
    PWM_LGP_ONTIME_156MS,
    PWM_LGP_ONTIME_172MS,
    PWM_LGP_ONTIME_188MS,
    PWM_LGP_ONTIME_200MS,
    PWM_LGP_ONTIME_218MS,
    PWM_LGP_ONTIME_234MS,
    OPENAT_PWM_LPG_ON_QTY
}E_OPENAT_PWM_LPG_ON;


/*+\NEW\RUFEI\2015.9.8\Add pwm function */
typedef enum
{
	OPENAT_PWM_PWT_OUT, //gpio_5
	OPENAT_PWM_LPG_OUT, //gpio_13
	OPENAT_PWM_PWL_OUT0, //gpio_4
	OPENAT_PWM_PWL_OUT1, //gpio_7
	OPENAT_PWM_INVALID_PARAM
}E_AMOPENAT_PWM_PORT;
/*-\NEW\RUFEI\2015.9.8\Add pwm function */
/*+\BUG\wangyuan\2020.07.29\BUG_2663:普玄：请参考2G CSDK开发iot_debug_set_fault_mode接口*/
typedef enum openatFaultModeE
{
	/*!< 异常重启，默认状态*/
	OPENAT_FAULT_RESET,
	/*!< 异常调试模式*/
	OPENAT_FAULT_HANG
}E_OPENAT_FAULT_MODE;
/*-\BUG\wangyuan\2020.07.29\BUG_2663:普玄：请参考2G CSDK开发iot_debug_set_fault_mode接口*/

typedef struct
{
    UINT32 onTimems; //0->forever
    E_AMOPENAT_PWM_PORT port;
    union
    {
        struct pwm_pwt{
        	UINT16  level;
        	UINT16 freq;
        }pwt,pwl;/*注意:使用PWL实现蜂鸣器时，freq实际有效范围:0-0xff*/
        struct pwm_lpg{
        	E_OPENAT_PWM_LPG_PERIOD period;
        	E_OPENAT_PWM_LPG_ON     onTime;
        }lpg;
    }cfg;
}T_AMOPENAT_PWM_CFG;
/*-\BUG WM-690\rufei\2013.3.18\AT+SPWM没有实现PWM1和PWM2*/
/*-\bug\wj\2020.4.30\lua添加pwm接口*/

typedef struct T_AMOPENAT_ALARM_MESSAGE_TAG
{
  E_OPENAT_DRV_EVT evtId;
  union
  {
    uint16  alarmIndex;/*mtk只能支持1个alram，默认index为0*/
  }param;  
}T_AMOPENAT_ALARM_MESSAGE;

typedef VOID (*PALARM_MESSAGE)(T_AMOPENAT_ALARM_MESSAGE *pAlarmMessage);

typedef struct T_AMOPENAT_ALARM_CONFIG_TAG
{
    PALARM_MESSAGE pAlarmMessageCallback;
}T_AMOPENAT_ALARM_CONFIG;


/*+\NewReq WM-725\xiongjunqun\2013.3.25\ [OpenAt]增加FM接口*/
typedef enum
{
    /// 87.5-108 MHz    (US/Europe)
    OPENAT_FM_BAND_US_EUROPE = 0,
    /// 76-91 MHz       (Japan)
    OPENAT_FM_BAND_JAPAN,
    /// 76-108 MHz      (World Wide)
    OPENAT_FM_BAND_WORLD,
    /// 65-76 MHz       (East Europe)
    OPENAT_FM_BAND_EAST_EUROPE,

    OPENAT_FM_BAND_QTY
} E_AMOPENAT_FM_BAND;

typedef enum
{
    OPENAT_FM_MUTE = 0,
    OPENAT_FM_VOL_1,
    OPENAT_FM_VOL_2,
   	OPENAT_FM_VOL_3,
    OPENAT_FM_VOL_4,
    OPENAT_FM_VOL_5,
    OPENAT_FM_VOL_6,
   	OPENAT_FM_VOL_7,

    OPENAT_FM_VOL_QTY
} E_AMOPENAT_FM_VOL_LEVEL;


typedef struct
{
    /// FM Frequency(KHZ)
    UINT32              freqKHz;
    /// Volume
    E_AMOPENAT_FM_VOL_LEVEL     volume;
    /// Enable/Disable Bass Boost
    BOOL                bassBoost;
    /// Enable/Disable Mono output of stereo radios
    BOOL                forceMono;
} T_AMOPENAT_FM_INIT;

typedef struct 
{
  E_OPENAT_DRV_EVT evtId;
  struct
  {
  	UINT32 freqKHz; 
  	BOOL found;
  	BOOL stereo;
  }param;
}T_AMOPENAT_FM_MESSAGE;

typedef void (*PFM_MESSAGE)(UINT32 freq, BOOL found, BOOL stereoStatus);

typedef struct T_AMOPENAT_FM_PARAM_TAG
{

    PFM_MESSAGE messageCallback;
    E_AMOPENAT_FM_BAND fmBand;
	T_AMOPENAT_FM_INIT fmInit;
}T_AMOPENAT_FM_PARAM;
/*-\NewReq WM-725\xiongjunqun\2013.3.25\ [OpenAt]增加FM接口*/


typedef VOID (*PINBANDINFO_CALLBACK)(void);

/*+\NEW\brezen\2013.12.30\添加蓝牙接口*/
#define OPENAT_BT_NAME_MAX_LEN (59)
#define OPENAT_BT_PB_LENGHT     (20)  
#define OPENAT_BT_MAX_SDAP_UUID_NO (15)
#define OPENAT_BT_MAX_PHONE_NUMBER 48

#define OPENAT_BT_SUPPORT_SPP_PROFILE (1<<0)
#define OPENAT_BT_SUPPORT_HFP_PROFILE (1<<1)
#define OPENAT_BT_SUPPORT_PBAP_PROFILE (1<<2)

/*app主动请求*/
typedef enum
{
  OPENAT_BT_MGR_DISCORY_REQ_CMD,
  OPENAT_BT_MGR_DISCORY_CANCEL_CMD,
  OPENAT_BT_MGR_SET_SCANNABLE_CMD,
  OPENAT_BT_MGR_READ_LOCAL_ADDR_CMD,
  OPENAT_BT_MGR_WRITE_LOCAL_NAME_CMD,
  OPENAT_BT_MGR_SLEEP_MODE_CMD,

  OPENAT_BT_BM_BONDING_REQ_CMD,
  OPENAT_BT_BM_DEBOND_REQ_CMD,
  OPENAT_BT_PBAP_CON_REQ_CMD,
  OPENAT_BT_PBAP_GET_NEXT_REQ_CMD,
  OPENAT_BT_PBAP_DISCON_REQ_CMD,

  OPENAT_BT_HFG_CONNECT_REQ,
  OPENAT_BT_HFG_DISCONNECT_REQ,
  OPENAT_BT_HFG_DIAL_REQ,
  OPENAT_BT_HFG_HUNGUP_REQ,
  OPENAT_BT_HFG_CALL_ANSWER_REQ,
  OPENAT_BT_HFG_SEND_DTMF_REQ,
  OPENAT_BT_HFG_PLAY_SCO_AUDIO_REQ,
  OPENAT_BT_HFG_CONNECT_SCO_AUDIO_REQ,
  OPENAT_BT_HFG_SET_MIC_GAIN_REQ,

  /*for cmu test*/
  OPENAT_BT_TEST_POWERON_REQ,
  OPENAT_BT_TEST_POWEROFF_REQ,
  OPENAT_BT_TEST_VOC_REQ,
  OPENAT_BT_TEST_DUT_REQ,
  OPENAT_BT_TEST_SINGLEHOP_REQ
  
  
}E_AMOPENAT_BT_CMD;
/*app对BT的相应*/
typedef enum
{
  OPENAT_BT_MGR_LINK_ACCEPT_RSP,
  OPENAT_BT_MGR_PIN_CODE_RSP,

  OPENAT_BT_MAX_RSP
  
}E_AMOPENAT_BT_RSP;

/*BT主动上报或者BT相应APP请求*/
typedef enum
{
  OPENAT_BT_POWER_ON_IND,
  OPENAT_BT_BM_WRITE_SCANENABLE_MODE_CNF,
  OPENAT_BT_BM_READ_LOCAL_ADDR_CNF,
  OPENAT_BT_BM_WRITE_LOCAL_NAME_CNF,
  OPENAT_BT_BM_LINK_CONNECT_ACCEPT_IND,
  OPENAT_BT_BM_PIN_CODE_IND,
  OPENAT_BT_BM_BONDING_RESULT_IND,
  OPENAT_BT_BM_DEBOND_CNF,
  OPENAT_BT_BM_DISCOVERY_RESULT_IND,
  OPENAT_BT_BM_DISCOVERY_CNF,
  OPENAT_BM_BM_DISCOVERY_CANCEL_CNF,

  OPENAT_BT_PBAP_DATA_IND,
  OPENAT_BT_PBAP_DISCON_CNF,

  OPENAT_BT_HFG_CONNECT_IND,
  OPENAT_BT_HFG_CONNECT_CNF,
  OPENAT_BT_HFG_DISCONNECT_IND,
  OPENAT_BT_HFG_DISCONNECT_CNF,
  OPENAT_BT_HFG_SCO_CON_CNF,
  OPENAT_BT_HFG_SCO_DISCON_CNF,
  OPENAT_BT_PHONE_CALL_INFO_IND,
  OPENAT_BT_HFG_SCO_INFO_IND,

  OPENAT_BT_SPP_CONNECT_IND,
  OPENAT_BT_SPP_DISCONNECT_IND,
  OPENAT_BT_SPP_DISCONNECT_CNF,
  OPENAT_BT_SPP_CONNECT_CNF,
  OPENAT_BT_SPP_DATA_IND,
  OPENAT_BT_SPP_SEND_DATA_CNF,

  OPENAT_BT_POWER_OFF_IND,

  OPENAT_BT_DRV_EVENT_INVALID
}E_AMOPENAT_BT_EVENT;

typedef enum
{
  OPENAT_BTBM_ADP_P_OFF_I_OFF = 0,
  OPENAT_BTBM_ADP_P_OFF_I_ON,
  OPENAT_BTBM_ADP_P_ON_I_OFF,
  OPENAT_BTBM_ADP_P_ON_I_ON,
  OPENAT_BTBM_ADP_P_ON_I_ON_L
}E_AMOPENAT_BT_SCANNABLE;

typedef enum
{
	OPENAT_PBAP_DISCON_SUCCSEE,
	OPENAT_PBAP_DISCON_OPPER_UNSUPPORT,
	OPENAT_PBAP_DISCON_OPPER_NOT_ACCEPT
	
}E_AMOPENAT_BT_PBAP_DISCON_STATUS;


typedef struct
{
  UINT8	    name_len;
  UINT8	    name[OPENAT_BT_NAME_MAX_LEN];
}T_AMOPENAT_BT_NAME;
typedef struct
{
  UINT32   addrLap;
  UINT8    addrUap;
  UINT16   addrNap;
}T_AMOPENAT_BT_ADDR;


typedef struct
{
	UINT16 name[OPENAT_BT_PB_LENGHT];
	UINT8 name_length;

	UINT8 phone_num[OPENAT_BT_PB_LENGHT];
	UINT8 call_type;
	UINT8 data_time[17];

}T_AMOPENAT_BT_PBAP_CALL_HISTORY;

typedef struct
{
	UINT16 name[OPENAT_BT_PB_LENGHT];
	UINT8 name_length;
	UINT8 phone_num[3][OPENAT_BT_PB_LENGHT];

}T_AMOPENAT_BT_PBAP_INFO;

typedef union
{
	T_AMOPENAT_BT_PBAP_CALL_HISTORY history_info_array[10];
	T_AMOPENAT_BT_PBAP_INFO         pbap_info_array[10];

}U_AMOPENAT_BT_PBAP_ITEM_ARRAY;


/*BT_BM_WRITE_SCANENABLE_MODE_CNF*/
typedef struct
{
    UINT8	result;
}T_AMOPENAT_BT_WRITE_SCANNABLE_MODE_CNF;

/*BT_BM_READ_LOCAL_ADDR_CNF*/
typedef struct
{
    UINT8	         result;
    T_AMOPENAT_BT_ADDR  bd_addr;
}T_AMOPENAT_BT_READ_LOCAL_ADDR_CNF;

/*BT_BM_WRITE_LOCAL_NAME_CNF*/
typedef struct
{
    UINT8	result;
}T_AMOPENAT_BT_WRITE_LOCAL_NAME_CNF;

/*BT_BM_LINK_CONNECT_ACCEPT_IND*/
typedef struct
{
    T_AMOPENAT_BT_ADDR	bd_addr;
}T_AMOPENAT_BT_LINK_CONNECT_ACCEPT_IND;

/*BT_BM_PIN_CODE_IND*/
typedef struct
{
    T_AMOPENAT_BT_ADDR	bd_addr;
    UINT8	name_len;
    UINT8	name[OPENAT_BT_NAME_MAX_LEN];
}T_AMOPENAT_BT_BM_PIN_CODE_INT;

/*BT_BM_BONDING_RESULT_IND*/
typedef struct
{
    UINT8           result;
    T_AMOPENAT_BT_ADDR	bd_addr;
    UINT8	KeyType;
    UINT8  linkKey[0x10]; //support linkkey store in MMI	
    UINT32  cod;
}T_AMOPENAT_BT_BONDING_RESULT_IND;
typedef struct
{
  UINT8 result;
  T_AMOPENAT_BT_ADDR bd_addr;
}T_AMOPENAT_BT_DEBOND_CNF;
/*BT_PBAP_DATA_IND*/
typedef struct
{
	UINT8 	        con_type;//0 phone book; 1 combined call historys
	UINT32          tid;
	UINT8           status;
	UINT16          current_item_num;
	UINT16          all_item_num;
	U_AMOPENAT_BT_PBAP_ITEM_ARRAY  pbap_data_array;
	UINT8           is_spp_ind;
}T_AMOPENAT_BT_PBAP_BT_DATA_IND;

/*OPENAT_BT_PBAP_DISCON_CNF*/
typedef struct
{
	UINT8 con_type;//0 phone book; 1 combined call historys
	UINT32 tid;
	E_AMOPENAT_BT_PBAP_DISCON_STATUS status;
}T_AMOPENAT_BT_PBAP_CON_DISCON_INFO;

/*BT_BM_DISCOVERY_RESULT_IND*/
typedef struct  
{
    T_AMOPENAT_BT_ADDR bd_addr;
    UINT32	cod;
    UINT8	name_len;
    UINT8	name[OPENAT_BT_NAME_MAX_LEN];
}T_AMOPENAT_BT_BM_DISCOVERY_RESULT_IND;

/*BT_BM_DISCOVERY_CNF*/
typedef struct
{
    UINT8	result;
    UINT8	total_number;
}T_AMOPENAT_BT_BM_DISCOVERY_CNF;
/*BM_BM_DISCOVERY_CANCEL_CNF*/
typedef struct
{
    UINT8	result;
    UINT8	total_number;
}T_AMOPENAT_BT_BM_DISCOVERY_CANCEL_CNF;
/*BT_HFG_CONNECT_IND*/
typedef struct
{
    T_AMOPENAT_BT_ADDR bt_addr;
    UINT32   connection_id;    
    UINT8         profile; //handle if take earphone role
}T_AMOPENAT_BT_HFG_CONNECT_IND;
/*BT_HFG_CONNECT_CNF*/
typedef struct
{
    UINT16                 result;
    T_AMOPENAT_BT_ADDR     bt_addr;
    UINT32                 connection_id;
    UINT8                  profile; //handle if take earphone role
}T_AMOPENAT_BT_HFG_CONNECT_CNF;

typedef struct
{
    UINT16        result;
    T_AMOPENAT_BT_ADDR bt_addr;
    UINT32   connection_id;
}T_AMOPENAT_BT_HFG_DISCONNECT_CNF;

typedef struct
{
    T_AMOPENAT_BT_ADDR    bt_addr;
    UINT32   connection_id;
}T_AMOPENAT_BT_HFG_DISCONNECT_IND;

typedef struct
{
  UINT8 call_director;   // 1 is incoming call, 2 is out going call
	UINT8 call_status;    // 0 is no call,1 is setup,2 is active
	UINT8 call_number[OPENAT_BT_MAX_PHONE_NUMBER];
	UINT8 call_number_length;
}T_AMOPENAT_BT_PHONE_CALL_INFO;
typedef struct
{
	UINT16			result;
	UINT8 	    connection_id;
}T_AMOPENAT_BT_HFG_SCO_CON_CNF;
typedef struct
{
	UINT16 	       result;
	UINT8 	       connection_id;
}T_AMOPENAT_BT_HFG_SCO_DISCON_CNF;

typedef struct
{
  BOOL connect;
}T_AMOPENAT_BT_HFG_SCO_INFO_IND;

typedef struct
{
	UINT8	 port;	/* virtual port number*/
	UINT8        result;
	UINT16       maxFrameSize; /*一次传输最大字节数*/
	T_AMOPENAT_BT_ADDR addr;
}T_AMOPENAT_BT_SPP_CONN_IND;

typedef struct
{
	UINT8	             port;	/* virtual port number*/
  UINT8              result;  /* This is result field of this returned cnf msg */
	T_AMOPENAT_BT_ADDR addr;

}T_AMOPENAT_BT_SPP_DISCONN_IND;

typedef struct
{
	UINT8	 port;	/* virtual port number*/
 	UINT8         result;  /* This is result field of this returned cnf msg */	
	T_AMOPENAT_BT_ADDR addr;
}T_AMOPENAT_BT_SPP_DISCONN_CNF;

typedef struct
{
	UINT8	 port;	/* virtual port number*/
	UINT8         result;  /* This is result field of this returned cnf msg */
	UINT16        maxFrameSize; /*一次传输最大字节数*/
	T_AMOPENAT_BT_ADDR addr;
}T_AMOPENAT_BT_SPP_CONN_CNF;

typedef struct
{
	UINT8	       port;	 /* virtual port number*/
	UINT32       dataLen;
	T_AMOPENAT_BT_ADDR addr;
}T_AMOPENAT_BT_SPP_DATA_IND_T;

typedef struct
{
	T_AMOPENAT_BT_ADDR addr;
	UINT8	         port;	 /* virtual port number*/
	UINT8          result;  /* This is result field of this returned cnf msg */
}T_AMOPENAT_BT_SPP_SEND_DATA_CNF;
typedef union
{
  T_AMOPENAT_BT_WRITE_SCANNABLE_MODE_CNF writeScannableModeCnf;
  T_AMOPENAT_BT_READ_LOCAL_ADDR_CNF      readLocalAddrCnf;
  T_AMOPENAT_BT_WRITE_LOCAL_NAME_CNF     writeLocalNameCnf;
  T_AMOPENAT_BT_LINK_CONNECT_ACCEPT_IND  linkConnectAcceptInd;
  T_AMOPENAT_BT_BM_PIN_CODE_INT          pinCodeInd;
  T_AMOPENAT_BT_BONDING_RESULT_IND       bondingResultInd;
  T_AMOPENAT_BT_DEBOND_CNF               debondCnf;
  T_AMOPENAT_BT_PBAP_BT_DATA_IND         pbapBtDataInd;
  T_AMOPENAT_BT_PBAP_CON_DISCON_INFO     pbapDisconInfo;
  T_AMOPENAT_BT_BM_DISCOVERY_RESULT_IND  discoveryResultInd;
  T_AMOPENAT_BT_BM_DISCOVERY_CNF         discoveryCnf;
  T_AMOPENAT_BT_BM_DISCOVERY_CANCEL_CNF  discoveryCancelCnf;
  T_AMOPENAT_BT_HFG_CONNECT_IND          hfgConnectInd;
  T_AMOPENAT_BT_HFG_CONNECT_CNF          hfgConnectCnf;
  T_AMOPENAT_BT_HFG_DISCONNECT_IND       hfgDisconnectInd;
  T_AMOPENAT_BT_HFG_DISCONNECT_CNF       hfgDisconnectCnf;
  T_AMOPENAT_BT_PHONE_CALL_INFO          phoneCallInfo;
  T_AMOPENAT_BT_HFG_SCO_CON_CNF          hfgScoConCnf;
  T_AMOPENAT_BT_HFG_SCO_DISCON_CNF       hfgScoDisConCnf;
  T_AMOPENAT_BT_HFG_SCO_INFO_IND         hfgScoInfoInd;
  T_AMOPENAT_BT_SPP_CONN_IND             sppConnInd;
  T_AMOPENAT_BT_SPP_DISCONN_IND          sppDiscConInd;
  T_AMOPENAT_BT_SPP_DISCONN_CNF          sppDiscConCnf;
  T_AMOPENAT_BT_SPP_CONN_CNF             sppConnCnf;
  T_AMOPENAT_BT_SPP_DATA_IND_T           sppDataInd;
  T_AMOPENAT_BT_SPP_SEND_DATA_CNF        sppSendDataCnf;
}U_AMOPENAT_BT_EVENT_PARAM;

typedef VOID (*OPENAT_BLUETOOTH_EVT_HANDLE)(E_AMOPENAT_BT_EVENT event,U_AMOPENAT_BT_EVENT_PARAM* param);


typedef struct
{
	T_AMOPENAT_BT_ADDR	  bd_addr;
	UINT8         linkKey[0x10];
	UINT8         KeyType;
	UINT32   	      cod;
}T_AMOPENAT_BT_DEV_PAIRED;

typedef struct 
{
	UINT32 		                devNum;
	T_AMOPENAT_BT_DEV_PAIRED	devInfo_Array[10];
}T_AMOPENAT_BT_DEV_INFO_ARRAY;

typedef struct 
{
  E_AMOPENAT_BT_SCANNABLE scannable;
  T_AMOPENAT_BT_NAME      btName;
  UINT32                  supportProfile; /*OPENAT_BT_SUPPORT_SPP_PROFILE*/
  T_AMOPENAT_BT_DEV_INFO_ARRAY pairedDevices;
  OPENAT_BLUETOOTH_EVT_HANDLE pMessageHandle;
}T_AMOPENAT_BT_PARAM;


typedef union
{
  struct _mgr_discory_req
  {
    UINT32	                cod;              /**/
    UINT8	                  inquiry_timeoutms; /*查询超时*/
    UINT8	                  inquiry_max_count; /*最大查询个数*/
    BOOL                  	discovery_with_name;
  }mgrDiscoryReq;
  struct _mgr_discory_cancle
  {
    UINT8 nullParm;
  }mgrDiscoryCancle;
  struct _mgr_set_scannable
  {
    E_AMOPENAT_BT_SCANNABLE scannable;
  }mgrSetScannable;
  struct _mgr_read_local_addr
  {
    UINT8 nullParm;
  }mgrReadLocalAddr;
  struct _mgr_write_local_name
  {
    T_AMOPENAT_BT_NAME localName;
  }mgrWriteLocalName;
  struct _bm_bonding_req
  {
    T_AMOPENAT_BT_ADDR remoteAddr;
    UINT8             sdap_len;
    UINT32            sdap_uuid[OPENAT_BT_MAX_SDAP_UUID_NO];
  }bmBondingReq;
  struct _bm_debond_req
  {
    T_AMOPENAT_BT_ADDR remoteAddr;
  }bmDebondReq;
  struct _pbap_con_req
  {
    T_AMOPENAT_BT_ADDR remoteAddr;
  }pbapConReq;
  struct _pbap_get_next_req
  {
    UINT8 nullParm;
  }pbapGetNextReq;
  struct _pbap_con_cancel
  {
    UINT8 nullParm;
  }pbapConCancel;
  struct _hfp_con_req
  {
    T_AMOPENAT_BT_ADDR remoteAddr;
  }hfpConReq;
  struct _hfp_dial_req
  {
    UINT8 call_number[OPENAT_BT_MAX_PHONE_NUMBER];
    UINT8 call_number_length;
  }hfpDialReq;
  struct _hfp_hungup_req
  {
    UINT8 nullParm;
  }hfpHungUpReq;
  struct _hfp_call_answer
  {
    UINT8 nullParam;
  }hfpCallAnswer;
  struct _hfp_send_dtmf
  {
    UINT8 assicNum;
  }hfpSendDTMF;
  struct _hfp_sco_audio_open_req
  {
    BOOL open;
  }hfpScoAudoReq;
  struct _hfp_disconnect_req
  {
    T_AMOPENAT_BT_ADDR remoteAddr;
    UINT32 connectId;
  }hfpDisconnectReq;
  struct _hfp_connect_sco_req
  {
    BOOL connect;
    UINT32 connect_id;
  }hfpConnectSCOReq;
  struct _hfg_set_mic_gain_req
  {
    INT8 anaGain; /*0 ~ 21dB*/
    INT8 adcGain; /*-12 ~ 16dB*/
    INT8 nsGain; /*1 ~ 16*/
  }hfgSetMicGainReq;
  struct _hfg_set_sleep_mode_req
  {
    BOOL quickSleepMode;
  }hfgSetSleepModeReq;
}U_AMOPENAT_BT_CMD_PARAM;

typedef union
{
  struct _mgr_link_accept
  {
    BOOL       accept;
    T_AMOPENAT_BT_ADDR remote_bd_addr;
  }mgrLinkAccept;
  struct _mgr_pin_code
  {
    T_AMOPENAT_BT_ADDR	remote_bd_addr;
    UINT8	pin_len;
    UINT8	pin_code[16];
  }mgrPinCode;
  
}U_AMOPENAT_BT_RSP_PARAM;
/*-\NEW\brezen\2013.12.30\添加蓝牙接口*/

typedef enum
{
    /// No error occured
    OPENAT_MEMD_ERR_NO = 0,

    /// An error occurred during the erase operation
    OPENAT_MEMD_ERR_ERASE = -10,

    /// An error occurred during the write operation
    OPENAT_MEMD_ERR_WRITE,

    /// This error occurs when a command requiring 
    /// sector aligned addresses as parameters is called with unaligned addresses. 
    /// (Those are 
    /// #memd_FlashErrors memd_FlashErase, #memd_FlashLock and #memd_FlashUnlock)
    OPENAT_MEMD_ERR_ALIGN,

    /// An erase or write operation was attempted on a protected sector
    OPENAT_MEMD_ERR_PROTECT,
    /// erase suspend.
    OPENAT_MEMD_ERR_SUSPEND,
    /// device is busy.
    OPENAT_MEMD_ERR_BUSY,
    
}E_AMOPENAT_MEMD_ERR;

/*+\NEW\RUFEI\2014.4.4\增加外部看门狗配置接口*/
#ifdef DSS_CONFIG_EX_WATCH_DOG
/*CUSTOM*/
typedef enum
{
    OPENAT_CUST_EX_WATCH_DOG_MODE_DEFAULT,
    OPENAT_CUST_EX_WATCH_DOG_MODE_CUST,

    OPENAT_CUST_EX_WATCH_DOG_MODE_NUM
}E_OPEANT_CUST_EX_WATCH_DOG_MODE;

typedef void (*CUSHandle)(void);

typedef union
{
    struct _default_mode_cfg
    {
        E_AMOPENAT_GPIO_PORT port;
        CUSHandle                      handle; /*reset接口使用*/
    }defaultModeCfg;
    struct _cust_mode_cfg
    {
        CUSHandle                      handle;/*reset接口使用*/
    }custModeCfg;
}U_AMOPENAT_EX_WATCH_DOG_CFG;
#endif //DSS_CONFIG_EX_WATCH_DOG
/*-\NEW\RUFEI\2014.4.4\增加外部看门狗配置接口*/

/*+\NEW\RUFEI\2014.8.20\增加gps接口实现*/
typedef struct
{
    E_AMOPENAT_UART_PORT port;
    T_AMOPENAT_UART_PARAM cfg;
}T_AMOPENAT_RDAGPS_UART_CFG;

typedef struct
{
    E_AMOPENAT_I2C_PORT port;
}T_AMOPENAT_RDAGPS_I2C_CFG;

typedef struct
{
    E_AMOPENAT_GPIO_PORT pinPowerOnPort;
    E_AMOPENAT_GPIO_PORT pinResetPort;
    E_AMOPENAT_GPIO_PORT pinBpWakeupGpsPort;
    BOOL                             pinBpWakeupGpsPolarity;
    E_AMOPENAT_GPIO_PORT pinGpsWakeupBpPort;
    BOOL                             pinGpsWakeupBpPolarity;
}T_AMOPENAT_RDAGPS_GPS_CFG;
typedef struct
{
    T_AMOPENAT_RDAGPS_I2C_CFG    i2c;
    T_AMOPENAT_RDAGPS_GPS_CFG   gps;
}T_AMOPENAT_RDAGPS_PARAM;
/*-\NEW\RUFEI\2014.8.20\增加gps接口实现*/

/*+\NEW\RUFEI\2015.8.31\Update key init*/
/*cfg*/

typedef enum E_AMOPENAT_MOUDLE_TAG{
    KEY_MOUDLE,
    GPIO_MOUDLE,
    UART_MOUDLE,
    I2C_MOUDLE,
    SPI_MOUDLE,

    MOUDLE_MAX
}E_AMOPENAT_MOUDLE;


typedef union{
  struct pin_key{
    E_AMOPENAT_KEYPAD_TYPE keyMode;
    UINT32           row;
   //keyin 
    UINT32           col;
   //keyout
  }key;
}U_AMOPENAT_MOUDLE_CFG;
/*-\NEW\RUFEI\2015.8.31\Update key init*/

//+TTS, panjun 160326.
typedef enum enum_AMOPENAT_TTSPLY_STATE
{
    OPENAT_TTSPLY_STATE_IDLE = 0,
    OPENAT_TTSPLY_STATE_PLAY = 1,
    OPENAT_TTSPLY_STATE_PAUSE = 2,
    OPENAT_TTSPLY_STATE_STOP = 3,
    OPENAT_TTSPLY_STATE_END_PLAYING = 4,
    OPENAT_TTSPLY_STATE_ABNORMAL_EXIT = 5,
    OPENAT_TTSPLY_STATE_UNKOWN = 255
}AMOPENAT_TTSPLY_STATE;

typedef enum  enum_AMOPENAT_TTSPLY_ERROR {
    OPENAT_TTSPLY_ERR_NO = 0,
    OPENAT_TTSPLY_ERR_BUFFER_OVERFLOW = -1,
    OPENAT_TTSPLY_ERR_BUFFER_UNDERFLOW = -2,
    OPENAT_TTSPLY_ERR_EVENT_NONE = -3,
    OPENAT_TTSPLY_ERR_EVENT_DATA_REQUEST = -4,
    OPENAT_TTSPLY_ERR_EVENT_ERROR = -5,
    OPENAT_TTSPLY_ERR_RECOVER = -6,
    OPENAT_TTSPLY_ERR_FAILED = -7,
    OPENAT_TTSPLY_ERR_INVALID_RESOULTION = -8,
    OPENAT_TTSPLY_ERR_UNSUPPORTED_FORMAT = -9,
    OPENAT_TTSPLY_ERR_INVALID_BITSTREAM = -10,
    OPENAT_TTSPLY_ERR_MEMORY_INSUFFICIENT = -11,
    OPENAT_TTSPLY_ERR_INSUFFICIENT_MEMORY = -12,
    OPENAT_TTSPLY_ERR_INVALID_FORMAT = -13,
    OPENAT_TTSPLY_ERR_NOT_SUPPORTED = -14,
    OPENAT_TTSPLY_ERR_INVALID_PARAMETER = -15,
    OPENAT_TTSPLY_ERR_TIME_EXPIRED = -16,
    OPENAT_TTSPLY_ERR_LICENCE = -17,
    OPENAT_TTSPLY_ERR_INPUT_PARAM = -18,
    OPENAT_TTSPLY_ERR_TOO_MORE_TEXT = -19,
    OPENAT_TTSPLY_ERR_NOT_INIT = -20,
    OPENAT_TTSPLY_ERR_OPEN_DATA = -21,
    OPENAT_TTSPLY_ERR_NO_INPUT = -22,
    OPENAT_TTSPLY_ERR_MORE_TEXT = -23,
    OPENAT_TTSPLY_ERR_INPUT_MODE = -24,
    OPENAT_TTSPLY_ERR_ENGINE_BUSY = -25,
    OPENAT_TTSPLY_ERR_BE_INITIALIZED = -26,
    OPENAT_TTSPLY_ERR_PCM_OPEN_FAIL = -27,         		           
    OPENAT_TTSPLY_ERR_MEMORY = -28,	     
    OPENAT_TTSPLY_ERR_DONOTHING = -29,		   
    OPENAT_TTSPLY_ERR_PLAYING = -30,	      
    OPENAT_TTSPLY_ERR_AUDIO_DEVICE = -31,
    OPENAT_TTSPLY_ERR_RINGQUEUE_MEMORY = -32,
    OPENAT_TTSPLY_ERR_UNKOWN = -255,	               
} AMOPENAT_TTSPLY_ERROR;

typedef struct  tag_AMOPENAT_TTSPLY_PARAM
{
      INT16    volume;
      INT16    speed;
      INT16    pitch;
      UINT16  codepage;
      UINT8    digit_mode;
      UINT8    punc_mode;
      UINT8    tag_mode;
      UINT8    wav_format;
      UINT8    eng_mode;
}AMOPENAT_TTSPLY_PARAM;

typedef struct  tagAMOPENAT_TTSPLY
{
      WCHAR *text;
      UINT32  text_size;
      U8 spk_vol;
}AMOPENAT_TTSPLY;
//-TTS, panjun 160326.


typedef enum
{
    OPENAT_GPS_UART_MODE_RAW_DATA = 0,         /*Just need raw data*/
    OPENAT_GPS_UART_MODE_LOCATION,             /*Just need location*/
    OPENAT_GPS_UART_MODE_LOCATION_WITH_QOP     /*Need AGPS data with Qop*/
}E_AMOPENAT_GPS_WORK_MODE;

/*Data type for callback function of NMEA data or parserred data*/
typedef enum
{
    OPENAT_GPS_PARSER_RAW_DATA = 0,    /*Raw data of NMEA*/
    OPENAT_GPS_PARSER_NMEA_GGA,        /*Data structure of GGA info*/
    OPENAT_GPS_PARSER_NMEA_GLL,        /*Data structure of GLL info*/
    OPENAT_GPS_PARSER_NMEA_GSA,        /*Data structure of GSA info*/
    OPENAT_GPS_PARSER_NMEA_GSV,        /*Data structure of GSV info*/
    OPENAT_GPS_PARSER_NMEA_RMC,        /*Data structure of RMC info*/
    OPENAT_GPS_PARSER_NMEA_VTG,        /*Data structure of VTG info*/
    OPENAT_GPS_PARSER_NMEA_GAGSA,       /*Data structure of GAGSA info*/
    OPENAT_GPS_PARSER_NMEA_GAGSV,       /*Data structure of GAGSV info*/
    OPENAT_GPS_PARSER_NMEA_GLGSA,       /*Data structure of GLGSA info*/
    OPENAT_GPS_PARSER_NMEA_GLGSV,       /*Data structure of GLGSV info*/
    OPENAT_GPS_PARSER_NMEA_SENTENCE,
    OPENAT_GPS_UART_EVENT_VPORT_LOST,  /*Virtual port is lost, maybe bluetooth connection is break(not support current)*/
    OPENAT_GPS_SHOW_AGPS_ICON,
    OPENAT_GPS_HIDE_AGPS_ICON,
    OPENAT_GPS_PARSER_NMEA_ACC,        /*Data structure of ACCURACY info*/
    OPENAT_GPS_PARSER_NMEA_END,
    OPENAT_GPS_OPEN_IND,
    OPENAT_GPS_UART_RAW_DATA,
    OPENAT_GPS_PARSER_MA_STATUS = 255
}E_AMOPENAT_DATA_TYPE;
typedef void (*F_GPS_CB)(E_AMOPENAT_DATA_TYPE type, VOID *buffer, UINT32 length);

typedef enum
{
    OPENAT_GPS_UART_GPS_WARM_START = 0,        /*Let GPS do warm start*/
    OPENAT_GPS_UART_GPS_HOT_START,             /*Let GPS do hot start*/
    OPENAT_GPS_UART_GPS_COLD_START,            /*Let GPS do cold start*/
    OPENAT_GPS_UART_GPS_VERSION,
    OPENAT_GPS_UART_GPS_ENABLE_DEBUG_INFO,    
    OPENAT_GPS_UART_GPS_SWITCH_MODE_MA,
    OPENAT_GPS_UART_GPS_SWITCH_MODE_MB,
    OPENAT_GPS_UART_GPS_SWITCH_MODE_NORMAL,
    OPENAT_GPS_UART_GPS_QUERY_POS, //8
    OPENAT_GPS_UART_GPS_QUERY_MEAS, //9
    OPENAT_GPS_UART_GPS_CLEAR_NVRAM,           /*Clear GPS NVRAM*/
    OPENAT_GPS_UART_GPS_AGPS_START,            /*Clear GPS data*/
    OPENAT_GPS_UART_GPS_SLEEP,                 /*Let GPS chip goto sleep mode*/
    OPENAT_GPS_UART_GPS_STOP,                  /*Let GPS chip stop*/
    OPENAT_GPS_UART_GPS_WAKE_UP,               /*Let GPS chip wake up from sleep mode*/
    OPENAT_GPS_UART_GPS_DUMMY = -1
}T_OPENAT_GPS_CMD;

/*+\NEW \zhuwangbin\2020.01.06\添加自动检测升级功能*/
typedef enum
{
  OPENAT_UPGRADE_INVALID_URL = 1000,
  OPENAT_UPGRADE_NET_ERROR,
  OPENAT_UPGRADE_SERVER_CONNECT_ERROR,
  OPENAT_UPGRADE_INVALID_FILE,
  OPENAT_UPGRADE_SERVER_RESPONSE_ERROR,
  OPENAT_UPGRADE_WRITE_FLASH_ERROR,
  OPENAT_UPGRADE_ERROR,
  
}OPENAT_UPGRADE_ERR;
/*-\NEW \zhuwangbin\2020.01.06\添加自动检测升级功能*/

typedef enum
{
  OPENAT_OTA_SUCCESS = 0,
  OPENAT_OTA_ERROR_FLASH_NOT_SUPPORT = -100,
  OPENAT_OTA_ERROR_NO_MEMORY,
  OPENAT_OTA_ERROR_FBF_ERROR,
  OPENAT_OTA_ERROR_FW_NOT_ENOUGH,
  OPENAT_OTA_ERROR_VERIFY_ERROR,
  OPENAT_OTA_ERROR_WRITE,
}E_OPENAT_OTA_RESULT;

typedef enum
{
    OPENAT_OTP_SUCCESS,
    OPENAT_OTP_INVALID_PARAM,
    OPENAT_OTP_LOCKED,
    OPENAT_OTP_WRITE_ERROR,
    OPENAT_OTP_READ_ERROR,
    OPENAT_OTP_LOCK_ERROR,
    OPENAT_OPT_NULL_DATA,
    OPENAT_OPT_DATA_ERROR
}E_OPENAT_OTP_RET;


typedef enum
{
    OPENAT_MODULE_HW_AFF,
    OPENAT_MODULE_HW_A10,
    OPENAT_MODULE_HW_A11,
    OPENAT_MODULE_HW_A12,
    OPENAT_MODULE_HW_A13,
    OPENAT_MODULE_HW_A14,

}E_OPEANT_MODULE_HWVER;

typedef enum
{
    OPENAT_MODULE_Air720FF,        
    OPENAT_MODULE_Air720H,
    
    OPENAT_MODULE_Air720,
    OPENAT_MODULE_Air720D,
    OPENAT_MODULE_Air720T,
    OPENAT_MODULE_Air720U,
    OPENAT_MODULE_Air720M,
    OPENAT_MODULE_Air720G,
    OPENAT_MODULE_Air720GM,
    OPENAT_MODULE_Air720GL
}E_OPENAT_MODULE_TYPE;

typedef struct
{
    E_OPENAT_MODULE_TYPE type;
    E_OPEANT_MODULE_HWVER hw;
}T_OPENAT_MODULE;

/*----------------------------------------------*
 * 外部变量说明                                 *
 *----------------------------------------------*/

/*----------------------------------------------*
 * 外部函数原型说明                             *
 *----------------------------------------------*/
extern void lua_fm_set_loopback(UINT32 on, void* arg );

// +panjun, 2015.09.16, Add some asynchronous flags for LUA task.
void lua_sync_mmi_wait_event(UINT32 evt);
void lua_sync_mmi_set_event(UINT32 evt);
// -panjun, 2015.09.16, Add some asynchronous flags for LUA task.

/*+\NEW\RUFEI\2015.8.31\Update key init*/
 BOOL OPENAT_CFGPIN(E_AMOPENAT_MOUDLE moudle, U_AMOPENAT_MOUDLE_CFG *cfg);
/*-\NEW\RUFEI\2015.8.31\Update key init*/

VOID OPENAT_InitGPS(VOID);

BOOL OPENAT_OpenGPS(E_AMOPENAT_GPS_WORK_MODE mode, F_GPS_CB cb);

BOOL OPENAT_CloseGPS(VOID);

BOOL OPENAT_WriteGPS(VOID* buffer, UINT32 length, UINT32 *write);
BOOL OPENAT_SendCmdGPS(T_OPENAT_GPS_CMD cmd);

E_OPENAT_OTP_RET OPENAT_muid_write(char* muidStr, UINT32 muidStrlen);
E_OPENAT_OTP_RET OPENAT_muid_read(char* muidStrOut);

T_OPENAT_MODULE OPENAT_GetModuleType(void);


/*----------------------------------------------*
 * 内部函数原型说明                             *
 *----------------------------------------------*/

/*----------------------------------------------*
 * 全局变量                                     *
 *----------------------------------------------*/

/*----------------------------------------------*
 * 模块级变量                                   *
 *----------------------------------------------*/

/*----------------------------------------------*
 * 常量定义                                     *
 *----------------------------------------------*/

/*----------------------------------------------*
 * 宏定义                                       *
 *----------------------------------------------*/


#ifdef __cplusplus
#if __cplusplus
}
#endif
#endif // __cplusplus

#endif // __AM_OPENAT_DRV_H__

