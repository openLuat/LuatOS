#ifndef _LITTLE_FLASH_TABLE_H_
#define _LITTLE_FLASH_TABLE_H_

#ifdef __cplusplus
extern "C" {
#endif

/* Flash MANUFACTURER ID */
#define LF_MF_ID_WINBOND                             0xEF
#define LF_MF_ID_MACRONIX                            0xC2

/* 
    Flash table 
    name | manufacturer ID |device ID | falsh type | capacity | erase cmd | erase size
*/

#define LITTLE_FLASH_CHIP_TABLE                                                                                                                                                     \
{                                                                                                                                                                                   \
    /* NOR FLASH */                                                                                                                                                                 \
    {.name="W25Q128FVSG",  .manufacturer_id=LF_MF_ID_WINBOND, .device_id=0x4018, .type=LF_DRIVER_NOR_FLASH , .capacity=16L*1024L*1024L , .erase_cmd=0x20, .erase_size=4096L     },  \
    /* NAND FLASH */                                                                                                                                                                \
    {.name="W25N01GVZEIG", .manufacturer_id=LF_MF_ID_WINBOND, .device_id=0xAA21, .type=LF_DRIVER_NAND_FLASH, .capacity=128L*1024L*1024L, .erase_cmd=0xD8, .erase_size=64L*2048L },  \
    {.name="W25N01KVZEIR", .manufacturer_id=LF_MF_ID_WINBOND, .device_id=0xAE21, .type=LF_DRIVER_NAND_FLASH, .capacity=128L*1024L*1024L, .erase_cmd=0xD8, .erase_size=64L*2048L },  \
    {.name="W25N02KVZEIR", .manufacturer_id=LF_MF_ID_WINBOND, .device_id=0xAA22, .type=LF_DRIVER_NAND_FLASH, .capacity=256L*1024L*1024L, .erase_cmd=0xD8, .erase_size=64L*2048L },  \
    {.name="W25N04KVZEIR", .manufacturer_id=LF_MF_ID_WINBOND, .device_id=0xAA23, .type=LF_DRIVER_NAND_FLASH, .capacity=512L*1024L*1024L, .erase_cmd=0xD8, .erase_size=64L*2048L },  \
    {.name="MX35LF512"   , .manufacturer_id=LF_MF_ID_MACRONIX,.device_id=0x12C2, .type=LF_DRIVER_NAND_FLASH, .capacity=64L*1024L*1024L , .erase_cmd=0xD8, .erase_size=64L*2048L },  \
}

#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_TABLE_H_ */










