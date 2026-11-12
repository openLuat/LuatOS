/** Image preparation shares one lazy VFS file across info and decode. */
#ifndef LUAT_PLCUI_FS_H
#define LUAT_PLCUI_FS_H
#include <stdio.h>
#include <stdbool.h>
#include <stddef.h>
bool plcui_fs_scope_begin(const char *key);
void plcui_fs_scope_end(void);
/* 1=borrowed, 0=no matching scope, -1=scope open/size check failed. */
int plcui_fs_scope_acquire(const char *key, FILE **file, size_t *size);
void plcui_fs_scope_release(FILE *file);
#endif
