#ifndef _LITTLE_FLASH_CONFIG_H_
#define _LITTLE_FLASH_CONFIG_H_

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef __cplusplus
extern "C" {
#endif

/* define the printf function for little flash */
#define LF_PRINTF LLOGI

#ifndef LF_DEBUG_MODE
/* LF_DEBUG_MODE: 0 = release (assert degrade to LLOGE), 1 = dev (assert = while(1) loop)
 * release builds default OFF; pass -DLF_DEBUG_MODE=1 in the build to enable. */
#define LF_DEBUG_MODE 0
#endif

#define LF_FLASH_NAME_LEN    16         /* the max length of flash name */

#define LF_USE_HEAP                     /* enable malloc/free for little flash */

// #define LF_USE_QSPI                     /* enable QSPI for little flash */

#define LF_USE_SFDP                     /* enable SFDP driver for little flash */

#define LF_USE_LOCAL_TABLE              /* enable local table driver for little flash */

#define LF_USE_NOR                      /* enable NOR for little flash */

#define LF_USE_NAND                     /* enable NAND for little flash */


#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_CONFIG_H_ */










