#ifndef _LITTLE_FLASH_CONFIG_H_
#define _LITTLE_FLASH_CONFIG_H_

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef __cplusplus
extern "C" {
#endif

/* define the printf function for little flash */
#define LF_PRINTF LLOGI

#define LF_DEBUG_MODE                   /* enable debug mode for little flash */

#define LF_FLASH_NAME_LEN    16         /* the max length of flash name */

#define LF_USE_HEAP                     /* enable malloc/free for little flash */

// #define LF_USE_QSPI                     /* enable QSPI for little flash */

// #define LF_USE_SFDP                     /* enable SFDP driver for little flash */

#define LF_USE_LOCAL_TABLE              /* enable local table driver for little flash */

// #define LF_USE_NOR                      /* enable NOR for little flash */

#define LF_USE_NAND                     /* enable NAND for little flash */


#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_CONFIG_H_ */










