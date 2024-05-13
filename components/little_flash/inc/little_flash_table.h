#ifndef _LITTLE_FLASH_TABLE_H_
#define _LITTLE_FLASH_TABLE_H_

#ifdef __cplusplus
extern "C" {
#endif

/* Flash MANUFACTURER ID */
#define LF_MF_ID_WINBOND                             0xEF



/* 
    Flash table 
    name | manufacturer ID |device ID | falsh type | capacity | erase cmd | erase size
*/

#define LITTLE_FLASH_CHIP_TABLE                                                                                 \
{                                                                                                               \
    {"W25N01GVZEIG", LF_MF_ID_WINBOND, 0xAA21, LF_DRIVER_NAND_FLASH, 128L*1024L*1024L, 0xD8, 64L*2048L},     \
    {"W25Q128FVSG", LF_MF_ID_WINBOND, 0x4018, LF_DRIVER_NOR_FLASH, 16L*1024L*1024L, 0x20, 4096L},            \
}

#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_TABLE_H_ */










