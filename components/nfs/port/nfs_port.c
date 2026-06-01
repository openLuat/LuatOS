/*
 * nfs_port.c — FreeRTOS / bare-metal port implementation example
 *
 * Provides concrete implementations of the nfs_drv_t callbacks.
 * Adapt to your RTOS or OS-less environment.
 */

#include "../inc/nfs_port.h"
#include "../inc/nfs_types.h"

#include <stdlib.h>   /* malloc / free (replace with RTOS heap API) */
#include <string.h>

/*===================================================================
 *  Heap (swap for pvPortMalloc / pvPortFree on FreeRTOS)
 *===================================================================*/

static void *port_malloc(void *ctx, nfs_u32 size)
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

static nfs_u32 port_get_time(void)
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
    /* e.g.: xSemaphoreTake(nfs_mutex, portMAX_DELAY); */
}

static void port_unlock(void *ctx)
{
    (void)ctx;
    /* e.g.: xSemaphoreGive(nfs_mutex); */
}

/*===================================================================
 *  NAND driver stubs — replace with real hardware calls
 *===================================================================*/

static int port_write_page(void *ctx,
                           nfs_u32 page,
                           const nfs_u8 *data, nfs_u32 data_len,
                           const nfs_u8 *oob,  nfs_u32 oob_len)
{
    (void)ctx; (void)page;
    (void)data; (void)data_len;
    (void)oob;  (void)oob_len;
    /* Call your NAND controller write function here */
    return NFS_OK;
}

static int port_read_page(void *ctx,
                          nfs_u32 page,
                          nfs_u8 *data, nfs_u32 data_len,
                          nfs_u8 *oob,  nfs_u32 oob_len)
{
    (void)ctx; (void)page;
    (void)data; (void)data_len;
    (void)oob;  (void)oob_len;
    /* Call your NAND controller read function here */
    return NFS_OK;
}

static int port_erase_block(void *ctx, nfs_u32 block)
{
    (void)ctx; (void)block;
    /* Call your NAND controller erase function here */
    return NFS_OK;
}

static int port_mark_bad(void *ctx, nfs_u32 block)
{
    (void)ctx; (void)block;
    /* Mark bad block in OOB byte 0 = 0x00 (ONFI convention) */
    return NFS_OK;
}

static int port_check_bad(void *ctx, nfs_u32 block)
{
    (void)ctx; (void)block;
    /* Check OOB byte 0; return 1 if bad */
    return 0;
}

/*===================================================================
 *  Driver table constructor
 *===================================================================*/

nfs_drv_t nfs_port_make_drv(void *user_ctx)
{
    nfs_drv_t drv;
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
