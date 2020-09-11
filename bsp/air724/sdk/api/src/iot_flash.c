#include "iot_flash.h"
#include "hal_config.h"


/**获取flash可用的地址空间，返回的地址用来传入iot_flash_erase、iot_flash_write、iot_flash_read等接口。
*@param		addrout:	返回可用flash地址
*@param		lenout:	返回可用flash长度，单位为字节
*@return	E_AMOPENAT_MEMD_ERR: 	成功:OPENAT_MEMD_ERR_NO, 其余失败
*@note      该接口返回的地址是64KB对齐 返回的地址空间根据当前程序大小来确定。
**/
VOID iot_flash_getaddr(    
                    UINT32* addrout,
                    UINT32* lenout
               )
{
    extern char __flash_start;
    extern char __flash_end;
    UINT32 aligned = ((UINT32)&__flash_end + 0x10000 - 1) & (~(0x10000 - 1));
    if(addrout)
    {
        *addrout = aligned - CONFIG_NOR_PHY_ADDRESS;
    }
    if(lenout)
    {
        *lenout = CONFIG_APPIMG_FLASH_SIZE - (aligned - (UINT32)&__flash_start);
    }
}

/**flash擦 
*@param		startAddr:		擦写地址 64K对齐
*@param		endAddr:		擦写结束地址
*@return	E_AMOPENAT_MEMD_ERR: 	成功:OPENAT_MEMD_ERR_NO, 其余失败
**/
E_AMOPENAT_MEMD_ERR iot_flash_erase(             
                        UINT32 startAddr,
                        UINT32 endAddr
                   )
{
    return OPENAT_flash_erase(startAddr, endAddr);
}

/**flash写 
*@param		startAddr:		写地址 
*@param		size:		    写数据大小
*@param		writenSize:		写数据类型大小
*@param		buf:		    写数据指针
*@return	E_AMOPENAT_MEMD_ERR: 	成功:OPENAT_MEMD_ERR_NO, 其余失败
**/
E_AMOPENAT_MEMD_ERR iot_flash_write(             
                        UINT32 startAddr,
                        UINT32 size,
                        UINT32* writenSize,
                        CONST UINT8* buf
                   )
{
    return OPENAT_flash_write(startAddr, size, writenSize, buf);
}

/**flash读
*@param		startAddr:		读地址 
*@param		size:		    读数据大小
*@param		readSize:		读数据类型大小
*@param		buf:		    读数据指针
*@return	E_AMOPENAT_MEMD_ERR: 	成功:OPENAT_MEMD_ERR_NO, 其余失败
**/
E_AMOPENAT_MEMD_ERR iot_flash_read(               
                        UINT32 startAddr,
                        UINT32 size,
                        UINT32* readSize,
                        UINT8* buf
                   )
{
    return OPENAT_flash_read(startAddr, size, readSize, buf);
}

