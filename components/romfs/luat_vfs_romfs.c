#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "romfs"
#include "luat_log.h"
#include "luat_romfs.h"
#include "string.h"
#include "stdint.h"

#ifdef LUAT_USE_FS_VFS

#define ROMFS_MAGIC      "-rom1fs-"
#define ROMFS_ALIGN      16
#define ROMFS_HEAD_FIXED 16   // magic(8)+full_size(4)+cksum(4)
#define ROMFS_FH_FIXED   16   // next(4)+spec(4)+size(4)+cksum(4)

#define ROMFS_T_HARDLINK 0
#define ROMFS_T_DIR      1
#define ROMFS_T_FILE     2
#define ROMFS_T_SYMLINK  3
#define ROMFS_T_BROKEN   0xFF    // 链接目标不可达(如悬空硬链接), 按"不存在"处理

#if LUAT_ROMFS_USE_DIR_CACHE
// 目录树缓存节点: mount 时从镜像全量构建, 运行时路径解析/lsdir 只走内存
typedef struct {
    uint32_t data_off;      // 文件数据偏移(FILE); 软链接为目标串偏移(SYMLINK)
    uint32_t size;          // 数据长度
    int32_t  first_child;   // DIR: 首个子节点索引, -1=无
    int32_t  next_sibling;  // 兄弟链下一节点索引, -1=链尾
    int32_t  alias;         // HARDLINK: 目标节点索引(构建期先暂存目标头偏移); 其他 -1
    uint8_t  type;          // ROMFS_T_DIR/FILE/SYMLINK/HARDLINK/BROKEN
    uint8_t  name_too_long; // 1=名字超 LUAT_ROMFS_MAX_NAME: 不参与按名匹配/lsdir, 但可被硬链接引用
    char     name[LUAT_ROMFS_MAX_NAME + 1];
} romfs_cnode_t;
#endif

typedef struct {
    luat_romfs_ctx_t ctx;     // 挂载时拷贝, 调用方 ctx 不需保活
    uint32_t img_size;        // 头部 full_size, 所有读的边界
    uint32_t root_off;        // 根目录头偏移
#if LUAT_ROMFS_USE_DIR_CACHE
    romfs_cnode_t* cache;     // 目录树缓存(单块分配), umount 时释放
    uint32_t cache_cnt;       // 节点总数(含根)
    int32_t  root_idx;        // 根节点索引
#endif
} romfs_mount_t;

typedef struct {
    uint32_t off;             // 本头绝对偏移
    uint32_t next;            // 下一兄弟头偏移(0=链尾)
    uint32_t spec;            // spec.info
    uint32_t size;            // 数据长度
    uint32_t data_off;        // 数据绝对偏移
    uint8_t  type;            // next 低4位
    uint8_t  name_too_long;   // 名字超 LUAT_ROMFS_MAX_NAME, 永不匹配
    char     name[LUAT_ROMFS_MAX_NAME + 1];
} romfs_hdr_t;

typedef struct {
    uint32_t data_off;
    uint32_t size;
    uint32_t pos;
    int      err;             // 粘性错误标志, ferror 用
} romfs_fd_t;

static uint32_t be32(const uint8_t* p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

// 统一读入口: 边界检查(uint64中间值, 防32位回绕) + 双后端
static int romfs_read(romfs_mount_t* fs, uint32_t offset, void* buff, uint32_t len) {
    if (len == 0) return 0;
    if ((uint64_t)offset + (uint64_t)len > (uint64_t)fs->img_size) return -1;
    if (fs->ctx.read) {
        int ret = fs->ctx.read(fs->ctx.userdata, (char*)buff, (size_t)offset, (size_t)len);
        return ret == (int)len ? 0 : -1;
    }
    memcpy(buff, (const char*)fs->ctx.userdata + offset, len);
    return 0;
}

// 读文件头: 固定16字节 + 变长文件名(16字节块扫描到NUL, 防超长/防环)
static int romfs_read_hdr(romfs_mount_t* fs, uint32_t off, romfs_hdr_t* hdr) {
    uint8_t fixed[ROMFS_FH_FIXED];
    if (off & (ROMFS_ALIGN - 1)) return -1;                 // 头必须16对齐
    if (romfs_read(fs, off, fixed, ROMFS_FH_FIXED)) return -1;
    hdr->off  = off;
    hdr->next = be32(fixed) & 0xFFFFFFF0u;
    hdr->type = (uint8_t)(be32(fixed) & 0x0Fu);
    hdr->spec = be32(fixed + 4);
    hdr->size = be32(fixed + 8);
    hdr->name_too_long = 0;
    uint32_t field_len = 0;                                 // 已扫描名字字节数(不含NUL)
    uint32_t stored = 0;
    for (;;) {
        uint8_t block[ROMFS_ALIGN];
        if (romfs_read(fs, off + ROMFS_FH_FIXED + field_len, block, ROMFS_ALIGN)) return -1;
        int nul = -1;
        for (int i = 0; i < ROMFS_ALIGN; i++) {
            if (block[i] == 0) { nul = i; break; }
        }
        uint32_t chunk = (nul >= 0) ? (uint32_t)nul : ROMFS_ALIGN;
        uint32_t room  = LUAT_ROMFS_MAX_NAME - stored;
        uint32_t take  = chunk < room ? chunk : room;
        if (take) memcpy(hdr->name + stored, block, take);
        stored += take;
        field_len += chunk;
        if (nul >= 0) break;
        if (stored >= LUAT_ROMFS_MAX_NAME) hdr->name_too_long = 1;
    }
    hdr->name[stored] = 0;
    hdr->data_off = off + ROMFS_FH_FIXED + ((field_len + 1 + ROMFS_ALIGN - 1) & ~(ROMFS_ALIGN - 1u));
    return 0;
}

#if LUAT_ROMFS_VERIFY_HEAD_CKSUM
// BE u32 求和(尾部零填充到4字节), 和为0校验通过
static int romfs_cksum_ok(romfs_mount_t* fs, uint32_t off, uint32_t region_len) {
    uint8_t buf[64];
    uint32_t sum = 0;
    uint32_t len = region_len < 512 ? region_len : 512;
    if ((uint64_t)off + len > fs->img_size) len = fs->img_size - off;
    len = (len + 3) & ~3u;
    for (uint32_t i = 0; i < len; i += sizeof(buf)) {
        uint32_t n = len - i;
        if (n > sizeof(buf)) n = sizeof(buf);
        memset(buf, 0, sizeof(buf));
        if (romfs_read(fs, off + i, buf, n)) return 0;
        for (uint32_t j = 0; j + 4 <= n; j += 4) sum += be32(buf + j);
    }
    return sum == 0;
}
#endif

#if !LUAT_ROMFS_USE_DIR_CACHE
// 在 dir 的直接子节点链中找 comp[0..comp_len); 0=找到 1=未找到 -1=错误
static int romfs_dir_find(romfs_mount_t* fs, uint32_t dir_off, const char* comp, uint32_t comp_len, romfs_hdr_t* out) {
    romfs_hdr_t dir;
    if (romfs_read_hdr(fs, dir_off, &dir)) return -1;
    if (dir.type != ROMFS_T_DIR) return -1;
    uint32_t cur = dir.spec;
    uint32_t guard = fs->img_size / ROMFS_ALIGN + 1;        // 链长度上限, 防损坏镜像成环
    while (cur && guard--) {
        romfs_hdr_t h;
        if (romfs_read_hdr(fs, cur, &h)) return -1;
        if (!h.name_too_long
            && !(h.name[0] == '.' && h.name[1] == 0)                     // 跳过 "."
            && !(h.name[0] == '.' && h.name[1] == '.' && h.name[2] == 0) // 跳过 ".."
            && strlen(h.name) == comp_len && memcmp(h.name, comp, comp_len) == 0) {
            *out = h;
            return 0;
        }
        cur = h.next;
    }
    return 1;
}

// 解引用: 硬链接跳到目标头; 符号链接展开为 目标+剩余路径 写回 pbuf
// 返回 0=已是非链接节点; 2=符号链接, *pp 已指向 pbuf, 调用方须重启解析; -1=错误
static int romfs_deref(romfs_mount_t* fs, romfs_hdr_t* h, int* link_depth, char* pbuf, size_t pbuf_size, const char** pp) {
    int guard = LUAT_ROMFS_MAX_DEPTH;
    while (h->type == ROMFS_T_HARDLINK) {
        if (!guard--) return -1;
        if (h->spec == 0 || romfs_read_hdr(fs, h->spec, h)) return -1;
    }
    if (h->type != ROMFS_T_SYMLINK) return 0;
    if (++(*link_depth) > LUAT_ROMFS_MAX_DEPTH) return -1;
    char rest[LUAT_ROMFS_MAX_PATH];
    size_t rest_len = strlen(*pp);
    if (rest_len >= sizeof(rest)) return -1;
    memcpy(rest, *pp, rest_len + 1);                        // 先撤下剩余路径, 防 pbuf 重叠
    if (h->size == 0 || h->size >= pbuf_size) return -1;
    if (romfs_read(fs, h->data_off, pbuf, h->size)) return -1;
    size_t n = h->size;
    while (n && pbuf[n - 1] == 0) n--;                      // 容忍尾部NUL
    size_t head = 0;
    while (head < n && pbuf[head] == '/') head++;           // 绝对链接按根相对处理
    if (n - head + (rest_len ? 1 + rest_len : 0) + 1 > pbuf_size) return -1;
    memmove(pbuf, pbuf + head, n - head);
    n -= head;
    if (rest_len) {
        pbuf[n++] = '/';
        memcpy(pbuf + n, rest, rest_len);
        n += rest_len;
    }
    pbuf[n] = 0;
    *pp = pbuf;
    return 2;
}

// 解析挂载点相对路径("a/b.txt", ""=根); 0=找到 1=未找到 -1=错误
static int romfs_resolve(romfs_mount_t* fs, const char* path, romfs_hdr_t* out) {
    if (path == NULL) return -1;
    char pbuf[LUAT_ROMFS_MAX_PATH];
    const char* p = path;
    int link_depth = 0;
restart:;
    romfs_hdr_t h;
    if (romfs_read_hdr(fs, fs->root_off, &h)) return -1;
    while (*p == '/') p++;
    while (*p) {
        int r = romfs_deref(fs, &h, &link_depth, pbuf, sizeof(pbuf), &p);
        if (r == 2) goto restart;
        if (r) return -1;
        if (h.type != ROMFS_T_DIR) return 1;                // 中间组件必须落在目录上
        const char* slash = strchr(p, '/');
        uint32_t clen = slash ? (uint32_t)(slash - p) : (uint32_t)strlen(p);
        if (clen == 0 || (clen == 1 && p[0] == '.')) { p = slash ? slash + 1 : p + clen; continue; }
        if (clen == 2 && p[0] == '.' && p[1] == '.') return 1;   // 不支持 ..
        if (clen > LUAT_ROMFS_MAX_NAME) return 1;
        r = romfs_dir_find(fs, h.off, p, clen, &h);
        if (r) return r;
        p = slash ? slash + 1 : p + clen;
    }
    int r = romfs_deref(fs, &h, &link_depth, pbuf, sizeof(pbuf), &p);
    if (r == 2) goto restart;
    if (r) return -1;
    *out = h;
    return 0;
}
#else
//----------------- 目录树缓存: mount 时全量构建 -----------------
// 三趟: Pass A 计数(同序DFS) → 分配 → Pass B 填充挂链 → 硬链接头偏移换索引
// 软链接保持"存镜像内目标串, 运行时展开"的惰性语义(与镜像内查找版完全一致)

typedef struct {
    romfs_mount_t* fs;
    uint32_t* src_off;   // 每节点镜像头偏移(仅构建期, 用于硬链接偏移→索引)
    uint32_t  count;     // 已计/已建节点数
    int       err;       // 粘性错误
    uint32_t  depth;     // 当前目录嵌套深度(根=0)
} romfs_build_t;

// Pass A: 计入目录自身及其全部子孙; 嵌套超 LUAT_ROMFS_MAX_DIR_DEPTH 或镜像损坏则置 err
static void romfs_cache_count(romfs_build_t* b, uint32_t dir_off) {
    if (b->err) return;
    romfs_hdr_t dir;
    if (romfs_read_hdr(b->fs, dir_off, &dir)) { b->err = 1; return; }
    if (dir.type != ROMFS_T_DIR) { b->err = 1; return; }
    b->count++;                                             // 目录自身
    uint32_t cur = dir.spec;
    uint32_t guard = b->fs->img_size / ROMFS_ALIGN + 1;     // 链长度上限, 防损坏镜像成环
    while (cur && guard--) {
        romfs_hdr_t h;
        if (romfs_read_hdr(b->fs, cur, &h)) { b->err = 1; return; }
        cur = h.next;
        if ((h.name[0] == '.' && h.name[1] == 0) || (h.name[0] == '.' && h.name[1] == '.' && h.name[2] == 0)) continue;
        if (b->depth + 1 > LUAT_ROMFS_MAX_DIR_DEPTH) {
            LLOGW("romfs dir depth over %u, mount failed", (unsigned)LUAT_ROMFS_MAX_DIR_DEPTH);
            b->err = 1; return;
        }
        if (h.type == ROMFS_T_DIR) {
            b->depth++;
            romfs_cache_count(b, h.off);
            b->depth--;
            if (b->err) return;
        }
        else {
            b->count++;
        }
    }
    if (cur) b->err = 1;                                    // guard 耗尽, 镜像损坏成环
}

// 建一个缓存节点(填充基础字段, 挂链由调用方完成); 返回索引, 失败返回 -1
static int32_t romfs_cache_add_node(romfs_build_t* b, const romfs_hdr_t* h) {
    if (b->count >= b->fs->cache_cnt) { b->err = 1; return -1; }   // 与 Pass A 计数不符, 防御
    int32_t idx = (int32_t)b->count++;
    romfs_cnode_t* n = &b->fs->cache[idx];
    memset(n, 0, sizeof(*n));
    n->type = h->type;
    n->name_too_long = h->name_too_long;
    memcpy(n->name, h->name, strlen(h->name) + 1);
    n->size = h->size;
    n->data_off = h->data_off;
    n->first_child = -1;
    n->next_sibling = -1;
    n->alias = -1;
    if (h->type == ROMFS_T_HARDLINK) n->alias = (int32_t)h->spec;  // 暂存目标头偏移, 构建收尾时换索引
    b->src_off[idx] = h->off;
    return idx;
}

// Pass B: 填充 self_idx 的全部直接子节点(递归), 兄弟间按镜像顺序挂 next_sibling
static void romfs_cache_fill(romfs_build_t* b, uint32_t dir_off, int32_t self_idx) {
    if (b->err) return;
    romfs_hdr_t dir;
    if (romfs_read_hdr(b->fs, dir_off, &dir)) { b->err = 1; return; }
    if (dir.type != ROMFS_T_DIR) { b->err = 1; return; }
    int32_t prev = -1;
    uint32_t cur = dir.spec;
    uint32_t guard = b->fs->img_size / ROMFS_ALIGN + 1;
    while (cur && guard--) {
        romfs_hdr_t h;
        if (romfs_read_hdr(b->fs, cur, &h)) { b->err = 1; return; }
        cur = h.next;
        if ((h.name[0] == '.' && h.name[1] == 0) || (h.name[0] == '.' && h.name[1] == '.' && h.name[2] == 0)) continue;
        int32_t idx = romfs_cache_add_node(b, &h);
        if (idx < 0) return;
        if (prev < 0) b->fs->cache[self_idx].first_child = idx;
        else b->fs->cache[prev].next_sibling = idx;
        prev = idx;
        if (h.type == ROMFS_T_DIR) {
            romfs_cache_fill(b, h.off, idx);
            if (b->err) return;
        }
    }
    if (cur) b->err = 1;
}

// 构建目录树缓存; 0=成功 -1=失败(已释放部分分配)
static int romfs_cache_build(romfs_mount_t* fs) {
    romfs_build_t b = {fs, NULL, 0, 0, 0};
    romfs_cache_count(&b, fs->root_off);
    if (b.err || b.count == 0) {
        LLOGW("romfs dir cache count fail");
        return -1;
    }
    fs->cache = luat_heap_malloc(b.count * sizeof(romfs_cnode_t));
    if (fs->cache == NULL) {
        LLOGE("out of memory when malloc romfs dir cache");
        return -1;
    }
    memset(fs->cache, 0, b.count * sizeof(romfs_cnode_t));
    fs->cache_cnt = b.count;
    b.src_off = luat_heap_malloc(b.count * sizeof(uint32_t));
    if (b.src_off == NULL) {
        LLOGE("out of memory when malloc romfs dir cache helper");
        luat_heap_free(fs->cache);
        fs->cache = NULL;
        return -1;
    }
    // 根节点
    romfs_hdr_t root;
    if (romfs_read_hdr(fs, fs->root_off, &root) || root.type != ROMFS_T_DIR) {
        luat_heap_free(b.src_off);
        luat_heap_free(fs->cache);
        fs->cache = NULL;
        return -1;
    }
    b.count = 0;
    fs->root_idx = romfs_cache_add_node(&b, &root);
    if (fs->root_idx < 0) {
        luat_heap_free(b.src_off);
        luat_heap_free(fs->cache);
        fs->cache = NULL;
        return -1;
    }
    romfs_cache_fill(&b, fs->root_off, fs->root_idx);
    if (b.err) {
        LLOGW("romfs dir cache build fail");
        luat_heap_free(b.src_off);
        luat_heap_free(fs->cache);
        fs->cache = NULL;
        return -1;
    }
    // 硬链接: 目标头偏移 → 节点索引; 找不到目标=悬空硬链接, 标记 BROKEN
    for (uint32_t i = 0; i < fs->cache_cnt; i++) {
        romfs_cnode_t* n = &fs->cache[i];
        if (n->type != ROMFS_T_HARDLINK) continue;
        int32_t tgt = -1;
        uint32_t want = (uint32_t)n->alias;
        for (uint32_t j = 0; j < fs->cache_cnt; j++) {
            if (b.src_off[j] == want) { tgt = (int32_t)j; break; }
        }
        if (tgt < 0) {
            n->type = ROMFS_T_BROKEN;
            n->alias = -1;
        }
        else {
            n->alias = tgt;
        }
    }
    luat_heap_free(b.src_off);
    return 0;
}

// 解析挂载点相对路径("a/b.txt", ""=根); 返回节点指针, 未找到/损坏返回 NULL
// 语义与镜像内查找版一致: 软链接根相对展开+重启, 链深≤LUAT_ROMFS_MAX_DEPTH, 不支持 ".."
static romfs_cnode_t* romfs_cache_resolve(romfs_mount_t* fs, const char* path) {
    if (path == NULL) return NULL;
    char pbuf[LUAT_ROMFS_MAX_PATH];
    const char* p = path;
    int link_depth = 0;
restart:;
    romfs_cnode_t* cur = &fs->cache[fs->root_idx];
    while (*p == '/') p++;
    while (*p) {
        if (cur->type != ROMFS_T_DIR) return NULL;          // 中间组件必须落在目录上
        const char* slash = strchr(p, '/');
        uint32_t clen = slash ? (uint32_t)(slash - p) : (uint32_t)strlen(p);
        if (clen == 0 || (clen == 1 && p[0] == '.')) { p = slash ? slash + 1 : p + clen; continue; }
        if (clen == 2 && p[0] == '.' && p[1] == '.') return NULL;   // 不支持 ..
        if (clen > LUAT_ROMFS_MAX_NAME) return NULL;
        romfs_cnode_t* next = NULL;
        for (int32_t i = cur->first_child; i >= 0; i = fs->cache[i].next_sibling) {
            romfs_cnode_t* c = &fs->cache[i];
            if (c->name_too_long) continue;
            if (strlen(c->name) == clen && memcmp(c->name, p, clen) == 0) { next = c; break; }
        }
        if (next == NULL) return NULL;
        cur = next;
        p = slash ? slash + 1 : p + clen;
        // 链接解引用(同 romfs_deref 语义): 硬链接跟索引, 符号链接展开剩余路径并重启
        int guard = LUAT_ROMFS_MAX_DEPTH;
        while (cur->type == ROMFS_T_HARDLINK) {
            if (cur->alias < 0 || !guard--) return NULL;    // 悬空硬链接=损坏
            cur = &fs->cache[cur->alias];
        }
        if (cur->type == ROMFS_T_SYMLINK) {
            if (++link_depth > LUAT_ROMFS_MAX_DEPTH) return NULL;
            char restbuf[LUAT_ROMFS_MAX_PATH];
            size_t rest_len = strlen(p);                    // 剩余路径(末尾组件为空串)
            if (rest_len >= sizeof(restbuf)) return NULL;
            if (rest_len) memcpy(restbuf, p, rest_len + 1); // 先撤下剩余路径, 防 pbuf 重叠
            char tmp[LUAT_ROMFS_MAX_PATH];
            if (cur->size == 0 || cur->size >= sizeof(tmp)) return NULL;
            if (romfs_read(fs, cur->data_off, tmp, cur->size)) return NULL;
            size_t n = cur->size;
            while (n && tmp[n - 1] == 0) n--;               // 容忍尾部NUL
            size_t head = 0;
            while (head < n && tmp[head] == '/') head++;    // 绝对链接按根相对处理
            if (n - head + (rest_len ? 1 + rest_len : 0) + 1 > sizeof(pbuf)) return NULL;
            memcpy(pbuf, tmp + head, n - head);
            n -= head;
            if (rest_len) {
                pbuf[n++] = '/';
                memcpy(pbuf + n, restbuf, rest_len + 1);
            }
            else {
                pbuf[n] = 0;
            }
            p = pbuf;
            goto restart;
        }
        if (cur->type == ROMFS_T_BROKEN) return NULL;
        if (slash == NULL) return cur;                      // 末尾组件(非链接)
    }
    return (cur->type == ROMFS_T_DIR) ? cur : NULL;         // 空路径/尾斜杠 → 目录本身
}
#endif

//----------------- VFS 文件操作 -----------------

FILE* luat_vfs_romfs_fopen(void* userdata, const char* filename, const char* mode) {
    if (strcmp(mode, "r") != 0 && strcmp(mode, "rb") != 0) {
        LLOGW("romfs is readonly, reject mode %s", mode);
        return NULL;
    }
    romfs_mount_t* fs = (romfs_mount_t*)userdata;
    uint32_t data_off, size;
#if LUAT_ROMFS_USE_DIR_CACHE
    romfs_cnode_t* n = romfs_cache_resolve(fs, filename);
    if (n == NULL || n->type != ROMFS_T_FILE) return NULL;  // 目录/设备等不可打开
    data_off = n->data_off;
    size = n->size;
#else
    romfs_hdr_t h;
    if (romfs_resolve(fs, filename, &h)) return NULL;
    if (h.type != ROMFS_T_FILE) return NULL;                // 目录/设备等不可打开
    data_off = h.data_off;
    size = h.size;
#endif
    romfs_fd_t* fd = luat_heap_malloc(sizeof(romfs_fd_t));
    if (fd == NULL) {
        LLOGE("out of memory when malloc romfs_fd_t");
        return NULL;
    }
    fd->data_off = data_off;
    fd->size     = size;
    fd->pos      = 0;
    fd->err      = 0;
    return (FILE*)fd;
}

size_t luat_vfs_romfs_fread(void* userdata, void* ptr, size_t size, size_t nmemb, FILE* stream) {
    romfs_mount_t* fs = (romfs_mount_t*)userdata;
    romfs_fd_t* fd = (romfs_fd_t*)stream;
    uint64_t want = (uint64_t)size * (uint64_t)nmemb;
    if (want > 0x7FFFFFFFu) want = 0x7FFFFFFFu;
    uint32_t avail = fd->size - fd->pos;                    // pos<=size 由 fseek 钳制保证
    uint32_t n = want > avail ? avail : (uint32_t)want;
    if (n && romfs_read(fs, fd->data_off + fd->pos, ptr, n)) {
        fd->err = 1;
        return 0;
    }
    fd->pos += n;
    return n;                                               // 按 luat_fs.h 约定返回实际读取字节数
}

int luat_vfs_romfs_getc(void* userdata, FILE* stream) {
    uint8_t c = 0;
    return luat_vfs_romfs_fread(userdata, &c, 1, 1, stream) == 1 ? (int)c : -1;
}

int luat_vfs_romfs_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    (void)userdata;
    romfs_fd_t* fd = (romfs_fd_t*)stream;
    int64_t base;
    if (origin == SEEK_SET)      base = 0;
    else if (origin == SEEK_CUR) base = (int64_t)fd->pos;
    else if (origin == SEEK_END) base = (int64_t)fd->size;  // POSIX: end + offset
    else return -1;
    int64_t np = base + offset;
    if (np < 0) np = 0;
    if (np > (int64_t)fd->size) np = fd->size;              // 越界钳制
    fd->pos = (uint32_t)np;
    return 0;
}

int luat_vfs_romfs_ftell(void* userdata, FILE* stream) {
    (void)userdata;
    return (int)((romfs_fd_t*)stream)->pos;
}

int luat_vfs_romfs_fclose(void* userdata, FILE* stream) {
    (void)userdata;
    luat_heap_free(stream);
    return 0;
}

int luat_vfs_romfs_feof(void* userdata, FILE* stream) {
    (void)userdata;
    romfs_fd_t* fd = (romfs_fd_t*)stream;
    return fd->pos >= fd->size ? 1 : 0;
}

int luat_vfs_romfs_ferror(void* userdata, FILE* stream) {
    (void)userdata;
    return ((romfs_fd_t*)stream)->err;
}

void* luat_vfs_romfs_mmap(void* userdata, FILE* stream) {
    romfs_mount_t* fs = (romfs_mount_t*)userdata;
    romfs_fd_t* fd = (romfs_fd_t*)stream;
    if (fs->ctx.read) return NULL;                          // 回调模式无线性地址
    return (char*)fs->ctx.userdata + fd->data_off;
}

//----------------- VFS 元数据/目录操作 -----------------

int luat_vfs_romfs_fexist(void* userdata, const char* filename) {
#if LUAT_ROMFS_USE_DIR_CACHE
    return romfs_cache_resolve((romfs_mount_t*)userdata, filename) != NULL ? 1 : 0;
#else
    romfs_hdr_t h;
    return romfs_resolve((romfs_mount_t*)userdata, filename, &h) == 0 ? 1 : 0;
#endif
}

size_t luat_vfs_romfs_fsize(void* userdata, const char* filename) {
#if LUAT_ROMFS_USE_DIR_CACHE
    romfs_cnode_t* n = romfs_cache_resolve((romfs_mount_t*)userdata, filename);
    return (n != NULL && n->type == ROMFS_T_FILE) ? n->size : 0;
#else
    romfs_hdr_t h;
    if (romfs_resolve((romfs_mount_t*)userdata, filename, &h) == 0 && h.type == ROMFS_T_FILE)
        return h.size;
    return 0;
#endif
}

int luat_vfs_romfs_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t ent_offset, size_t len) {
    romfs_mount_t* fs = (romfs_mount_t*)userdata;
#if LUAT_ROMFS_USE_DIR_CACHE
    romfs_cnode_t* dir = romfs_cache_resolve(fs, _DirName);
    if (dir == NULL || dir->type != ROMFS_T_DIR) return -1;
    size_t count = 0, skip = ent_offset;
    for (int32_t i = dir->first_child; i >= 0 && count < len; i = fs->cache[i].next_sibling) {
        romfs_cnode_t* e = &fs->cache[i];
        if (e->name_too_long) continue;
        if (skip) { skip--; continue; }
        uint8_t t = e->type;
        if (t == ROMFS_T_HARDLINK && e->alias >= 0) {       // 硬链接解一层取真实类型
            t = fs->cache[e->alias].type;
        }
        ents[count].d_type = (t == ROMFS_T_DIR) ? 1 : 0;
        size_t name_len = strlen(e->name) + 1;              // e.name 已限长, 含NUL一起拷
        if (name_len > sizeof(ents[count].d_name)) name_len = sizeof(ents[count].d_name);
        memcpy(ents[count].d_name, e->name, name_len);
        ents[count].d_name[sizeof(ents[count].d_name) - 1] = 0;
        ents[count].d_size = 0;                             // VFS 层统一回填
        count++;
    }
    return (int)count;                                      // 契约: 返回条目数
#else
    romfs_hdr_t dir;
    if (romfs_resolve(fs, _DirName, &dir)) return -1;
    if (dir.type != ROMFS_T_DIR) return -1;
    uint32_t cur = dir.spec;
    size_t count = 0, skip = ent_offset;
    uint32_t guard = fs->img_size / ROMFS_ALIGN + 1;
    while (cur && guard-- && count < len) {
        romfs_hdr_t e;
        if (romfs_read_hdr(fs, cur, &e)) return -1;
        int is_dot = (e.name[0] == '.' && e.name[1] == 0) || (e.name[0] == '.' && e.name[1] == '.' && e.name[2] == 0);
        if (!is_dot && !e.name_too_long) {
            if (skip) skip--;
            else {
                uint8_t t = e.type;
                if (t == ROMFS_T_HARDLINK) {                // 硬链接解一层取真实类型
                    romfs_hdr_t t2;
                    if (romfs_read_hdr(fs, e.spec, &t2) == 0) t = t2.type;
                }
                ents[count].d_type = (t == ROMFS_T_DIR) ? 1 : 0;
                size_t name_len = strlen(e.name) + 1;       // e.name 已限长, 含NUL一起拷
                if (name_len > sizeof(ents[count].d_name)) name_len = sizeof(ents[count].d_name);
                memcpy(ents[count].d_name, e.name, name_len);
                ents[count].d_name[sizeof(ents[count].d_name) - 1] = 0;
                ents[count].d_size = 0;                     // VFS 层统一回填
                count++;
            }
        }
        cur = e.next;
    }
    return (int)count;                                      // 契约: 返回条目数
#endif
}

//----------------- 挂载/卸载/信息 -----------------

int luat_vfs_romfs_mount(void** userdata, luat_fs_conf_t* conf) {
    if (conf == NULL || conf->busname == NULL) return -1;
    luat_romfs_ctx_t* in = (luat_romfs_ctx_t*)conf->busname;
    if (in->userdata == NULL) return -1;
    romfs_mount_t tmp;
    memset(&tmp, 0, sizeof(tmp));
    tmp.ctx = *in;
    tmp.img_size = 0xFFFFFFFFu;                             // 首读头部前不限制
    uint8_t head[ROMFS_HEAD_FIXED];
    if (romfs_read(&tmp, 0, head, ROMFS_HEAD_FIXED)) return -1;
    if (memcmp(head, ROMFS_MAGIC, 8) != 0) {
        LLOGW("not a romfs image");
        return -1;
    }
    tmp.img_size = be32(head + 8);
    if (tmp.img_size < 32) return -1;
    // 卷名: 16起按块扫到NUL(上限256), 对齐16得根目录头偏移
    uint32_t vlen = 0;
    int nul_found = 0;
    while (vlen < 256 && !nul_found) {
        uint8_t block[ROMFS_ALIGN];
        if (romfs_read(&tmp, ROMFS_HEAD_FIXED + vlen, block, ROMFS_ALIGN)) return -1;
        for (int i = 0; i < ROMFS_ALIGN; i++) {
            if (block[i] == 0) { nul_found = 1; break; }
            vlen++;
        }
        if (!nul_found) vlen = (vlen + ROMFS_ALIGN - 1) & ~(ROMFS_ALIGN - 1u);
    }
    if (!nul_found) return -1;
    tmp.root_off = ROMFS_HEAD_FIXED + ((vlen + 1 + ROMFS_ALIGN - 1) & ~(ROMFS_ALIGN - 1u));
#if LUAT_ROMFS_VERIFY_HEAD_CKSUM
    if (!romfs_cksum_ok(&tmp, 0, 512)) {
        LLOGW("romfs head checksum error");
        return -1;
    }
#endif
    romfs_hdr_t root;
    if (romfs_read_hdr(&tmp, tmp.root_off, &root) || root.type != ROMFS_T_DIR) {
        LLOGW("romfs root header bad");
        return -1;
    }
    romfs_mount_t* fs = luat_heap_malloc(sizeof(romfs_mount_t));
    if (fs == NULL) {
        LLOGE("out of memory when malloc romfs_mount_t");
        return -1;
    }
    *fs = tmp;
#if LUAT_ROMFS_USE_DIR_CACHE
    if (romfs_cache_build(fs)) {
        LLOGW("romfs dir cache build failed, mount aborted");
        luat_heap_free(fs);
        return -1;
    }
#endif
    *userdata = fs;
#if LUAT_ROMFS_USE_DIR_CACHE
    LLOGI("romfs mounted, image size %u, dir cache %u nodes", (unsigned int)fs->img_size, (unsigned int)fs->cache_cnt);
#else
    LLOGI("romfs mounted, image size %u", (unsigned int)fs->img_size);
#endif
    return 0;
}

int luat_vfs_romfs_umount(void* userdata, luat_fs_conf_t* conf) {
    (void)conf;
    if (userdata) {
#if LUAT_ROMFS_USE_DIR_CACHE
        luat_heap_free(((romfs_mount_t*)userdata)->cache);
#endif
        luat_heap_free(userdata);
    }
    return 0;
}

int luat_vfs_romfs_info(void* userdata, const char* path, luat_fs_info_t* conf) {
    (void)path;
    romfs_mount_t* fs = (romfs_mount_t*)userdata;
    memcpy(conf->filesystem, "romfs", sizeof("romfs"));
    conf->type = 0;
    conf->block_size  = 512;
    conf->total_block = (fs->img_size + 511) / 512;
    conf->block_used  = conf->total_block;                  // 只读镜像, 全部占用
    return 0;
}

//----------------- 只读语义: 写操作显式拒绝 -----------------

int luat_vfs_romfs_remove(void* userdata, const char* filename) {
    (void)userdata;
    LLOGW("romfs is readonly, reject remove %s", filename);
    return -1;
}
int luat_vfs_romfs_rename(void* userdata, const char* old_filename, const char* new_filename) {
    (void)userdata; (void)new_filename;
    LLOGW("romfs is readonly, reject rename %s", old_filename);
    return -1;
}
int luat_vfs_romfs_mkdir(void* userdata, char const* _DirName) {
    (void)userdata;
    LLOGW("romfs is readonly, reject mkdir %s", _DirName);
    return -1;
}
int luat_vfs_romfs_rmdir(void* userdata, char const* _DirName) {
    (void)userdata;
    LLOGW("romfs is readonly, reject rmdir %s", _DirName);
    return -1;
}

#define T(name) .name = luat_vfs_romfs_##name
const struct luat_vfs_filesystem vfs_fs_romfs = {
    .name = "romfs",
    .opts = {
        .mkfs = NULL,
        T(mount),
        T(umount),
        T(mkdir),
        T(rmdir),
        T(remove),
        T(rename),
        T(fsize),
        T(fexist),
        T(info),
        T(lsdir),
    },
    .fopts = {
        T(fopen),
        T(getc),
        T(fseek),
        T(ftell),
        T(fclose),
        T(feof),
        T(ferror),
        T(fread),
        .fwrite = NULL,
        T(mmap),
    }
};
#endif
