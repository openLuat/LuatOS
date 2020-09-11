/******************************************************************************

                  版权所有 (C), 2001-2011

 ******************************************************************************
  文 件 名   : cfg_pal.h
  版 本 号   : 初稿
  作    者   : brezen
  生成日期   : 2012年12月12日
  最近修改   :
  功能描述   : 驱动配置平台适配
  函数列表   :
  修改历史   :
  1.日    期   : 2012年12月12日
    作    者   : brezen
    修改内容   : 创建文件
  2.日    期   : 2013年03月18日
    作    者   : rufei
    修改内容   : 增加pwm端口配置

******************************************************************************/

/*----------------------------------------------*
 * 包含头文件                                   *
 *----------------------------------------------*/
/*----------------------------------------------*
 * 外部变量说明                                 *
 *----------------------------------------------*/

/*----------------------------------------------*
 * 外部函数原型说明                             *
 *----------------------------------------------*/

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

#ifndef __CFG_PAL_H__
#define __CFG_PAL_H__
//#include "gpio.h"

#ifdef __cplusplus
#if __cplusplus
extern "C"{
#endif
#endif /* __cplusplus */

typedef  int  DRV_OPER_RESULT;

#define   DRV_SUCCESS            (0)
#define   DRV_ERROR              (-1)
#define   DRV_ERR_INVALID_MODE   (1)
#define   DRV_ERR_INVALID_PARAM  (2)
#define   DRV_ERR_INVALID_CMD    (3)
#define   DRV_ERR_REG_HANDLE_FAILED (4)
#define   DRV_ERR_CFG               (5)

#define   DRV_ERR_CFG_PIN_IN_USE    (6)
#define   DRV_ERR_CFG_PIN_NOT_SUPPORT (7)

#define   DRV_ERR_DEVICE_BUSY       (8)
#define   DRV_ERR_NOT_SUPPORT_CFG   (9)


typedef enum {
  PIN_NULL,
/*+\zhuwangbin\2018.09.18\添加管脚33-36,67,69,70-78, 80-81*/
	PIN_B6_IO33,     //33 FUN0
	PIN_C5_IO34,     //34 FUN0
	PIN_F6_IO35,		 //35 FUN0
	PIN_B5_IO36,     //36 FUN0

	PIN_M4_TDS_MIXCTRL, //56 FUN1
	PIN_L9_IO61,     //61 FUN0
	
	PIN_L8_TDS_DID0, //67 FUN1 
	PIN_N7_TDS_DIO2, //69 FUN1

	PIN_L7_TDS_DIO3, //70 FUN1
	PIN_T4_TDS_DIO4, //71 FUN1
	PIN_L6_TDS_DIO5, //72 FUN1
	PIN_R4_TDS_DIO6, //73 FUN1
	PIN_N6_TDS_DIO7, //74 FUN1
	PIN_P5_TDS_CLK, //75 FUN1
	PIN_T3_TDS_DIO8, //76 FUN1
	PIN_R3_TDS_DIO9, //77 FUN1
	PIN_P6_TDS_PAON, //78 FUN1
	//PIN_T2_TDS_PACTRL, //79 FCUN1
	PIN_P4_TDS_RXON, //80 FUN1
	PIN_P3_TDS_TXON, //81 FUN1
/*-\zhuwangbin\2018.09.18\添加管脚33-36,67,69,70-78, 80-81*/
  PIN_N3_IO58_U2TX, //
  PIN_M3_IO57_U2RX,  //uart2_rx
  PIN_P7_IO59_U2CTS, //uart2_cts
  PIN_N4_IO55_U2RTS, //UART2_RTS
  PIN_T2_IO79,//STATUS TDS_PACTRL
  PIN_E3_IO54_I2CSDA,//I2C_SDA GPIO_54
  PIN_A4_IO53_I2CSCL,//gpio 53 i2c_scl
  PIN_B4_IO51_U1RX, //DBG_RX GPIO51 SSP0_CLK
  PIN_C6_IO52_U1TX, //DBG_TX GPIO52 SSP0_FRM
  PIN_L10_IO64_SPI2DATAIN, //NET STATUS SPI2_DATAIN2 SCLK
  PIN_N9_IO65_SPI2STR,  //NET_MODE SPI2_STROBE1_1
  PIN_R5_IO68, //W_DISABLE TDS_DIO1
  PIN_R6_IO63, //AP_READY SSP2_FRM
  PIN_P8_IO62_SPI2TXD, //WAKEUP_IN SSP2_TXD
  /*+NEW\lijiaodi\2018.08.23\ 添加GPIO26,27,28,23*/  
  PIN_D6_IO26,
  PIN_C7_IO27,
  PIN_F7_IO28,
  PIN_F11_IO23_MMC1_CD,
  /*-NEW\lijiaodi\2018.08.23\ 添加GPIO26,27,28,23*/  
}DRV_CFG_REF_E;


typedef enum {
  UART1_PIN_CFG,
  UART2_PIN_CFG,
 /*+:\NewReq-WM-608\brezen\2013.3.1\将host uart作为普通串口使用 */ 
  UART_HOST_PIN_CFG,
 /*-:\NewReq-WM-608\brezen\2013.3.1\将host uart作为普通串口使用 */ 
  UART_MAX_NUM
}DRV_CFG_PIN_UART_E;

typedef enum {
  SPI1_PIN_CFG,
  SPI2_PIN_CFG,
  SPI_MAX_NUM
}DRV_CFG_PIN_SPI_E;
/*+\NEW\AMOPENAT-108\brezen\2014.7.3\添加I2C1接口*/
typedef enum {
  I2C1_PIN_CFG,
  I2C2_PIN_CFG,
  I2C3_PIN_CFG,
  I2C_MAX_NUM
}DRV_CFG_PIN_I2C_E;
/*-\NEW\AMOPENAT-108\brezen\2014.7.3\添加I2C1接口*/
typedef enum {
  KEY_CONFIG_INVALID,
  
  KEY_CONFIG_NONE,
  KEY_ADC_PIN_CFG,
  KEY_MATRIX_PIN_CFG,
/*+\NEW WM-718\rufei\2013.3.21\ 增加gpio键盘加密模式*/
  KEY_GPIO_PIN_CFG,
/*-\NEW WM-718\rufei\2013.3.21\ 增加gpio键盘加密模式*/
  KEY_CONFIG_QTY
}DRV_CFG_PIN_KEY_MODE_E;

typedef enum {
  /// invalid
  
  UART_CONFIG_INVALID = 0,
  /// UART is not used
  UART_CONFIG_NONE,

  
  /// UART use only data lines (TXD & RXD)
  
  UART_CONFIG_DATA,
  

  /// UART use data and flow control lines (TXD, RXD, RTS & CTS)
  UART_CONFIG_FLOWCONTROL,

  
  /// UART use all lines (TXD, RXD, RTS, CTS, RI, DSR, DCD & DTR)
  
  UART_CONFIG_MODEM,

  
  UART_CONFIG_QTY
}DRV_CFG_PIN_UART_MODE_E;



typedef enum {
  
  SPI_CONFIG_INVALID = 0,
  
  SPI_CONFIG_NONE,
  
  /*CLK,DO 其他接口用gpio模拟*/
  SPI_CONFIG_DATA,
  
  /*CLK,DO,CS*/
  SPI_CONFIG_DATA_CS,

  /*CLK,DO,DI*/
  SPI_CONFIG_DUPLEX_DATA,
  
  /*CLK,DO,DI,CS*/
  SPI_CONFIG_DUPLEX_DATA_CS,
  
  SPI_CONFIG_QTY
}DRV_CFG_PIN_SPI_MODE_E;


typedef enum {

  I2C_CONFIG_INVALID = 0,
  
  I2C_CONFIG_NONE,

  /*DATA,CLK*/

  I2C_CONFIG_DATA,


  I2C_CONFIG_QTY
}DRV_CFG_PIN_I2C_MODE_E;

typedef enum {
  PWM_CONFIG_PWT,
  PWM_CONFIG_LPG,
  PWM_CONFIG_PWL,

  PWM_CONFIG_QTY
}DRV_CFG_PIN_PWM_PORT_E;

typedef enum{
  
  CFG_PIN_FUN_0 = 0,
  CFG_PIN_FUN_1,
  CFG_PIN_FUN_2,
  CFG_PIN_FUN_3,
  CFG_PIN_FUN_4,
  CFG_PIN_FUN_5,
  CFG_PIN_FUN_6,
  CFG_PIN_FUN_7
}DRV_CFG_FUN_T;

typedef enum{
  CFG_PIN_EDGE_DISABLE,
  CFG_PIN_EDGE_DET_FALL,
  CFG_PIN_EDGE_DET_RAISE,
  CFG_PIN_EDGE_DET_ALL_EDGE,
}DRV_CFG_EDGE_E;


/*********************************************************
  Function:    DRVCFGAPI_ConfigPin
  Description: 配置pin的功能
  Input:
               1. pinRef  功能pin
               2. pinConfig pin配置参数
  Output:
  Return:       是否成功
  Others:
*********************************************************/
DRV_OPER_RESULT DRVCFGAPI_ConfigGpio(DRV_CFG_REF_E pinRef);
DRV_OPER_RESULT DRVCFGAPI_ConfigUart(DRV_CFG_REF_E pinRef);
DRV_OPER_RESULT DRVCFGAPI_ConfigI2C(DRV_CFG_REF_E pinRef);
DRV_OPER_RESULT DRVCFGAPI_ConfigWakeupEdge(DRV_CFG_REF_E pinRef, DRV_CFG_EDGE_E detEdge);
DRV_OPER_RESULT DRVCFGAPI_ConfigWakeUpEnable(BOOL enable);





#ifdef __cplusplus
#if __cplusplus
}
#endif
#endif /* __cplusplus */


#endif /* __CFG_PAL_H__ */
