#ifndef __IOT_NETWORK_H__
#define __IOT_NETWORK_H__

#include "am_openat.h"

// #define OPENAT_NETWORK_ISP_LENGTH (64)
// #define OPENAT_NETWORK_IMSI_LENGHT (64)
#define OPENAT_NETWORK_APN_LENGTH (64)
#define OPENAT_NETWORK_PASSWORD_LENGTH	(64)
#define OPENAT_NETWORK_USER_NAME_LENGTH (64)


typedef enum
{
    /*!< 网络断开 表示GPRS网络不可用，无法进行数据连接，有可能可以打电话*/
	OPENAT_NETWORK_DISCONNECT            		= 0x00,
    /*!< 网络已连接 表示GPRS网络可用，可以进行链路激活*/
	OPENAT_NETWORK_READY,
	/*!< 链路正在激活 */
	OPENAT_NETWORK_LINKING,
    /*!< 链路已经激活 PDP已经激活，可以通过socket接口建立数据连接*/
	OPENAT_NETWORK_LINKED,
	/*!< 链路正在去激活 */
	OPENAT_NETWORK_GOING_DOWN,
}E_OPENAT_NETWORK_STATE;

typedef VOID(*F_OPENAT_NETWORK_IND_CB)(E_OPENAT_NETWORK_STATE state);



typedef enum
{
    /*!< sim卡状态未知*/
	OPENAT_NETWORK_UNKNOWN=0,
    /*!< sim卡状态有效*/
	OPENAT_NETWORK_TRUE,
    /*!< SIM未插入或PIN码未解锁*/
	OPENAT_NETWORK_FALSE=255,
}E_OPENAT_SIM_STATE;

typedef struct
{
	/*!< 网络状态 */
	E_OPENAT_NETWORK_STATE state;
	/*!< 网络信号：0-31 (值越大，信号越好) */
	UINT8 csq;
	/*!< SIM卡状态 */
	E_OPENAT_SIM_STATE  simpresent;
}T_OPENAT_NETWORK_STATUS;

typedef struct
{
	char apn[OPENAT_NETWORK_APN_LENGTH];
	char username[OPENAT_NETWORK_USER_NAME_LENGTH];
	char password[OPENAT_NETWORK_PASSWORD_LENGTH];
}T_OPENAT_NETWORK_CONNECT;




/**
 * @defgroup iot_sdk_network 网络接口
 * @{
 */
/**获取网络状态
*@param     status:   返回网络状态
*@return    TRUE:    成功
            FLASE:   失败            
**/                                
BOOL iot_network_get_status (
                            T_OPENAT_NETWORK_STATUS* status
                            );
/**设置网络状态回调函数
*@param     indCb:   回调函数
*@return    TRUE:    成功
            FLASE:   失败
**/                            
BOOL iot_network_set_cb(F_OPENAT_NETWORK_IND_CB indCb);
/**建立网络连接，实际为pdp激活流程
*@param     connectParam:  网络连接参数，需要设置APN，username，passwrd信息
*@return    TRUE:    成功
            FLASE:   失败
@note      该函数为异步函数，返回后不代表网络连接就成功了，indCb会通知上层应用网络连接是否成功，连接成功后会进入OPENAT_NETWORK_LINKED状态
           创建socket连接之前必须要建立网络连接
           建立连接之前的状态需要为OPENAT_NETWORK_READY状态，否则会连接失败
**/                          
BOOL iot_network_connect(T_OPENAT_NETWORK_CONNECT* connectParam);
/**断开网络连接，实际为pdp去激活
*@param     flymode:   暂时不支持，设置为FLASE
*@return    TRUE:    成功
            FLASE:   失败
@note      该函数为异步函数，返回后不代表网络连接立即就断开了，indCb会通知上层应用
           连接断开后网络状态会回到OPENAT_NETWORK_READY状态
           此前创建socket连接也会失效，需要close掉
**/                                        
BOOL iot_network_disconnect(BOOL flymode);

/** @}*/

#endif

