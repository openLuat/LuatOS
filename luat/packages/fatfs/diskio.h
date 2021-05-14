/*-----------------------------------------------------------------------/
/  Low level disk interface modlue include file   (C)ChaN, 2019          /
/-----------------------------------------------------------------------*/

#ifndef _DISKIO_DEFINED
#define _DISKIO_DEFINED

#ifdef __cplusplus
extern "C" {
#endif

/* Status of Disk Functions */
typedef BYTE	DSTATUS;

/* Results of Disk Functions */
typedef enum {
	RES_OK = 0,		/* 0: Successful */
	RES_ERROR,		/* 1: R/W Error */
	RES_WRPRT,		/* 2: Write Protected */
	RES_NOTRDY,		/* 3: Not Ready */
	RES_PARERR		/* 4: Invalid Parameter */
} DRESULT;


/*---------------------------------------*/
/* Prototypes for disk control functions */


DSTATUS disk_initialize (BYTE pdrv);
DSTATUS disk_status (BYTE pdrv);
DRESULT disk_read (BYTE pdrv, BYTE* buff, LBA_t sector, UINT count);
DRESULT disk_write (BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count);
DRESULT disk_ioctl (BYTE pdrv, BYTE cmd, void* buff);

typedef struct block_disk_opts {
    DSTATUS (*initialize) (void* userdata);
	DSTATUS (*status) (void* userdata);
	DRESULT (*read) (void* userdata, BYTE* buff, LBA_t sector, UINT count);
	DRESULT (*write) (void* userdata, const BYTE* buff, LBA_t sector, UINT count);
	DRESULT (*ioctl) (void* userdata, BYTE cmd, void* buff);
}block_disk_opts_t;

typedef struct block_disk {
	void* userdata;
	const block_disk_opts_t* opts;
}block_disk_t;

DRESULT diskio_open(BYTE pdrv, block_disk_t * disk);
DRESULT diskio_close(BYTE pdrv);

/* Disk Status Bits (DSTATUS) */

#define STA_NOINIT		0x01	/* Drive not initialized */
#define STA_NODISK		0x02	/* No medium in the drive */
#define STA_PROTECT		0x04	/* Write protected */


/* Command code for disk_ioctrl fucntion */

/* Generic command (Used by FatFs) */
#define CTRL_SYNC			0	/* Complete pending write process (needed at FF_FS_READONLY == 0) */
#define GET_SECTOR_COUNT	1	/* Get media size (needed at FF_USE_MKFS == 1) */
#define GET_SECTOR_SIZE		2	/* Get sector size (needed at FF_MAX_SS != FF_MIN_SS) */
#define GET_BLOCK_SIZE		3	/* Get erase block size (needed at FF_USE_MKFS == 1) */
#define CTRL_TRIM			4	/* Inform device that the data on the block of sectors is no longer used (needed at FF_USE_TRIM == 1) */

/* Generic command (Not used by FatFs) */
#define CTRL_POWER			5	/* Get/Set power status */
#define CTRL_LOCK			6	/* Lock/Unlock media removal */
#define CTRL_EJECT			7	/* Eject media */
#define CTRL_FORMAT			8	/* Create physical format on the media */

/* MMC/SDC specific ioctl command */
#define MMC_GET_TYPE		10	/* Get card type */
#define MMC_GET_CSD			11	/* Get CSD */
#define MMC_GET_CID			12	/* Get CID */
#define MMC_GET_OCR			13	/* Get OCR */
#define MMC_GET_SDSTAT		14	/* Get SD status */
#define ISDIO_READ			55	/* Read data form SD iSDIO register */
#define ISDIO_WRITE			56	/* Write data to SD iSDIO register */
#define ISDIO_MRITE			57	/* Masked write data to SD iSDIO register */

/* ATA/CF specific ioctl command */
#define ATA_GET_REV			20	/* Get F/W revision */
#define ATA_GET_MODEL		21	/* Get model name */
#define ATA_GET_SN			22	/* Get serial number */

/* MMC card type flags (MMC_GET_TYPE) */
#define CT_MMC		0x01		/* MMC ver 3 */
#define CT_SD1		0x02		/* SD ver 1 */
#define CT_SD2		0x04		/* SD ver 2 */
#define CT_SDC		(CT_SD1|CT_SD2)	/* SD */
#define CT_BLOCK	0x08		/* Block addressing */


#ifdef __cplusplus
}
#endif

#endif
