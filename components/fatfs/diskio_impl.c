/*-----------------------------------------------------------------------*/
/* Low level disk I/O module SKELETON for FatFs     (C)ChaN, 2019        */
/*-----------------------------------------------------------------------*/
/* If a working storage control module is available, it should be        */
/* attached to the FatFs via a glue function rather than modifying it.   */
/* This is an example of glue functions to attach various exsisting      */
/* storage control modules to the FatFs module with a defined API.       */
/*-----------------------------------------------------------------------*/

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "luat_rtos.h"

#ifdef __LUATOS__
#include "lauxlib.h"
#endif

#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */

#define LUAT_LOG_TAG "luat.fatfs"
#include "luat_log.h"

#define __FATFS_POWER_PIN_ENABLE__ 0x8000
BYTE FATFS_DEBUG = 0; // debug log, 0 -- disable , 1 -- enable


static block_disk_t disks[FF_VOLUMES+1] = {0};
static WORD _power_delay[FF_VOLUMES];
static WORD _power_pin[FF_VOLUMES];

/* 挂载槽位, 下标即 FatFs 逻辑盘号 pdrv */
typedef struct {
	FATFS* fs;
	char mount_point[16];
	uint8_t mount_point_len;
	uint8_t mode;
	uint8_t used;
}fatfs_mount_slot_t;
static fatfs_mount_slot_t _slot[FF_VOLUMES];

int disk_find_vol(const char *path)
{
	for (int i = 0; i < FF_VOLUMES; i++) {
		if (_slot[i].used && !memcmp(_slot[i].mount_point, path, _slot[i].mount_point_len)) {
			return i;
		}
	}
	return -1;
}

void disk_set_power_pin(BYTE pdrv, BYTE pin, WORD delay)
{
	if (pdrv >= FF_VOLUMES) {
		return;
	}
	_power_pin[pdrv] = pin | __FATFS_POWER_PIN_ENABLE__;
	_power_delay[pdrv] = delay;
}

DSTATUS disk_initialize (BYTE pdrv) {
	if (FATFS_DEBUG)
		LLOGD("disk_initialize >> %d", pdrv);
	if (pdrv >= FF_VOLUMES || disks[pdrv].opts == NULL) {
		LLOGD("NOTRDY >> %d", pdrv);
		return RES_NOTRDY;
	}
	if (_power_pin[pdrv] & __FATFS_POWER_PIN_ENABLE__)
	{
		uint8_t pin = _power_pin[pdrv] & 0x00ff;
		luat_gpio_mode(pin, Luat_GPIO_OUTPUT, LUAT_GPIO_PULLUP, 0);
		luat_rtos_task_sleep(_power_delay[pdrv]);
		luat_gpio_mode(pin, Luat_GPIO_OUTPUT, LUAT_GPIO_PULLUP, 1);
	}
	return disks[pdrv].opts->initialize(disks[pdrv].userdata);
}

DSTATUS disk_status (BYTE pdrv) {
	if (FATFS_DEBUG)
		LLOGD("disk_status >> %d", pdrv);
	if (pdrv >= FF_VOLUMES || disks[pdrv].opts == NULL) {
		return RES_NOTRDY;
	}
	return disks[pdrv].opts->status(disks[pdrv].userdata);
}

DRESULT disk_read (BYTE pdrv, BYTE* buff, LBA_t sector, UINT count) {
	if (FATFS_DEBUG)
		LLOGD("disk_read >> %d", pdrv);
	if (pdrv >= FF_VOLUMES || disks[pdrv].opts == NULL) {
		return RES_NOTRDY;
	}
	return disks[pdrv].opts->read(disks[pdrv].userdata, buff, sector, count);
}

DRESULT disk_write (BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count) {
	//if (FATFS_DEBUG)
	//	LLOGD("disk_write >> %d", pdrv);
	if (pdrv >= FF_VOLUMES || disks[pdrv].opts == NULL) {
		return RES_NOTRDY;
	}
	return disks[pdrv].opts->write(disks[pdrv].userdata, buff, sector, count);
}

DRESULT disk_ioctl (BYTE pdrv, BYTE cmd, void* buff) {
	if (FATFS_DEBUG)
		LLOGD("disk_ioctl >> %d %d", pdrv, cmd);
	if (pdrv >= FF_VOLUMES || disks[pdrv].opts == NULL) {
		return RES_NOTRDY;
	}
	return disks[pdrv].opts->ioctl(disks[pdrv].userdata, cmd, buff);
}

DRESULT diskio_open(BYTE pdrv, block_disk_t * disk) {
	if (FATFS_DEBUG)
		LLOGD("disk_open >> %d", pdrv);
	if (pdrv >= FF_VOLUMES || disks[pdrv].opts != NULL) {
		return RES_NOTRDY;
	}
	disks[pdrv].opts = disk->opts;
	disks[pdrv].userdata = disk->userdata;
	return RES_OK;
}

#include "luat_mem.h"
DRESULT diskio_close(BYTE pdrv) {
	if (pdrv >= FF_VOLUMES || disks[pdrv].opts == NULL) {
		return RES_NOTRDY;
	}
	if (disks[pdrv].opts->close) {
		disks[pdrv].opts->close(disks[pdrv].userdata);
	}
	disks[pdrv].opts = NULL;
	if (disks[pdrv].userdata)
		luat_heap_free(disks[pdrv].userdata);
	disks[pdrv].userdata = NULL;
	return RES_OK;
}

#include "time.h"
DWORD get_fattime (void) {
	struct tm *tm;
	time_t t;
	time(&t);
    tm = gmtime(&t);
	return ( ((tm->tm_year-80) & 0x3F) << 25)
			| ((tm->tm_mon + 1) << 21)
			| (tm->tm_mday << 16)
			| (tm->tm_hour << 11)
			| (tm->tm_min << 5)
			| ((tm->tm_sec % 60) >> 1)
	;
}

