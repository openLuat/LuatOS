/*
 * tfs_port.h — Platform port interface for TFS
 *
 * All OS and hardware dependencies are injected through this struct.
 * No platform headers are included by the core TFS source.
 *
 * Usage:
 *   1. Fill an tfs_geo_t describing your NAND geometry.
 *   2. Fill an tfs_drv_t with pointers to your HAL functions.
 *   3. Call tfs_add_device(name, &drv, &geo) before tfs_mount().
 */

#ifndef TFS_PORT_H
#define TFS_PORT_H

#include "tfs_types.h"
#include "tfs_config.h"

/*===================================================================
 *  NAND geometry descriptor
 *===================================================================*/

typedef struct {
    uint32_t data_bytes_per_chunk;   /* Page data area, e.g. 2048 */
    uint32_t spare_bytes_per_chunk;  /* OOB area,       e.g. 64   */
    uint32_t chunks_per_block;       /* Pages per block,e.g. 64   */
    uint32_t start_block;            /* First usable block        */
    uint32_t end_block;              /* Last usable block (incl.) */
    int     inband_tags;            /* 1 = tags in data area     */
    int     stored_endian;          /* 0=cpu 1=LE 2=BE           */
} tfs_geo_t;

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
     * Return:    TFS_OK on success, TFS_EFLASH only for a confirmed NAND
     *            program failure, or another TFS error for invalid arguments
     *            and non-media failures. Only TFS_EFLASH may retire a block.
     */
    int (*write_page)(void *ctx, uint32_t page,
                      const uint8_t *data, uint32_t data_len,
                      const uint8_t *oob,  uint32_t oob_len);

    /**
     * read_page — read a page from NAND
     * Return: TFS_OK, TFS_EECCFIXED, TFS_EECCUNFIXED, or TFS_EFLASH
     */
    int (*read_page)(void *ctx, uint32_t page,
                     uint8_t *data, uint32_t data_len,
                     uint8_t *oob,  uint32_t oob_len);

    /**
     * erase_block — erase one block
     * Return: 0 success, <0 failure (block should be marked bad)
     */
    int (*erase_block)(void *ctx, uint32_t block);

    /**
     * mark_bad — mark block as permanently bad in the OOB
     * Return: 0 on success
     */
    int (*mark_bad)(void *ctx, uint32_t block);

    /**
     * check_bad — check whether block is marked bad
     * Return: 1 if bad, 0 if good, <0 on read error
     */
    int (*check_bad)(void *ctx, uint32_t block);

    /**
     * init / deinit — optional hardware initialisation hooks
     */
    int (*init)  (void *ctx);   /* may be NULL */
    int (*deinit)(void *ctx);   /* may be NULL */

    /*---------------------------------------------------------------
     *  OS / memory callbacks (all required except trace)
     *---------------------------------------------------------------*/

    /** malloc / free — heap allocator; ctx forwarded from tfs_drv_t */
    void *(*malloc)(void *ctx, uint32_t size);
    void  (*free)  (void *ctx, void *ptr);

    /**
     * lock / unlock — protect TFS in-RAM state from concurrent access.
     * Called around every public API function.
     * For single-threaded bare metal, both can be no-ops.
     */
    void (*lock)  (void *ctx);
    void (*unlock)(void *ctx);

    /**
     * get_time — return current time in seconds (or monotonic ticks).
     * Used for atime/mtime/ctime. May return 0 if not available.
     */
    uint32_t (*get_time)(void);

    /**
     * trace — optional debug output callback.
     * TFS will call: drv->trace("nfs: " fmt "\n", args...)
     * Set to NULL to suppress all trace output.
     */
    void (*trace)(const char *fmt, ...);  /* may be NULL */

    /**
     * checkpt_anchor_read / checkpt_anchor_write — optional fast checkpoint
     * locator stored by the port outside the TFS data area.
     *
     * Ports that implement this should return TFS_OK with the first checkpoint
     * chunk and sequence number. Return TFS_EINVAL when no valid anchor exists;
     * TFS will then fall back to scanning the NAND for checkpoint data.
     */
    int (*checkpt_anchor_read)(void *ctx, uint32_t *chunk, uint32_t *seq);
    int (*checkpt_anchor_write)(void *ctx, uint32_t chunk, uint32_t seq);

    /** Opaque context forwarded to all callbacks above */
    void *ctx;
} tfs_drv_t;

/*===================================================================
 *  Device registration
 *===================================================================*/

/**
 * tfs_add_device — register a NAND device before mounting
 * @name: mount-point prefix, e.g. "/nand"
 * @drv:  driver/OS callback table (copied internally)
 * @geo:  NAND geometry (copied internally)
 * Return: 0 on success, TFS_FAIL on error
 */
int tfs_add_device(const char *name, const tfs_drv_t *drv,
                   const tfs_geo_t *geo);

/**
 * tfs_remove_device — deregister a device (must be unmounted first)
 */
int tfs_remove_device(const char *name);

#endif /* TFS_PORT_H */
