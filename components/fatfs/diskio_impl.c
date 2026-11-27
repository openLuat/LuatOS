/*-----------------------------------------------------------------------*/
/* Low level disk I/O module SKELETON for FatFs     (C)ChaN, 2019        */
/*-----------------------------------------------------------------------*/
/* If a working storage control module is available, it should be        */
/* attached to the FatFs via a glue function rather than modifying it.   */
/* This is an example of glue functions to attach various exsisting      */
/* storage control modules to the FatFs module with a defined API.       */
/*-----------------------------------------------------------------------*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_spi.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "luat_rtos.h"
#include <stdint.h>

#ifdef __LUATOS__
#include "lauxlib.h"
#endif

#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */

#define LUAT_LOG_TAG "diskio"
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
	uint8_t index;
	uint8_t used:1;
	uint8_t fs_is_alloc:1;
}fatfs_mount_slot_t;
static fatfs_mount_slot_t _slot[FF_VOLUMES];
static int _current_vol = -1;

void disk_set_current_vol(BYTE vol)
{
	if (vol < FF_VOLUMES) {
		_current_vol = vol;
	} else {
		_current_vol = -1;
	}
}

int disk_get_currnt_vol(void) {
	return _current_vol;
}

int disk_find_vol(const char *path)
{
	for (int i = 0; i < FF_VOLUMES; i++) {
		if (_slot[i].used && !memcmp(_slot[i].mount_point, path, _slot[i].mount_point_len)) {
			LLOGD("find slot %d for path %s", i, path);
			return i;
		}
	}
	return -1;
}

int disk_alloc_vol(const char *path, FATFS* fs, uint8_t mode, uint8_t index)
{
	if (strlen(path) > 16) {
		LLOGE("path %s name too long", path);
		return -1;
	}
	for (int i = 0; i < FF_VOLUMES; i++) {
		if (_slot[i].used) {
			if (!_slot[i].fs) {
				_slot[i].used = 0;
				_slot[i].fs_is_alloc = 0;
			} else {
				if (!memcmp(_slot[i].mount_point, path, _slot[i].mount_point_len)) {
					LLOGD("slot %d already alloc for path %s", i, path);
					if ((_slot[i].mode == mode) && (_slot[i].index == index)) {
						if (!fs || (_slot[i].fs == fs)) {
							memset(_slot[i].fs, 0, sizeof(FATFS));
							_slot[i].fs->pdev = i;
							return i;
						} else {
							LLOGE("but fs point not match %p-%p", _slot[i].fs, fs);
							return -1;
						}
						
					} else {
						LLOGE("but mode or index not match  mode %d-%d, index %d-%d", _slot[i].mode, mode,
							_slot[i].index, index);
						return -1;
					}
				}
			}
		}

	}
	for (int i = 0; i < FF_VOLUMES; i++) {
		if (!_slot[i].used) {
			LLOGD("slot %d alloc for path %s", i, path);
			_slot[i].used = 1;
			_slot[i].mount_point_len = strlen(path);
			_slot[i].mode = mode;
			_slot[i].index = index;
			memcpy(_slot[i].mount_point, path, _slot[i].mount_point_len);
			if (fs) {
				_slot[i].fs = fs;
				_slot[i].fs_is_alloc = 0;
			} else {
				_slot[i].fs = luat_heap_malloc(sizeof(FATFS));
				if (_slot[i].fs == NULL) {
					LLOGD("out of memory when malloc FATFS");
					return -1;
				}
				_slot[i].fs_is_alloc = 1;
			}
			memset(_slot[i].fs, 0, sizeof(FATFS));
			_slot[i].fs->pdev = i;
			return i;
		}
	}
	return -1;
}

void disk_release_vol(const char *path)
{
	for (int i = 0; i < FF_VOLUMES; i++) {
		if (!memcmp(_slot[i].mount_point, path, _slot[i].mount_point_len)) {
			LLOGD("release slot %d path %s", i, path);
			_slot[i].used = 0;
			if (_slot[i].fs_is_alloc) {
				luat_heap_free(_slot[i].fs);
			}
			_slot[i].fs = NULL;
			_slot[i].fs_is_alloc = 0;
		}
	}
}

FATFS* disk_get_fs(BYTE vol)
{
	if (vol >= FF_VOLUMES) {
		return NULL;
	}
	return _slot[vol].fs;
}

int disk_get_mode(BYTE vol)
{
	if (vol >= FF_VOLUMES) {
		return -1;
	}
	return _slot[vol].mode;
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

