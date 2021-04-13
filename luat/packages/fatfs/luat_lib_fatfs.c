
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "lauxlib.h"

#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */

#define LUAT_LOG_TAG "luat.fatfs"
#include "luat_log.h"

static FATFS fs;		/* FatFs work area needed for each volume */
extern BYTE FATFS_DEBUG; // debug log, 0 -- disable , 1 -- enable
extern BYTE FATFS_SPI_ID; // 0 -- SPI_1, 1 -- SPI_2
extern BYTE FATFS_SPI_CS; // GPIO 3

static int fatfs_mount(lua_State *L)
{
    //int spiId = luaL_checkinteger(L, 1);    
    //int result = platform_spi_close(spiId);
	//if (FATFS_DEBUG)
	//	LLOGD("fatfs_init>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\r\n");

	//DWORD fre_clust, fre_sect, tot_sect;
	// 挂载点
	const char *mount_point = luaL_optstring(L, 1, "");
	FATFS_SPI_ID = luaL_optinteger(L, 2, 0); // SPI_1
	FATFS_SPI_CS = luaL_optinteger(L, 3, 3); // GPIO_3

	DRESULT re = f_mount(&fs, mount_point, 0);
	
	lua_pushinteger(L, re);
	if (re == FR_OK) {
		if (FATFS_DEBUG)
			LLOGD("[FatFS]fatfs_init success\r\n");
	}
	else {
		if (FATFS_DEBUG)
			LLOGD("[FatFS]fatfs_init FAIL!! re=%d\r\n", re);
	}

	//if (FATFS_DEBUG)
	//	LLOGD("fatfs_init<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\r\n");
    return 1;
}

static int fatfs_unmount(lua_State *L) {
	const char *mount_point = luaL_optstring(L, 1, "");
	FRESULT re = f_unmount(mount_point);
	lua_pushinteger(L, re);
	return 1;
}

static int fatfs_mkfs(lua_State *L) {
	const char *mount_point = luaL_optstring(L, 1, "");
	BYTE sfd = luaL_optinteger(L, 2, 0);
	DWORD au = luaL_optinteger(L, 3, 0);
	BYTE work[FF_MAX_SS];
	FRESULT re = f_mkfs(mount_point, sfd, au, work, sizeof work);
	lua_pushinteger(L, re);
	return 1;
}

static int fatfs_getfree(lua_State *L)
{
	DWORD fre_clust, fre_sect, tot_sect;
	// 挂载点
	const char *mount_point = luaL_optstring(L, 1, "");
	FATFS *fs2;
	DRESULT re2 = f_getfree(mount_point, &fre_clust, &fs2);
	if (re2) {
		lua_pushnil(L);
		lua_pushinteger(L, re2);
		return 2;
	}
	/* Get total sectors and free sectors */
    tot_sect = (fs2->n_fatent - 2) * fs2->csize;
    fre_sect = fre_clust * fs2->csize;
	lua_newtable(L);

	lua_pushstring(L, "total_sectors");
	lua_pushinteger(L, tot_sect);
	lua_settable(L, -3);

	lua_pushstring(L, "free_sectors");
	lua_pushinteger(L, fre_sect);
	lua_settable(L, -3);

	lua_pushstring(L, "total_kb");
	lua_pushinteger(L, tot_sect / 2);
	lua_settable(L, -3);

	lua_pushstring(L, "free_kb");
	lua_pushinteger(L, fre_sect / 2);
	lua_settable(L, -3);
	
	return lua_gettop(L);
}

// ------------------------------------------------
// ------------------------------------------------

static int fatfs_mkdir(lua_State *L) {
	int luaType = lua_type( L, 1);
	if(luaType != LUA_TSTRING) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "file path must string");
		return 2;
	}
	FRESULT re = f_mkdir(lua_tostring(L, 1));
	lua_pushinteger(L, re);
	return 1;
}

static int fatfs_lsdir(lua_State *L)
{
	//FIL Fil;			/* File object needed for each open file */
	DIR dir;
	FILINFO fileinfo;
	int luaType = lua_type( L, 1);
	if(luaType != LUA_TSTRING) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "dir must string");
		return 2;
	}
	//u8 *buf;
	int len;
	const char *buf = lua_tolstring( L, 1, &len );
	char dirname[len+1];
	memcpy(dirname, buf, len);
	dirname[len] = 0x00;
	DRESULT re = f_opendir(&dir, dirname);
	if (re != FR_OK) {
		lua_pushinteger(L, re);
		return 1;
	}

	lua_pushinteger(L, 0);
	lua_newtable(L);
	while(f_readdir(&dir, &fileinfo) == FR_OK) {
		if(!fileinfo.fname[0]) break;

		lua_pushlstring(L, fileinfo.fname, strlen(fileinfo.fname));
		lua_newtable(L);
		
		lua_pushstring(L, "size");
		lua_pushinteger(L, fileinfo.fsize);
		lua_settable(L, -3);
		
		lua_pushstring(L, "date");
		lua_pushinteger(L, fileinfo.fdate);
		lua_settable(L, -3);
		
		lua_pushstring(L, "time");
		lua_pushinteger(L, fileinfo.ftime);
		lua_settable(L, -3);
		
		lua_pushstring(L, "attrib");
		lua_pushinteger(L, fileinfo.fattrib);
		lua_settable(L, -3);

		lua_pushstring(L, "isdir");
		lua_pushinteger(L, fileinfo.fattrib & AM_DIR);
		lua_settable(L, -3);

		lua_settable(L, -3);
	}
	f_closedir(&dir);
	LLOGD("[FatFS] lua_gettop=%d\r\n", lua_gettop(L));
    return 2;
}

//-------------------------------------------------------------

static int fatfs_stat(lua_State *L) {
	int luaType = lua_type(L, 1);
	if(luaType != LUA_TSTRING) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "file path must string");
		return 2;
	}
	FILINFO fileinfo;
	const char *path = lua_tostring(L, 1);
	FRESULT re = f_stat(path, &fileinfo);
	lua_pushinteger(L, re);
	if (re == FR_OK) {
		lua_newtable(L);
		
		lua_pushstring(L, "size");
		lua_pushinteger(L, fileinfo.fsize);
		lua_rawset(L, -3);
		
		lua_pushstring(L, "date");
		lua_pushinteger(L, fileinfo.fdate);
		lua_rawset(L, -3);
		
		lua_pushstring(L, "time");
		lua_pushinteger(L, fileinfo.ftime);
		lua_rawset(L, -3);
		
		lua_pushstring(L, "attrib");
		lua_pushinteger(L, fileinfo.fattrib);
		lua_rawset(L, -3);

		lua_pushstring(L, "isdir");
		lua_pushinteger(L, fileinfo.fattrib & AM_DIR);
		lua_rawset(L, -3);
	}
	else {
		lua_pushnil(L);
	}
	return 2;
}

/**
 * fatfs.open("adc.txt") 
 * fatfs.open("adc.txt", 2) 
 */
static int fatfs_open(lua_State *L) {
	int luaType = lua_type( L, 1);
	if(luaType != LUA_TSTRING) {
		lua_pushnil(L);
		lua_pushinteger(L, -1);
		lua_pushstring(L, "file path must string");
		return 3;
	}
	const char *path  = lua_tostring(L, 1);

	FIL* fil = (FIL*)lua_newuserdata(L, sizeof(FIL));
	int flag = luaL_optinteger(L, 2, 1); // 第二个参数
	flag |= luaL_optinteger(L, 3, 0); // 第三个参数
	flag |= luaL_optinteger(L, 4, 0); // 第四个参数

	if (FATFS_DEBUG)
		LLOGD("[FatFS]open %s %0X\r\n", path, flag);
	DRESULT re = f_open(fil, path, (BYTE)flag);
	if (re != FR_OK) {
		lua_remove(L, -1);
		lua_pushnil(L);
		lua_pushinteger(L, re);
		return 2;
	}
	return 1;
}

static int fatfs_close(lua_State *L) {
	int luaType = lua_type(L, 1);
	if(luaType != LUA_TUSERDATA) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "must be FIL*");
		return 2;
	}
	FIL* fil = (FIL*)lua_touserdata(L, 1);
	FRESULT re = f_close(fil);
	//free(fil);
	lua_pushinteger(L, re);
	return 1;
}

static int fatfs_seek(lua_State *L) {
	int luaType = lua_type( L, 1);
	if(luaType != LUA_TUSERDATA) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "must be FIL*");
		return 2;
	}
	UINT seek = luaL_optinteger(L, 2, 0);
	FRESULT re = f_lseek((FIL*)lua_touserdata(L, 1), seek);
	lua_pushinteger(L, re);
	return 1;
}

static int fatfs_truncate(lua_State *L) {
	int luaType = lua_type( L, 1);
	if(luaType != LUA_TUSERDATA) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "must be FIL*");
		return 2;
	}
	FRESULT re = f_truncate((FIL*)lua_touserdata(L, 1));
	lua_pushinteger(L, re);
	return 1;
}

static int fatfs_read(lua_State *L) {
	int luaType = lua_type( L, 1);
	if(luaType != LUA_TUSERDATA) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "must be FIL*");
		return 2;
	}
	UINT limit = luaL_optinteger(L, 2, 512);
	u8 buf[limit];
	UINT len;
	if (FATFS_DEBUG)
		LLOGD("[FatFS]readfile limit=%d\r\n", limit);
	FRESULT re = f_read((FIL*)lua_touserdata(L, 1), buf, limit, &len);
	lua_pushinteger(L, re);
	if (re != FR_OK) {
		return 1;
	}
	lua_pushlstring(L, buf, len);
	return 2;
}

static int fatfs_write(lua_State *L) {
	int luaType = lua_type( L, 1);
	if(luaType != LUA_TUSERDATA) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "must be FIL*");
		return 2;
	}
	FIL* fil = (FIL*)lua_touserdata(L, 1);
    luaType = lua_type( L, 2 );
    int len;
    char* buf;
	int re = -1;
    
    if(luaType == LUA_TSTRING )
    {
        buf = (char*)lua_tolstring( L, 2, &len );
        
        re = f_write(fil, buf, len, &len);
    }
    else if(luaType == LUA_TLIGHTUSERDATA)
    {         
         buf = lua_touserdata(L, 2);
         len = lua_tointeger( L, 3);
         
         re = f_write(fil, buf, len, &len);
    }
    if (FATFS_DEBUG)
		LLOGD("[FatFS]write re=%d len=%d\r\n", re, len);
    lua_pushinteger(L, re);
    lua_pushinteger(L, len);
    return 2;
}

static int fatfs_remove(lua_State *L) {
	int luaType = lua_type(L, 1);
	if(luaType != LUA_TSTRING) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "file path must string");
		return 2;
	}
	FRESULT re = f_unlink(lua_tostring(L, 1));
	lua_pushinteger(L, re);
	return 1;
}

static int fatfs_rename(lua_State *L) {
	int luaType = lua_type(L, 1);
	if(luaType != LUA_TSTRING) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "source file path must string");
		return 2;
	}
	luaType = lua_type(L, 2);
	if(luaType != LUA_TSTRING) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "dest file path must string");
		return 2;
	}
	FRESULT re = f_rename(lua_tostring(L, 1), lua_tostring(L, 2));
	lua_pushinteger(L, re);
	return 1;
}



/**
 * fatfs.readfile("adc.txt") 
 * fatfs.readfile("adc.txt", 512, 0) 默认只读取512字节,从0字节开始读
 */
static int fatfs_readfile(lua_State *L) {
	int luaType = lua_type( L, 1);
	if(luaType != LUA_TSTRING) {
		lua_pushinteger(L, -1);
		lua_pushstring(L, "file path must string");
		return 2;
	}
	FIL fil;

	DRESULT re = f_open(&fil, lua_tostring(L, 1), FA_READ);
	if (re != FR_OK) {
		lua_pushinteger(L, re);
		return 1;
	}

	u32 limit = luaL_optinteger(L, 2, 512);
	u32 seek = luaL_optinteger(L, 3, 0);
	if (seek > 0) {
		f_lseek(&fil, seek);
	}

	u8 buf[limit];
	UINT len;
	if (FATFS_DEBUG)
		LLOGD("[FatFS]readfile seek=%d limit=%d\r\n", seek, limit);
	FRESULT fr = f_read(&fil, buf, limit, &len);
	if (fr != FR_OK) {
		lua_pushinteger(L, -3);
		lua_pushinteger(L, fr);
		return 2;
	}
	f_close(&fil);
	lua_pushinteger(L, 0);
	lua_pushlstring(L, buf, len);
	if (FATFS_DEBUG)
		LLOGD("[FatFS]readfile seek=%d limit=%d len=%d\r\n", seek, limit, len);
	return 2;
}

// static int fatfs_playmp3(lua_State *L) {
// 	int luaType = lua_type( L, 1);
// 	if(luaType != LUA_TSTRING) {
// 		lua_pushinteger(L, -1);
// 		lua_pushstring(L, "file path must string");
// 		return 2;
// 	}
// 	FILINFO fileinfo;
// 	u8 *path = lua_tostring(L, 1);
// 	FRESULT re = f_stat(path, &fileinfo);
// 	if (re) {
// 		lua_pushinteger(L, re);
// 		return 1;
// 	}
// 	FIL fil;
// 	re = f_open(&fil, path, FA_READ);
// 	if (re != FR_OK) {
// 		lua_pushinteger(L, re);
// 		return 1;
// 	}

// 	u8 buf[fileinfo.fsize];
// 	UINT len;
// 	FRESULT fr = f_read(&fil, buf, fileinfo.fsize, &len);
// 	if (fr) {
// 		lua_pushinteger(L, fr);
// 		return 1;
// 	}
// 	f_close(&fil);
// 	AudioPlayParam param;
    
//     param.isBuffer = TRUE;
//     param.buffer.format = PLATFORM_AUD_MP3;
//     param.buffer.loop = 0;
//     param.buffer.data = buf;
//     param.buffer.len = len;

// 	re = platform_audio_play(&param);
// 	lua_pushinteger(L, re);
// 	return 1;
// }

static int fatfs_debug_mode(lua_State *L) {
	FATFS_DEBUG = luaL_optinteger(L, 1, 1);
	return 0;
}

// Module function map
#include "rotable.h"
static const rotable_Reg reg_fatfs[] =
{ 
  { "init",		fatfs_mount, 0}, //初始化,挂载, 别名方法
  { "mount",	fatfs_mount, 0}, //初始化,挂载
  { "unmount",	fatfs_unmount, 0}, // 取消挂载
  { "mkfs",		fatfs_mkfs, 0}, // 格式化!!!
  //{ "test",  fatfs_test, 0},
  { "getfree",	fatfs_getfree, 0}, // 获取文件系统大小,剩余空间
  { "debug",	fatfs_debug_mode, 0}, // 调试模式,打印更多日志

  { "lsdir",	fatfs_lsdir, 0}, // 列举目录下的文件,名称,大小,日期,属性
  { "mkdir",	fatfs_mkdir, 0}, // 列举目录下的文件,名称,大小,日期,属性

  { "stat",		fatfs_stat, 0}, // 查询文件信息
  { "open",		fatfs_open, 0}, // 打开一个文件句柄
  { "close",	fatfs_close, 0}, // 关闭一个文件句柄
  { "seek",		fatfs_seek, 0}, // 移动句柄的当前位置
  { "truncate",	fatfs_truncate, 0}, // 缩减文件尺寸到当前seek位置
  { "read",		fatfs_read, 0}, // 读取数据
  { "write",	fatfs_write, 0}, // 写入数据
  { "remove",	fatfs_remove, 0}, // 删除文件,别名方法
  { "unlink",	fatfs_remove, 0}, // 删除文件
  { "rename",	fatfs_rename, 0}, // 文件改名

  { "readfile",	fatfs_readfile, 0}, // 读取文件的简易方法
//   { "playmp3",	fatfs_playmp3, 0}, // 读取文件的简易方法
  { NULL,		NULL,	0 }
};

int luaopen_fatfs( lua_State *L )
{
  luat_newlib(L, reg_fatfs);
  return 1;
}
