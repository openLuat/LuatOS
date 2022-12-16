/*
@module  sfud
@summary SPI FLASH sfud软件包
@version 1.0
@date    2021.09.23
@demo sfud
@tag LUAT_USE_SFUD
*/

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "sfud"
#include "luat_log.h"
#include "sfud.h"

luat_sfud_flash_t luat_sfud;

/*
初始化sfud
@api  sfud.init(spi_id, spi_cs, spi_bandrate)/sfud.init(spi_device)
@int  spi_id SPI的ID/userdata spi_device
@int  spi_cs SPI的片选
@int  spi_bandrate SPI的频率
@return bool 成功返回true,否则返回false
@usage
--spi
log.info("sfud.init",sfud.init(0,20,20 * 1000 * 1000))
--spi_device
local spi_device = spi.deviceSetup(0,17,0,0,8,2000000,spi.MSB,1,0)
log.info("sfud.init",sfud.init(spi_device))
*/
static int luat_sfud_init(lua_State *L){
    static luat_spi_t sfud_spi_flash;
    static luat_spi_device_t* sfud_spi_device_flash = NULL;
    if (lua_type(L, 1) == LUA_TNUMBER){
        luat_sfud.luat_spi = LUAT_TYPE_SPI;
        sfud_spi_flash.id = luaL_checkinteger(L, 1);
        sfud_spi_flash.cs = luaL_checkinteger(L, 2);
        sfud_spi_flash.bandrate = luaL_checkinteger(L, 3);
        sfud_spi_flash.CPHA = 1; // CPHA0
        sfud_spi_flash.CPOL = 1; // CPOL0
        sfud_spi_flash.dataw = 8; // 8bit
        sfud_spi_flash.bit_dict = 1; // MSB=1, LSB=0
        sfud_spi_flash.master = 1; // master=1,slave=0
        sfud_spi_flash.mode = 0; // FULL=1, half=0
        luat_spi_setup(&sfud_spi_flash);
        luat_sfud.user_data = &sfud_spi_flash;
    }else if (lua_type(L, 1) == LUA_TUSERDATA){
        luat_sfud.luat_spi = LUAT_TYPE_SPI_DEVICE;
        sfud_spi_device_flash = (luat_spi_device_t*)lua_touserdata(L, 1);
        luat_sfud.user_data = sfud_spi_device_flash;
    }
    
    int re = sfud_init();
    lua_pushboolean(L, re == 0 ? 1 : 0);
    return 1;
}

/*
获取flash设备信息表中的设备总数
@api  sfud.getDeviceNum()
@return int  返回设备总数
@usage
log.info("sfud.getDeviceNum",sfud.getDeviceNum())
*/
static int luat_sfud_get_device_num(lua_State *L){
    int re = sfud_get_device_num();
    lua_pushinteger(L, re);
    return 1;
}

/*
通过flash信息表中的索引获取flash设备
@api  sfud.getDevice(index)
@int  index flash信息表中的索引
@return userdata 成功返回一个数据结构,否则返回nil
@usage
local sfud_device = sfud.getDevice(1)
*/
static int luat_sfud_get_device(lua_State *L){
    sfud_flash *flash = sfud_get_device(luaL_checkinteger(L, 1));
    lua_pushlightuserdata(L, flash);
    return 1;
}

/*
获取flash设备信息表
@api  sfud.getDeviceTable()
@return userdata 成功返回一个数据结构,否则返回nil
@usage
local sfud_device = sfud.getDeviceTable()
*/
static int luat_sfud_get_device_table(lua_State *L){
    const sfud_flash *flash = sfud_get_device_table();
    lua_pushlightuserdata(L, flash);
    return 1;
}

/*
擦除 Flash 全部数据
@api  sfud.chipErase(flash)
@userdata flash Flash 设备对象 sfud.get_device_table()返回的数据结构
@return int 成功返回0
@usage
sfud.chipErase(flash)
*/
static int luat_sfud_chip_erase(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    sfud_err re = sfud_chip_erase(flash);
    lua_pushinteger(L, re);
    return 1;
}

/*
擦除 Flash 指定地址指定大小
@api  sfud.erase(flash,add,size)
@userdata flash Flash 设备对象 sfud.get_device_table()返回的数据结构
@number add 擦除地址
@number size 擦除大小
@return int 成功返回0
@usage
sfud.erase(flash,add,size)
*/
static int luat_sfud_erase(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = luaL_checkinteger(L, 3);
    sfud_err re = sfud_erase(flash,addr,size);
    lua_pushinteger(L, re);
    return 1;
}

/*
读取 Flash 数据
@api  sfud.read(flash, addr, size)
@userdata flash Flash 设备对象 sfud.get_device_table()返回的数据结构
@int addr 起始地址
@int size 从起始地址开始读取数据的总大小
@return string data 读取到的数据
@usage
log.info("sfud.read",sfud.read(sfud_device,1024,4))
*/
static int luat_sfud_read(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = luaL_checkinteger(L, 3);
    uint8_t* data = (uint8_t*)luat_heap_malloc(size);
    sfud_err re = sfud_read(flash, addr, size, data);
    if(re != SFUD_SUCCESS){
        size = 0;
        LLOGD("sfud_read re %d", re);
    }
    lua_pushlstring(L, (const char*)data, size);
    luat_heap_free(data);
    return 1;
}
    
/*
向 Flash 写数据
@api  sfud.write(flash, addr,data)
@userdata flash Flash 设备对象 sfud.get_device_table()返回的数据结构
@int addr 起始地址
@string data 待写入的数据
@return int 成功返回0
@usage
log.info("sfud.write",sfud.write(sfud_device,1024,"sfud"))
*/
static int luat_sfud_write(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = 0;
    const char* data = luaL_checklstring(L, 3, &size);
    sfud_err re = sfud_write(flash, addr, size, (const uint8_t*)data);
    lua_pushinteger(L, re);
    return 1;
}

/*
先擦除再往 Flash 写数据
@api  sfud.eraseWrite(flash, addr,data)
@userdata flash Flash 设备对象 sfud.get_device_table()返回的数据结构
@int addr 起始地址
@string data 待写入的数据
@return int 成功返回0
@usage
log.info("sfud.eraseWrite",sfud.eraseWrite(sfud_device,1024,"sfud"))
*/
static int luat_sfud_erase_write(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = 0;
    const char* data = luaL_checklstring(L, 3, &size);
    sfud_err re = sfud_erase_write(flash, addr, size, (const uint8_t*)data);
    lua_pushinteger(L, re);
    return 1;
}

#ifdef LUAT_USE_FS_VFS
#include "luat_fs.h"
#include "lfs.h"
extern lfs_t* flash_lfs_sfud(sfud_flash* flash, size_t offset, size_t maxsize);

/*
挂载sfud lfs文件系统
@api  sfud.mount(flash, mount_point, offset, maxsize)
@userdata flash Flash 设备对象 sfud.get_device_table()返回的数据结构
@string mount_point 挂载目录名
@int    起始偏移量,默认0
@int    总大小, 默认是整个flash
@return bool 成功返回true
@usage
log.info("sfud.mount",sfud.mount(sfud_device,"/sfud"))
log.info("fsstat", fs.fsstat("/"))
log.info("fsstat", fs.fsstat("/sfud"))
*/
static int luat_sfud_mount(lua_State *L) {
    const sfud_flash *flash = lua_touserdata(L, 1);
    const char* mount_point = luaL_checkstring(L, 2);
    size_t offset = luaL_optinteger(L, 3, 0);
    size_t maxsize = luaL_optinteger(L, 4, 0);
    lfs_t* lfs = flash_lfs_sfud(flash, offset, maxsize);
    if (lfs) {
	    luat_fs_conf_t conf = {
		    .busname = (char*)lfs,
		    .type = "lfs2",
		    .filesystem = "lfs2",
		    .mount_point = mount_point,
	    };
	    int ret = luat_fs_mount(&conf);
        LLOGD("vfs mount %s ret %d", mount_point, ret);
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}
#endif

#include "rotable2.h"
static const rotable_Reg_t reg_sfud[] =
{
    { "init",           ROREG_FUNC(luat_sfud_init)},
    { "getDeviceNum",   ROREG_FUNC(luat_sfud_get_device_num)},
    { "getDevice",      ROREG_FUNC(luat_sfud_get_device)},
    { "getDeviceTable", ROREG_FUNC(luat_sfud_get_device_table)},
    { "erase",          ROREG_FUNC(luat_sfud_erase)},
    { "chipErase",      ROREG_FUNC(luat_sfud_chip_erase)},
    { "read",           ROREG_FUNC(luat_sfud_read)},
    { "write",          ROREG_FUNC(luat_sfud_write)},
    { "eraseWrite",     ROREG_FUNC(luat_sfud_erase_write)},
#ifdef LUAT_USE_FS_VFS
    { "mount",          ROREG_FUNC(luat_sfud_mount)},
#endif
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_sfud( lua_State *L ) {
    luat_newlib2(L, reg_sfud);
    return 1;
}
