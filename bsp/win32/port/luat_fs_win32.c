#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "luat_luadb.h"

#ifdef LUAT_USE_LVGL
#include "lvgl.h"
void luat_lv_fs_init(void);
void lv_bmp_init(void);
void lv_png_init(void);
void lv_split_jpeg_init(void);
#endif

extern const struct luat_vfs_filesystem vfs_fs_posix;
// extern const struct luat_vfs_filesystem vfs_fs_onefile;
extern const struct luat_vfs_filesystem vfs_fs_luadb;
extern const char* luat_luadb_mock;

// #ifdef LUAT_USE_VFS_INLINE_LIB
// extern const luadb_file_t *luat_inline2_libs_64bit;
// #endif

typedef struct luat_fs_onefile
{
    char* ptr;
    uint32_t  size;
    uint32_t  offset;
}luat_fs_onefile_t;

int luat_fs_init(void) {
	#ifdef LUAT_USE_FS_VFS
	// vfs进行必要的初始化
	luat_vfs_init(NULL);
	// 注册vfs for posix 实现
	luat_vfs_reg(&vfs_fs_posix);
	luat_vfs_reg(&vfs_fs_luadb);

	luat_fs_conf_t conf = {
		.busname = "",
		.type = "posix",
		.filesystem = "posix",
		.mount_point = "", // window环境下, 需要支持任意路径的读取,不能强制要求必须是/
	};
	luat_fs_mount(&conf);
	luat_fs_conf_t conf2 = {
		.busname = (char*)luat_luadb_mock,
		.type = "luadb",
		.filesystem = "luadb",
		.mount_point = "/luadb/",
	};
	luat_fs_mount(&conf2);
	#endif

	#ifdef LUAT_USE_LVGL
	luat_lv_fs_init();
	lv_bmp_init();
	lv_png_init();
	lv_split_jpeg_init();
	#endif
	return 0;
}
