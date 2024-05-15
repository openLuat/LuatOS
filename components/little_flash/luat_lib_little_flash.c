/*
@module  little_flash
@summary LITTLE FLASH 软件包
@version 1.0
@date    2024.05.11
@demo little_flash
@tag LUAT_USE_LITTLE_FLASH
*/

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"
#include "little_flash.h"

/*
初始化 little_flash
@api  lf.init(spi_device)
@int  userdata spi_device
@return userdata 成功返回一个数据结构,否则返回nil
@usage
--spi_device
spi_device = spi.deviceSetup(0,17,0,0,8,2000000,spi.MSB,1,0)
log.info("lf.init",lf.init(spi_device))
*/
static int luat_little_flash_init(lua_State *L){
    luat_spi_device_t* little_flash_spi_device = NULL;
    little_flash_t* lf_flash = NULL;
    if (lua_type(L, 1) == LUA_TUSERDATA){
        little_flash_spi_device = (luat_spi_device_t*)lua_touserdata(L, 1);
        lf_flash = luat_heap_malloc(sizeof(little_flash_t));
        lf_flash->spi.user_data = little_flash_spi_device;
    }else{
        LLOGW("little_flash init spi_device is nil");
        return 0;
    }
    little_flash_init();
    lf_err_t re = little_flash_device_init(lf_flash);
    if (re == LF_ERR_OK){
        lua_pushlightuserdata(L, lf_flash);
        return 1;
    }
    luat_heap_free(lf_flash);
    return 0;
}

#ifdef LUAT_USE_FS_VFS
#include "luat_fs.h"
#include "lfs.h"
extern lfs_t* flash_lfs_lf(little_flash_t* flash, size_t offset, size_t maxsize);

/*
挂载 little_flash lfs文件系统
@api  lf.mount(flash, mount_point, offset, maxsize)
@userdata flash Flash 设备对象 lf.init()返回的数据结构
@string mount_point 挂载目录名
@int    起始偏移量,默认0
@int    总大小, 默认是整个flash
@return bool 成功返回true
@usage
log.info("lf.mount",lf.mount(little_flash_device,"/little_flash"))
*/
static int luat_little_flash_mount(lua_State *L) {
    little_flash_t *flash = lua_touserdata(L, 1);
    if (flash == NULL) {
        LLOGE("little_flash mount flash is nil");
        return 0;
    }
    const char* mount_point = luaL_checkstring(L, 2);
    size_t offset = luaL_optinteger(L, 3, 0);
    size_t maxsize = luaL_optinteger(L, 4, 0);
    lfs_t* lfs = flash_lfs_lf(flash, offset, maxsize);
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
static const rotable_Reg_t reg_little_flash[] =
{
    { "init",           ROREG_FUNC(luat_little_flash_init)},
#ifdef LUAT_USE_FS_VFS
    { "mount",          ROREG_FUNC(luat_little_flash_mount)},
#endif
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_little_flash( lua_State *L ) {
    luat_newlib2(L, reg_little_flash);
    return 1;
}
