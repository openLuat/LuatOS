/*
 * tfs_port.c — FreeRTOS / bare-metal port implementation example
 *
 * Provides concrete implementations of the tfs_drv_t callbacks.
 * Adapt to your RTOS or OS-less environment.
 */

#include "../inc/tfs_port.h"
#include "../inc/tfs_types.h"

#include <stdlib.h>   /* malloc / free (replace with RTOS heap API) */
#include <string.h>

/*===================================================================
 *  Heap (swap for pvPortMalloc / pvPortFree on FreeRTOS)
 *===================================================================*/

static void *port_malloc(void *ctx, uint32_t size)
{
    (void)ctx;
    return malloc(size);
}

static void port_free(void *ctx, void *ptr)
{
    (void)ctx;
    free(ptr);
}

/*===================================================================
 *  Time (replace with xTaskGetTickCount() / RTC on RTOS)
 *===================================================================*/

static uint32_t port_get_time(void)
{
    /* Return seconds since epoch or tick count */
    return 0;
}

/*===================================================================
 *  Trace (replace with your debug console output)
 *===================================================================*/

static void port_trace(const char *fmt, ...)
{
    (void)fmt;
    /* e.g.: vprintf(fmt, va_args); */
}

/*===================================================================
 *  Mutex (replace with xSemaphoreTake / xSemaphoreGive on FreeRTOS)
 *===================================================================*/

static void port_lock(void *ctx)
{
    (void)ctx;
    /* e.g.: xSemaphoreTake(tfs_mutex, portMAX_DELAY); */
}

static void port_unlock(void *ctx)
{
    (void)ctx;
    /* e.g.: xSemaphoreGive(tfs_mutex); */
}

/*===================================================================
 *  NAND driver stubs — replace with real hardware calls
 *===================================================================*/

static int port_write_page(void *ctx,
                           uint32_t page,
                           const uint8_t *data, uint32_t data_len,
                           const uint8_t *oob,  uint32_t oob_len)
{
    (void)ctx; (void)page;
    (void)data; (void)data_len;
    (void)oob;  (void)oob_len;
    /* Call your NAND controller write function here */
    return TFS_OK;
}

static int port_read_page(void *ctx,
                          uint32_t page,
                          uint8_t *data, uint32_t data_len,
                          uint8_t *oob,  uint32_t oob_len)
{
    (void)ctx; (void)page;
    (void)data; (void)data_len;
    (void)oob;  (void)oob_len;
    /* Call your NAND controller read function here */
    return TFS_OK;
}

static int port_erase_block(void *ctx, uint32_t block)
{
    (void)ctx; (void)block;
    /* Call your NAND controller erase function here */
    return TFS_OK;
}

static int port_mark_bad(void *ctx, uint32_t block)
{
    (void)ctx; (void)block;
    /* Mark bad block in OOB byte 0 = 0x00 (ONFI convention) */
    return TFS_OK;
}

static int port_check_bad(void *ctx, uint32_t block)
{
    (void)ctx; (void)block;
    /* Check OOB byte 0; return 1 if bad */
    return 0;
}

/*===================================================================
 *  Driver table constructor
 *===================================================================*/

tfs_drv_t tfs_port_make_drv(void *user_ctx)
{
    tfs_drv_t drv;
    memset(&drv, 0, sizeof(drv));

    drv.ctx         = user_ctx;
    drv.write_page  = port_write_page;
    drv.read_page   = port_read_page;
    drv.erase_block = port_erase_block;
    drv.mark_bad    = port_mark_bad;
    drv.check_bad   = port_check_bad;
    drv.malloc      = port_malloc;
    drv.free        = port_free;
    drv.lock        = port_lock;
    drv.unlock      = port_unlock;
    drv.get_time    = port_get_time;
    drv.trace       = port_trace;

    return drv;
}
