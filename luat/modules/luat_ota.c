
#include "luat_base.h"
#include "luat_ota.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include "luat_mem.h"
#include "luat_flash.h"
#define LUAT_LOG_TAG "ota"
#include "luat_log.h"

LUAT_WEAK void luat_ota_reboot(int timeout_ms) {
  if (timeout_ms > 0)
    luat_timer_mdelay(timeout_ms);
  luat_os_reboot(1);
}

#ifdef LUAT_USE_OTA

#include "luat_crypto.h"
#include "luat_md5.h"

#ifdef LUAT_USE_CRYPTO
#include "mbedtls/md5.h"
#undef luat_md5_init
#undef luat_md5_update
#undef luat_md5_finalize

#if MBEDTLS_VERSION_NUMBER >= 0x03000000
#define luat_md5_init mbedtls_md5_init
#define luat_md5_starts mbedtls_md5_starts
#define luat_md5_update mbedtls_md5_update
#define luat_md5_finalize mbedtls_md5_finish
#else
#define luat_md5_init mbedtls_md5_init
#define luat_md5_starts mbedtls_md5_starts_ret
#define luat_md5_update mbedtls_md5_update_ret
#define luat_md5_finalize mbedtls_md5_finish_ret
#endif
#endif

#define OTA_CHECK_BUFF_SIZE (64) // 超过64字节的话, luat_md5报错, 待查
typedef struct ota_md5
{
    uint8_t buff[OTA_CHECK_BUFF_SIZE];
    #ifdef LUAT_USE_CRYPTO
    mbedtls_md5_context context;
    #else
    struct md5_context context;
    #endif
    struct md5_digest digest;
}ota_md5_t;


int luat_ota_checkfile(const char* path) {
    int ret = 0;
    
    FILE * fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGE("no such file");
        return -1;
    }
    size_t binsize = luat_fs_fsize(path);
    if (binsize < 512 || binsize > 1024*1024) {
        luat_fs_fclose(fd);
        LLOGE("%s is too small/big %d", path, binsize);
        return -1;
    }
    ota_md5_t* ota = luat_heap_malloc(sizeof(ota_md5_t));
    if (ota == NULL) {
        luat_fs_fclose(fd);
        LLOGE("out of memory when check ota file md5");
        return -1;
    }
    
    size_t len = 0;
    int remain = binsize - 16;

    luat_md5_init(&ota->context);
#ifdef LUAT_USE_CRYPTO
    luat_md5_starts(&ota->context);
#endif
    while (remain > 0) {
        if (remain > OTA_CHECK_BUFF_SIZE) {
            len = luat_fs_fread(ota->buff, OTA_CHECK_BUFF_SIZE, 1, fd);
        }
        else {
            len = luat_fs_fread(ota->buff, remain, 1, fd);
        }
        //LLOGD("ota read %d byte", len);
        if (len == 0) { // 不可能的事
            break;
        }
        if (len > 512) {
            luat_heap_free(ota);
            luat_fs_fclose(fd);
            LLOGE("read file fail");
            return -1;
        }

        remain -= len;
        luat_md5_update(&ota->context, ota->buff, len);
    }
    luat_md5_finalize(&ota->context, ota->digest.bytes);
    #ifdef LUAT_USE_CRYPTO
    mbedtls_md5_free(&ota->context);
    #endif
    // 应该还有16字节的md5
    //memset(ota->buff, 0, OTA_CHECK_BUFF_SIZE);
    luat_fs_fread(ota->buff, 16, 1, fd);
    // 读完就可以关了
    luat_fs_fclose(fd);

    // 判断一下md5
    // uint8_t *expect_md5 = ota->buff + 64;
    // uint8_t *face_md5   = ota->buff + 128;

    if (!memcmp(ota->buff, ota->digest.bytes, 16)) {
        LLOGD("ota file MD5 ok");
        ret = 0;
    }
    else {
        LLOGE("ota file MD5 FAIL");
        ret = -1;
    }

    luat_heap_free(ota);
    return ret;
}


#ifdef LUAT_USE_OTA

int luat_ota(uint32_t luadb_addr){
#ifdef LUAT_USE_ZLIB 
    FILE *fd_out = NULL;
    FILE *fd_in = NULL;
    extern int zlib_decompress(FILE *source, FILE *dest);
    //检测是否有压缩升级文件
    if(luat_fs_fexist(UPDATE_TGZ_PATH)){
        LLOGI("found update.tgz, decompress ...");
        fd_in = luat_fs_fopen(UPDATE_TGZ_PATH, "r");
        if (fd_in == NULL){
            LLOGE("open the input file : %s error!", UPDATE_TGZ_PATH);
            goto _close_decompress;
        }
        luat_fs_remove(UPDATE_BIN_PATH);
        fd_out = luat_fs_fopen(UPDATE_BIN_PATH, "w+");
        if (fd_out == NULL){
            LLOGE("open the output file : %s error!", UPDATE_BIN_PATH);
            goto _close_decompress;
        }
        int ret = zlib_decompress(fd_in, fd_out);
        if (ret != 0){
            LLOGE("decompress file error!");
        }
_close_decompress:
        if(fd_in != NULL){
            luat_fs_fclose(fd_in);
        }
        if(fd_out != NULL){
            luat_fs_fclose(fd_out);
        }
        //不论成功与否都删掉避免每次启动都执行一遍
        luat_fs_remove(UPDATE_TGZ_PATH);
    }
#endif

    int ret  = -1;
    //检测是否有升级文件
    if(luat_fs_fexist(UPDATE_BIN_PATH)){
        LLOGI("found update.bin, checking");
        if (luat_ota_checkfile(UPDATE_BIN_PATH) == 0) {
            LLOGI("update.bin ok, updating... %08X", luadb_addr);
            #define UPDATE_BUFF_SIZE 4096
            uint8_t* buff = luat_heap_malloc(UPDATE_BUFF_SIZE);
            int len = 0;
            int offset = 0;
            if (buff != NULL) {
              FILE* fd = luat_fs_fopen(UPDATE_BIN_PATH, "rb");
              if (fd){
                while (1) {
                  memset(buff, 0, UPDATE_BUFF_SIZE);
                  len = luat_fs_fread(buff, sizeof(uint8_t), UPDATE_BUFF_SIZE, fd);
                  if (len < 1)
                      break;
                  luat_flash_erase(luadb_addr + offset, UPDATE_BUFF_SIZE);
                  luat_flash_write((char*)buff, luadb_addr + offset, UPDATE_BUFF_SIZE);
                  offset += len;
                }
              }else{
                ret = -1;
                LLOGW("update.bin open error");
              }
              ret = 0;
            }
        }
        else {
            ret = -1;
            LLOGW("update.bin NOT ok, skip");
        }
        luat_fs_remove(UPDATE_BIN_PATH);
    }
    return ret;
}
#endif

#endif
