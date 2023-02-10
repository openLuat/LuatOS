/*-----------------------------------------------------------------------*/
/* Low level disk I/O module skeleton for FatFs     (C)ChaN, 2016        */
/*-----------------------------------------------------------------------*/
/* If a working storage control module is available, it should be        */
/* attached to the FatFs via a glue function rather than modifying it.   */
/* This is an example of glue functions to attach various exsisting      */
/* storage control modules to the FatFs module with a defined API.       */
/*-----------------------------------------------------------------------*/

#include "luat_base.h"
#include "luat_sdio.h"

#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */

#define LUAT_LOG_TAG "fatfs"
#include "luat_log.h"


DSTATUS sdio_initialize (
	luat_fatfs_sdio_t* userdata
)
{
	return 0;
}


/*-----------------------------------------------------------------------*/
/* Get Disk Status                                                       */
/*-----------------------------------------------------------------------*/

DSTATUS sdio_status (
	luat_fatfs_sdio_t* userdata
)
{
	//if (drv) return STA_NOINIT;

	return 0;
}

/*-----------------------------------------------------------------------*/
/* Read Sector(s)                                                        */
/*-----------------------------------------------------------------------*/


DRESULT sdio_read (
	luat_fatfs_sdio_t* userdata,
	BYTE *buff,			/* Pointer to the data buffer to store read data */
	DWORD sector,		/* Start sector number (LBA) */
	UINT count			/* Sector count (1..128) */
)
{
	return 0;
}



/*-----------------------------------------------------------------------*/
/* Write Sector(s)                                                       */
/*-----------------------------------------------------------------------*/

DRESULT sdio_write (
	luat_fatfs_sdio_t* userdata,
	const BYTE *buff,	/* Pointer to the data to be written */
	DWORD sector,		/* Start sector number (LBA) */
	UINT count			/* Sector count (1..128) */
)
{
	return 0;
}


/*-----------------------------------------------------------------------*/
/* Miscellaneous Functions                                               */
/*-----------------------------------------------------------------------*/


DRESULT sdio_ioctl (
	luat_fatfs_sdio_t* userdata,
	BYTE ctrl,		/* Control code */
	void *buff		/* Buffer to send/receive control data */
)
{
	return 0;
}

const block_disk_opts_t sdio_disk_opts = {
    .initialize = sdio_initialize,
    .status = sdio_status,
    .read = sdio_read,
    .write = sdio_write,
    .ioctl = sdio_ioctl,
};

__attribute__((weak)) void luat_sdio_set_sdhc_ctrl(
		block_disk_t *disk)
{

}

static block_disk_t disk = {0};

DRESULT diskio_open_sdio(BYTE pdrv, luat_fatfs_sdio_t* userdata) {
	// 暂时只支持单个fatfs实例
	disk.opts = &sdio_disk_opts;
    disk.userdata = userdata;
    luat_sdio_set_sdhc_ctrl(&disk);
	return diskio_open(pdrv, &disk);
}

//static DWORD get_fattime() {
//	how to get?
//}

//--------------------------------------------------------------------------------------

