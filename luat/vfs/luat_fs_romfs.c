#include "luat_base.h"
#include "luat_fs.h"

#include "luat_malloc.h"
#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

typedef struct romfs_file
{
    uint32_t next_offset;
    uint32_t spec;
    uint32_t size;
    uint32_t checksum;
    char name[16];
} romfs_file_t;

typedef struct romfs_fd
{
    romfs_file_t *file;
    size_t offset;
} romfs_fd_t;

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

FILE *luat_vfs_romfs_fopen(void *userdata, const char *filename, const char *mode)
{
    // LLOGD("open romfs %s", filename);
    char *ptr = (char *)userdata;
    romfs_file_t *file = (romfs_file_t *)(ptr + sizeof(romfs_head_t));
    if (strcmp("r", mode) && strcmp("rb", mode))
    {
        return NULL; // romfs 是只读文件系统
    }

    while (1)
    {
        if (!memcmp(".", file->name, 2) || !memcmp("..", file->name, 3))
        {
            // pass
        }
        else
        {
            if (strcmp(file->name, filename) == 0)
            {
                romfs_fd_t *fd = luat_heap_malloc(sizeof(romfs_fd_t));
                if (fd == NULL)
                {
                    LLOGE("out of memory when malloc luat_fs_romfs_t");
                    return NULL;
                }
                fd->offset = 0;
                fd->file = file;
                return (FILE *)fd;
            }
        }
        if ((file->next_offset & 0xFFFFFFF0) == 0)
            break;
        file = (romfs_file_t *)(ptr + sizeof(romfs_head_t) + (file->next_offset & 0xFFFFFFF0));
    }
    return NULL;
}

int luat_vfs_romfs_getc(void *userdata, FILE *stream)
{
    // LLOGD("getc %p %p", userdata, stream);
    romfs_fd_t *fd = (romfs_fd_t *)stream;
    // LLOGD("getc %p %p %d %d", userdata, stream, fd->offset, fd->size);
    if (fd->offset < fd->file->size)
    {
        uint8_t c = FDATA(fd)[fd->offset];
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
        fd->offset = fd->file->size - offset;
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
    return fd->offset >= fd->file->size ? 1 : 0;
}

int luat_vfs_romfs_ferror(void *userdata, FILE *stream)
{
    return 0;
}

size_t luat_vfs_romfs_fread(void *userdata, void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    romfs_fd_t *fd = (romfs_fd_t *)stream;
    // LLOGD("fread %p %p %d %d", userdata, stream, fd->size, fd->offset);
    // LLOGD("fread2 %p %p %d %d", userdata, stream, size * nmemb, fd->offset);
    size_t read_size = size * nmemb;
    if (fd->offset + read_size > FSIZE(fd))
    {
        read_size = FSIZE(fd) - fd->offset;
    }
    memcpy(ptr, FDATA(fd) + fd->offset, read_size);
    fd->offset += read_size;
    return read_size;
}

int luat_vfs_romfs_fexist(void *userdata, const char *filename)
{
    // LLOGD("open romfs %s", filename);
    char *ptr = (char *)userdata;
    romfs_file_t *file = (romfs_file_t *)(ptr + sizeof(romfs_head_t));

    while (1)
    {
        if (!memcmp(".", file->name, 2) || !memcmp("..", file->name, 3))
        {
            // pass
        }
        else
        {
            if (strcmp(file->name, filename) == 0)
            {
                return 1;
            }
        }
        if ((file->next_offset & 0xFFFFFFF0) == 0)
            break;
        file = (romfs_file_t *)(ptr + sizeof(romfs_head_t) + (file->next_offset & 0xFFFFFFF0));
    }
    return 0;
}

size_t luat_vfs_romfs_fsize(void *userdata, const char *filename)
{
    // LLOGD("open romfs %s", filename);
    char *ptr = (char *)userdata;
    romfs_file_t *file = (romfs_file_t *)(ptr + sizeof(romfs_head_t));

    while (1)
    {
        if (!memcmp(".", file->name, 2) || !memcmp("..", file->name, 3))
        {
            // pass
        }
        else
        {
            if (strcmp(file->name, filename) == 0)
            {
                return file->size;
            }
        }
        if ((file->next_offset & 0xFFFFFFF0) == 0)
            break;
        file = (romfs_file_t *)(ptr + sizeof(romfs_head_t) + (file->next_offset & 0xFFFFFFF0));
    }
    return 0;
}

int luat_vfs_romfs_mount(void **userdata, luat_fs_conf_t *conf)
{
    romfs_head_t *head = (romfs_head_t *)conf->busname;
    if (memcmp(head->magic, "-rom1fs-", 8))
    {
        LLOGI("Not ROMFS at %p", head);
        return -1;
    }
    // TODO 加个 checkfs函数
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

int luat_vfs_romfs_lsdir(void *userdata, char const *_DirName, luat_fs_dirent_t *ents, size_t offset, size_t len)
{
    //romfs_head_t *head = (romfs_head_t *)userdata;
    const char *ptr = (const char *)userdata;
    int counter = 0;
    int count_down = offset;
    romfs_file_t *file = (romfs_file_t *)(ptr + sizeof(romfs_head_t));
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
        if ((file->next_offset & 0xFFFFFFF0) == 0)
            break;
        file = (romfs_fd_t *)(ptr + sizeof(romfs_head_t) + (file->next_offset & 0xFFFFFFF0));
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
