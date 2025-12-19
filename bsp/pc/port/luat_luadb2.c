/*
本文件用于管理luadb的数据
*/

#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_luadb2.h"

#include <stdlib.h>
#include <string.h>//add for memset

#define LUAT_LOG_TAG "luadb2"
#include "luat_log.h"

// 初始化上下文
int luat_luadb2_init(luat_luadb2_ctx_t* ctx) {
    if (ctx->dataptr) {
        return 0;
    }
    ctx->dataptr = malloc(1024);
    ctx->size = 1024;
    ctx->offset = 0;
	char *tmp = ctx->dataptr;
	size_t offset = 0;
	// magic of luadb
	tmp[offset + 0] = 0x01;
	tmp[offset + 1] = 0x04;
	tmp[offset + 2] = 0x5A;
	tmp[offset + 3] = 0xA5;
	tmp[offset + 4] = 0x5A;
	tmp[offset + 5] = 0xA5;
	offset += 6;

	// version 0x00 0x02
	tmp[offset + 0] = 0x02;
	tmp[offset + 1] = 0x02;
	tmp[offset + 2] = 0x02;
	tmp[offset + 3] = 0x00;
	offset += 4;

	// headers total size
	tmp[offset + 0] = 0x03;
	tmp[offset + 1] = 0x04;
	tmp[offset + 2] = 0x00;
	tmp[offset + 3] = 0x00;
	tmp[offset + 4] = 0x00;
	tmp[offset + 5] = 0x18;
	offset += 6;

	// file count
	tmp[offset + 0] = 0x04;
	tmp[offset + 1] = 0x02;
	tmp[offset + 2] = 0x00;
	tmp[offset + 3] = 0x00;
	offset += 4;

	// crc
	tmp[offset + 0] = 0xFE;
	tmp[offset + 1] = 0x02;
	tmp[offset + 2] = 0x00;
	tmp[offset + 3] = 0x00;
	offset += 4;

    ctx->offset = offset;
    // LLOGD("初始化luadb2成功, 当前偏移量 %d", ctx->offset);
    return 0;
}

// 写入数据, 就是添加一个文件
int luat_luadb2_write(luat_luadb2_ctx_t* ctx, const char* name, const char* data, size_t len) {
    if (!ctx->dataptr) {
        LLOGE("需要先初始化才能写入数据");
        return -1;
    }
    size_t offset = ctx->offset;
	char *tmp = realloc(ctx->dataptr, offset + len + 512);
	if (tmp == NULL)
	{
        LLOGE("内存不足, 无法新增文件");
		return -2;
	}

	// magic of file
	tmp[offset + 0] = 0x01;
	tmp[offset + 1] = 0x04;
	tmp[offset + 2] = 0x5A;
	tmp[offset + 3] = 0xA5;
	tmp[offset + 4] = 0x5A;
	tmp[offset + 5] = 0xA5;
	offset += 6;

	// name of file
	tmp[offset + 0] = 0x02;
	tmp[offset + 1] = (uint8_t)(strlen(name) & 0xFF);
	memcpy(tmp + offset + 2, name, strlen(name));
	offset += 2 + strlen(name);

	// len of file data
	tmp[offset + 0] = 0x03;
	tmp[offset + 1] = 0x04;
	tmp[offset + 2] = (len >> 0) & 0xFF;
	tmp[offset + 3] = (len >> 8) & 0xFF;
	tmp[offset + 4] = (len >> 16) & 0xFF;
	tmp[offset + 5] = (len >> 24) & 0xFF;
	offset += 6;

	// crc
	tmp[offset + 0] = 0xFE;
	tmp[offset + 1] = 0x02;
	tmp[offset + 2] = 0x00;
	tmp[offset + 3] = 0x00;
	offset += 4;

	memcpy(tmp + offset, data, len);

	offset += len;

	ctx->offset = offset;
	ctx->dataptr = tmp;

	// 调整文件数量, TODO 兼容256个以上的文件
	ctx->dataptr[0x12]++;

    // LLOGD("新增文件完成 文件名 %s, len=%d", name, len);
    // LLOGD("文件总数 %d", ctx->dataptr[0x12]);
    // LLOGD("指针偏移量 %d", ctx->offset);

	return 0;
}

// 读取数据, 就是删除一个文件
int luat_luadb2_read(luat_luadb2_ctx_t* ctx, const char* key, char* data, size_t* len);

