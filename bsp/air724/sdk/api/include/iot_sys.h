#ifndef __IOT_SYS_H__
#define __IOT_SYS_H__

#include "iot_os.h"
#include "openat_ota.h"

/**
 * @defgroup iot_sdk_fota 远程升级接口
 * @{
 */
	/**@example fota/demo_fota.c
	* OTA接口示例
	*/ 


/**远程升级初始化
*@return	0:   表示成功
*           <0：  表示有错误
**/
E_OPENAT_OTA_RESULT iot_fota_init(void);

/**远程升级下载
*@param		data:				下载固件包数据
*@param		len:				下载固件包长度
*@param		total:				固件包总大小
*@return	0:   表示成功
*           <0：  表示有错误
**/
E_OPENAT_OTA_RESULT iot_fota_download(const char* data, UINT32 len, UINT32 total);

/**远程升级
*@return	0:   表示成功
*           <0：  表示有错误
**/
E_OPENAT_OTA_RESULT iot_fota_done(void);

/**ota设置new core的文件，用来告知底层需要从文件读取升级新的程序
*@param		newCoreFile:		新程序文件 
*@return	TRUE: 成功   FALSE: 失败
*注：newCoreFile文件必须保存在/fota文件夹下,例如newCoreFile 为 "/fota/core.img"
**/
BOOL iot_ota_newcore(              
                    CONST char* newCoreFile
               );


/**ota设置new app的文件，用来告知底层需要从文件读取升级新的程序
*@param		newAPPFile:		新程序文件 
*@return	TRUE: 成功   FALSE: 失败
*注：newAPPFile文件必须保存在/fota文件夹下,例如newAPPFile 为 "/fota/app.img"
**/
BOOL iot_ota_newapp(              
                    CONST char* newAPPFile
               );


/**将char类型转换为WCHAR，结果用来作为iot_fs_open_file等接口的文件名参数
*@param     dst:        转换输出结果
*@param     src:        等待转换的字符串
*@return    返回dst首地址
**/ 
WCHAR* iot_strtows(WCHAR* dst, const char* src);

/** @}*/

#endif

