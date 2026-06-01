#ifndef _LITTLE_FLASH_FTL_H_
#define _LITTLE_FLASH_FTL_H_

#include "little_flash.h"

#ifdef __cplusplus
extern "C" {
#endif

lf_err_t little_flash_ftl_init(little_flash_t *lf, uint8_t op_percent);
void little_flash_ftl_deinit(little_flash_t *lf);
lf_err_t little_flash_ftl_map_page(const little_flash_t *lf, uint32_t logical_page, uint32_t *physical_page);
lf_err_t little_flash_ftl_mark_bad_and_remap(little_flash_t *lf, uint32_t logical_page, uint32_t bad_physical_page);
lf_err_t little_flash_ftl_sync(little_flash_t *lf);
lf_err_t little_flash_ftl_recover(little_flash_t *lf);
lf_err_t little_flash_ftl_gc_collect(little_flash_t *lf, uint8_t force);

#ifdef LUAT_USE_UTEST
int little_flash_ftl_utest_case(const char *case_name);
#endif

#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_FTL_H_ */
