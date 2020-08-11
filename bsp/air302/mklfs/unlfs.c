/*
 * Copyright (C) 2015 - 2018, IBEROXARXA SERVICIOS INTEGRALES, S.L.
 * Copyright (C) 2015 - 2018, Jaume Olivé Petrus (jolive@whitecatboard.org)
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *     * The WHITECAT logotype cannot be changed, you can remove it, but you
 *       cannot change it in any way. The WHITECAT logotype is:
 *
 *          /\       /\
 *         /  \_____/  \
 *        /_____________\
 *        W H I T E C A T
 *
 *     * Redistributions in binary form must retain all copyright notices printed
 *       to any local or remote output device. This include any reference to
 *       Lua RTOS, whitecatboard.org, Lua, and other copyright notices that may
 *       appear in the future.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Lua RTOS, a tool for make a LFS file system image
 *
 */

#include "lfs/lfs.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>

static struct lfs_config cfg;
static lfs_t lfs;
static uint8_t *data;

static int lfs_read(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size) {
    memcpy(buffer, data + (block * c->block_size) + off, size);
    return 0;
}

static int lfs_prog(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size) {
	memcpy(data + (block * c->block_size) + off, buffer, size);
    return 0;
}

static int lfs_erase(const struct lfs_config *c, lfs_block_t block) {
    memset(data + (block * c->block_size), 0, c->block_size);
    return 0;
}

static int lfs_sync(const struct lfs_config *c) {
	return 0;
}

static void create_dir(char *src) {
    char *path;
    int ret;

    path = strchr(src, '/');
    if (path) {
        fprintf(stdout, "%s\r\n", path);

		if ((ret = lfs_mkdir(&lfs, path)) < 0) {
			fprintf(stderr,"can't create directory %s: error=%d\r\n", path, ret);
			exit(1);
		}
	}
}

static void create_file(char *src) {
    char *path;
    int ret;

    path = strchr(src, '/');
    if (path) {
        fprintf(stdout, "%s\r\n", path);

        // Open source file
        FILE *srcf = fopen(src,"rb");
        if (!srcf) {
            fprintf(stderr,"can't open source file %s: errno=%d (%s)\r\n", src, errno, strerror(errno));
            exit(1);
        }

        // Open destination file
        lfs_file_t dstf;
        if ((ret = lfs_file_open(&lfs, &dstf, path, LFS_O_WRONLY | LFS_O_CREAT)) < 0) {
            fprintf(stderr,"can't open destination file %s: error=%d\r\n", path, ret);
            exit(1);
        }

		char c = fgetc(srcf);
		while (!feof(srcf)) {
			ret = lfs_file_write(&lfs, &dstf, &c, 1);
			if (ret < 0) {
				fprintf(stderr,"can't write to destination file %s: error=%d\r\n", path, ret);
				exit(1);
			}
			c = fgetc(srcf);
		}

        // Close destination file
		ret = lfs_file_close(&lfs, &dstf);
		if (ret < 0) {
			fprintf(stderr,"can't close destination file %s: error=%d\r\n", path, ret);
			exit(1);
		}

        // Close source file
        fclose(srcf);
    }
}

static void compact(char *src) {
    DIR *dir;
    struct dirent *ent;
    char curr_path[PATH_MAX];
	struct stat _stat;

    dir = opendir(src);
    if (dir) {
        while ((ent = readdir(dir))) {
            // Skip . and .. directories
            if ((strcmp(ent->d_name,".") != 0) && (strcmp(ent->d_name,"..") != 0)) {
                // Update the current path
                strcpy(curr_path, src);
                strcat(curr_path, "/");
                strcat(curr_path, ent->d_name);

                stat(curr_path, &_stat);
                if (S_ISDIR(_stat.st_mode)) {
                    create_dir(curr_path);
                    compact(curr_path);
                } else if (S_ISREG(_stat.st_mode)) {
                    create_file(curr_path);
                }
            }
        }

        closedir(dir);
    }
}

void usage() {
	fprintf(stdout, "usage: mklfs -c <pack-dir> -b <block-size> -r <read-size> -p <prog-size> -s <filesystem-size> -i <image-file-path>\r\n");
}

static int is_number(const char *s) {
	const char *c = s;

	while (*c) {
		if ((*c < '0') || (*c > '9')) {
			return 0;
		}
		c++;
	}

	return 1;
}

static int is_hex(const char *s) {
	const char *c = s;

	if (*c++ != '0') {
		return 0;
	}

	if (*c++ != 'x') {
		return 0;
	}

	while (*c) {
		if (((*c < '0') || (*c > '9')) && ((*c < 'A') || (*c > 'F')) && ((*c < 'a') || (*c > 'f'))) {
			return 0;
		}
		c++;
	}

	return 1;
}

static int to_int(const char *s) {
	if (is_number(s)) {
		return atoi(s);
	} else if (is_hex(s)) {
		return (int)strtol(s, NULL, 16);
	}

	return -1;
}

#define FLASH_FS_REGION_OFFSET          0x350000
#define FLASH_FS_REGION_END             0x3A4000
#define FLASH_FS_REGION_SIZE            (FLASH_FS_REGION_END-FLASH_FS_REGION_OFFSET)      // 336KB

#define LFS_BLOCK_DEVICE_READ_SIZE      (256)
#define LFS_BLOCK_DEVICE_PROG_SIZE      (256)
#define LFS_BLOCK_DEVICE_ERASE_SIZE     (4096)       // one sector 4KB
#define LFS_BLOCK_DEVICE_TOTOAL_SIZE    (FLASH_FS_REGION_SIZE)
#define LFS_BLOCK_DEVICE_LOOK_AHEAD     (64)

int main(int argc, char **argv) {
	int err = 0;
	int fs_size = LFS_BLOCK_DEVICE_TOTOAL_SIZE;
    lfs_dir_t dir;
    struct lfs_info info;

    // Mount the file system
    cfg.read  = lfs_read;
    cfg.prog  = lfs_prog;
    cfg.erase = lfs_erase;
    cfg.sync  = lfs_sync;

    cfg.block_size  = LFS_BLOCK_DEVICE_ERASE_SIZE;
    cfg.read_size   = LFS_BLOCK_DEVICE_READ_SIZE;
    cfg.prog_size   = LFS_BLOCK_DEVICE_PROG_SIZE;
    cfg.block_count = LFS_BLOCK_DEVICE_TOTOAL_SIZE / LFS_BLOCK_DEVICE_ERASE_SIZE;
    cfg.lookahead_size   = LFS_BLOCK_DEVICE_LOOK_AHEAD;
    cfg.context     = NULL;

	FILE* fimg = fopen("disk.fs", "r");
	data = calloc(1, fs_size);
	fread(data, LFS_BLOCK_DEVICE_ERASE_SIZE, cfg.block_count, fimg);
	fclose(fimg);
	err = lfs_mount(&lfs, &cfg);
	if (err < 0) {
		fprintf(stderr, "mount error: error=%d\r\n", err);
		return -1;
	}

    lfs_dir_open(&lfs, &dir, "/lua/");
	while (lfs_dir_read(&lfs, &dir, &info) == 1) {
        fprintf(stdout, "path=/lua/%s\r\n", info.name);
    }
    lfs_dir_close(&lfs, &dir);

    lfs_dir_open(&lfs, &dir, "/");
	while (lfs_dir_read(&lfs, &dir, &info) == 1) {
        fprintf(stdout, "path=/%s\r\n", info.name);
    }
    lfs_dir_close(&lfs, &dir);

	return 0;
}
