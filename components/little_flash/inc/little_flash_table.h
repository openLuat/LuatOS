#ifndef _LITTLE_FLASH_TABLE_H_
#define _LITTLE_FLASH_TABLE_H_

#ifdef __cplusplus
extern "C" {
#endif

/* Flash MANUFACTURER ID */
#define LF_MF_ID_WINBOND                             0xEF



/* 
    待考究是否需要 地址位数 页大小等参数
    Flash table 
    name | manufacturer ID |device ID | falsh type | capacity | addr bytes | erase cmd | erase size
*/

#define LITTLE_FLASH_CHIP_TABLE                                                                                 \
{                                                                                                               \
    {"W25N01GVZEIG", LF_MF_ID_WINBOND, 0xAA21, LF_DRIVER_NAND_FLASH, 128L*1024L*1024L, 2, 0xD8, 128L*1024L},    \
}

#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_TABLE_H_ */










