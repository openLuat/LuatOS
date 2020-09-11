#ifndef  __IOT_VAT_H__
#define  __IOT_VAT_H__

#include "am_openat_vat.h"
#include "iot_network.h"

#define URC_QUEUE_COUNT 10                      /* global urc count */
#define AT_CMD_QUEUE_COUNT 50
#define AT_CMD_EXECUTE_DELAY  10                /* 10 ms */

#define AT_CMD_DELAY "DELAY:"
#define AT_CMD_END "\x0d\x0a"
#define AT_CMD_CR  '\x0d'
#define AT_CMD_LF  '\x0a'
#define STR_TO_INT(x) 	(x-'0') 					/*数字的char转换为int*/


typedef enum
{
    AT_RSP_ERROR = -1,
    AT_RSP_WAIT= 0, 
    AT_RSP_CONTINUE = 1,                        /* 继续执行下一条AT队列里的命令 */
    AT_RSP_PAUSE= 2,                            /* 暂停执行AT队列命令 */
    AT_RSP_FINISH = 3,                          /* 停止执行AT队列命令 */

    AT_RSP_FUN_OVER = 4,                        /* 功能模块化AT命令组执行完毕，可以把本次运行的功能清除 */
    AT_RSP_STEP_MIN = 10,
    AT_RSP_STEP = 20,                           /* 继续执行本条AT命令 */
    AT_RSP_STEP_MAX = 30,

}AtCmdRsp;

typedef AtCmdRsp (*AtCmdRspCB)(char *pRspStr);
typedef VOID (*UrcCB)(char *pUrcStr, u16 len);
typedef VOID (*ResultNotifyCb)(BOOL result);

typedef struct AtCmdEntityTag
{
    char* p_atCmdStr;				/*AT命令字符串*/
    u16 cmdLen;					/*AT命令长度*/
    AtCmdRspCB p_atCmdCallBack;	/*AT命令回调函数*/
}AtCmdEntity;

typedef struct UrcEntityTag
{
    char* p_urcStr;
    UrcCB p_urcCallBack;

}UrcEntity;

typedef struct _CELL_INFO
{
	u32 CellId;  //cell ID
	u32 Lac;  //LAC
	u16 Mcc;  //MCC
	u16 Mnc;  //MNC
	u16 rssi; //rssi
}CELL_INFO;

typedef struct _gsmloc_cellinfo
{
	CELL_INFO Cellinfo[6];
}gsmloc_cellinfo;

/**
 * @defgroup iot_sdk_sys 系统接口
 * @{
 */
/**@example vat/demo_vat.c
* vat接口示例
*/ 
/**用来设置虚拟AT通道的回调函数
*@param		vatHandle:  虚拟AT主动上报或者AT命令结果返回的回调函数
*@return	TRUE: 成功   FALSE: 失败
**/
BOOL iot_vat_init(PAT_MESSAGE vatHandle);

/**用来发送AT命令
*@param		cmdStr:  AT命令字符串
*@param   	cmdLen:  AT命令长度
*@return	TRUE: 成功   FALSE: 失败
*@note      注意，AT命令字符串cmdStr中需要包含"\r\n"或者"\r"结尾
**/
BOOL iot_vat_send_cmd(UINT8* cmdStr, UINT16 cmdLen);

/**用来批量发送AT命令
*@param		cmd:  AT命令参数
*@param   	cmd_count:  AT命令个数
*@return	TRUE: 成功   FALSE: 失败
**/
BOOL iot_vat_push_cmd(AtCmdEntity cmd[],u8 cmd_count);


/** @}*/


#endif

