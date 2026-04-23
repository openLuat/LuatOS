
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "lundump.h"
#include "luat_mock.h"
#include "luat_luadb2.h"
#include <stdlib.h>
#include <ctype.h>

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
int cfg_noexit;
// PC 模拟器默认开启依赖裁剪; 如需回退到旧行为, 用 --dep_strip=0 关闭
int cfg_dep_strip = 1;
// 是否已通过 --llt= / --ldb= 等方式预加载了项目文件(含 main.lua)
static int cfg_has_preload = 0;

static void *check_file_path_depth(const char *path, int depth);
void *check_file_path(const char *path);
static int add_onefile(const char *path);

static int luat_cmd_load_luadb(const char *path);
static int luat_cmd_load_luatools(const char *path);
int luat_search_module(const char *name, char *filename);

int luadb_do_report(luat_luadb2_ctx_t *ctx);

typedef enum luat_dep_file_kind
{
	LUAT_DEP_FILE_SOURCE = 1,
	LUAT_DEP_FILE_BINARY,
	LUAT_DEP_FILE_RESOURCE,
} luat_dep_file_kind_t;

typedef enum luat_dep_ref_kind
{
	LUAT_DEP_REF_MODULE = 1,
	LUAT_DEP_REF_FILE,
} luat_dep_ref_kind_t;

typedef struct luat_dep_ref
{
	char *value;
	uint8_t kind;
} luat_dep_ref_t;

typedef struct luat_dep_file
{
	// 原始全路径, 最终真正送入 add_onefile 的路径
	char *fullpath;
	// basename, 与当前 PC 模拟器打入 luadb 的文件名规则保持一致
	char *name;
	// 去扩展名后的模块名, 用于 require "foo" -> foo.lua/foo.luac 匹配
	char *stem;
	uint8_t kind;
	// selected 表示最终需要打入 luadb, parsed/expanded 仅服务静态分析流程
	uint8_t selected;
	uint8_t parsed;
	uint8_t expanded;
	luat_dep_ref_t *deps;
	size_t dep_count;
	size_t dep_capacity;
} luat_dep_file_t;

typedef struct luat_dep_ctx
{
	// 本次命令行所有目录/文件参数统一汇总后的候选文件集
	luat_dep_file_t *files;
	size_t count;
	size_t capacity;
	// 一旦发现只有二进制脚本、无法安全分析等场景, 直接退回到全量 Lua 打包
	uint8_t fallback_all_lua;
	size_t skipped_lua_count;
} luat_dep_ctx_t;

static int luat_cmd_pack_with_dep_strip(const char **paths, size_t count);
static int luat_cmd_collect_path(luat_dep_ctx_t *ctx, const char *path, int depth);
static void luat_cmd_free_dep_ctx(luat_dep_ctx_t *ctx);
static luat_dep_file_t *luat_cmd_find_file_by_name(luat_dep_ctx_t *ctx, const char *name);
static luat_dep_file_t *luat_cmd_find_source_by_stem(luat_dep_ctx_t *ctx, const char *stem);
static luat_dep_file_t *luat_cmd_find_binary_by_stem(luat_dep_ctx_t *ctx, const char *stem);
static int luat_cmd_mark_required(luat_dep_ctx_t *ctx, luat_dep_file_t *file, const char *from_name);
static int luat_cmd_expand_dependencies(luat_dep_ctx_t *ctx, luat_dep_file_t *file, const char *from_name);
static int luat_cmd_parse_file_deps(luat_dep_file_t *file);
static int luat_cmd_add_dep(luat_dep_file_t *file, uint8_t kind, const char *value, size_t len);
static int luat_cmd_parse_lua_buffer(luat_dep_file_t *file, const char *data, size_t len);
static int luat_cmd_module_exists_elsewhere(const char *name);
static int luat_cmd_resolve_module(luat_dep_ctx_t *ctx, const char *module_name, luat_dep_file_t **pack_file, luat_dep_file_t **parse_file);
static int luat_cmd_resolve_file(luat_dep_ctx_t *ctx, const char *file_name, luat_dep_file_t **pack_file, luat_dep_file_t **parse_file);

static char *luat_cmd_strdup_n(const char *src, size_t len)
{
	char *dst = malloc(len + 1);
	if (dst == NULL)
	{
		return NULL;
	}
	memcpy(dst, src, len);
	dst[len] = 0;
	return dst;
}

static const char *luat_cmd_basename(const char *path)
{
	const char *slash = strrchr(path, '/');
	const char *backslash = strrchr(path, '\\');
	const char *base = slash;
	if (backslash && (!base || backslash > base))
	{
		base = backslash;
	}
	return base ? base + 1 : path;
}

static char *luat_cmd_dup_stem(const char *name)
{
	const char *dot = strrchr(name, '.');
	if (!dot)
	{
		return luat_cmd_strdup_n(name, strlen(name));
	}
	return luat_cmd_strdup_n(name, (size_t)(dot - name));
}

static const char *luat_cmd_file_ext(const char *name)
{
	const char *dot = strrchr(name, '.');
	return dot ? dot : "";
}

static int luat_cmd_is_lua_source_name(const char *name)
{
	return strcmp(luat_cmd_file_ext(name), ".lua") == 0;
}

static int luat_cmd_is_lua_binary_name(const char *name)
{
	const char *ext = luat_cmd_file_ext(name);
	return strcmp(ext, ".luac") == 0 || strcmp(ext, ".luae") == 0;
}

static size_t luat_cmd_skip_space(const char *data, size_t len, size_t pos)
{
	while (pos < len)
	{
		char ch = data[pos];
		if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n' && ch != '\f' && ch != '\v')
		{
			break;
		}
		pos++;
	}
	return pos;
}

static int luat_cmd_is_ident_char(char ch)
{
	return isalnum((unsigned char)ch) || ch == '_';
}

static int luat_cmd_match_keyword(const char *data, size_t len, size_t pos, const char *keyword)
{
	size_t keyword_len = strlen(keyword);
	if (pos + keyword_len > len)
	{
		return 0;
	}
	if (memcmp(data + pos, keyword, keyword_len) != 0)
	{
		return 0;
	}
	if (pos > 0 && luat_cmd_is_ident_char(data[pos - 1]))
	{
		return 0;
	}
	if (pos + keyword_len < len && luat_cmd_is_ident_char(data[pos + keyword_len]))
	{
		return 0;
	}
	return 1;
}

static int luat_cmd_long_bracket_level(const char *data, size_t len, size_t pos)
{
	size_t cursor = pos + 1;
	int level = 0;
	if (pos >= len || data[pos] != '[')
	{
		return -1;
	}
	while (cursor < len && data[cursor] == '=')
	{
		level++;
		cursor++;
	}
	if (cursor < len && data[cursor] == '[')
	{
		return level;
	}
	return -1;
}

static size_t luat_cmd_skip_long_bracket(const char *data, size_t len, size_t pos, int level)
{
	size_t cursor = pos + 1;
	while (cursor < len && data[cursor] == '=')
	{
		cursor++;
	}
	if (cursor < len)
	{
		cursor++;
	}
	while (cursor < len)
	{
		if (data[cursor] == ']')
		{
			size_t check = cursor + 1;
			int matched = 1;
			for (int i = 0; i < level; i++)
			{
				if (check >= len || data[check] != '=')
				{
					matched = 0;
					break;
				}
				check++;
			}
			if (matched && check < len && data[check] == ']')
			{
				return check + 1;
			}
		}
		cursor++;
	}
	return len;
}

static size_t luat_cmd_skip_quoted(const char *data, size_t len, size_t pos, char quote)
{
	pos++;
	while (pos < len)
	{
		if (data[pos] == '\\')
		{
			pos += 2;
			continue;
		}
		if (data[pos] == quote)
		{
			return pos + 1;
		}
		pos++;
	}
	return len;
}

static int luat_cmd_parse_string_literal(const char *data, size_t len, size_t *pos, char **value, size_t *value_len)
{
	char quote;
	size_t start;
	size_t cursor;
	if (*pos >= len)
	{
		return -1;
	}
	quote = data[*pos];
	if (quote != '\'' && quote != '"')
	{
		return -1;
	}
	start = *pos + 1;
	cursor = start;
	while (cursor < len)
	{
		if (data[cursor] == '\\')
		{
			cursor += 2;
			continue;
		}
		if (data[cursor] == quote)
		{
			*value = luat_cmd_strdup_n(data + start, cursor - start);
			if (*value == NULL)
			{
				return -2;
			}
			*value_len = cursor - start;
			*pos = cursor + 1;
			return 0;
		}
		cursor++;
	}
	return -1;
}

static int luat_cmd_append_file(luat_dep_ctx_t *ctx, const char *path)
{
	const char *name = luat_cmd_basename(path);
	luat_dep_file_t *file;
	size_t name_len = strlen(name);
	if (name_len == 0 || name_len >= 256)
	{
		LLOGE("文件名不合法 %s", path);
		return -1;
	}
	if (luat_cmd_find_file_by_name(ctx, name) != NULL)
	{
		// 现有 PC 模拟器会把目录结构抹平成 basename, 所以这里必须提前拦截重名
		LLOGE("依赖裁剪模式下不允许重名文件 %s", name);
		return 0;
	}
	if (ctx->count + 1 > ctx->capacity)
	{
		size_t next_capacity = ctx->capacity == 0 ? 16 : ctx->capacity * 2;
		luat_dep_file_t *next_files = realloc(ctx->files, next_capacity * sizeof(luat_dep_file_t));
		if (next_files == NULL)
		{
			LLOGE("内存不足, 无法建立文件索引");
			return -1;
		}
		ctx->files = next_files;
		ctx->capacity = next_capacity;
	}
	file = &ctx->files[ctx->count++];
	memset(file, 0, sizeof(luat_dep_file_t));
	file->fullpath = luat_cmd_strdup_n(path, strlen(path));
	file->name = luat_cmd_strdup_n(name, name_len);
	file->stem = luat_cmd_dup_stem(name);
	if (file->fullpath == NULL || file->name == NULL || file->stem == NULL)
	{
		LLOGE("内存不足, 无法记录文件信息");
		return -1;
	}
	if (luat_cmd_is_lua_source_name(name))
	{
		file->kind = LUAT_DEP_FILE_SOURCE;
	}
	else if (luat_cmd_is_lua_binary_name(name))
	{
		file->kind = LUAT_DEP_FILE_BINARY;
	}
	else
	{
		file->kind = LUAT_DEP_FILE_RESOURCE;
	}
	return 0;
}

static int luat_cmd_collect_path(luat_dep_ctx_t *ctx, const char *path, int depth)
{
	size_t plen = strlen(path);
	if (plen == 0 || plen >= 512)
	{
		LLOGD("文件长度不对劲 %d %s", plen, path);
		return -1;
	}
	// 若路径不以 / 或 \ 结尾, 先尝试 opendir 检测是否为目录
	char last = path[plen - 1];
	if (last != '/' && last != '\\')
	{
		DIR *dp_probe = opendir(path);
		if (dp_probe != NULL)
		{
			closedir(dp_probe);
			// 补上尾斜杠后递归
			char pathbuf[512] = {0};
#ifdef LUA_USE_WINDOWS
			snprintf(pathbuf, sizeof(pathbuf), "%s\\", path);
#else
			snprintf(pathbuf, sizeof(pathbuf), "%s/", path);
#endif
			return luat_cmd_collect_path(ctx, pathbuf, depth);
		}
		return luat_cmd_append_file(ctx, path);
	}
	if (!memcmp(path + plen - 1, "/", 1) || !memcmp(path + plen - 1, "\\", 1))
	{
		// 目录模式: 这里只收集候选文件, 不立即 add_onefile, 方便后面统一算闭包
		DIR *dp;
		struct dirent *ep;
		char buff[512] = {0};
	#ifdef LUA_USE_WINDOWS
		memcpy(buff, path, strlen(path));
	#else
		memcpy(buff, path, strlen(path) - 1);
	#endif
		dp = opendir(buff);
		if (dp == NULL)
		{
			LLOGW("opendir file %s failed", path);
			return -1;
		}
		while ((ep = readdir(dp)) != NULL)
		{
			if (!strcmp(ep->d_name, ".") || !strcmp(ep->d_name, ".."))
			{
				continue;
			}
			if (ep->d_type == DT_DIR)
			{
				char child_path[512] = {0};
				if (depth >= 4)
				{
					continue;
				}
	#ifdef LUA_USE_WINDOWS
				snprintf(child_path, sizeof(child_path), "%s\\%s\\", path, ep->d_name);
	#else
				snprintf(child_path, sizeof(child_path), "%s/%s/", path, ep->d_name);
	#endif
				if (luat_cmd_collect_path(ctx, child_path, depth + 1))
				{
					closedir(dp);
					return -1;
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
			if (luat_cmd_append_file(ctx, buff))
			{
				closedir(dp);
				return -1;
			}
		}
		closedir(dp);
		return 0;
	}
	return 0;
}

static luat_dep_file_t *luat_cmd_find_file_by_name(luat_dep_ctx_t *ctx, const char *name)
{
	for (size_t i = 0; i < ctx->count; i++)
	{
		if (!strcmp(ctx->files[i].name, name))
		{
			return &ctx->files[i];
		}
	}
	return NULL;
}

static luat_dep_file_t *luat_cmd_find_source_by_stem(luat_dep_ctx_t *ctx, const char *stem)
{
	for (size_t i = 0; i < ctx->count; i++)
	{
		if (ctx->files[i].kind == LUAT_DEP_FILE_SOURCE && !strcmp(ctx->files[i].stem, stem))
		{
			return &ctx->files[i];
		}
	}
	return NULL;
}

static luat_dep_file_t *luat_cmd_find_binary_by_stem(luat_dep_ctx_t *ctx, const char *stem)
{
	luat_dep_file_t *luae = NULL;
	for (size_t i = 0; i < ctx->count; i++)
	{
		if (ctx->files[i].kind != LUAT_DEP_FILE_BINARY || strcmp(ctx->files[i].stem, stem))
		{
			continue;
		}
		if (!strcmp(luat_cmd_file_ext(ctx->files[i].name), ".luac"))
		{
			return &ctx->files[i];
		}
		if (luae == NULL)
		{
			luae = &ctx->files[i];
		}
	}
	return luae;
}

static int luat_cmd_add_dep(luat_dep_file_t *file, uint8_t kind, const char *value, size_t len)
{
	luat_dep_ref_t *ref;
	for (size_t i = 0; i < file->dep_count; i++)
	{
		if (file->deps[i].kind == kind && strlen(file->deps[i].value) == len && !memcmp(file->deps[i].value, value, len))
		{
			return 0;
		}
	}
	if (file->dep_count + 1 > file->dep_capacity)
	{
		size_t next_capacity = file->dep_capacity == 0 ? 8 : file->dep_capacity * 2;
		luat_dep_ref_t *next_deps = realloc(file->deps, next_capacity * sizeof(luat_dep_ref_t));
		if (next_deps == NULL)
		{
			LLOGE("内存不足, 无法记录依赖");
			return -1;
		}
		file->deps = next_deps;
		file->dep_capacity = next_capacity;
	}
	ref = &file->deps[file->dep_count++];
	memset(ref, 0, sizeof(luat_dep_ref_t));
	ref->kind = kind;
	ref->value = luat_cmd_strdup_n(value, len);
	if (ref->value == NULL)
	{
		LLOGE("内存不足, 无法复制依赖字符串");
		return -1;
	}
	return 0;
}

static int luat_cmd_parse_simple_call(luat_dep_file_t *file, const char *data, size_t len, size_t *pos, const char *keyword, uint8_t dep_kind)
{
	char *value = NULL;
	size_t value_len = 0;
	size_t cursor = *pos + strlen(keyword);
	cursor = luat_cmd_skip_space(data, len, cursor);
	if (cursor >= len)
	{
		return 0;
	}
	if (data[cursor] == '(')
	{
		// 兼容 require("foo") / dofile("a.lua") 这种带括号写法
		cursor++;
		cursor = luat_cmd_skip_space(data, len, cursor);
		if (luat_cmd_parse_string_literal(data, len, &cursor, &value, &value_len))
		{
			return 0;
		}
		cursor = luat_cmd_skip_space(data, len, cursor);
		if (cursor >= len || data[cursor] != ')')
		{
			free(value);
			return 0;
		}
		cursor++;
	}
	else
	{
		// 兼容 require "foo" 这种不带括号写法
		if (luat_cmd_parse_string_literal(data, len, &cursor, &value, &value_len))
		{
			return 0;
		}
	}
	if (luat_cmd_add_dep(file, dep_kind, value, value_len))
	{
		free(value);
		return -1;
	}
	free(value);
	*pos = cursor;
	return 1;
}

static int luat_cmd_parse_pcall_require(luat_dep_file_t *file, const char *data, size_t len, size_t *pos)
{
	char *value = NULL;
	size_t value_len = 0;
	size_t cursor = *pos + strlen("pcall");
	cursor = luat_cmd_skip_space(data, len, cursor);
	if (cursor >= len || data[cursor] != '(')
	{
		return 0;
	}
	cursor++;
	cursor = luat_cmd_skip_space(data, len, cursor);
	if (!luat_cmd_match_keyword(data, len, cursor, "require"))
	{
		return 0;
	}
	cursor += strlen("require");
	cursor = luat_cmd_skip_space(data, len, cursor);
	if (cursor >= len || data[cursor] != ',')
	{
		return 0;
	}
	cursor++;
	cursor = luat_cmd_skip_space(data, len, cursor);
	if (luat_cmd_parse_string_literal(data, len, &cursor, &value, &value_len))
	{
		return 0;
	}
	cursor = luat_cmd_skip_space(data, len, cursor);
	if (cursor >= len || data[cursor] != ')')
	{
		free(value);
		return 0;
	}
	cursor++;
	if (luat_cmd_add_dep(file, LUAT_DEP_REF_MODULE, value, value_len))
	{
		free(value);
		return -1;
	}
	free(value);
	*pos = cursor;
	return 1;
}

static int luat_cmd_parse_lua_buffer(luat_dep_file_t *file, const char *data, size_t len)
{
	size_t pos = 0;
	while (pos < len)
	{
		// 先跳过注释/字符串/长字符串, 避免把注释里的 require 误识别成真实依赖
		if (data[pos] == '-' && pos + 1 < len && data[pos + 1] == '-')
		{
			int level = -1;
			if (pos + 2 < len)
			{
				level = luat_cmd_long_bracket_level(data, len, pos + 2);
			}
			if (level >= 0)
			{
				pos = luat_cmd_skip_long_bracket(data, len, pos + 2, level);
			}
			else
			{
				pos += 2;
				while (pos < len && data[pos] != '\n')
				{
					pos++;
				}
			}
			continue;
		}
		if (data[pos] == '\'' || data[pos] == '"')
		{
			pos = luat_cmd_skip_quoted(data, len, pos, data[pos]);
			continue;
		}
		if (data[pos] == '[')
		{
			int level = luat_cmd_long_bracket_level(data, len, pos);
			if (level >= 0)
			{
				pos = luat_cmd_skip_long_bracket(data, len, pos, level);
				continue;
			}
		}
		if (luat_cmd_match_keyword(data, len, pos, "pcall"))
		{
			// 仅处理 pcall(require, "foo") 这种静态字符串形式
			int ret = luat_cmd_parse_pcall_require(file, data, len, &pos);
			if (ret < 0)
			{
				return -1;
			}
			if (ret > 0)
			{
				continue;
			}
		}
		if (luat_cmd_match_keyword(data, len, pos, "require"))
		{
			// 模块依赖: require "foo" -> foo.lua/foo.luac
			int ret = luat_cmd_parse_simple_call(file, data, len, &pos, "require", LUAT_DEP_REF_MODULE);
			if (ret < 0)
			{
				return -1;
			}
			if (ret > 0)
			{
				continue;
			}
		}
		if (luat_cmd_match_keyword(data, len, pos, "dofile"))
		{
			// 文件依赖: dofile("foo.lua")
			int ret = luat_cmd_parse_simple_call(file, data, len, &pos, "dofile", LUAT_DEP_REF_FILE);
			if (ret < 0)
			{
				return -1;
			}
			if (ret > 0)
			{
				continue;
			}
		}
		if (luat_cmd_match_keyword(data, len, pos, "loadfile"))
		{
			// 文件依赖: loadfile("foo.lua")
			int ret = luat_cmd_parse_simple_call(file, data, len, &pos, "loadfile", LUAT_DEP_REF_FILE);
			if (ret < 0)
			{
				return -1;
			}
			if (ret > 0)
			{
				continue;
			}
		}
		pos++;
	}
	return 0;
}

static int luat_cmd_parse_file_deps(luat_dep_file_t *file)
{
	long len;
	char *buffer;
	FILE *f;
	if (file->parsed || file->kind != LUAT_DEP_FILE_SOURCE)
	{
		return 0;
	}
	f = fopen(file->fullpath, "rb");
	if (!f)
	{
		LLOGE("文件不存在 %s", file->fullpath);
		return -1;
	}
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);
	buffer = malloc((size_t)len + 1);
	if (buffer == NULL)
	{
		fclose(f);
		LLOGE("文件太大,内存放不下 %s", file->fullpath);
		return -1;
	}
	if (len > 0)
	{
		fread(buffer, 1, (size_t)len, f);
	}
	buffer[len] = 0;
	fclose(f);
	if (luat_cmd_parse_lua_buffer(file, buffer, (size_t)len))
	{
		free(buffer);
		return -1;
	}
	file->parsed = 1;
	free(buffer);
	return 0;
}

static int luat_cmd_module_exists_elsewhere(const char *name)
{
	char filename[64] = {0};
	return luat_search_module(name, filename) == 0;
}

static int luat_cmd_resolve_module(luat_dep_ctx_t *ctx, const char *module_name, luat_dep_file_t **pack_file, luat_dep_file_t **parse_file)
{
	luat_dep_file_t *source = luat_cmd_find_source_by_stem(ctx, module_name);
	luat_dep_file_t *binary = luat_cmd_find_binary_by_stem(ctx, module_name);
	*pack_file = NULL;
	*parse_file = NULL;
	if (binary)
	{
		// 若同时存在 foo.lua 与 foo.luac, 优先把二进制产物打进包, 但仍用源码继续分析依赖
		*pack_file = binary;
		if (source)
		{
			*parse_file = source;
		}
		else
		{
			ctx->fallback_all_lua = 1;
			LLOGW("模块 %s 只有编译产物, 退回到全量 Lua 打包", module_name);
		}
		return 0;
	}
	if (source)
	{
		*pack_file = source;
		*parse_file = source;
		return 0;
	}
	if (luat_cmd_module_exists_elsewhere(module_name))
	{
		return 0;
	}
	return -1;
}

static int luat_cmd_resolve_file(luat_dep_ctx_t *ctx, const char *file_name, luat_dep_file_t **pack_file, luat_dep_file_t **parse_file)
{
	const char *base = luat_cmd_basename(file_name);
	luat_dep_file_t *exact;
	*pack_file = NULL;
	*parse_file = NULL;
	if (strchr(file_name, '/') || strchr(file_name, '\\'))
	{
		// 当前运行时打包键是 basename, 第一版不尝试恢复目录语义, 避免误裁剪
		LLOGW("暂不分析带路径的 dofile/loadfile %s", file_name);
		return 0;
	}
	exact = luat_cmd_find_file_by_name(ctx, base);
	if (exact)
	{
		*pack_file = exact;
		if (exact->kind == LUAT_DEP_FILE_SOURCE)
		{
			*parse_file = exact;
		}
		else if (exact->kind == LUAT_DEP_FILE_BINARY)
		{
			luat_dep_file_t *source = luat_cmd_find_source_by_stem(ctx, exact->stem);
			if (source)
			{
				*parse_file = source;
			}
			else
			{
				ctx->fallback_all_lua = 1;
				LLOGW("文件 %s 只有编译产物, 退回到全量 Lua 打包", base);
			}
		}
		return 0;
	}
	if (luat_fs_fexist(file_name) || luat_fs_fexist(base))
	{
		return 0;
	}
	return -1;
}

static int luat_cmd_mark_required(luat_dep_ctx_t *ctx, luat_dep_file_t *file, const char *from_name)
{
	if (file == NULL)
	{
		return 0;
	}
	if (file->selected)
	{
		return 0;
	}
	file->selected = 1;
	if (ctx->fallback_all_lua || file->kind != LUAT_DEP_FILE_SOURCE)
	{
		return 0;
	}
	return luat_cmd_expand_dependencies(ctx, file, from_name);
}

static int luat_cmd_expand_dependencies(luat_dep_ctx_t *ctx, luat_dep_file_t *file, const char *from_name)
{
	if (file == NULL || file->kind != LUAT_DEP_FILE_SOURCE)
	{
		return 0;
	}
	if (file->expanded)
	{
		return 0;
	}
	if (luat_cmd_parse_file_deps(file))
	{
		return -1;
	}
	file->expanded = 1;
	for (size_t i = 0; i < file->dep_count; i++)
	{
		// pack_file 是最终要打入 luadb 的目标; parse_file 是继续递归分析的源码来源
		luat_dep_file_t *pack_file = NULL;
		luat_dep_file_t *parse_file = NULL;
		int ret;
		if (file->deps[i].kind == LUAT_DEP_REF_MODULE)
		{
			ret = luat_cmd_resolve_module(ctx, file->deps[i].value, &pack_file, &parse_file);
		}
		else
		{
			ret = luat_cmd_resolve_file(ctx, file->deps[i].value, &pack_file, &parse_file);
		}
		if (ret)
		{
			/* Module not found as a Lua file — it may be a C built-in (e.g. require("memprof")).
			 * Treat as a non-fatal warning and continue: if the module truly does not exist the
			 * Lua VM will raise an error at runtime. */
			LLOGW("依赖未找到(可能是C内置模块) %s <- %s", file->deps[i].value, from_name ? from_name : file->name);
			continue;
		}
		if (pack_file && luat_cmd_mark_required(ctx, pack_file, file->name))
		{
			return -1;
		}
		if (parse_file && parse_file != pack_file && luat_cmd_expand_dependencies(ctx, parse_file, file->name))
		{
			return -1;
		}
	}
	return 0;
}

static void luat_cmd_free_dep_ctx(luat_dep_ctx_t *ctx)
{
	if (ctx == NULL)
	{
		return;
	}
	for (size_t i = 0; i < ctx->count; i++)
	{
		free(ctx->files[i].fullpath);
		free(ctx->files[i].name);
		free(ctx->files[i].stem);
		for (size_t j = 0; j < ctx->files[i].dep_count; j++)
		{
			free(ctx->files[i].deps[j].value);
		}
		free(ctx->files[i].deps);
	}
	free(ctx->files);
	memset(ctx, 0, sizeof(luat_dep_ctx_t));
}

static int luat_cmd_pack_with_dep_strip(const char **paths, size_t count)
{
	luat_dep_ctx_t ctx = {0};
	luat_dep_file_t *main_file = NULL;
	int ret = 0;
	for (size_t i = 0; i < count; i++)
	{
		// 先把所有输入目录/文件扁平收集到同一个候选集, 再统一从 main.lua 求依赖闭包
		if (luat_cmd_collect_path(&ctx, paths[i], 1))
		{
			ret = -1;
			goto done;
		}
	}
	main_file = luat_cmd_find_file_by_name(&ctx, "main.lua");
	if (main_file == NULL)
	{
		luat_dep_file_t *binary_main = luat_cmd_find_file_by_name(&ctx, "main.luac");
		if (binary_main != NULL)
		{
			ctx.fallback_all_lua = 1;
			LLOGW("main.lua 不存在, 依赖裁剪退回到全量 Lua 打包");
		}
		else
		{
			LLOGE("依赖裁剪模式要求存在 main.lua");
			ret = -1;
			goto done;
		}
	}
	if (main_file && luat_cmd_mark_required(&ctx, main_file, "main.lua"))
	{
		ret = -1;
		goto done;
	}
	if (ctx.fallback_all_lua)
	{
		// 回退模式下保留旧行为: 所有 Lua/luac/luae 全量打包, 资源文件照常保留
		for (size_t i = 0; i < ctx.count; i++)
		{
			if (ctx.files[i].kind != LUAT_DEP_FILE_RESOURCE)
			{
				ctx.files[i].selected = 1;
			}
		}
	}
	for (size_t i = 0; i < ctx.count; i++)
	{
		if (ctx.files[i].kind == LUAT_DEP_FILE_RESOURCE || ctx.files[i].selected)
		{
			if (add_onefile(ctx.files[i].fullpath))
			{
				ret = -1;
				goto done;
			}
		}
		else
		{
			ctx.skipped_lua_count++;
			//LLOGD("剔除未引用脚本 %s", ctx.files[i].name);
		}
	}
	if (ctx.skipped_lua_count > 0)
	{
		LLOGI("依赖裁剪完成, 文件总数 %d, 剔除脚本 %d", (int)ctx.count, (int)ctx.skipped_lua_count);
	}
done:
	luat_cmd_free_dep_ctx(&ctx);
	return ret;
}

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
	char **input_paths = NULL;
	size_t input_count = 0;
	size_t input_capacity = 0;
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
			cfg_has_preload = 1;
			continue;
		}
		if (is_opts("--ldb=", arg))
		{
			if (luat_cmd_load_luadb(arg + strlen("--ldb=")))
			{
				LLOGE("加载luadb镜像失败");
				return -1;
			}
			cfg_has_preload = 1;
			continue;
		}
		// 加载LuaTools项目文件: 始终收集路径到 input_paths, 策略在循环后统一决定
		if (is_opts("--load_luatools=", arg))
		{
			const char *ini = arg + strlen("--load_luatools=");
			if (luat_cmd_collect_luatools_paths(ini, &input_paths, &input_count, &input_capacity))
			{
				LLOGE("收集luatools项目路径失败");
				goto cleanup_err;
			}
			continue;
		}
		if (is_opts("--llt=", arg))
		{
			const char *ini = arg + strlen("--llt=");
			if (luat_cmd_collect_luatools_paths(ini, &input_paths, &input_count, &input_capacity))
			{
				LLOGE("收集luatools项目路径失败");
				goto cleanup_err;
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

		if (!strcmp("--noexit", arg) || is_opts("--noexit=", arg))
		{
			if (!strcmp("--noexit", arg) || !strcmp("--noexit=1", arg)) {
				cfg_noexit = 1;
			}
			continue;
		}

		if (is_opts("--dep_strip=", arg))
		{
			// 开关:默认已开启
			if (!strcmp("--dep_strip=1", arg)) {
				cfg_dep_strip = 1;
			}
			else if (!strcmp("--dep_strip=0", arg)) {
				cfg_dep_strip = 0;
			}
			continue;
		}

		if (arg[0] == '-')
		{
			continue;
		}
		// 位置参数: 始终收集到 input_paths, 策略在循环后统一决定
		if (input_count + 1 > input_capacity)
		{
			size_t next_capacity = input_capacity == 0 ? 4 : input_capacity * 2;
			char **next_paths = realloc(input_paths, next_capacity * sizeof(char *));
			if (next_paths == NULL)
			{
				LLOGE("内存不足, 无法缓存待分析路径");
				goto cleanup_err;
			}
			input_paths = next_paths;
			input_capacity = next_capacity;
		}
		char *dup = strdup(arg);
		if (dup == NULL)
		{
			LLOGE("内存不足, strdup路径失败");
			goto cleanup_err;
		}
		input_paths[input_count++] = dup;
	}

	if (input_count > 0)
	{
		if (cfg_has_preload)
		{
			// --ldb= 预加载了二进制 luadb, input_paths 作为补充库目录, 全量添加
			LLOGI("检测到预加载项目, 位置路径作为补充库全量添加 (共 %d 个路径)", (int)input_count);
			for (size_t i = 0; i < input_count; i++)
			{
				if (check_file_path(input_paths[i]) == NULL)
				{
					goto cleanup_err;
				}
			}
		}
		else if (cfg_dep_strip)
		{
			// 统一分析 main.lua 的静态依赖闭包, 只打入命中的脚本和全部资源文件
			if (luat_cmd_pack_with_dep_strip((const char **)input_paths, input_count))
			{
				goto cleanup_err;
			}
		}
		else
		{
			// dep_strip=0: 全量添加所有收集到的路径
			for (size_t i = 0; i < input_count; i++)
			{
				if (check_file_path(input_paths[i]) == NULL)
				{
					goto cleanup_err;
				}
			}
		}
	}
	for (size_t i = 0; i < input_count; i++) free(input_paths[i]);
	free(input_paths);
	input_paths = NULL;

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

cleanup_err:
	for (size_t i = 0; i < input_count; i++) free(input_paths[i]);
	free(input_paths);
	return -1;
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
						//LLOGD("目录行 %s", ret);
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

// 解析 LuaTools INI 文件, 将其中的文件路径收集到 paths 数组中(不立即打包), 供依赖分析使用
static int luat_cmd_collect_luatools_paths(const char *ini_path, char ***ppaths, size_t *pcount, size_t *pcapacity)
{
	long len = 0;
	FILE *f = fopen(ini_path, "rb");
	if (!f)
	{
		LLOGE("无法打开luatools项目文件 %s", ini_path);
		return -1;
	}
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);
	char *buf = malloc(len + 1);
	if (buf == NULL)
	{
		fclose(f);
		LLOGE("luatools项目文件太大,内存放不下 %s", ini_path);
		return -1;
	}
	fread(buf, len, 1, f);
	fclose(f);
	buf[len] = 0;

	char *cur = buf;
	char *line_start = cur;
	char dirline[512] = {0};
	char rpath[1024] = {0};
	int ret = 0;

	while (cur[0] != 0)
	{
		if (cur[0] == '\r' || cur[0] == '\n')
		{
			if (line_start != cur)
			{
				cur[0] = 0;
				size_t retlen = strlen(line_start);
				if (!strcmp("[info]", line_start))
				{
					/* skip */
				}
				else if (retlen > 5)
				{
					if (line_start[0] == '[' && line_start[retlen - 1] == ']')
					{
						memcpy(dirline, line_start + 1, retlen - 2);
						dirline[retlen - 2] = 0;
					}
					else if (dirline[0])
					{
						// 找到 '=' 或 ' ' 截断, 取文件名部分
						for (size_t i = 0; i < retlen; i++)
						{
							if (line_start[i] == ' ' || line_start[i] == '=')
							{
								line_start[i] = 0;
								memset(rpath, 0, sizeof(rpath));
								size_t dlen = strlen(dirline);
								memcpy(rpath, dirline, dlen);
#ifdef LUA_USE_WINDOWS
								rpath[dlen] = '\\';
#else
								rpath[dlen] = '/';
#endif
								memcpy(rpath + dlen + 1, line_start, strlen(line_start));
								LLOGI("收集文件 %s", rpath);
								// 追加 strdup 到 paths 数组
								if (*pcount + 1 > *pcapacity)
								{
									size_t next_cap = *pcapacity == 0 ? 16 : *pcapacity * 2;
									char **next = realloc(*ppaths, next_cap * sizeof(char *));
									if (next == NULL)
									{
										LLOGE("内存不足, 无法收集INI路径");
										ret = -1;
										goto done;
									}
									*ppaths = next;
									*pcapacity = next_cap;
								}
								char *dup = strdup(rpath);
								if (dup == NULL)
								{
									LLOGE("内存不足, strdup失败");
									ret = -1;
									goto done;
								}
								(*ppaths)[(*pcount)++] = dup;
								break;
							}
						}
					}
				}
			}
			line_start = cur + 1;
		}
		cur++;
	}

done:
	free(buf);
	return ret;
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
	size_t plen = strlen(path);
	if (plen == 0 || plen >= 512)
	{
		LLOGD("文件长度不对劲 %d %s", plen, path);
		return NULL;
	}
	// 若路径不以 / 或 \ 结尾, 先尝试 opendir 检测是否为目录
	char last = path[plen - 1];
	if (last != '/' && last != '\\')
	{
		DIR *dp_probe = opendir(path);
		if (dp_probe != NULL)
		{
			closedir(dp_probe);
			// 补上尾斜杠后递归
			char pathbuf[512] = {0};
#ifdef LUA_USE_WINDOWS
			snprintf(pathbuf, sizeof(pathbuf), "%s\\", path);
#else
			snprintf(pathbuf, sizeof(pathbuf), "%s/", path);
#endif
			return check_file_path_depth(pathbuf, depth);
		}
		if (add_onefile(path))
			return NULL;
		return luadb_ptr;
	}
	// 目录模式 (last == '/' 或 '\\')
	else
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
