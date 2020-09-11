#ifndef __IOT_FS_H__
#define __IOT_FS_H__

#include "iot_os.h"


/**
 * @defgroup iot_sdk_fs 文件系统接口
 * @{
 */
	/**@example fs/demo_fs.c
	* fs接口示例
	*/ 

/**打开文件
*@param		pszFileNameUniLe:		文件全路径名称
*@param		iFlag:		打开标志详细请参见E_AMOPENAT_FILE_OPEN_FLAG
*@return	INT32: 	    返回文件句柄
**/
INT32 iot_fs_open_file(                           
                        char* pszFileNameUniLe,
                        UINT32 iFlag         
                  );

/**关闭文件
*@param		iFd:		文件句柄，open_file 或 create_file 返回的
*@return	INT32: 	    返回值小于0失败, 其余成功
**/
INT32 iot_fs_close_file(                     
                        INT32 iFd           
                   );

/**读取文件
*@param		iFd:		文件句柄，open_file 或 create_file 返回的
*@param		pBuf:		数据保存指针
*@param		iLen:		buf长度
*@return	INT32: 	    返回读取长度, 小于0表示失败,其余成功
**/
INT32 iot_fs_read_file(                            
                        INT32 iFd,            
                        UINT8 *pBuf,            
                        UINT32 iLen            
                  );

/**写入文件
*@param		iFd:		文件句柄，open_file 或 create_file 返回的
*@param		pBuf:		需要写入的数据指针
*@param		iLen:		数据长度
*@return	INT32: 	    返回写入长度, 小于0表示失败,其余成功
**/
INT32 iot_fs_write_file(                           
                        INT32 iFd,            
                        UINT8 *pBuf,          
                        UINT32 iLen             
                   );

/**立即写入flash
*@param		iFd:		文件句柄，open_file 或 create_file 返回的
*@return	INT32: 	    返回立即写入长度, 小于0表示失败,其余成功
**/
INT32 iot_fs_flush_file(                           
                        INT32 iFd              
                   );    

/**文件定位
*@note  参数iOffset的含义取决于iOrigin的值.
*@param		iFd:		文件句柄，open_file 或 create_file 返回的
*@param		iOffset:	偏移量
*@param		iOrigin:	参数详细请参见E_AMOPENAT_FILE_SEEK_FLAG
*@return	INT32: 	    返回文件的偏移量
**/
INT32 iot_fs_seek_file(                           
                        INT32 iFd,            
                        INT32 iOffset,         
                        UINT8 iOrigin          
                  );

/**创建文件
*@param		pszFileNameUniLe:	文件全路径名称
*@return	INT32: 	            返回文件句柄, 小于0表示失败,其余成功
**/
INT32 iot_fs_create_file(                          
                        char* pszFileNameUniLe   
                    );

/**删除文件
*@param		pszFileNameUniLe:	文件全路径名称
*@return	INT32: 	            返回值小于0表示失败,其余成功
**/
INT32 iot_fs_delete_file(                          
                        char* pszFileNameUniLe
                    );

/**切换当前工作目录
*@param		pszDirNameUniLe:	目录路径
*@return	INT32: 	返回值小于0表示失败,其余成功
**/
INT32 iot_fs_change_dir(                            
                        char* pszDirNameUniLe  
                   );

/**创建目录
*@param		pszDirNameUniLe:	目录路径
*@param		iMode:	            目录属性，详细请参见E_AMOPENAT_FILE_ATTR_TAG
*@return	INT32: 	返回值小于0表示失败,其余成功
**/
INT32 iot_fs_make_dir(                              
                        char* pszDirNameUniLe, 
                        UINT32 iMode          
                 );

/**删除目录
*@param		pszDirNameUniLe:	目录路径,该目录必须为空，接口才能返回成功
*@return	INT32: 	返回值小于0表示失败,其余成功
**/
INT32 iot_fs_remove_dir(                          
                        char* pszDirNameUniLe  
                   );

/**获取当前路径
*@param		pCurDirUniLe:	目录路径
*@param		uUnicodeSize:	    存储目录信息空间大小
*@return	INT32: 	返回值小于0表示失败,其余成功
**/
INT32 iot_fs_get_current_dir(                    
                        char* pCurDirUniLe,   
                        UINT32 uUnicodeSize   
                        );

/**获取文件系统信息
*@param		devName:	查找文件句柄
*@param		fileInfo:	文件系统信息
*@return	INT32 	返回值小于0表示失败,其余成功
**/
INT32 iot_fs_get_fs_info(                         
                        E_AMOPENAT_FILE_DEVICE_NAME       devName,         
                        T_AMOPENAT_FILE_INFO               *fileInfo                 
                   );

/**获取文件大小接口
*@param	   pszFileNameUniLe:   文件全路径名称
*@return   UINT32:			   返回文件的大小
**/
UINT32 iot_fs_file_size(
                    char* pszFileNameUniLe
                );

/**打开查找，并且获取文件夹下文件名
*@param		dirName:	路径
*@param     findResult: 对应路径下的第一个文件
*@return	fileInfo: 	查找返回的句柄，返回值小于0表示失败,其余成功
**/                   
INT32 iot_fs_find_first(
     char* dirName,
     PAMOPENAT_FS_FIND_DATA findResult
);

/**获取文件夹下文件名
*@param		iFd:  iot_fs_find_first接口返回值
*@param     findResult: 对应路径下的文件
*@return	fileInfo: 	返回小于0表示没有剩余文件，其他值表示还有文件
**/                   
INT32 iot_fs_find_next(
     INT32 iFd, 
     PAMOPENAT_FS_FIND_DATA findResult
);

/**关闭查找
*@param		iFd:  iot_fs_find_first接口返回值
*@return	fileInfo: 	返回值小于0表示失败,其余成功
**/           
INT32 iot_fs_find_close(
     INT32 iFd
);

/** @}*/

#endif
