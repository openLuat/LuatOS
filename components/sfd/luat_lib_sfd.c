/*
@module  sfd
@summary SPI FLASH操作库
@version 1.0
@date    2021.05.18
@tag LUAT_USE_SFD
*/
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_sfd.h"

#define LUAT_LOG_TAG "sfd"
#include "luat_log.h"

extern const sdf_opts_t sfd_w25q_opts;
extern const sdf_opts_t sfd_mem_opts;
extern const sdf_opts_t sfd_onchip_opts;

/*
初始化spi flash
@api    sfd.init(type, spi_id, spi_cs)
@string 类型, 可以是"spi", 也可以是"zbuff", 或者"onchip"
@int  SPI总线的id, 或者 zbuff实例
@int  SPI FLASH的片选脚对应的GPIO, 当类型是spi时才需要传
@return userdata 成功返回一个数据结构,否则返回nil
@usage
local drv = sfd.init("spi", 0, 17)
if drv then
    log.info("sfd", "chip id", sfd.id(drv):toHex())
end
-- 2023.01.15之后的固件支持onchip类型, 支持直接读写片上flash的一小块区域,一般是64k
-- 这块区域通常是fdb/fskv库所在的区域, 所以不要混着用
local onchip = sfd.init("onchip")
local data = sfd.read(onchip, 0x100, 256)
sfd.erase(onchip, 0x100)
sfd.write(onchip, 0x100, data or "Hi")

*/
static int l_sfd_init(lua_State *L) {

    const char* type = luaL_checkstring(L, 1);
    if (!strcmp("spi", type)) {
        
        int spi_id = luaL_checkinteger(L, 2);
        int spi_cs = luaL_checkinteger(L, 3);

        sfd_drv_t *drv = (sfd_drv_t *)lua_newuserdata(L, sizeof(sfd_drv_t));
        memset(drv, 0, sizeof(sfd_drv_t));
        drv->cfg.spi.id = spi_id;
        drv->cfg.spi.cs = spi_cs;
        drv->opts = &sfd_w25q_opts;
        drv->type = 0;

        int re = drv->opts->initialize(drv);
        if (re == 0) {
            return 1;
        }
        return 0;
    }
    if (!strcmp("zbuff", type)) {
        sfd_drv_t *drv = (sfd_drv_t *)lua_newuserdata(L, sizeof(sfd_drv_t));
        memset(drv, 0, sizeof(sfd_drv_t));
        drv->type = 1;
        drv->cfg.zbuff = luaL_checkudata(L, 2, "ZBUFF*");
        drv->opts = &sfd_mem_opts;
        drv->sector_count = drv->cfg.zbuff->len / 256;

        int re = drv->opts->initialize(drv);
        if (re == 0) {
            return 1;
        }
        return 0;
    }
    if (!strcmp("onchip", type)) {
        sfd_drv_t *drv = (sfd_drv_t *)lua_newuserdata(L, sizeof(sfd_drv_t));
        memset(drv, 0, sizeof(sfd_drv_t));
        drv->type = 3;
        drv->opts = &sfd_onchip_opts;
        int re = drv->opts->initialize(drv);
        if (re == 0) {
            return 1;
        }
        return 0;
    }
    return 0;
}

/*
检查spi flash状态
@api    sfd.status(drv)
@userdata  sfd.init返回的数据结构
@return int 状态值, 0 未初始化成功,1初始化成功且空闲,2正忙
@usage
local drv = sfd.init("spi", 0, 17)
if drv then
    log.info("sfd", "status", sfd.status(drv))
end
*/
static int l_sfd_status(lua_State *L) {
    sfd_drv_t *drv = (sfd_drv_t *) lua_touserdata(L, 1);
    lua_pushinteger(L, drv->opts->status(drv));
    return 1;
}

/*
读取数据
@api    sfd.read(drv, offset, len)
@userdata  sfd.init返回的数据结构
@int    起始偏移量
@int    读取长度,当前限制在256以内
@return string 数据
@usage
local drv = sfd.init("spi", 0, 17)
if drv then
    log.info("sfd", "read", sfd.read(drv, 0x100, 256))
end
*/
static int l_sfd_read(lua_State *L) {
    sfd_drv_t *drv = (sfd_drv_t *) lua_touserdata(L, 1);
    size_t offset = luaL_checkinteger(L, 2);
    size_t len = luaL_checkinteger(L, 3);
    luaL_Buffer buff;
    luaL_buffinitsize(L, &buff, len);
    drv->opts->read(drv, buff.b, offset, len);
    luaL_pushresult(&buff);
    return 1;
}

/*
写入数据
@api    sfd.write(drv, offset, data)
@userdata  sfd.init返回的数据结构
@int    起始偏移量
@string    需要写入的数据,当前支持256字节及以下
@return boolean 成功返回true,失败返回false
@usage
local drv = sfd.init("spi", 0, 17)
if drv then
    log.info("sfd", "write", sfd.write(drv, 0x100, "hi,luatos"))
end
*/
static int l_sfd_write(lua_State *L) {
    sfd_drv_t *drv = (sfd_drv_t *) lua_touserdata(L, 1);
    size_t offset = luaL_checkinteger(L,2);
    size_t len = 0;
    const char* buff = luaL_checklstring(L, 3, &len);
    int re = drv->opts->write(drv, buff, offset, len);
    lua_pushboolean(L, re == 0 ? 1 : 0);
    return 1;
}

/*
擦除数据
@api    sfd.erase(drv, offset)
@userdata  sfd.init返回的数据结构
@int    起始偏移量
@return boolean 成功返回true,失败返回false
@usage
local drv = sfd.init("spi", 0, 17)
if drv then
    log.info("sfd", "write", sfd.erase(drv, 0x100))
end
*/
static int l_sfd_erase(lua_State *L) {
    sfd_drv_t *drv = (sfd_drv_t *) lua_touserdata(L, 1);
    size_t offset = luaL_checkinteger(L, 2);
    size_t len = luaL_optinteger(L, 3, 4096);
    int re = drv->opts->erase(drv, offset, len);
    lua_pushboolean(L, re == 0 ? 1 : 0);
    return 1;
}

static int l_sfd_ioctl(lua_State *L) {
    return 0;
}

/*
芯片唯一id
@api    sfd.id(drv)
@userdata  sfd.init返回的数据结构
@return string 8字节(64bit)的芯片id
@usage
local drv = sfd.init("spi", 0, 17)
if drv then
    log.info("sfd", "chip id", sfd.id(drv))
end
*/
static int l_sfd_id(lua_State *L) {
    sfd_drv_t *drv = (sfd_drv_t *) lua_touserdata(L, 1);
    lua_pushlstring(L, drv->chip_id, 8);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_sfd[] =
{
    { "init" ,             ROREG_FUNC(l_sfd_init)},
    { "status",            ROREG_FUNC(l_sfd_status)},
    { "read",              ROREG_FUNC(l_sfd_read)},
    { "write",             ROREG_FUNC(l_sfd_write)},
    { "erase",             ROREG_FUNC(l_sfd_erase)},
    { "ioctl",             ROREG_FUNC(l_sfd_ioctl)},
    { "id",                ROREG_FUNC(l_sfd_id)},
    { NULL,                ROREG_INT(0)}
};

LUAMOD_API int luaopen_sfd( lua_State *L ) {
    luat_newlib2(L, reg_sfd);
    return 1;
}
