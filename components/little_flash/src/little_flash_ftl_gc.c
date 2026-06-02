/*
 * little_flash_ftl_gc.c — DEPRECATED / STRIPPED.
 * GC is now owned by pgfs. little_flash_ftl.c provides all required stubs.
 * This file is kept to avoid breaking the build while the file exists.
 * Do not add any code here.
 */
#include "little_flash_ftl_internal.h"

/*
 * All required symbols are provided by little_flash_ftl.c:
 *   little_flash_ftl_gc_collect()
 *   little_flash_ftl_refresh_free_spares()
 *
 * These stubs simply return LF_ERR_OK / no-op.
 */
