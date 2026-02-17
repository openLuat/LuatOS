
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "lundump.h"
#include "luat_mock.h"
#include "luat_luadb2.h"
#include <stdlib.h>

#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

#include "dirent.h"

extern int cmdline_argc;
extern char **cmdline_argv;

// luadb数据的上下文
luat_luadb2_ctx_t luadb_ctx = {0};
char *luadb_ptr;

// 导出luadb数据的路径,默认是导出
char luadb_dump_path[1024];
// 脚本lua文件转luac时,是否删除调试信息,默认不删
int cfg_luac_strip;
int cfg_dump_luadb;
int cfg_dump_report;
int cfg_norun;

static void *check_file_path_depth(const char *path, int depth);
void *check_file_path(const char *path);

static int luat_cmd_load_luadb(const char *path);
static int luat_cmd_load_luatools(const char *path);

int luadb_do_report(luat_luadb2_ctx_t *ctx);

static int is_opts(const char *key, const char *arg)
{
	if (strlen(key) >= strlen(arg))
	{
		return 0;
	}
	return memcmp(key, arg, strlen(key)) == 0;
}

int luat_cmd_parse(int argc, char **argv)
{
	if (cmdline_argc == 1)
	{
		return 0;
	}
	luat_luadb2_init(&luadb_ctx);
	for (size_t i = 1; i < (size_t)argc; i++)
	{
		const char *arg = argv[i];
		// 加载luadb文件镜像直接启动
		if (is_opts("--load_luadb=", arg))
		{
			if (luat_cmd_load_luadb(arg + strlen("--load_luadb=")))
			{
				LLOGE("加载luadb镜像失败");
				return -1;
			}
			continue;
		}
		if (is_opts("--ldb=", arg))
		{
			if (luat_cmd_load_luadb(arg + strlen("--ldb=")))
			{
				LLOGE("加载luadb镜像失败");
				return -1;
			}
			continue;
		}
		// 加载LuaTools项目文件直接启动
		if (is_opts("--load_luatools=", arg))
		{
			if (luat_cmd_load_luatools(arg + strlen("--load_luatools=")))
			{
				LLOGE("加载luatools项目文件失败");
				return -1;
			}
			continue;
		}
		if (is_opts("--llt=", arg))
		{
			if (luat_cmd_load_luatools(arg + strlen("--llt=")))
			{
				LLOGE("加载luatools项目文件失败");
				return -1;
			}
			continue;
		}

		// mock加载
		if (is_opts("--mlua=", arg))
		{
			if (luat_mock_init(arg + strlen("--mlua=")))
			{
				LLOGE("加载mock功能失败");
				return -1;
			}
			continue;
		}

		// 导出luadb文件
		if (is_opts("--dump_luadb=", arg))
		{
			memcpy(luadb_dump_path, arg + strlen("--dump_luadb="), strlen(arg) - strlen("--dump_luadb="));
			continue;
		}
		
		if (is_opts("--luac_strip=", arg))
		{
			if (!strcmp("--luac_strip=1", arg)) {
				cfg_luac_strip = 1;
			}
			else if (!strcmp("--luac_strip=0", arg)) {
				cfg_luac_strip = 0;
			}
			else if (!strcmp("--luac_strip=2", arg)) {
				cfg_luac_strip = 2;
			}
			continue;
		}

		if (is_opts("--luac_report=", arg))
		{
			// LLOGD("只导出luadb数据");
			if (!strcmp("--luac_report=1", arg)) {
				cfg_dump_report = 1;
			}
			continue;
		}
		// 是否导出luadb文件
		if (is_opts("--norun=", arg))
		{
			// LLOGD("只导出luadb数据");
			if (!strcmp("--norun=1", arg)) {
				cfg_norun = 1;
			}
			continue;
		}

		if (arg[0] == '-')
		{
			continue;
		}
		check_file_path(arg);
	}

	if (luadb_dump_path[0]) {
		LLOGD("导出luadb数据到 %s 大小 %d", luadb_dump_path, luadb_ctx.offset);
		FILE* f = fopen(luadb_dump_path, "wb+");
		if (f == NULL) {
			LLOGE("无法打开luadb导出路径 %s", luadb_dump_path);
			exit(1);
		}
		fwrite(luadb_ptr, 1, luadb_ctx.offset, f);
		fclose(f);
	}

	if (cfg_norun) {
		exit(0);
	}

	return 0;
}

static int luat_cmd_load_luadb(const char *path)
{
	long len = 0;
	FILE *f = fopen(path, "rb");
	if (!f)
	{
		LLOGE("无法打开luadb镜像文件 %s", path);
		return -1;
	}
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);
	char *ptr = malloc(len);
	if (ptr == NULL)
	{
		fclose(f);
		LLOGE("luadb镜像文件太大,内存放不下 %s", path);
		return -1;
	}
	fread(ptr, len, 1, f);
	fclose(f);
	luadb_ptr = ptr;
	// luadb_offset = len;
	return 0;
}

static int luat_cmd_load_luatools(const char *path)
{
	long len = 0;
	FILE *f = fopen(path, "rb");
	if (!f)
	{
		LLOGE("无法打开luatools项目文件 %s", path);
		return -1;
	}
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);
	char *ptr = malloc(len + 1);
	if (ptr == NULL)
	{
		fclose(f);
		LLOGE("luatools项目文件太大,内存放不下 %s", path);
		return -1;
	}
	fread(ptr, len, 1, f);
	fclose(f);

	ptr[len] = 0;

	char *ret = ptr;
	char dirline[512] = {0};
	char rpath[1024] = {0};
	size_t retlen = 0;
	while (ptr[0] != 0x00)
	{
		// LLOGD("ptr %c", ptr[0]);
		if (ptr[0] == '\r' || ptr[0] == '\n')
		{
			if (ret != ptr)
			{
				ptr[0] = 0x00;
				retlen = strlen(ret);
				// LLOGD("检索到的行 %s", ret);
				if (!strcmp("[info]", ret))
				{
				}
				else if (retlen > 5)
				{
					if (ret[0] == '[' && ret[retlen - 1] == ']')
					{
						LLOGD("目录行 %s", ret);
						memcpy(dirline, ret + 1, retlen - 2);
						dirline[retlen - 2] = 0x00;
					}
					else
					{
						if (dirline[0])
						{
							for (size_t i = 0; i < strlen(ret); i++)
							{
								if (ret[i] == ' ' || ret[i] == '=')
								{
									ret[i] = 0;
									memset(rpath, 0, 1024);
									memcpy(rpath, dirline, strlen(dirline));
#ifdef LUA_USE_WINDOWS
									rpath[strlen(dirline)] = '\\';
#else
									rpath[strlen(dirline)] = '/';
#endif
									memcpy(rpath + strlen(rpath), ret, strlen(ret));
									LLOGI("加载文件 %s", rpath);
									if (check_file_path(rpath) == NULL)
										return -2;
									break;
								}
							}
						}
					}
				}
			}
			ret = ptr + 1;
		}
		ptr++;
	}
	return 0;
}

typedef struct luac_ctx
{
	char *ptr;
	size_t len;
} luac_ctx_t;

luac_ctx_t* last_ctx = NULL;

static int writer(lua_State *L, const void *p, size_t size, void *u)
{
	UNUSED(L);
	// LLOGD("写入部分数据 %p %d", p, size);
	luac_ctx_t *ctx = (luac_ctx_t *)u;
	if (ctx->ptr == NULL)
	{
		ctx->ptr = malloc(size);
		ctx->len = size;
		memcpy(ctx->ptr, p, size);
		return 0;
	}
	char *ptr = realloc(ctx->ptr, ctx->len + size);
	if (ptr == NULL)
	{
		LLOGE("内存分配失败");
		return 1;
	}
	memcpy(ptr + ctx->len, p, size);
	ctx->ptr = ptr;
	ctx->len += size;
	return 0;
}

static int pmain(lua_State *L)
{
	const char *name = luaL_checkstring(L, 1);
	size_t len = 0;
	const char *data = luaL_checklstring(L, 2, &len);
	int ret = luaL_loadbufferx(L, data, len, name, NULL);
	if (ret)
	{
		LLOGE("文件加载失败 %s %s", name, lua_tostring(L, -1));
		return 0;
	}
	// LLOGD("luac转换成功,开始转buff %s", name);
	luac_ctx_t *ctx = malloc(sizeof(luac_ctx_t));
	memset(ctx, 0, sizeof(luac_ctx_t));
	// LLOGD("getproto ");
	const Proto *f = getproto(L->top - 1);
	// LLOGD("Proto %p", f);
	if (cfg_luac_strip) {
		if (cfg_luac_strip == 1 && !strcmp("main.lua", name)) {
			ret = luaU_dump(L, f, writer, ctx, 0);
		}
		else {
			ret = luaU_dump(L, f, writer, ctx, 1);
		}
	}
	else {
		ret = luaU_dump(L, f, writer, ctx, 0);
	}
	
	// LLOGD("luaU_dump 执行完成");
	if (ret == 0)
	{
		// luadb_addfile(name, ctx->ptr, ctx->len);
		luat_luadb2_write(&luadb_ctx, name, ctx->ptr, ctx->len);
		luadb_ptr = luadb_ctx.dataptr;
	}
	lua_pushinteger(L, ret);
	free(ctx->ptr);
	free(ctx);
	return 1;
}

static int to_luac(const char *fullpath, const char *name, char *data, size_t len)
{
	// LLOGD("检查语法并转换成luac %s 路径 %s", name, fullpath);
	lua_State *L = lua_newstate(luat_heap_alloc, NULL);
	// LLOGD("创建临时luavm");
	lua_pushcfunction(L, &pmain);
	lua_pushstring(L, name);
	lua_pushlstring(L, data, len);
	// LLOGD("准备执行luac转换");
	int ret = lua_pcall(L, 2, 1, 0);
	if (ret)
	{
		LLOGD("lua文件加载失败 %s %d", fullpath, ret);
		lua_close(L);
		return -1;
	}
	ret = luaL_checkinteger(L, -1);
	lua_close(L);
	return ret;
}

static int add_onefile(const char *path)
{
	size_t len = 0;
	int ret = 0;
	// LLOGD("把%s当做main.lua运行", path);
	char tmpname[512] = {0};
	FILE *f = fopen(path, "rb");
	if (!f)
	{
		LLOGE("文件不存在 %s", path);
		return -1;
	}
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);
	// void* fptr = luat_heap_malloc(len);
	char *tmp = malloc(len);
	if (tmp == NULL)
	{
		fclose(f);
		LLOGE("文件太大,内存放不下 %s", path);
		return -2;
	}
	fread(tmp, 1, len, f);
	fclose(f);

	for (size_t i = strlen(path); i > 0; i--)
	{
		if (path[i - 1] == '/' || path[i - 1] == '\\')
		{
			memcpy(tmpname, path + i, strlen(path) - 1);
			break;
		}
	}
	if (tmpname[0] == 0x00)
	{
		memcpy(tmpname, path, strlen(path));
	}

	if (!memcmp(path + strlen(path) - 4, ".lua", 4))
	{

		ret = to_luac(path, tmpname, tmp, len);
	}
	else
	{
		// ret = luadb_addfile(tmpname, tmp, len);
		ret = luat_luadb2_write(&luadb_ctx, tmpname, tmp, len);
		luadb_ptr = luadb_ctx.dataptr;
	}
	free(tmp);
	return ret;
}

void *check_file_path(const char *path)
{
	return check_file_path_depth(path, 1);
}

static void *check_file_path_depth(const char *path, int depth)
{
	if (strlen(path) < 4 || strlen(path) >= 512)
	{
		LLOGD("文件长度不对劲 %d %s", strlen(path), path);
		return NULL;
	}
	// 目录模式
	if (!memcmp(path + strlen(path) - 1, "/", 1) || !memcmp(path + strlen(path) - 1, "\\", 1))
	{
		DIR *dp;
		struct dirent *ep;
		// int index = 0;
		char buff[512] = {0};

		// LLOGD("加载目录 %s", path);
		#ifdef LUA_USE_WINDOWS
		memcpy(buff, path, strlen(path));
		#else
		memcpy(buff, path, strlen(path) - 1);
		#endif
		dp = opendir(buff);
		// LLOGD("目录打开 %p", dp);
		if (dp != NULL)
		{
			// LLOGD("开始遍历目录 %s", path);
			while ((ep = readdir(dp)) != NULL)
			{
				// LLOGD("文件/目录 %s %d", ep->d_name, ep->d_type);
				if (!strcmp(ep->d_name, ".") || !strcmp(ep->d_name, ".."))
				{
					continue;
				}

				if (ep->d_type == DT_DIR)
				{
					if (depth >= 4) // 限制目录深度为三层
					{
						continue;
					}
					char child_path[512] = {0};
					#ifdef LUA_USE_WINDOWS
					snprintf(child_path, sizeof(child_path), "%s\\%s\\", path, ep->d_name);
					#else
					snprintf(child_path, sizeof(child_path), "%s/%s/", path, ep->d_name);
					#endif
					if (check_file_path_depth(child_path, depth + 1) == NULL)
					{
						return NULL;
					}
					continue;
				}

				if (ep->d_type != DT_REG)
				{
					continue;
				}

				#ifdef LUA_USE_WINDOWS
				snprintf(buff, sizeof(buff), "%s\\%s", path, ep->d_name);
				#else
				snprintf(buff, sizeof(buff), "%s/%s", path, ep->d_name);
				#endif
				if (add_onefile(buff))
				{
					return NULL;
				}
			}
			// LLOGD("遍历结束");
			(void)closedir(dp);
			return luadb_ptr;
		}
		else
		{
			LLOGW("opendir file %s failed", path);
			return NULL;
		}
	}
	else
	{
		if (add_onefile(path))
		{
			return NULL;
		}
		return luadb_ptr;
	}
	// return NULL;
}

// 加载并分析文件
int luat_cmd_load_and_analyse(const char *path)
{
	size_t len = 0;
	int ret = 0;
	// LLOGD("把%s当做main.lua运行", path);
	char tmpname[512] = {0};
	FILE *f = fopen(path, "rb");
	if (!f)
	{
		LLOGE("文件不存在 %s", path);
		return -1;
	}
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);
	// void* fptr = luat_heap_malloc(len);
	char *tmp = malloc(len);
	if (tmp == NULL)
	{
		fclose(f);
		LLOGE("文件太大,内存放不下 %s", path);
		return -2;
	}
	fread(tmp, 1, len, f);
	fclose(f);

	for (size_t i = strlen(path); i > 0; i--)
	{
		if (path[i - 1] == '/' || path[i - 1] == '\\')
		{
			memcpy(tmpname, path + i, strlen(path) - 1);
			break;
		}
	}
	if (tmpname[0] == 0x00)
	{
		memcpy(tmpname, path, strlen(path));
	}

	if (!memcmp(path + strlen(path) - 4, ".lua", 4))
	{

		ret = to_luac(path, tmpname, tmp, len);
	}
	else
	{
		// ret = luadb_addfile(tmpname, tmp, len);
		ret = luat_luadb2_write(&luadb_ctx, tmpname, tmp, len);
		luadb_ptr = luadb_ctx.dataptr;
	}
	free(tmp);
	return ret;
}
