/*
 * nfs_port.h — Platform port interface for NFS
 *
 * All OS and hardware dependencies are injected through this struct.
 * No platform headers are included by the core NFS source.
 *
 * Usage:
 *   1. Fill an nfs_geo_t describing your NAND geometry.
 *   2. Fill an nfs_drv_t with pointers to your HAL functions.
 *   3. Call nfs_add_device(name, &drv, &geo) before nfs_mount().
 */

#ifndef NFS_PORT_H
#define NFS_PORT_H

#include "nfs_types.h"
#include "nfs_config.h"

/*===================================================================
 *  NAND geometry descriptor
 *===================================================================*/

typedef struct {
    nfs_u32 data_bytes_per_chunk;   /* Page data area, e.g. 2048 */
    nfs_u32 spare_bytes_per_chunk;  /* OOB area,       e.g. 64   */
    nfs_u32 chunks_per_block;       /* Pages per block,e.g. 64   */
    nfs_u32 start_block;            /* First usable block        */
    nfs_u32 end_block;              /* Last usable block (incl.) */
    int     inband_tags;            /* 1 = tags in data area     */
    int     stored_endian;          /* 0=cpu 1=LE 2=BE           */
} nfs_geo_t;

/*===================================================================
 *  Driver / OS callback table
 *
 *  All callbacks receive the opaque `ctx` pointer you supplied.
 *  Callbacks marked "may be NULL" are optional.
 *===================================================================*/

typedef struct {
    /*---------------------------------------------------------------
     *  NAND hardware callbacks (all required)
     *---------------------------------------------------------------*/

    /**
     * write_page — write a page to NAND
     * @ctx:      opaque driver context
     * @page:     absolute page/chunk number
     * @data:     data buffer (data_bytes_per_chunk bytes), may be NULL
     * @data_len: bytes to write from data (may be < data_bytes_per_chunk)
     * @oob:      OOB buffer (spare_bytes_per_chunk bytes), may be NULL
     * @oob_len:  bytes to write from oob
     * Return:    0 on success, <0 on failure
     */
    int (*write_page)(void *ctx, nfs_u32 page,
                      const nfs_u8 *data, nfs_u32 data_len,
                      const nfs_u8 *oob,  nfs_u32 oob_len);

    /**
     * read_page — read a page from NAND
     * Return: NFS_OK, NFS_EECCFIXED, NFS_EECCUNFIXED, or NFS_EFLASH
     */
    int (*read_page)(void *ctx, nfs_u32 page,
                     nfs_u8 *data, nfs_u32 data_len,
                     nfs_u8 *oob,  nfs_u32 oob_len);

    /**
     * erase_block — erase one block
     * Return: 0 success, <0 failure (block should be marked bad)
     */
    int (*erase_block)(void *ctx, nfs_u32 block);

    /**
     * mark_bad — mark block as permanently bad in the OOB
     * Return: 0 on success
     */
    int (*mark_bad)(void *ctx, nfs_u32 block);

    /**
     * check_bad — check whether block is marked bad
     * Return: 1 if bad, 0 if good, <0 on read error
     */
    int (*check_bad)(void *ctx, nfs_u32 block);

    /**
     * init / deinit — optional hardware initialisation hooks
     */
    int (*init)  (void *ctx);   /* may be NULL */
    int (*deinit)(void *ctx);   /* may be NULL */

    /*---------------------------------------------------------------
     *  OS / memory callbacks (all required except trace)
     *---------------------------------------------------------------*/

    /** malloc / free — heap allocator; ctx forwarded from nfs_drv_t */
    void *(*malloc)(void *ctx, nfs_u32 size);
    void  (*free)  (void *ctx, void *ptr);

    /**
     * lock / unlock — protect NFS in-RAM state from concurrent access.
     * Called around every public API function.
     * For single-threaded bare metal, both can be no-ops.
     */
    void (*lock)  (void *ctx);
    void (*unlock)(void *ctx);

    /**
     * get_time — return current time in seconds (or monotonic ticks).
     * Used for atime/mtime/ctime. May return 0 if not available.
     */
    nfs_u32 (*get_time)(void);

    /**
     * trace — optional debug output callback.
     * NFS will call: drv->trace("nfs: " fmt "\n", args...)
     * Set to NULL to suppress all trace output.
     */
    void (*trace)(const char *fmt, ...);  /* may be NULL */

    /** Opaque context forwarded to all callbacks above */
    void *ctx;
} nfs_drv_t;

/*===================================================================
 *  Device registration
 *===================================================================*/

/**
 * nfs_add_device — register a NAND device before mounting
 * @name: mount-point prefix, e.g. "/nand"
 * @drv:  driver/OS callback table (copied internally)
 * @geo:  NAND geometry (copied internally)
 * Return: 0 on success, NFS_FAIL on error
 */
int nfs_add_device(const char *name, const nfs_drv_t *drv,
                   const nfs_geo_t *geo);

/**
 * nfs_remove_device — deregister a device (must be unmounted first)
 */
int nfs_remove_device(const char *name);

#endif /* NFS_PORT_H */
