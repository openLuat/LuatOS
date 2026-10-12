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

typedef struct {
    luat_romfs_ctx_t ctx;     // 挂载时拷贝, 调用方 ctx 不需保活
    uint32_t img_size;        // 头部 full_size, 所有读的边界
    uint32_t root_off;        // 根目录头偏移
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

//----------------- VFS 文件操作 -----------------

FILE* luat_vfs_romfs_fopen(void* userdata, const char* filename, const char* mode) {
    if (strcmp(mode, "r") != 0 && strcmp(mode, "rb") != 0) {
        LLOGW("romfs is readonly, reject mode %s", mode);
        return NULL;
    }
    romfs_mount_t* fs = (romfs_mount_t*)userdata;
    romfs_hdr_t h;
    if (romfs_resolve(fs, filename, &h)) return NULL;
    if (h.type != ROMFS_T_FILE) return NULL;                // 目录/设备等不可打开
    romfs_fd_t* fd = luat_heap_malloc(sizeof(romfs_fd_t));
    if (fd == NULL) {
        LLOGE("out of memory when malloc romfs_fd_t");
        return NULL;
    }
    fd->data_off = h.data_off;
    fd->size     = h.size;
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
    romfs_hdr_t h;
    return romfs_resolve((romfs_mount_t*)userdata, filename, &h) == 0 ? 1 : 0;
}

size_t luat_vfs_romfs_fsize(void* userdata, const char* filename) {
    romfs_hdr_t h;
    if (romfs_resolve((romfs_mount_t*)userdata, filename, &h) == 0 && h.type == ROMFS_T_FILE)
        return h.size;
    return 0;
}

int luat_vfs_romfs_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t ent_offset, size_t len) {
    romfs_mount_t* fs = (romfs_mount_t*)userdata;
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
    *userdata = fs;
    LLOGI("romfs mounted, image size %u", (unsigned int)fs->img_size);
    return 0;
}

int luat_vfs_romfs_umount(void* userdata, luat_fs_conf_t* conf) {
    (void)conf;
    if (userdata) luat_heap_free(userdata);
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
