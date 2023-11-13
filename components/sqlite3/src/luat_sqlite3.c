#include "luat_base.h"
#include "sqlite3.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_crypto.h"


#define LUAT_LOG_TAG "sqlite3"
#include "luat_log.h"

#ifndef LUAT_SQLITE3_DEBUG
#define LUAT_SQLITE3_DEBUG 0
#endif

#if LUAT_SQLITE3_DEBUG == 0 
#undef LLOGD
#undef LLOGDUMP
#define LLOGD(...)
#define LLOGDUMP(...)
#endif

static int svfs_Open(sqlite3_vfs* ctx, sqlite3_filename zName, sqlite3_file*, int flags, int *pOutFlags);
static int svfs_Delete(sqlite3_vfs*, const char *zName, int syncDir);
static int svfs_Access(sqlite3_vfs* ctx, const char *zName, int flags, int *pResOut);
static int svfs_FullPathname(sqlite3_vfs* ctx, const char *zName, int nOut, char *zOut);
static int svfs_Randomness(sqlite3_vfs* ctx, int nByte, char *zOut);
static int svfs_Sleep(sqlite3_vfs* ctx, int microseconds);
static int svfs_CurrentTime(sqlite3_vfs* ctx, double*);
static int svfs_GetLastError(sqlite3_vfs* ctx, int, char *);

// vfs io
static int svfs_io_Close(sqlite3_file*);
static int svfs_io_Read(sqlite3_file*, void*, int iAmt, sqlite3_int64 iOfst);
static int svfs_io_Write(sqlite3_file*, const void*, int iAmt, sqlite3_int64 iOfst);
static int svfs_io_Truncate(sqlite3_file*, sqlite3_int64 size);
static int svfs_io_Sync(sqlite3_file*, int flags);
static int svfs_io_FileSize(sqlite3_file*, sqlite3_int64 *pSize);
static int svfs_io_Lock(sqlite3_file*, int);
static int svfs_io_Unlock(sqlite3_file*, int);
static int svfs_io_CheckReservedLock(sqlite3_file*, int *pResOut);
static int svfs_io_FileControl(sqlite3_file*, int op, void *pArg);
static int svfs_io_SectorSize(sqlite3_file*);
static int svfs_io_DeviceCharacteristics(sqlite3_file*);



static const sqlite3_io_methods svfs_io = {
    .iVersion = 1,
    .xClose = svfs_io_Close,
    .xRead = svfs_io_Read,
    .xWrite = svfs_io_Write,
    .xTruncate = svfs_io_Truncate,
    .xSync = svfs_io_Sync,
    .xFileSize = svfs_io_FileSize,
    .xLock = svfs_io_Lock,
    .xUnlock = svfs_io_Unlock,
    .xCheckReservedLock = svfs_io_CheckReservedLock,
    .xFileControl = svfs_io_FileControl,
    .xSectorSize = svfs_io_SectorSize,
    .xDeviceCharacteristics = svfs_io_DeviceCharacteristics
};

typedef struct sfile
{
    sqlite3_file sf;
    const char* path;
    int flags;
}sfile_t;


static sqlite3_vfs svfs = {
    .iVersion = 1,
    .mxPathname = 63,
    .szOsFile = sizeof(sfile_t),
    .zName = "luatos",
    .xOpen = svfs_Open,
    .xDelete = svfs_Delete,
    .xAccess = svfs_Access,
    .xFullPathname = svfs_FullPathname,
    .xRandomness = svfs_Randomness,
    .xSleep = svfs_Sleep,
    .xCurrentTime = svfs_CurrentTime,
    .xGetLastError = svfs_GetLastError
};

int sqlite3_os_init(void) {
    sqlite3_vfs_register(&svfs, 1);
    return 0;
};

int sqlite3_os_end(void) {
    sqlite3_vfs_unregister(&svfs);
    return 0;
}

static FILE* sopen(const char* zName, int flags) {
    size_t len = luat_fs_fsize(zName);
    LLOGD("打开文件 %s %d %d", zName, flags, len);
    FILE* fd = NULL;
    fd = luat_fs_fopen(zName, "rb");
    if (fd == NULL) {
        fd = luat_fs_fopen(zName, "wb");
    }
    if (fd) {
        luat_fs_fclose(fd);
    }
    fd = luat_fs_fopen(zName, "rb+");
    if (fd == NULL) {
        LLOGW("文件打开失败 %s", zName);
    }
    LLOGD("文件句柄 %s %p", zName, fd);
    return fd;
}

static int svfs_Open(sqlite3_vfs* ctx, sqlite3_filename zName, sqlite3_file* f, int flags, int *pOutFlags) {
    FILE* fd = sopen(zName, flags);
    if (fd == NULL) {
        return SQLITE_NOTFOUND;
    }
    luat_fs_fclose(fd);
    sfile_t* t = (sfile_t*)f;
    t->sf.pMethods = &svfs_io;
    t->path = zName;
    t->flags = flags;
    return SQLITE_OK;
}
static int svfs_Delete(sqlite3_vfs* ctx, const char *zName, int syncDir) {
    LLOGD("删除文件 %s", zName);
    luat_fs_remove(zName);
    return SQLITE_OK;
}
static int svfs_Access(sqlite3_vfs* ctx, const char *zName, int flags, int *pResOut) {
    // LLOGD("访问文件 %s %d", zName, flags);
    return SQLITE_OK;
}
static int svfs_FullPathname(sqlite3_vfs* ctx, const char *zName, int nOut, char *zOut) {
    memcpy(zOut, zName, strlen(zName));
    zOut[strlen(zName)] = 0x00;
    return SQLITE_OK;
}
static int svfs_Randomness(sqlite3_vfs* ctx, int nByte, char *zOut) {
    // LLOGD("随机数生成 长度 %d", nByte);
    luat_crypto_trng(zOut, nByte);
    return SQLITE_OK;
}
static int svfs_Sleep(sqlite3_vfs* ctx, int microseconds) {
    LLOGD("休眠微秒 %d", microseconds);
    return SQLITE_OK;
}
static int svfs_CurrentTime(sqlite3_vfs* ctx, double* t) {
    *t = 0.0;
    return SQLITE_OK;
}
static int svfs_GetLastError(sqlite3_vfs* ctx, int err, char * msg) {
    LLOGD("获取最后的报错 %d", err);
    return SQLITE_OK;
}

// vfs io
static int svfs_io_Close(sqlite3_file* f) {
    sfile_t* t = (sfile_t*)f;
    LLOGD("文件关闭 %s", t->path);
    return 0;
}

static int svfs_io_Read(sqlite3_file* f, void* data, int iAmt, sqlite3_int64 iOfst) {
    int ret = 0;
    sfile_t* t = (sfile_t*)f;
    char* ptr = data;
    if (ptr == NULL) {
        LLOGD("io read 目标地址为NULL");
        return SQLITE_IOERR;
    }
    memset(ptr, 0, iAmt);
    FILE* fd = sopen(t->path, t->flags);
    if (fd == NULL) {
        LLOGD("读取目标文件不存在 %s", t->path);
        return SQLITE_NOTFOUND;
    }
    LLOGD("文件读取 %s 长度 %d 偏移量 %d", t->path, iAmt, iOfst);
    ret = luat_fs_fseek(fd, iOfst, SEEK_SET);
    if (ret < 0) {
        luat_fs_fclose(fd);
        LLOGD("读取位置seek失败 %s %d", t->path, ret);
        return SQLITE_IOERR_READ;
    }
    ret = luat_fs_fread(data, iAmt, 1, fd);
    if (ret < 0) {
        luat_fs_fclose(fd);
        LLOGD("读取数据失败 %s %d", t->path, ret);
        return SQLITE_IOERR_READ;
    }
    if (ret <= 0) {
        luat_fs_fclose(fd);
        LLOGD("读取的长度不足 %s %d %d", t->path, ret, iAmt);
        return SQLITE_IOERR_SHORT_READ;
    }
    LLOGD("读取完成 %p 长度 %d 偏移量 %d", t->path, iAmt, iOfst);
    LLOGDUMP(ptr, iAmt > 48 ? 48 : iAmt);
    luat_fs_fclose(fd);
    return SQLITE_OK;
}

static int svfs_io_Write(sqlite3_file* f, const void* data, int iAmt, sqlite3_int64 iOfst) {
    int ret = 0;
    sfile_t* t = (sfile_t*)f;
    char* ptr = data;
    if (ptr == NULL) {
        LLOGD("io write 目标地址为NULL");
        return SQLITE_IOERR;
    }
    FILE* fd = sopen(t->path, t->flags);
    if (fd == NULL) {
        LLOGD("io write 目标文件不存在 %s", t->path);
        return SQLITE_NOTFOUND;
    }
    LLOGD("文件写入 指针 %p 长度 %d 偏移量 %d", data, iAmt, iOfst);
    ret = luat_fs_fseek(fd, iOfst, SEEK_SET);
    if (ret < 0) {
        luat_fs_fclose(fd);
        LLOGD("文件写入设置偏移量失败 %d", ret);
        return SQLITE_IOERR_WRITE;
    }
    ret = luat_fs_fwrite(data, iAmt, 1, fd);
    if (ret < 0) {
        luat_fs_fclose(fd);
        LLOGD("文件写入失败 %s %d", t->path, ret);
        return SQLITE_IOERR_WRITE;
    }
    if (ret <= 0) {
        luat_fs_fclose(fd);
        LLOGD("文件写入长度不足 结果 %d 长度 %d", ret, iAmt);
        return SQLITE_IOERR_WRITE;
    }
    LLOGD("文件写入完成 %s 长度 %d 偏移量 %d", t->path, iAmt, iOfst);
    LLOGDUMP(ptr, iAmt > 48 ? 48 : iAmt);
    luat_fs_fclose(fd);
    return SQLITE_OK;
}

static int svfs_io_Truncate(sqlite3_file* f, sqlite3_int64 size) {
    sfile_t* t = (sfile_t*)f;
    int ret = 0;
    ret = luat_fs_truncate(t->path, size);
    if (ret == 0)
        return SQLITE_OK;
    return SQLITE_IOERR_TRUNCATE;
}

static int svfs_io_Sync(sqlite3_file* f, int flags) {
    return 0;
}

static int svfs_io_FileSize(sqlite3_file* f, sqlite3_int64 *pSize) {
    sfile_t* t = (sfile_t*)f;
    *pSize = luat_fs_fsize(t->path);
    // LLOGD("读取文件大小 %s %d", t->path, *pSize);
    return 0;
}

static int svfs_io_Lock(sqlite3_file* f, int t) {
    return 0;
}

static int svfs_io_Unlock(sqlite3_file* f, int t) {
    return 0;
}

static int svfs_io_CheckReservedLock(sqlite3_file* f, int *pResOut) {
    return 0;
}

static int svfs_io_FileControl(sqlite3_file* f, int op, void *pArg) {
    return 0;
}

static int svfs_io_SectorSize(sqlite3_file* f) {
    return 16;
}

static int svfs_io_DeviceCharacteristics(sqlite3_file* f) {
    return SQLITE_IOCAP_ATOMIC;
}
