
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "luat.bin"
#include "luat_log.h"

// TLV结构 Tag-Len-Value
typedef struct luat_bin_tlv
{
    uint16_t tag;   // 类型
    uint16_t revert;// 保留字段
    uint32_t len;   // 数据长度
}luat_bin_tlv_t;

// 缓冲区
typedef struct luat_bin_buff
{
    FILE* fd;
    size_t offset;
    size_t size;
    char data[4096 + 64];
}luat_bin_buff_t;

// 填充缓冲区
static int fill_buff(luat_bin_buff_t* binbuff) {
    size_t remain = binbuff->size - binbuff->offset;
    if (remain > 64) {
        return 0;
    }
    if (remain > 0 && remain < 64) {
        memcpy(binbuff->data, binbuff->data + binbuff->offset, remain);
    }
    binbuff->size = luat_fs_fread(binbuff->data + remain, 1, 4096, binbuff->fd) + remain;
    binbuff->offset = 0;
    return 0;
}

// 解包bin文件
int luat_bin_unpack(const char* binpath, int writeOut) {
    FILE* fd = NULL; // 文件句柄
    luat_bin_buff_t * binbuff = NULL; // 缓冲区
    int ret = -1; // 返回值
    luat_bin_tlv_t* tlv = NULL; // TLV结构
    char path[64] = {0}; // 路径

    size_t fsize = luat_fs_fsize(binpath);
    LLOGI("unpack path=%s size=%d", binpath, fsize);

    fd = luat_fs_fopen(binpath, "rb");
    if (!fd) {
        LLOGI("open %s fail ret=%d", binpath, ret);
        goto _exit;
    }
    // 预先分配好内存给缓冲区
    binbuff = luat_heap_malloc(sizeof(luat_bin_buff_t));
    if (binbuff == NULL) {
        LLOGI("luat_heap_malloc FAIL!!");
        goto _exit;
    }
    // 初始化好
    memset(binbuff, 0, sizeof(luat_bin_buff_t));
    binbuff->fd = fd;
    // 第一次填充
    fill_buff(binbuff);

    // 连TLV都不够,肯定是非法文件,拒绝
    if (binbuff->size < sizeof(luat_bin_tlv_t)) {
        LLOGI("file is too small! size=%d", binbuff->size);
        ret = -1;
        goto _exit;
    }

    // 检查头部的TLV,必须是 {0x12, 0x34, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}
    tlv = (luat_bin_tlv_t*)(binbuff->data);
    if (tlv->tag != 0x1234 || tlv->len != 0) {
        LLOGW("bad header, reject update!! tlv->tag=%04X tlv->len=%d", tlv->tag, tlv->len);
        ret = -1;
        goto _exit;
    }
    // 跳过头部
    binbuff->offset += sizeof(luat_bin_tlv_t);
    
    size_t wsize = 0;

    // 开始解析主体
    while (1) {
        // 再次填充
        fill_buff(binbuff);
        // 填充完还有没有数据呢?
        if (binbuff->size - binbuff->offset == 0) {
            // 没有数据了, 退出
            LLOGI("unpack reach EOF");
            break;
        }
        // 剩余数据会不会太少
        if (binbuff->size - binbuff->offset < sizeof(luat_bin_tlv_t)) {
            // 太少了, 肯定是非法文件
            LLOGI("only remain %d byte, less than luat_bin_tlv_t", binbuff->size - binbuff->offset);
            ret = -3;
            goto _exit;
        }
        // TLV结构指向buff
        tlv = (luat_bin_tlv_t*)(binbuff->data + binbuff->offset);
        binbuff->offset += sizeof(luat_bin_tlv_t);
        // 逐一判断TAG值

        LLOGI("tlv->tag=0x%04X tlv-len=%d", tlv->tag, tlv->len);

        // 文件名
        if (tlv->tag == 0x0101) { // 读到文件名
            if (tlv->len == 0 || tlv->len > 63) {
                // 文件名必须小于64字节!!
                LLOGE("bad bin format, FileName invaild!!!");
                ret = -5;
                goto _exit;
            }
            // 剩余缓冲区够不够, 不够就读取一下
            if (tlv->len > binbuff->size - binbuff->offset) {
                fill_buff(binbuff);
                if (tlv->len > binbuff->size - binbuff->offset) {
                    // 填充完, 依然不够, 那肯定非法了
                    LLOGW("bad bin format, FileName not Good");
                    ret = -5;
                    goto _exit;
                }
            }
            // 看来是合法了,拷贝备用
            memcpy(path, binbuff->data + binbuff->offset, tlv->len);
            path[tlv->len] = 0x00; // 确保有结束符
            LLOGD("read file name %s", path);
            binbuff->offset += tlv->len;
        }
        // 文件数据
        else if (tlv->tag == 0x0202) {
            if (path[0] == 0) {
                // 连路径都没有就出现文件数据了,肯定非法
                LLOGE("file data without path!!!!");
                ret = -6;
                goto _exit;
            }
            // 开始写入数据
            LLOGI("write path=%s len=%d", path, tlv->len);
            size_t dst_fsz = tlv->len;
            if (writeOut == 0) {
                // 仅读取文件内容,不真实写出到文件
                LLOGD("writeOut testing...");
                while (dst_fsz > 0) {
                    if (binbuff->size - binbuff->offset == 0) {
                        fill_buff(binbuff);
                        if (binbuff->size - binbuff->offset == 0) {
                            LLOGE("fill buff fail! reach EOF!!");
                            ret = -7;
                            goto _exit;
                        }
                    }
                    wsize = binbuff->size - binbuff->offset;
                    if (wsize > dst_fsz)
                        wsize = dst_fsz;
                    dst_fsz -= wsize;
                    binbuff->offset += wsize;
                }
                continue;
            }
            // 首先, 删除目标文件
            luat_fs_remove(path); // 鉴于Littlefs的特性, 先删除会比较省空间
            // 然后新建文件
            FILE* dst = luat_fs_fopen(path, "wb");
            if (!dst) {
                LLOGE("create file fail! %s", path);
                ret = -2;
                goto _exit;
            }
            while (dst_fsz > 0) {
                if (binbuff->size - binbuff->offset == 0) {
                    fill_buff(binbuff);
                    if (binbuff->size - binbuff->offset == 0) {
                        LLOGE("fill buff fail! reach EOF!!");
                        ret = -7;
                        luat_fs_fclose(dst);
                        goto _exit;
                    }
                }
                size_t wsize = binbuff->size - binbuff->offset;
                if (wsize > dst_fsz)
                    wsize = dst_fsz;
                LLOGD("write file=%s write len=%d remain len=%d", path, wsize, dst_fsz - wsize);
                luat_fs_fwrite(binbuff->data + binbuff->offset, 1, wsize, dst);
                dst_fsz -= wsize;
                binbuff->offset += wsize;
            }
            LLOGD("write ok path=%s", path);
            luat_fs_fclose(dst);
        }
        else {
            LLOGI("unknow tlv->tag=%04x tlv->len=%d", tlv->tag, tlv->len);
            if (tlv->len > 0) {
                // 跳过数据
                size_t dlen = tlv->len;
                while (dlen > 0) {
                    if (dlen > binbuff->size - binbuff->offset) {
                        dlen -= binbuff->size - binbuff->offset;
                        binbuff->offset = binbuff->size;
                        fill_buff(binbuff);
                        if (binbuff->size - binbuff->offset == 0) {
                            LLOGE("fill buff fail! reach EOF!!");
                            ret = -8;
                            goto _exit;
                        }
                    }
                    else {
                        binbuff->offset += dlen;
                        dlen = 0;
                        break;
                    }
                }
            }
        }
    }
    // 结束, 手工!!
    LLOGI("unpack success!");
    ret = 0;

_exit:

    if (fd) // 文件句柄关掉
        luat_fs_fclose(fd);
    if (binbuff) // 缓冲区释放
        luat_heap_free(binbuff);
    LLOGI("unpack ret=%d", ret);
    return ret;
}
