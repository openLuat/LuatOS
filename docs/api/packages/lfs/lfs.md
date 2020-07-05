---
title: lfs
path: lfs/lfs.c
---
--------------------------------------------------
# lfs_cache_drop

```c
static inline void lfs_cache_drop(lfs_t *lfs, lfs_cache_t *rcache)
```

/ Caching block device operations ///

## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**rcache**|`lfs_cache_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_cache_zero

```c
static inline void lfs_cache_zero(lfs_t *lfs, lfs_cache_t *pcache)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**pcache**|`lfs_cache_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_bd_erase

```c
static int lfs_bd_erase(lfs_t *lfs, lfs_block_t block)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**block**|`lfs_block_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_pair_swap

```c
static inline void lfs_pair_swap(lfs_block_t pair[2])
```

/ Small type-level utilities ///
operations on block pairs

## 参数表

Name | Type | Description
-----|------|--------------
**pair[2]**|`lfs_block_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_pair_isnull

```c
static inline bool lfs_pair_isnull(const lfs_block_t pair[2])
```


## 参数表

Name | Type | Description
-----|------|--------------
**pair[2]**|`lfs_block_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`bool`| *无*


--------------------------------------------------
# lfs_pair_fromle32

```c
static inline void lfs_pair_fromle32(lfs_block_t pair[2])
```


## 参数表

Name | Type | Description
-----|------|--------------
**pair[2]**|`lfs_block_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_pair_tole32

```c
static inline void lfs_pair_tole32(lfs_block_t pair[2])
```


## 参数表

Name | Type | Description
-----|------|--------------
**pair[2]**|`lfs_block_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_tag_isvalid

```c
static inline bool lfs_tag_isvalid(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`bool`| *无*


--------------------------------------------------
# lfs_tag_isdelete

```c
static inline bool lfs_tag_isdelete(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`bool`| *无*


--------------------------------------------------
# lfs_tag_type1

```c
static inline uint16_t lfs_tag_type1(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint16_t`| *无*


--------------------------------------------------
# lfs_tag_type3

```c
static inline uint16_t lfs_tag_type3(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint16_t`| *无*


--------------------------------------------------
# lfs_tag_chunk

```c
static inline uint8_t lfs_tag_chunk(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint8_t`| *无*


--------------------------------------------------
# lfs_tag_splice

```c
static inline int8_t lfs_tag_splice(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int8_t`| *无*


--------------------------------------------------
# lfs_tag_id

```c
static inline uint16_t lfs_tag_id(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint16_t`| *无*


--------------------------------------------------
# lfs_tag_size

```c
static inline lfs_size_t lfs_tag_size(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`lfs_size_t`| *无*


--------------------------------------------------
# lfs_tag_dsize

```c
static inline lfs_size_t lfs_tag_dsize(lfs_tag_t tag)
```


## 参数表

Name | Type | Description
-----|------|--------------
**tag**|`lfs_tag_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`lfs_size_t`| *无*


--------------------------------------------------
# lfs_gstate_iszero

```c
static inline bool lfs_gstate_iszero(const structlfs_gstate *a)
```


## 参数表

Name | Type | Description
-----|------|--------------
**a**|`structlfs_gstate*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`bool`| *无*


--------------------------------------------------
# lfs_gstate_hasorphans

```c
static inline bool lfs_gstate_hasorphans(const structlfs_gstate *a)
```


## 参数表

Name | Type | Description
-----|------|--------------
**a**|`structlfs_gstate*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`bool`| *无*


--------------------------------------------------
# lfs_gstate_getorphans

```c
static inline uint8_t lfs_gstate_getorphans(const structlfs_gstate *a)
```


## 参数表

Name | Type | Description
-----|------|--------------
**a**|`structlfs_gstate*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`uint8_t`| *无*


--------------------------------------------------
# lfs_gstate_hasmove

```c
static inline bool lfs_gstate_hasmove(const structlfs_gstate *a)
```


## 参数表

Name | Type | Description
-----|------|--------------
**a**|`structlfs_gstate*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`bool`| *无*


--------------------------------------------------
# lfs_gstate_fromle32

```c
static inline void lfs_gstate_fromle32(struct lfs_gstate *a)
```


## 参数表

Name | Type | Description
-----|------|--------------
**a**|`lfs_gstate*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_gstate_tole32

```c
static inline void lfs_gstate_tole32(struct lfs_gstate *a)
```


## 参数表

Name | Type | Description
-----|------|--------------
**a**|`lfs_gstate*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_ctz_fromle32

```c
static void lfs_ctz_fromle32(struct lfs_ctz *ctz)
```

other endianness operations

## 参数表

Name | Type | Description
-----|------|--------------
**ctz**|`lfs_ctz*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_ctz_tole32

```c
static void lfs_ctz_tole32(struct lfs_ctz *ctz)
```


## 参数表

Name | Type | Description
-----|------|--------------
**ctz**|`lfs_ctz*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_superblock_fromle32

```c
static inline void lfs_superblock_fromle32(lfs_superblock_t *superblock)
```


## 参数表

Name | Type | Description
-----|------|--------------
**superblock**|`lfs_superblock_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_superblock_tole32

```c
static inline void lfs_superblock_tole32(lfs_superblock_t *superblock)
```


## 参数表

Name | Type | Description
-----|------|--------------
**superblock**|`lfs_superblock_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_file_outline

```c
static int lfs_file_outline(lfs_t *lfs, lfs_file_t *file)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**file**|`lfs_file_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_file_flush

```c
static int lfs_file_flush(lfs_t *lfs, lfs_file_t *file)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**file**|`lfs_file_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_fs_preporphans

```c
static void lfs_fs_preporphans(lfs_t *lfs, int8_t orphans)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**orphans**|`int8_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_fs_forceconsistency

```c
static int lfs_fs_forceconsistency(lfs_t *lfs)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_deinit

```c
static int lfs_deinit(lfs_t *lfs)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_alloc_lookahead

```c
static int lfs_alloc_lookahead(void *p, lfs_block_t block)
```

/ Block allocator ///

## 参数表

Name | Type | Description
-----|------|--------------
**p**|`void*`| *无*
**block**|`lfs_block_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_alloc

```c
static int lfs_alloc(lfs_t *lfs, lfs_block_t *block)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**block**|`lfs_block_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_alloc_ack

```c
static void lfs_alloc_ack(lfs_t *lfs)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_dir_commitcrc

```c
static int lfs_dir_commitcrc(lfs_t *lfs, struct lfs_commit *commit)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**commit**|`lfs_commit*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_dir_alloc

```c
static int lfs_dir_alloc(lfs_t *lfs, lfs_mdir_t *dir)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**dir**|`lfs_mdir_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_dir_drop

```c
static int lfs_dir_drop(lfs_t *lfs, lfs_mdir_t *dir, lfs_mdir_t *tail)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**dir**|`lfs_mdir_t*`| *无*
**tail**|`lfs_mdir_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_dir_commit_size

```c
static int lfs_dir_commit_size(void *p, lfs_tag_t tag, const void *buffer)
```


## 参数表

Name | Type | Description
-----|------|--------------
**p**|`void*`| *无*
**tag**|`lfs_tag_t`| *无*
**buffer**|`void*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_dir_commit_commit

```c
static int lfs_dir_commit_commit(void *p, lfs_tag_t tag, const void *buffer)
```


## 参数表

Name | Type | Description
-----|------|--------------
**p**|`void*`| *无*
**tag**|`lfs_tag_t`| *无*
**buffer**|`void*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_ctz_index

```c
static int lfs_ctz_index(lfs_t *lfs, lfs_off_t *off)
```

/ File index list operations ///

## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**off**|`lfs_off_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_file_relocate

```c
static int lfs_file_relocate(lfs_t *lfs, lfs_file_t *file)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**file**|`lfs_file_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_file_outline

```c
static int lfs_file_outline(lfs_t *lfs, lfs_file_t *file)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**file**|`lfs_file_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_file_flush

```c
static int lfs_file_flush(lfs_t *lfs, lfs_file_t *file)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**file**|`lfs_file_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_init

```c
static int lfs_init(lfs_t *lfs, const structlfs_config *cfg)
```

/ Filesystem operations ///

## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**cfg**|`structlfs_config*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_deinit

```c
static int lfs_deinit(lfs_t *lfs)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_fs_preporphans

```c
static void lfs_fs_preporphans(lfs_t *lfs, int8_t orphans)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**orphans**|`int8_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs_fs_demove

```c
static int lfs_fs_demove(lfs_t *lfs)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_fs_deorphan

```c
static int lfs_fs_deorphan(lfs_t *lfs)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_fs_forceconsistency

```c
static int lfs_fs_forceconsistency(lfs_t *lfs)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs_fs_size_count

```c
static int lfs_fs_size_count(void *p, lfs_block_t block)
```


## 参数表

Name | Type | Description
-----|------|--------------
**p**|`void*`| *无*
**block**|`lfs_block_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs1_crc

```c
static void lfs1_crc(uint32_t *crc, const void *buffer, size_t size)
```

/ Low-level wrappers v1->v2 ///

## 参数表

Name | Type | Description
-----|------|--------------
**crc**|`uint32_t*`| *无*
**buffer**|`void*`| *无*
**size**|`size_t`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs1_dir_fromle32

```c
static void lfs1_dir_fromle32(struct lfs1_disk_dir *d)
```

/ Endian swapping functions ///

## 参数表

Name | Type | Description
-----|------|--------------
**d**|`lfs1_disk_dir*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs1_dir_tole32

```c
static void lfs1_dir_tole32(struct lfs1_disk_dir *d)
```


## 参数表

Name | Type | Description
-----|------|--------------
**d**|`lfs1_disk_dir*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs1_entry_fromle32

```c
static void lfs1_entry_fromle32(struct lfs1_disk_entry *d)
```


## 参数表

Name | Type | Description
-----|------|--------------
**d**|`lfs1_disk_entry*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs1_entry_tole32

```c
static void lfs1_entry_tole32(struct lfs1_disk_entry *d)
```


## 参数表

Name | Type | Description
-----|------|--------------
**d**|`lfs1_disk_entry*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs1_superblock_fromle32

```c
static void lfs1_superblock_fromle32(struct lfs1_disk_superblock *d)
```


## 参数表

Name | Type | Description
-----|------|--------------
**d**|`lfs1_disk_superblock*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# lfs1_entry_size

```c
static inline lfs_size_t lfs1_entry_size(const lfs1_entry_t *entry)
```

/// Metadata pair and directory operations ///

## 参数表

Name | Type | Description
-----|------|--------------
**entry**|`lfs1_entry_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`lfs_size_t`| *无*


--------------------------------------------------
# lfs1_dir_next

```c
static int lfs1_dir_next(lfs_t *lfs, lfs1_dir_t *dir, lfs1_entry_t *entry)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**dir**|`lfs1_dir_t*`| *无*
**entry**|`lfs1_entry_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs1_moved

```c
static int lfs1_moved(lfs_t *lfs, const void *e)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*
**e**|`void*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# lfs1_unmount

```c
static int lfs1_unmount(lfs_t *lfs)
```


## 参数表

Name | Type | Description
-----|------|--------------
**lfs**|`lfs_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


