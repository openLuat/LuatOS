/*
 * nfs_port_cfg.h — Example port configuration for FreeRTOS / bare-metal
 *
 * Copy this file to your project and adjust to match your platform.
 * Include before nfs_port.h.
 */

#ifndef NFS_PORT_CFG_H
#define NFS_PORT_CFG_H

/*-------------------------------------------------------------------
 *  Chunk / page size matching your NAND device
 *-------------------------------------------------------------------*/

/* 2 KiB data + 64-byte OOB per page */
#define NFS_CFG_DATA_BYTES_PER_CHUNK  2048u
#define NFS_CFG_CHUNKS_PER_BLOCK      64u
#define NFS_CFG_N_BLOCKS              1024u

/*-------------------------------------------------------------------
 *  Performance
 *-------------------------------------------------------------------*/

#define NFS_CFG_N_CACHES              10
#define NFS_CFG_N_TEMP_BUFFERS        4
#define NFS_CFG_RESERVED_BLOCKS       5

/*-------------------------------------------------------------------
 *  ECC: use hardware ECC if your controller supports it
 *-------------------------------------------------------------------*/

/* #define NFS_CFG_HW_ECC  1 */

/*-------------------------------------------------------------------
 *  Thread safety: enable for RTOS builds
 *-------------------------------------------------------------------*/

#define NFS_CFG_THREADSAFE  1

#endif /* NFS_PORT_CFG_H */
