
/*
@module  sqlite3
@summary sqlite3数据库操作
@version 1.0
@date    2023.11.13
@demo    sqlite3
@tag LUAT_USE_SQLITE3
@usage
-- 注意, 本库仍处于开发阶段, 大部分BSP尚不支持本库
-- 本移植基于 sqlite3 3.44.0
sys.taskInit(function()
    sys.wait(1000)
    local db = sqlite3.open("/ram/test.db")
    log.info("sqlite3", db)
    if db then
        sqlite3.exec(db, "CREATE TABLE devs(ID INT PRIMARY KEY NOT NULL, name CHAR(50));")
        sqlite3.exec(db, "insert into devs values(1, \"ABC\");")
        sqlite3.exec(db, "insert into devs values(2, \"DEF\");")
        sqlite3.exec(db, "insert into devs values(3, \"HIJ\");")
        local ret, data = sqlite3.exec(db, "select * from devs;")
        log.info("查询结果", ret, data)
        if ret then
            for k, v in pairs(data) do
                log.info("数据", json.encode(v))
            end
        end
        sqlite3.close(db)
    end
end)
*/

#include "luat_base.h"
#include "sqlite3.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "sqlite3"
#include "luat_log.h"

/*
打开数据库
@api sqlite3.open(path)
@string 数据库文件路径,必须填写,不存在就会自动新建
@return userdata 数据库指针,是否就返回nil
@usage
local db = sqlite3.open("/test.db")
if db then
   -- 数据库操作xxxx

    -- 用完必须关掉
    sqlite3.close(db)
end
*/
static int l_sqlite3_open(lua_State *L) {
    sqlite3 *db;
    int rc;
    const char* path = luaL_checkstring(L, 1);
    rc = sqlite3_open(path, &db);
    if (rc == SQLITE_OK) {
        lua_pushlightuserdata(L, db);
        return 1;
    }
    LLOGW("打开数据库失败 %d %s", rc, sqlite3_errstr(rc));
    return 0;
}

static int s_cb(void* args, int nc, char* azResults[], char* azColumns[]) {
    lua_State *L = (lua_State*)args;
    lua_createtable(L, 0, nc);
    size_t count = nc > 0 ? nc : 0;
    for (size_t i = 0; i < count; i++)
    {
        lua_pushstring(L, azResults[i]);
        lua_setfield(L, -2, azColumns[i]);
    }
    lua_seti(L, -2, lua_rawlen(L, -2) + 1);
    return 0;
}

/*
执行SQL语句
@api sqlite3.exec(db, sql)
@userdata 通过sqlite3.open获取到的数据库指针
@string SQL字符串,必须填写
@return boolean 成功返回true,否则返回nil
@return table 成功返回查询结果(若有),否则返回报错的字符串
*/
static int l_sqlite3_exec(lua_State *L) {
    sqlite3 *db;
    int rc;
    char* errmsg;
    db = lua_touserdata(L, 1);
    if (db == NULL) {
        return 0;
    }
    const char* sql = luaL_checkstring(L, 2);
    lua_newtable(L);
    rc = sqlite3_exec(db, sql, s_cb, L, &errmsg);
    if (rc == SQLITE_OK) {
        lua_pushboolean(L, 1);
        lua_pushvalue(L, -2);
        return 2;
    }
    lua_pushnil(L);
    lua_pushstring(L, errmsg);
    //LLOGW("执行SQL失败 %s %d %s", sql, rc, errmsg);
    return 2;
}

/*
关闭数据库
@api sqlite3.close(db)
@userdata 通过sqlite3.open获取到的数据库指针
@return boolean 成功返回true,否则返回nil
*/
static int l_sqlite3_close(lua_State *L) {
    sqlite3 *db;
    int rc;
    db = lua_touserdata(L, 1);
    if (db == NULL) {
        return 0;
    }
    rc = sqlite3_close(db);
    if (rc == SQLITE_OK) {
        lua_pushboolean(L, 1);
        return 0;
    }
    LLOGW("关闭数据库失败 %d", rc);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_sqlite3[] =
{
    { "open" ,            ROREG_FUNC(l_sqlite3_open)},
    { "exec" ,            ROREG_FUNC(l_sqlite3_exec)},
    { "close" ,           ROREG_FUNC(l_sqlite3_close)},
	{ NULL,               ROREG_INT(0)}
};

extern int luat_sqlite3_init(void);

LUAMOD_API int luaopen_sqlite3( lua_State *L ) {
    luat_newlib2(L, reg_sqlite3);
    luat_sqlite3_init();
    return 1;
}


/*
对sqlite3源码的修改说明
主体没有做任何变动,只在头部添加了以下宏定义

#define SQLITE_OMIT_WAL 1
#define SQLITE_THREADSAFE 0
#define SQLITE_DEFAULT_MEMSTATUS 0
#define SQLITE_OMIT_LOAD_EXTENSION 1
#define SQLITE_OMIT_LOCALTIME 1
#define SQLITE_OMIT_MEMORYDB 1
#define SQLITE_OMIT_SHARED_CACHE
#define SQLITE_OS_OTHER 1
#define SQLITE_OMIT_SEH

对sqlite3的最大限制是内存占用, 栈内存据说需要12k以上, 堆内存需要100~200k, 尚无实际验证
*/
