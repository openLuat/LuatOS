#ifndef LUAT_LUADB2_T
#define LUAT_LUADB2_T 1

#include "luat_base.h"
#include "luat_luadb.h"

typedef struct luat_luadb2_ctx {
    luadb_fs_t* fs;
    char* dataptr;
    size_t offset;
    size_t size;
}luat_luadb2_ctx_t;

// 初始化上下文
int luat_luadb2_init(luat_luadb2_ctx_t* ctx);

// 写入数据, 就是添加一个文件
int luat_luadb2_write(luat_luadb2_ctx_t* ctx, const char* key, const char* data, size_t len);

// 读取数据, 就是删除一个文件
int luat_luadb2_read(luat_luadb2_ctx_t* ctx, const char* key, char* data, size_t* len);



#endif
