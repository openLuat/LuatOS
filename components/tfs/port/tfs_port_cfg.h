/*
 * tfs_port_cfg.h — Example port configuration for FreeRTOS / bare-metal
 *
 * Copy this file to your project and adjust to match your platform.
 * Include before tfs_port.h.
 */

#ifndef TFS_PORT_CFG_H
#define TFS_PORT_CFG_H

/*-------------------------------------------------------------------
 *  Chunk / page size matching your NAND device
 *-------------------------------------------------------------------*/

/* 2 KiB data + 64-byte OOB per page */
#define TFS_CFG_DATA_BYTES_PER_CHUNK  2048u
#define TFS_CFG_CHUNKS_PER_BLOCK      64u
#define TFS_CFG_N_BLOCKS              1024u

/*-------------------------------------------------------------------
 *  Performance
 *-------------------------------------------------------------------*/

#define TFS_CFG_N_CACHES              10
#define TFS_CFG_N_TEMP_BUFFERS        4
#define TFS_CFG_RESERVED_BLOCKS       5

/*-------------------------------------------------------------------
 *  ECC: use hardware ECC if your controller supports it
 *-------------------------------------------------------------------*/

/* #define TFS_CFG_HW_ECC  1 */

/*-------------------------------------------------------------------
 *  Thread safety: enable for RTOS builds
 *-------------------------------------------------------------------*/

#define TFS_CFG_THREADSAFE  1

#endif /* TFS_PORT_CFG_H */
