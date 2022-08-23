#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "sysp"
#include "luat_log.h"
#include <sys/stat.h>

#ifdef LUAT_USE_LVGL
#include "lvgl.h"
void luat_lv_fs_init(void);
void lv_bmp_init(void);
void lv_png_init(void);
void lv_split_jpeg_init(void);
#endif

extern const struct luat_vfs_filesystem vfs_fs_posix;
extern const struct luat_vfs_filesystem vfs_fs_onefile;

// #ifdef LUAT_USE_VFS_INLINE_LIB
extern const char luat_inline_sys[];
extern const uint32_t luat_inline_sys_size;
// #endif

static uint8_t fs_init_done = 0;

int luat_fs_init(void) {
	if (fs_init_done)
		return 0;
	fs_init_done = 1;

	// vfs进行必要的初始化
	luat_vfs_init(NULL);
	// 注册vfs for posix 实现
	luat_vfs_reg(&vfs_fs_posix);
	luat_vfs_reg(&vfs_fs_onefile);

	luat_fs_conf_t conf = {
		.busname = "posix",
		.type = "posix",
		.filesystem = "posix",
		.mount_point = "",
	};
	luat_fs_mount(&conf);
	mkdir("/luadb", S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
	FILE* fd = fopen("/luadb/sys.luac", "w");
	if (fd) {
		fwrite(luat_inline_sys, luat_inline_sys_size, 1, fd);
		fflush(fd);
		fclose(fd);
	}

	#ifdef LUAT_USE_LVGL
	luat_lv_fs_init();
	lv_bmp_init();
	lv_png_init();
	lv_split_jpeg_init();
	#endif
	return 0;
}
