#include "luat_base.h"
#include "luat_fs.h"

#include "luat_mem.h"
#define LUAT_LOG_TAG "romfs"
#include "luat_log.h"
#include "luat_romfs.h"

#define ROMFS_DEBUG 0
#if ROMFS_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif


static uint32_t toInt32(uint8_t buff[4]) {
    uint32_t ret = 0;
    ret += (buff[0] << 24);
    ret += (buff[1] << 16);
    ret += (buff[2] << 8);
    ret += (buff[3] << 0);
    return ret;
}

// typedef struct luat_fs_romfs
// {
//     size_t count;
//     romfs_file_t *files[256 - 1];
// }luat_fs_romfs_t;

typedef struct romfs_head
{
    char magic[8];
    size_t count;
    size_t checksum;
    char volume[16];
} romfs_head_t;

#define FDATA(fd) ((char *)(fd) + sizeof(romfs_file_t))
#define FSIZE(fd) (fd->file->size)

#ifdef LUAT_USE_FS_VFS

static int romfs_find(luat_romfs_ctx* fs, const char* filename, romfs_file_t *file) {
    int ret = 0;
    int offset = sizeof(romfs_head_t);
    // LLOGD("romfs_find %s", filename);
    ret = fs->read(fs->userdata, (char*)file, offset, sizeof(romfs_file_t));
    while (1)
    {
        // LLOGD("name %s", file->name);
        if (!memcmp(".", file->name, 2) || !memcmp("..", file->name, 3))
        {
            // pass
        }
        else
        {
            if (strcmp(file->name, filename) == 0)
            {
                // LLOGD("found %s %08X %08X", file->name, toInt32(file->size), toInt32(file->next_offset));
                return offset;
            }
        }
        if ((toInt32(file->next_offset) & 0xFFFFFFF0) == 0)
            break;
        // LLOGD("file->next_offset %08X", toInt32(file->next_offset));
        offset = sizeof(romfs_head_t) + (toInt32(file->next_offset) & 0xFFFFFFF0);
        // LLOGD("Next offset %08X", offset);
        ret = fs->read(fs->userdata, (char*)file, offset, sizeof(romfs_file_t));
        if (ret < 0) {
            LLOGW("romfs ERROR find %d", ret);
            return -1;
        }
    }
    LLOGD("NOT found %s", filename);
    return 0;
}

FILE *luat_vfs_romfs_fopen(void *userdata, const char *filename, const char *mode)
{
    // LLOGD("open romfs >> ============== %s", filename);
    // int ret = 0;
    size_t offset = 0;
    luat_romfs_ctx* fs = (luat_romfs_ctx*)userdata;
    romfs_file_t tfile = {0};
    if (memcmp("r", mode, 1))
    {
        return NULL; // romfs 是只读文件系统
    }
    offset = romfs_find(fs, filename, &tfile);
    if (offset > 0) {
        romfs_fd_t *fd = luat_heap_malloc(sizeof(romfs_fd_t));
        if (fd == NULL)
        {
            LLOGE("out of memory when malloc luat_fs_romfs_t");
            return NULL;
        }
        fd->offset = 0;
        fd->addr = offset;
        // LLOGD("fopen addr %08X", fd->addr);
        memcpy(&fd->file, &tfile, sizeof(romfs_file_t));
        return (FILE *)fd;
    }
    return NULL;
}

int luat_vfs_romfs_getc(void *userdata, FILE *stream)
{
    // LLOGD("getc %p %p", userdata, stream);
    romfs_fd_t *fd = (romfs_fd_t *)stream;
    luat_romfs_ctx* fs = (luat_romfs_ctx*)userdata;
    // LLOGD("getc %p %p %d %d", userdata, stream, fd->offset, fd->size);
    char c = 0;
    if (fd->offset < toInt32(fd->file.size))
    {
        fs->read(fs->userdata, &c, fd->offset + fd->addr + sizeof(romfs_file_t), 1);
        fd->offset++;
        // LLOGD("getc %02X", c);
        return c;
    }
    return -1;
}

int luat_vfs_romfs_fseek(void *userdata, FILE *stream, long int offset, int origin)
{
    // LLOGD("fseek %p %p %d %d", userdata, stream, offset, origin);
    romfs_fd_t *fd = (romfs_fd_t *)stream;
    if (origin == SEEK_CUR)
    {
        fd->offset += offset;
        return 0;
    }
    else if (origin == SEEK_SET)
    {
        fd->offset = offset;
        return 0;
    }
    else
    {
        fd->offset = toInt32(fd->file.size) - offset;
        return 0;
    }
}

int luat_vfs_romfs_ftell(void *userdata, FILE *stream)
{
    romfs_fd_t *fd = (romfs_fd_t *)stream;
    // LLOGD("tell %p %p %d %d", userdata, stream, fd->size, fd->offset);
    return fd->offset;
}

int luat_vfs_romfs_fclose(void *userdata, FILE *stream)
{
    romfs_fd_t *fd = (romfs_fd_t *)stream;
    // LLOGD("fclose %p %p %d %d", userdata, stream, fd->size, fd->offset);
    luat_heap_free(fd);
    return 0;
}

int luat_vfs_romfs_feof(void *userdata, FILE *stream)
{
    romfs_fd_t *fd = (romfs_fd_t *)stream;
    // LLOGD("feof %p %p %d %d", userdata, stream, fd->size, fd->offset);
    return fd->offset >= toInt32(fd->file.size) ? 1 : 0;
}

int luat_vfs_romfs_ferror(void *userdata, FILE *stream)
{
    return 0;
}

size_t luat_vfs_romfs_fread(void *userdata, void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    romfs_fd_t *fd = (romfs_fd_t *)stream;
    luat_romfs_ctx* fs = (luat_romfs_ctx*)userdata;
    // LLOGD("fread %p %p %d %d", userdata, stream, fd->size, fd->offset);
    // LLOGD("fread2 %p %p %d %d", userdata, stream, size * nmemb, fd->offset);
    size_t read_size = size * nmemb;
    if (fd->offset + read_size > toInt32(fd->file.size))
    {
        read_size = toInt32(fd->file.size) - fd->offset;
    }
    // memcpy(ptr, FDATA(fd) + fd->offset, read_size);
    fs->read(fs->userdata, ptr, fd->offset + fd->addr + sizeof(romfs_file_t), read_size);
    fd->offset += read_size;
    return read_size;
}

int luat_vfs_romfs_fexist(void *userdata, const char *filename)
{
    // LLOGD("open romfs %s", filename);
    luat_romfs_ctx* fs = (luat_romfs_ctx*)userdata;
    romfs_file_t file = {0};
    int ret = romfs_find(fs, filename, &file);
    // LLOGD("found? %s %d", filename, ret);
    return ret > 0 ? 1 : 0;
}

size_t luat_vfs_romfs_fsize(void *userdata, const char *filename)
{
    // LLOGD("open romfs %s", filename);
    luat_romfs_ctx* fs = (luat_romfs_ctx*)userdata;
    romfs_file_t file = {0};
    int ret = romfs_find(fs, filename, &file);
    if (ret > 0) {
        return toInt32(file.size);
    }
    return 0;
}

int luat_vfs_romfs_mount(void **userdata, luat_fs_conf_t *conf)
{
    // LLOGD("luat_vfs_romfs_mount ==================");
    luat_romfs_ctx* fs = (luat_romfs_ctx*)conf->busname;
    // LLOGD("luat_romfs_ctx %p", fs);
    // LLOGD("luat_romfs_ctx %p", fs->read);
    // LLOGD("luat_romfs_ctx %p", fs->userdata);
    romfs_head_t head = {0};
    fs->read(fs->userdata, (char*)&head, 0, sizeof(romfs_head_t));
    if (memcmp(head.magic, "-rom1fs-", 8))
    {
        LLOGI("Not ROMFS at %p", &head);
        return -1;
    }
    // LLOGD("romfs mounted");
    *userdata = conf->busname;
    return 0;
}

int luat_vfs_romfs_umount(void *userdata, luat_fs_conf_t *conf)
{
    return 0;
}

int luat_vfs_romfs_info(void *userdata, const char *path, luat_fs_info_t *conf)
{
    memcpy(conf->filesystem, "romfs", strlen("romfs") + 1);
    conf->type = 0;
    conf->total_block = 0;
    conf->block_used = 0;
    conf->block_size = 512;
    return 0;
}

int luat_vfs_romfs_lsdir(void *userdata, char const *_DirName, luat_fs_dirent_t *ents, size_t ent_offset, size_t len)
{
    luat_romfs_ctx* fs = (luat_romfs_ctx*)userdata;
    int offset = sizeof(romfs_head_t);
    // romfs_head_t head = {0};
    romfs_file_t tfile = {0};
    // fs->read(fs->addr, &head, sizeof(romfs_head_t));
    int counter = 0;
    int count_down = ent_offset;
    romfs_file_t *file = &tfile;
    fs->read(fs->userdata, (char*)file, offset, sizeof(romfs_file_t));
    while (1)
    {
        if (counter >= len)
            break;
        if (!memcmp(".", file->name, 2) || !memcmp("..", file->name, 3))
        {
            // pass
        }
        else if (count_down > 0)
        {
            count_down--;
        }
        else
        {
            ents[counter].d_type = 0;
            strcpy(ents[counter].d_name, file->name);
            counter++;
        }
        if ((toInt32(file->next_offset) & 0xFFFFFFF0) == 0)
            break;
        offset = sizeof(romfs_head_t) + (toInt32(file->next_offset) & 0xFFFFFFF0);
        fs->read(fs->userdata, (char*)file, offset, sizeof(romfs_file_t));
    }
    return 0;
}

#define T(name) .name = luat_vfs_romfs_##name
const struct luat_vfs_filesystem vfs_fs_romfs = {
    .name = "romfs",
    .opts = {
        .mkfs = NULL,
        T(mount),
        .umount = NULL,
        .mkdir = NULL,
        .rmdir = NULL,
        .remove = NULL,
        .rename = NULL,
        T(fsize),
        T(fexist),
        T(info),
        T(lsdir)},
    .fopts = {T(fopen), T(getc), T(fseek), T(ftell), T(fclose), T(feof), T(ferror), T(fread), .fwrite = NULL}};
#endif
