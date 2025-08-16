#ifndef _LITTLE_FLASH_DEFINE_H_
#define _LITTLE_FLASH_DEFINE_H_

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "little_flash_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define LF_SW_VERSION                             "0.0.1"

struct little_flash;
typedef struct little_flash little_flash_t;

#ifndef LF_PRINTF
#define LF_PRINTF printf
#endif

#ifndef LF_INFO
#define LF_INFO(...)  LF_PRINTF(__VA_ARGS__)
#endif

#ifndef LF_ERROR
#define LF_ERROR(...)  LF_PRINTF(__VA_ARGS__)
#endif

/* assert for developer. */
#ifdef LF_DEBUG_MODE
#ifndef LF_DEBUG
#define LF_DEBUG(...)  LF_PRINTF(__VA_ARGS__)
#endif
#define LF_ASSERT(EXPR)                                                         \
if (!(EXPR))                                                                    \
{                                                                               \
    LF_PRINTF("(%s) has assert failed at %s.", #EXPR, __FUNCTION__);            \
    while (1);                                                                  \
}
#else
#ifndef LF_DEBUG
#define LF_DEBUG(...)
#endif
#define LF_ASSERT(EXPR)
#endif

#ifndef LF_NULL
#define LF_NULL NULL
#endif

#define LF_ENABLE       1
#define LF_DISABLE      0

/**
 * status register bits
 */
enum {
    LF_STATUS_REGISTER_BUSY = (1 << 0),                  /**< busing */
    LF_STATUS_REGISTER_WEL = (1 << 1),                   /**< write enable latch */
};

/**
 * @brief flash type
 * 
 */
#define LF_DRIVER_NOR_FLASH     (0)
#define LF_DRIVER_NAND_FLASH    (1)

/** Address Bytes */
#define LF_ADDR_BYTES_3         (1<<0)
#define LF_ADDR_BYTES_4         (1<<1)

typedef enum {
    LF_ERR_OK = 0,
    LF_ERR_NO_FLASH,
    LF_ERR_TIMEOUT,
    LF_ERR_TRANSFER,
    LF_ERR_ERASE,
    LF_ERR_WRITE,
    LF_ERR_READ,
    LF_ERR_BUSY,
    LF_ERR_BAD_ADDRESS,
    LF_ERR_NO_MEM,
    LF_ERR_SFDP_HEADER,
    LF_ERR_SFDP_PARAMETER,
}lf_err_t;

#ifndef LF_FLASH_NAME_LEN
#define LF_FLASH_NAME_LEN 16
#endif

/* JEDEC Basic Flash Parameter Table */
typedef struct {
    union{                                          /**< 1st DWORD */
        struct {
            uint32_t Erase_Sizes : 2;               /**< Erase Sizes */
            uint32_t Write_Granularity:1;           /**< Write Granularity */
            uint32_t Volatile_Block_Protect:1;      /**< Volatile Status Register Block Protect bits */
            uint32_t Write_Enable_Select:1;         /**< Write Enable Instruction Select for Writing to Volatile Status Register */
            uint32_t :3;                            /**< Contains 111b and can never be changed. */
            uint32_t Erase_4k:8;                    /**< 4 Kilobyte Erase Instruction */
            uint32_t Fast_Read_1S1S2S:1;            /**< Supports (1S-1S-2S) Fast Read */
            uint32_t Address_Bytes:2;               /**< Address Bytes */
            uint32_t DTR_Clocking:1;                /**< Supports Double Transfer Rate (DTR) Clocking */
            uint32_t Fast_Read_1S2S2S:1;            /**< Supports (1S-2S-2S) Fast Read */
            uint32_t Fast_Read_1S4S4S:1;            /**< Supports (1S-4S-4S) Fast Read */
            uint32_t Fast_Read_1S1S4S:1;            /**< Supports (1S-1S-4S) Fast Read */
            uint32_t :8;                            /**< Contains FFh and can never be changed. */
        };
        uint32_t pt1;                         
    };
    uint32_t Flash_Memory_Density;                  /**< Flash Memory Density */
    union{
        struct {
            uint32_t Fast_Read_1S4S4S_Wait:5;       /**< (1S-4S-4S) Fast Read Number of Wait states (dummy clocks) needed before valid output */
            uint32_t Fast_Read_1S4S4S_Clocks:3;     /**< Quad Input Address Quad Output (1S-4S-4S) Fast Read Number of Mode Clocks */
            uint32_t Fast_Read_1S4S4S_Instruction:8;/**< (1S-4S-4S) Fast Read Instruction */
            uint32_t Fast_Read_1S1S4S_Wait:5;       /**< (1S-1S-4S) Fast Read Number of Wait states (dummy clocks) needed before valid output */
            uint32_t Fast_Read_1S1S4S_Clocks:3;     /**< (1S-1S-4S) Fast Read Number of Mode Clocks */
            uint32_t Fast_Read_1S1S4S_Instruction:8;/**< (1S-1S-4S) Fast Read Instruction */
        };
        uint32_t pt3;
    };
    union{
        struct {
            uint32_t Fast_Read_1S1S2S_Wait:5;       /**< (1S-1S-2S) Fast Read Number of Wait states (dummy clocks) needed before valid output */
            uint32_t Fast_Read_1S1S2S_Clocks:3;     /**< Quad Input Address Quad Output (1S-1S-2S) Fast Read Number of Mode Clocks */
            uint32_t Fast_Read_1S1S2S_Instruction:8;/**< (1S-1S-2S) Fast Read Instruction */
            uint32_t Fast_Read_1S2S2S_Wait:5;       /**< (1S-2S-2S) Fast Read Number of Wait states (dummy clocks) needed before valid output */
            uint32_t Fast_Read_1S2S2S_Clocks:3;     /**< (1S-2S-2S) Fast Read Number of Mode Clocks */
            uint32_t Fast_Read_1S2S2S_Instruction:8;/**< (1S-2S-2S) Fast Read Instruction */
        };
        uint32_t pt4;
    };
    union{
        struct {
            uint32_t Fast_Read_2S2S2S:1;            /**< Supports (2S-2S-2S) Fast Read */
            uint32_t :3;                            /**< Reserved. These bits default to all 1’s */
            uint32_t Fast_Read_4S4S4S:1;            /**< Supports (4S-4S-4S) Fast Read */
            uint32_t :27;                           /**< Reserved. These bits default to all 1’s */
        };
        uint32_t pt5;
    };
    union{
        struct {
            uint32_t :16;                           /**< Reserved. These bits default to all 1’s */
            uint32_t Fast_Read_2S2S2S_Wait:5;       /**< (2S-2S-2S) Fast Read Number of Wait states (dummy clocks) needed before valid output */
            uint32_t Fast_Read_2S2S2S_Clocks:3;     /**< (2S-2S-2S) Fast Read Number of Mode Clocks */
            uint32_t Fast_Read_2S2S2S_Instruction:8;/**< (2S-2S-2S) Fast Read Instruction */
        };
        uint32_t pt6;
    };
    union{
        struct {
            uint32_t :16;                           /**< Reserved. These bits default to all 1’s */
            uint32_t Fast_Read_4S4S4S_Wait:5;       /**< (4S-4S-4S) Fast Read Number of Wait states (dummy clocks) needed before valid output */
            uint32_t Fast_Read_4S4S4S_Clocks:3;     /**< (4S-4S-4S) Fast Read Number of Mode Clocks */
            uint32_t Fast_Read_4S4S4S_Instruction:8;/**< (4S-4S-4S) Fast Read Instruction */
        };
        uint32_t pt7;
    };
    union{
        struct {
            uint32_t Erase_Type_1_Size:8;           /**< Erase Type 1 Size */
            uint32_t Erase_Type_1_Instruction:8;    /**< Erase Type 1 Instruction */
            uint32_t Erase_Type_2_Size:8;           /**< Erase Type 2 Size */
            uint32_t Erase_Type_2_Instruction:8;    /**< Erase Type 2 Instruction */
        };
        uint32_t pt8;
    };
    union{
        struct {
            uint32_t Erase_Type_3_Size:8;           /**< Erase Type 3 Size */
            uint32_t Erase_Type_3_Instruction:8;    /**< Erase Type 3 Instruction */
            uint32_t Erase_Type_4_Size:8;           /**< Erase Type 4 Size */
            uint32_t Erase_Type_4_Instruction:8;    /**< Erase Type 4 Instruction */
        };
        uint32_t pt9;
    };
    union{
        struct {
            uint32_t Erase_Time_Multiplier:4;       /**< Multiplier from typical erase time to maximum erase time */
            uint32_t Erase_Type_1_Time:7;           /**< Erase Type 1 Erase, Typical time */
            uint32_t Erase_Type_2_Time:7;           /**< Erase Type 2 Erase, Typical time */
            uint32_t Erase_Type_3_Time:7;           /**< Erase Type 3 Erase, Typical time */
            uint32_t Erase_Type_4_Time:7;           /**< Erase Type 4 Erase, Typical time */
        };
        uint32_t pt10;
    };
    union{
        struct {
            uint32_t Page_Program_Time_Multiplier:4;        /**< Multiplier from typical time to max time for Page or byte program*/
            uint32_t Page_Size:4;                           /**< Page Size */
            uint32_t Page_Program_Type_1_Time:6;            /**< Page Program Typical time */
            uint32_t Page_Program_Type_2_Time:5;            /**< Byte Program Typical time, first byte */
            uint32_t Page_Program_Type_3_Time:5;            /**< Byte Program Typical time, additional byte */
            uint32_t Erase_Chip_Type_Time:7;                /**< Chip Erase, Typical time */
            uint32_t :1;
        };
        uint32_t pt11;
    };
    // ...
    uint32_t pt12;
    uint32_t pt13;
    uint32_t pt14;
    uint32_t pt15;
    uint32_t pt16;
    uint32_t pt17;
    uint32_t pt18;
    uint32_t pt19;
    uint32_t pt20;
    uint32_t pt21;
    uint32_t pt22;
    uint32_t pt23;
    // ...
    uint32_t reserved[8];
    // ...
}little_flash_sfdp_pt_t;

typedef struct {
    uint8_t minor_rev;                          /**< sfdp minor revision */
    uint8_t major_rev;                          /**< sfdp major revision */
    uint8_t nph;                                /**< Number of Parameter Headers (NPH) */
    uint8_t access_protocol;                    /**< SFDP Access Protocol */

    uint16_t parameter_id;                      /**< Parameter ID */
    uint8_t parameter_minor_rev;                /**< Parameter Minor Revision */
    uint8_t parameter_major_rev;                /**< Parameter Major Revision */
    uint8_t parameter_length;                   /**< Parameter Length */
    uint32_t parameter_pointer;                 /**< Parameter Table Pointer */
    little_flash_sfdp_pt_t pt;                  /**< Parameter Table */
}little_flash_sfdp_t;

typedef struct {
    char name[LF_FLASH_NAME_LEN];                /**< flash chip name */
    uint8_t manufacturer_id;                     /**< MANUFACTURER ID */
    uint16_t device_id;                          /**< DEVICE ID (1byte or 2bytes) */
    union{                                       /**< driver type */
        struct {
            uint16_t type : 2;                   /**< flash type */
            uint16_t :14;                        /**< reserved */
        };
        uint16_t driver_type;                          
    };
    uint32_t capacity;                           /**< flash capacity (bytes) */
    uint8_t erase_cmd;                           /**< erase granularity size block command */
    uint32_t erase_size;                         /**< erase granularity (bytes) */
    /* 以下基本可以代码自动推断无需指定 */
    uint8_t addr_bytes;                          /**< address bytes */
    uint32_t prog_size;                          /**< page size (bytes) */
    uint32_t read_size;                          /**< read size (bytes) */
    uint32_t retry_times;                        /**< retry times */
    uint32_t erase_times;                        /**< erase time (ms) */
} little_flash_chipinfo_t;

typedef struct{
    lf_err_t (*transfer)(little_flash_t *lf,uint8_t *tx_buf, uint32_t tx_len, uint8_t *rx_buf, uint32_t rx_len);
    void* user_data;
} little_flash_spi_t;

struct little_flash{
    little_flash_chipinfo_t chip_info;
    little_flash_spi_t spi;
    /* lock */
    void (*lock)(little_flash_t *lf);
    /* unlock */
    void (*unlock)(little_flash_t *lf);
    /* wait 10us */
    void (*wait_10us)(uint32_t count);
    /* wait ms */
    void (*wait_ms)(uint32_t ms);
#ifdef LF_USE_HEAP
    /* malloc */
    void* (*malloc)(size_t size);
    /* free */
    void (*free)(void* ptr);
#endif /* LF_USE_HEAP */
    /* user data */
    void* user_data;
};

/* SFDP JESD216F revision */
#define LF_SFDP_MAJOR_REV                           (0x01)
#define LF_SFDP_MINOR_REV                           (0x0A)

#define LF_RETRY_TIMES                              (10)
#define LF_NORFLASH_ERASE_TIMES                     (50)
#define LF_NANDFLASH_ERASE_TIMES                    (2)

#define LF_NORFLASH_PAGE_ZISE                       (256)      /**< NOR flash page size (bytes) */
#define LF_NORFLASH_SECTOR_ZISE                     (4096)     /**< NOR flash sector size (bytes) */

#define LF_NANDFLASH_PAGE_ZISE                      (2048)     /**< NAND flash page size (bytes) */

#define LF_CMD_WRITE_STATUS_REGISTER                (0x01)

#define LF_CMD_WRITE_DISABLE                        (0x04)

#define LF_CMD_READ_STATUS_REGISTER                 (0x05)

#define LF_CMD_WRITE_ENABLE                         (0x06)

#define LF_CMD_SFDP_REGISTER                        (0x5A)
#define LF_CMD_SFDP_HEADER                          (0x00)
#define LF_CMD_SFDP_PARAMETER_HEADER1               (0x08)
#define LF_CMD_SFDP_PARAMETER_HEADER2               (0x10)

#define LF_CMD_JEDEC_ID                             (0x9F)

#define LF_CMD_ERASE_CHIP                           (0xC7)

#define LF_CMD_ENABLE_RESET                         (0x66)

#define LF_CMD_NORFLASH_RESET                       (0x99)

#define LF_CMD_BLOCK_ERASE                          (0xD8)

#define LF_CMD_NANDFLASH_RESET                      (0xFF)

#define LF_CMD_PROG_DATA                            (0x02)
#define LF_CMD_READ_DATA                            (0x03)

#define LF_NANDFLASH_PAGE_DATA_READ                 (0x13)
#define LF_NANDFLASH_PAGE_PROG_EXEC                 (0x10)


/* NAND flash status registers */
#define LF_NANDFLASH_STATUS_REGISTER1               (0xA0)
#define LF_NANDFLASH_STATUS_REGISTER2               (0xB0)
#define LF_NANDFLASH_STATUS_REGISTER3               (0xC0)
#define LF_NANDFLASH_STATUS_REGISTER4               (0xD0)

#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_DEFINE_H_ */










