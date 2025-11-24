#ifndef LUAT_LUF_H
#define LUAT_LUF_H

#include "luat_base.h"
#include "luat_luac_report.h"

// 定义一下luf的存储结构

typedef struct luf_file {
    uint8_t magic[4];
    uint32_t version;
    uint32_t size;
    uint32_t crc;
}luf_file_t;

typedef struct luf_func_head {
    lu_byte magic;
    lu_byte numparams;  /* number of fixed parameters */
    lu_byte is_vararg;
    lu_byte maxstacksize;  /* number of registers needed by this function */
    uint32_t size;    // 总大小,包含头部
    uint32_t offset;  // 偏移,相对于luf_file_t的起始位置
    uint32_t sizecode; // 代码指令
    uint32_t sizep;  /* size of 'p' 子函数数量 */
    uint32_t sizek;  /* size of 'k' 常量表 */
    uint32_t sizeupvalues;  /* size of 'upvalues' */
    uint32_t sizeupvalues2;  /* size of 'upvalues'的名称信息 */
    uint32_t sizelineinfo; // 行号数据
    uint32_t sizelocvars;   // 局部变量信息和名称信息
    uint32_t linedefined;  /* debug information  */
    uint32_t lastlinedefined;  /* debug information  */

    // 后续存放的内容:
    // 1. code指令, 实际长度为 sizecode * 4 字节
    // 2. 子函数数量id索引     sizep * 4 字节
    // 3. k 常量表            sizek * 4 字节
    // 4. upvalues           sizeupvalues * 2 字节
    // 5. upvalues的名称信息  sizeupvalues2 * 4 字节
    // 6. 行号数据            sizelineinfo * 4 字节
    // 7. 局部变量信息         sizelocvars * 8 字节
    // 8. 局部变量的名称信息   sizelocvars * 4 字节

    // 所以总长度等于
    // sizecode * 4 + sizep * 4 + sizek * 4 + sizeupvalues * 2 + sizeupvalues2 * 4 + sizelineinfo * 4 + sizelocvars * 8 + sizelocvars * 4
}luf_func_head_t;

void luat_luf_toluac(luac_file_t *cf);
void luac_to_luf(luac_file_t *cfs, size_t count, luac_report_t *rpt);

#endif
