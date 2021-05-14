
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "ramdisk"
#include "luat_log.h"

#include "ff.h"
#include "diskio.h"

extern BYTE FATFS_DEBUG; // debug log, 0 -- disable , 1 -- enable

typedef struct luat_ramdisk {
    BYTE debug;
    size_t len;
    void* ptr;
}luat_ramdisk_t;

DSTATUS ramdisk_initialize (void* userdata);
DSTATUS ramdisk_status (void* userdata);
DRESULT ramdisk_read (void* userdata, BYTE* buff, LBA_t sector, UINT count);
DRESULT ramdisk_write (void* userdata, const BYTE* buff, LBA_t sector, UINT count);
DRESULT ramdisk_ioctl (void* userdata, BYTE cmd, void* buff);

const block_disk_opts_t ramdisk_disk_opts = {
    .initialize = ramdisk_initialize,
    .status = ramdisk_status,
    .read = ramdisk_read,
    .write = ramdisk_write,
    .ioctl = ramdisk_ioctl,
};

// TODO 补齐实现

DSTATUS ramdisk_initialize (void* userdata) {
    luat_ramdisk_t* disk = (luat_ramdisk_t*)userdata;
    if (disk->ptr == NULL || disk->len < FF_MIN_SS) {
        if (FATFS_DEBUG)
            LLOGD("ramdisk initialize check error");
        return RES_ERROR;
    }
    if (FATFS_DEBUG)
        LLOGD("ramdisk initialize ok");
    return RES_OK;
};

DSTATUS ramdisk_status (void* userdata) {
    luat_ramdisk_t* disk = (luat_ramdisk_t*)userdata;
    if (disk->ptr == NULL || disk->len < FF_MIN_SS){
        if (FATFS_DEBUG)
            LLOGD("ramdisk status check error");
        return RES_ERROR;
    }
    return RES_OK;
};

DRESULT ramdisk_read (void* userdata, BYTE* buff, LBA_t sector, UINT count) {
    luat_ramdisk_t* disk = (luat_ramdisk_t*)userdata;
    if (disk->ptr == NULL || disk->len < FF_MIN_SS){
        if (FATFS_DEBUG)
            LLOGD("ramdisk read check error");
        return RES_ERROR;
    }
    memcpy(buff, (char*)disk->ptr + (sector) * FF_MIN_SS, FF_MIN_SS*count);
    return RES_OK;
};

DRESULT ramdisk_write (void* userdata, const BYTE* buff, LBA_t sector, UINT count) {
    luat_ramdisk_t* disk = (luat_ramdisk_t*)userdata;
    if (disk->ptr == NULL || disk->len < FF_MIN_SS){
        if (FATFS_DEBUG)
            LLOGD("ramdisk write check error");
        return RES_ERROR;
    }
    //LLOGD("write(disk->ptr == %p) at %p , len = 0x%08X", disk->ptr, disk->ptr + (sector) * FF_MIN_SS, FF_MIN_SS*count);
    memcpy((char*)disk->ptr + (sector) * FF_MIN_SS, (void*)buff, FF_MIN_SS*count);
    return RES_OK;
};

DRESULT ramdisk_ioctl (void* userdata, BYTE cmd, void* buff) {
    luat_ramdisk_t* disk = (luat_ramdisk_t*)userdata;
    if (disk->ptr == NULL || disk->len < FF_MIN_SS){
        if (FATFS_DEBUG)
            LLOGD("ramdisk ioctl check error");
        return RES_ERROR;
    }
    if (FATFS_DEBUG)
            LLOGD("ramdisk ioctl cmd %d", cmd);
    switch (cmd) {
        case CTRL_SYNC :
            //*(DWORD*)buff = 0;
            break;
        case GET_SECTOR_COUNT:
            *(DWORD*)buff = disk->len / FF_MIN_SS;
            LLOGD("ramdisk GET_SECTOR_COUNT %d", disk->len / FF_MIN_SS);
            break;
        case GET_SECTOR_SIZE:
            *(DWORD*)buff = FF_MIN_SS;
            LLOGD("ramdisk GET_SECTOR_SIZE %d", FF_MIN_SS);
            break;
        case GET_BLOCK_SIZE:
            *(DWORD*)buff = 1;
            break;
        default :
            if (FATFS_DEBUG)
                LLOGD("ramdisk unkown cmd %d", cmd);
            return RES_ERROR;
    }
    return RES_OK;
};

DRESULT diskio_open_ramdisk(BYTE pdrv, size_t len) {
    void* ptr = luat_heap_malloc(len + sizeof(luat_ramdisk_t));
    if (ptr == NULL) {
        LLOGW("luat_heap_malloc return NULL");
        return RES_ERROR;
    }
    memset(ptr, 0, len + sizeof(luat_ramdisk_t));
    luat_ramdisk_t* ramdisk = ptr;
    ramdisk->ptr = ramdisk + sizeof(luat_ramdisk_t);
    ramdisk->len = len;
    ramdisk->debug = 0;

    block_disk_t disk = {
        .opts = &ramdisk_disk_opts,
        .userdata = ramdisk,
    };

    DRESULT ret = diskio_open(pdrv, &disk);
    if (ret != RES_OK) {
        luat_heap_free(ptr);
    }
    return ret;
}

