/*
 * little_flash FTL internal declarations.
 * NOTE: FTL has been stripped; only minimal typedefs retained for source
 * compatibility. All logic is identity-mapping stubs in little_flash_ftl.c.
 */
#ifndef _LITTLE_FLASH_FTL_INTERNAL_H_
#define _LITTLE_FLASH_FTL_INTERNAL_H_

#include "little_flash_ftl.h"

/* FTL constants (retained for any future pgfs migration reference) */
#define LF_FTL_INVALID_PAGE (0xFFFFFFFFu)
#define LF_FTL_JOURNAL_MAX  (256u)

/* FTL context — stripped; kept only to avoid breaking any residual source refs */
typedef struct {
    int dummy;  /* MSVC requires at least one member; real FTL state lives in pgfs */
} little_flash_ftl_ctx_t;

#endif /* _LITTLE_FLASH_FTL_INTERNAL_H_ */
