#include "luat_base.h"
#include "rotable2.h"

#include "../../tfs/inc/tfs.h"
#include "../../tfs/inc/tfs_port.h"
#include "../../tfs/src/tfs_block.h"
#include "../../tfs/src/tfs_checkpoint.h"
#include "../../tfs/src/tfs_core.h"
#include "../../tfs/src/tfs_dev.h"
#include "../../tfs/src/tfs_inode.h"
#include "../../tfs/src/tfs_tags.h"
#include "../../tfs/src/tfs_verify.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TFS_UTEST_DATA_SZ       2048u
#define TFS_UTEST_OOB_SZ        64u
#define TFS_UTEST_CPB           64u
#define TFS_UTEST_BLOCKS        128u
#define TFS_UTEST_BIG_BLOCKS    256u
#define TFS_UTEST_WRITE_CHUNK   (32u * 1024u)

typedef struct {
    uint32_t data_bytes_per_chunk;
    uint32_t oob_bytes_per_chunk;
    uint32_t chunks_per_block;
    uint32_t n_blocks;
} tfs_utest_nand_geo_t;

typedef struct {
    tfs_utest_nand_geo_t geo;
    uint8_t *data;
    uint8_t *oob;
    uint8_t *written;
    uint8_t *bad;
    uint32_t n_writes;
    uint32_t n_reads;
    uint32_t n_erases;
    int anchor_valid;
    uint32_t anchor_chunk;
    uint32_t anchor_seq;
    uint32_t fail_anchor_write_count;
    int fail_anchor_write_rc;
    uint32_t fail_read_page;
    uint32_t fail_read_count;
    int fail_read_rc;
} tfs_utest_nand_t;

static tfs_utest_nand_t *g_nand;
static tfs_dev_t g_dev;
static int g_dev_registered;

static void failf(const char *case_name, const char *fmt, ...)
{
    va_list ap;

    printf("[tfs-utest][FAIL][%s] ", case_name ? case_name : "?");
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    printf("\n");
}

static void infof(const char *case_name, const char *fmt, ...)
{
    va_list ap;

    printf("[tfs-utest][%s] ", case_name ? case_name : "?");
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    printf("\n");
}

static void fill_pattern(uint8_t *buf, uint32_t len, uint32_t seed)
{
    uint32_t i;

    for (i = 0; i < len; i++)
        buf[i] = (uint8_t)((seed + i) & 0xffu);
}

static tfs_utest_nand_t *nand_create(uint32_t n_blocks)
{
    tfs_utest_nand_t *nand;
    uint32_t chunk_count = n_blocks * TFS_UTEST_CPB;

    nand = (tfs_utest_nand_t *)malloc(sizeof(*nand));
    if (!nand)
        return NULL;
    memset(nand, 0, sizeof(*nand));

    nand->geo.data_bytes_per_chunk = TFS_UTEST_DATA_SZ;
    nand->geo.oob_bytes_per_chunk = TFS_UTEST_OOB_SZ;
    nand->geo.chunks_per_block = TFS_UTEST_CPB;
    nand->geo.n_blocks = n_blocks;

    nand->data = (uint8_t *)malloc(chunk_count * TFS_UTEST_DATA_SZ);
    nand->oob = (uint8_t *)malloc(chunk_count * TFS_UTEST_OOB_SZ);
    nand->written = (uint8_t *)malloc(chunk_count);
    nand->bad = (uint8_t *)malloc(n_blocks);
    if (!nand->data || !nand->oob || !nand->written || !nand->bad) {
        free(nand->data);
        free(nand->oob);
        free(nand->written);
        free(nand->bad);
        free(nand);
        return NULL;
    }

    memset(nand->data, 0xff, chunk_count * TFS_UTEST_DATA_SZ);
    memset(nand->oob, 0xff, chunk_count * TFS_UTEST_OOB_SZ);
    memset(nand->written, 0, chunk_count);
    memset(nand->bad, 0, n_blocks);
    return nand;
}

static void nand_destroy(tfs_utest_nand_t *nand)
{
    if (!nand)
        return;
    free(nand->data);
    free(nand->oob);
    free(nand->written);
    free(nand->bad);
    free(nand);
}

static int nand_write_page(void *ctx, uint32_t page,
                           const uint8_t *data, uint32_t data_len,
                           const uint8_t *oob, uint32_t oob_len)
{
    tfs_utest_nand_t *nand = (tfs_utest_nand_t *)ctx;
    uint32_t total = nand->geo.n_blocks * nand->geo.chunks_per_block;
    uint32_t len;

    if (page >= total)
        return TFS_EFLASH;

    if (data && data_len > 0) {
        len = data_len < nand->geo.data_bytes_per_chunk
              ? data_len : nand->geo.data_bytes_per_chunk;
        memcpy(nand->data + page * nand->geo.data_bytes_per_chunk,
               data, len);
    }
    if (oob && oob_len > 0) {
        len = oob_len < nand->geo.oob_bytes_per_chunk
              ? oob_len : nand->geo.oob_bytes_per_chunk;
        memcpy(nand->oob + page * nand->geo.oob_bytes_per_chunk,
               oob, len);
    }

    nand->written[page] = 1;
    nand->n_writes++;
    return TFS_OK;
}

static int nand_read_page(void *ctx, uint32_t page,
                          uint8_t *data, uint32_t data_len,
                          uint8_t *oob, uint32_t oob_len)
{
    tfs_utest_nand_t *nand = (tfs_utest_nand_t *)ctx;
    uint32_t total = nand->geo.n_blocks * nand->geo.chunks_per_block;
    uint32_t len;

    if (page >= total)
        return TFS_EFLASH;

    nand->n_reads++;
    if (nand->fail_read_count > 0 && page == nand->fail_read_page) {
        nand->fail_read_count--;
        return nand->fail_read_rc ? nand->fail_read_rc : TFS_EFLASH;
    }

    if (data && data_len > 0) {
        len = data_len < nand->geo.data_bytes_per_chunk
              ? data_len : nand->geo.data_bytes_per_chunk;
        memcpy(data, nand->data + page * nand->geo.data_bytes_per_chunk, len);
    }
    if (oob && oob_len > 0) {
        len = oob_len < nand->geo.oob_bytes_per_chunk
              ? oob_len : nand->geo.oob_bytes_per_chunk;
        memcpy(oob, nand->oob + page * nand->geo.oob_bytes_per_chunk, len);
    }
    return TFS_OK;
}

static int nand_erase_block(void *ctx, uint32_t block)
{
    tfs_utest_nand_t *nand = (tfs_utest_nand_t *)ctx;
    uint32_t first;
    uint32_t i;

    if (block >= nand->geo.n_blocks)
        return TFS_EFLASH;

    first = block * nand->geo.chunks_per_block;
    for (i = 0; i < nand->geo.chunks_per_block; i++) {
        uint32_t page = first + i;
        memset(nand->data + page * nand->geo.data_bytes_per_chunk,
               0xff, nand->geo.data_bytes_per_chunk);
        memset(nand->oob + page * nand->geo.oob_bytes_per_chunk,
               0xff, nand->geo.oob_bytes_per_chunk);
        nand->written[page] = 0;
    }
    nand->n_erases++;
    return TFS_OK;
}

static int nand_mark_bad(void *ctx, uint32_t block)
{
    tfs_utest_nand_t *nand = (tfs_utest_nand_t *)ctx;

    if (block < nand->geo.n_blocks)
        nand->bad[block] = 1;
    return TFS_OK;
}

static int nand_check_bad(void *ctx, uint32_t block)
{
    tfs_utest_nand_t *nand = (tfs_utest_nand_t *)ctx;

    if (block >= nand->geo.n_blocks)
        return 1;
    return nand->bad[block];
}

static void *nand_malloc(void *ctx, uint32_t size)
{
    (void)ctx;
    return malloc(size);
}

static void nand_free(void *ctx, void *ptr)
{
    (void)ctx;
    free(ptr);
}

static int nand_anchor_read(void *ctx, uint32_t *chunk, uint32_t *seq)
{
    tfs_utest_nand_t *nand = (tfs_utest_nand_t *)ctx;

    if (!nand->anchor_valid)
        return TFS_EINVAL;
    if (chunk)
        *chunk = nand->anchor_chunk;
    if (seq)
        *seq = nand->anchor_seq;
    return TFS_OK;
}

static int nand_anchor_write(void *ctx, uint32_t chunk, uint32_t seq)
{
    tfs_utest_nand_t *nand = (tfs_utest_nand_t *)ctx;

    if (nand->fail_anchor_write_count > 0) {
        nand->fail_anchor_write_count--;
        return nand->fail_anchor_write_rc ? nand->fail_anchor_write_rc
                                          : TFS_EFLASH;
    }
    nand->anchor_valid = 1;
    nand->anchor_chunk = chunk;
    nand->anchor_seq = seq;
    return TFS_OK;
}

static tfs_drv_t make_drv(tfs_utest_nand_t *nand, tfs_geo_t *geo)
{
    tfs_drv_t drv;

    memset(&drv, 0, sizeof(drv));
    drv.ctx = nand;
    drv.write_page = nand_write_page;
    drv.read_page = nand_read_page;
    drv.erase_block = nand_erase_block;
    drv.mark_bad = nand_mark_bad;
    drv.check_bad = nand_check_bad;
    drv.malloc = nand_malloc;
    drv.free = nand_free;
    drv.checkpt_anchor_read = nand_anchor_read;
    drv.checkpt_anchor_write = nand_anchor_write;

    memset(geo, 0, sizeof(*geo));
    geo->data_bytes_per_chunk = nand->geo.data_bytes_per_chunk;
    geo->spare_bytes_per_chunk = nand->geo.oob_bytes_per_chunk;
    geo->chunks_per_block = nand->geo.chunks_per_block;
    geo->start_block = 0;
    geo->end_block = nand->geo.n_blocks - 1;
    return drv;
}

static void nand_fail_read(tfs_utest_nand_t *nand, uint32_t page,
                           uint32_t count, int rc)
{
    nand->fail_read_page = page;
    nand->fail_read_count = count;
    nand->fail_read_rc = rc;
}

static void nand_fail_anchor_write(tfs_utest_nand_t *nand,
                                   uint32_t count, int rc)
{
    nand->fail_anchor_write_count = count;
    nand->fail_anchor_write_rc = rc;
}

static int setup_device(uint32_t n_blocks, int inband_tags, int do_format)
{
    tfs_drv_t drv;
    tfs_geo_t geo;
    int rc;

    tfs_init();
    g_nand = nand_create(n_blocks);
    if (!g_nand)
        return TFS_ENOMEM;

    memset(&g_dev, 0, sizeof(g_dev));
    g_dev.param.name = "ram0";
    drv = make_drv(g_nand, &geo);
    if (inband_tags)
        geo.inband_tags = 1;
    g_dev.drv = drv;
    g_dev.param.geo = geo;
    g_dev.param.inband_tags = inband_tags ? 1 : 0;
    g_dev.param.disable_summary = 0;

    tfs_core_add_device(&g_dev);
    g_dev_registered = 1;
    rc = do_format ? tfs_core_format(&g_dev) : tfs_core_mount(&g_dev);
    return rc;
}

static void teardown_device(void)
{
    if (g_dev_registered) {
        if (g_dev.is_mounted)
            (void)tfs_core_unmount(&g_dev);
        tfs_core_remove_device(&g_dev);
        g_dev_registered = 0;
    }
    nand_destroy(g_nand);
    g_nand = NULL;
    memset(&g_dev, 0, sizeof(g_dev));
}

static void simulate_power_cycle_without_sync(void)
{
    int inband_tags = g_dev.param.inband_tags;
    tfs_drv_t drv;
    tfs_geo_t geo;

    if (g_dev_registered) {
        tfs_core_remove_device(&g_dev);
        g_dev_registered = 0;
    }
    memset(&g_dev, 0, sizeof(g_dev));
    g_dev.param.name = "ram0";
    drv = make_drv(g_nand, &geo);
    if (inband_tags)
        geo.inband_tags = 1;
    g_dev.drv = drv;
    g_dev.param.geo = geo;
    g_dev.param.inband_tags = inband_tags ? 1 : 0;
    g_dev.param.disable_summary = 0;
    tfs_core_add_device(&g_dev);
    g_dev_registered = 1;
}

static int write_obj_pattern(tfs_obj_t *obj, uint32_t start_offset,
                             uint32_t bytes, uint32_t seed)
{
    uint8_t buf[TFS_UTEST_DATA_SZ];
    uint32_t done = 0;
    int chunk_sz = (int)g_dev.data_bytes_per_chunk;

    if (!obj || chunk_sz <= 0)
        return TFS_FAIL;
    if (chunk_sz > (int)sizeof(buf))
        chunk_sz = (int)sizeof(buf);

    while (done < bytes) {
        int n = chunk_sz;
        uint32_t i;

        if (done + (uint32_t)n > bytes)
            n = (int)(bytes - done);
        for (i = 0; i < (uint32_t)n; i++)
            buf[i] = (uint8_t)((seed + done + i) & 0xffu);
        if (tfs_file_write(&g_dev, obj, buf,
                           (tfs_off_t)(start_offset + done), n) != n)
            return TFS_FAIL;
        if (tfs_file_flush(&g_dev, obj) != TFS_OK)
            return TFS_FAIL;
        done += (uint32_t)n;
    }
    return TFS_OK;
}

static int verify_obj_pattern(tfs_obj_t *obj, uint32_t bytes, uint32_t seed)
{
    uint8_t buf[TFS_UTEST_DATA_SZ];
    uint32_t done = 0;
    int chunk_sz = (int)g_dev.data_bytes_per_chunk;

    if (!obj || obj->obj_type != TFS_OBJ_TYPE_FILE)
        return TFS_FAIL;
    if (chunk_sz > (int)sizeof(buf))
        chunk_sz = (int)sizeof(buf);

    while (done < bytes) {
        int n = chunk_sz;
        int i;

        if (done + (uint32_t)n > bytes)
            n = (int)(bytes - done);
        memset(buf, 0, sizeof(buf));
        if (tfs_file_read(&g_dev, obj, buf, (tfs_off_t)done, n) != n)
            return TFS_FAIL;
        for (i = 0; i < n; i++) {
            uint8_t exp = (uint8_t)((seed + done + (uint32_t)i) & 0xffu);
            if (buf[i] != exp)
                return TFS_FAIL;
        }
        done += (uint32_t)n;
    }
    return TFS_OK;
}

static int count_checkpoint_blocks(void)
{
    int blk;
    int n = 0;

    for (blk = (int)g_dev.internal_start_block;
         blk <= (int)g_dev.internal_end_block; blk++) {
        if (tfs_block_get_state(&g_dev, blk) == TFS_BLK_STATE_CHECKPOINT)
            n++;
    }
    return n;
}

static int count_gc_prioritised_blocks(void)
{
    int blk;
    int n = 0;

    for (blk = (int)g_dev.internal_start_block;
         blk <= (int)g_dev.internal_end_block; blk++) {
        if (tfs_get_block_info(&g_dev, blk)->bi.gc_prioritise)
            n++;
    }
    return n;
}

static int fill_to_reserved_watermark(tfs_obj_t *bulk, uint32_t seed_base)
{
    uint32_t offset = 0;
    int writes = 0;

    while (bulk &&
           g_dev.n_erased_blocks > tfs_user_reserved_blocks(&g_dev) + 2 &&
           writes < 1024) {
        if (write_obj_pattern(bulk, offset, TFS_UTEST_WRITE_CHUNK,
                              seed_base + (uint32_t)writes) != TFS_OK)
            break;
        offset += TFS_UTEST_WRITE_CHUNK;
        writes++;
    }
    return writes;
}

static int case_format_mount_remount(void)
{
    const char *cn = "format_mount_remount";
    tfs_obj_t *obj;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 0, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    obj = tfs_create_obj(&g_dev, g_dev.root_dir, "hello.bin",
                         TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!obj || write_obj_pattern(obj, 0, 2048u, 0x11u) != TFS_OK)
        fail++;
    if (tfs_core_sync(&g_dev) != TFS_OK || !g_dev.is_checkpointed)
        fail++;
    simulate_power_cycle_without_sync();
    rc = tfs_core_mount(&g_dev);
    obj = tfs_core_find_by_name(&g_dev, g_dev.root_dir, "hello.bin");
    if (rc != TFS_OK || !g_dev.is_checkpointed ||
        verify_obj_pattern(obj, 2048u, 0x11u) != TFS_OK) {
        failf(cn, "remount rc=%d is_cp=%d obj=%p", rc, g_dev.is_checkpointed,
              (void *)obj);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_inband_tags_persistence(void)
{
    const char *cn = "inband_tags_persistence";
    uint32_t total_chunks;
    tfs_obj_t *obj;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    obj = tfs_create_obj(&g_dev, g_dev.root_dir, "inband.bin",
                         TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!obj || write_obj_pattern(obj, 0, 4096u, 0x21u) != TFS_OK)
        fail++;
    if (tfs_core_sync(&g_dev) != TFS_OK)
        fail++;
    simulate_power_cycle_without_sync();
    total_chunks = g_nand->geo.n_blocks * g_nand->geo.chunks_per_block;
    memset(g_nand->oob, 0xff, total_chunks * g_nand->geo.oob_bytes_per_chunk);
    rc = tfs_core_mount(&g_dev);
    obj = tfs_core_find_by_name(&g_dev, g_dev.root_dir, "inband.bin");
    if (rc != TFS_OK || verify_obj_pattern(obj, 4096u, 0x21u) != TFS_OK) {
        failf(cn, "mount/read failed rc=%d obj=%p", rc, (void *)obj);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_mkfs_powercycle_generation(void)
{
    const char *cn = "mkfs_powercycle_generation";
    tfs_obj_t *obj;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    obj = tfs_create_obj(&g_dev, g_dev.root_dir, "before.txt",
                         TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!obj || write_obj_pattern(obj, 0, 512u, 0x31u) != TFS_OK ||
        tfs_core_sync(&g_dev) != TFS_OK)
        fail++;
    if (tfs_core_format(&g_dev) != TFS_OK)
        fail++;
    obj = tfs_create_obj(&g_dev, g_dev.root_dir, "sentinel.txt",
                         TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!obj || write_obj_pattern(obj, 0, 512u, 0x32u) != TFS_OK)
        fail++;
    simulate_power_cycle_without_sync();
    rc = tfs_core_mount(&g_dev);
    if (rc != TFS_OK)
        fail++;
    if (tfs_core_find_by_name(&g_dev, g_dev.root_dir, "before.txt"))
        fail++;
    obj = tfs_core_find_by_name(&g_dev, g_dev.root_dir, "sentinel.txt");
    if (verify_obj_pattern(obj, 512u, 0x32u) != TFS_OK) {
        failf(cn, "post-format sentinel missing");
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_unlink_powercycle_no_resurrect(void)
{
    const char *cn = "unlink_powercycle_no_resurrect";
    tfs_obj_t *obj;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    obj = tfs_create_obj(&g_dev, g_dev.root_dir, "victim.bin",
                         TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!obj || write_obj_pattern(obj, 0, 1024u, 0x41u) != TFS_OK ||
        tfs_core_sync(&g_dev) != TFS_OK)
        fail++;
    if (tfs_unlink_obj(&g_dev, obj) != TFS_OK)
        fail++;
    simulate_power_cycle_without_sync();
    rc = tfs_core_mount(&g_dev);
    if (rc != TFS_OK ||
        tfs_core_find_by_name(&g_dev, g_dev.root_dir, "victim.bin") ||
        tfs_verify_device(&g_dev) != 0) {
        failf(cn, "delete resurrected or verify failed rc=%d", rc);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_flush_without_close_delta_replay(void)
{
    const char *cn = "flush_without_close_delta_replay";
    uint8_t stable[1024];
    uint8_t tail[512];
    tfs_obj_t *dir;
    tfs_obj_t *closed;
    tfs_obj_t *unclosed;
    uint32_t reads_before;
    uint32_t mount_reads;
    uint32_t full_scan_reads;
    int fail = 0;
    int rc;

    fill_pattern(stable, sizeof(stable), 0x50u);
    fill_pattern(tail, sizeof(tail), 0xa0u);
    rc = setup_device(TFS_UTEST_BLOCKS, 0, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    dir = tfs_create_obj(&g_dev, g_dev.root_dir, "power",
                         TFS_S_IFDIR | 0755, TFS_OBJ_TYPE_DIR);
    closed = tfs_create_obj(&g_dev, dir, "closed.bin",
                            TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!dir || !closed ||
        tfs_file_write(&g_dev, closed, stable, 0, sizeof(stable)) !=
            (int)sizeof(stable) ||
        tfs_file_flush(&g_dev, closed) != TFS_OK ||
        tfs_checkpt_write(&g_dev) != TFS_OK) {
        fail++;
    }
    unclosed = tfs_create_obj(&g_dev, dir, "flush_open.bin",
                              TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!unclosed ||
        tfs_file_write(&g_dev, unclosed, stable, 0, sizeof(stable)) !=
            (int)sizeof(stable) ||
        tfs_file_flush(&g_dev, unclosed) != TFS_OK ||
        tfs_file_write(&g_dev, unclosed, tail, sizeof(stable),
                       sizeof(tail)) != (int)sizeof(tail)) {
        fail++;
    }
    simulate_power_cycle_without_sync();
    reads_before = g_dev.n_page_reads;
    full_scan_reads = (g_dev.param.geo.end_block -
                       g_dev.param.geo.start_block + 1u) *
                      g_dev.param.geo.chunks_per_block;
    rc = tfs_core_mount(&g_dev);
    mount_reads = g_dev.n_page_reads - reads_before;
    dir = tfs_core_find_by_name(&g_dev, g_dev.root_dir, "power");
    unclosed = dir ? tfs_core_find_by_name(&g_dev, dir, "flush_open.bin")
                   : NULL;
    if (rc != TFS_OK || mount_reads >= full_scan_reads / 4 ||
        verify_obj_pattern(unclosed, sizeof(stable), 0x50u) != TFS_OK) {
        failf(cn, "rc=%d reads=%u full=%u delta=%d",
              rc, (unsigned int)mount_reads, (unsigned int)full_scan_reads,
              g_dev.checkpt_delta_chunks);
        fail++;
    }
    if (tfs_core_sync(&g_dev) != TFS_OK || !g_dev.is_checkpointed)
        fail++;
    teardown_device();
    return fail ? -1 : 0;
}

static int case_closed_download_delta_replay(void)
{
    const char *cn = "closed_download_delta_replay";
    tfs_obj_t *obj;
    uint32_t reads_before;
    uint32_t mount_reads;
    uint32_t full_scan_reads;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    if (tfs_core_sync(&g_dev) != TFS_OK || !g_dev.is_checkpointed)
        fail++;
    obj = tfs_create_obj(&g_dev, g_dev.root_dir, "download.lua",
                         TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!obj || write_obj_pattern(obj, 0, 4096u, 0x61u) != TFS_OK ||
        g_dev.is_checkpointed)
        fail++;
    simulate_power_cycle_without_sync();
    reads_before = g_dev.n_page_reads;
    full_scan_reads = (g_dev.param.geo.end_block -
                       g_dev.param.geo.start_block + 1u) *
                      g_dev.param.geo.chunks_per_block;
    rc = tfs_core_mount(&g_dev);
    mount_reads = g_dev.n_page_reads - reads_before;
    obj = tfs_core_find_by_name(&g_dev, g_dev.root_dir, "download.lua");
    if (rc != TFS_OK || mount_reads >= full_scan_reads / 4 ||
        verify_obj_pattern(obj, 4096u, 0x61u) != TFS_OK) {
        failf(cn, "rc=%d reads=%u full=%u delta=%d",
              rc, (unsigned int)mount_reads, (unsigned int)full_scan_reads,
              g_dev.checkpt_delta_chunks);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_checkpoint_reserve_enospc(void)
{
    const char *cn = "checkpoint_reserve_enospc";
    tfs_obj_t *sentinel;
    tfs_obj_t *bulk;
    int estimate;
    int actual;
    int writes;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BIG_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    sentinel = tfs_create_obj(&g_dev, g_dev.root_dir, "reserve_sentinel.bin",
                              TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    bulk = tfs_create_obj(&g_dev, g_dev.root_dir, "reserve_bulk.bin",
                          TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!sentinel || !bulk ||
        write_obj_pattern(sentinel, 0, 4096u, 0x71u) != TFS_OK)
        fail++;
    writes = fill_to_reserved_watermark(bulk, 0x7200u);
    if (writes <= 0 ||
        g_dev.n_erased_blocks > tfs_user_reserved_blocks(&g_dev) + 2)
        fail++;
    estimate = tfs_checkpt_required_blocks(&g_dev);
    rc = tfs_checkpt_write(&g_dev);
    actual = (int)g_dev.blocks_in_checkpt;
    if (rc != TFS_OK || !g_dev.is_checkpointed ||
        actual <= 0 || actual > estimate) {
        failf(cn, "rc=%d erased=%d reserve=%d estimate=%d actual=%d",
              rc, g_dev.n_erased_blocks, tfs_user_reserved_blocks(&g_dev),
              estimate, actual);
        fail++;
    }
    simulate_power_cycle_without_sync();
    rc = tfs_core_mount(&g_dev);
    sentinel = tfs_core_find_by_name(&g_dev, g_dev.root_dir,
                                     "reserve_sentinel.bin");
    if (rc != TFS_OK || !g_dev.is_checkpointed ||
        verify_obj_pattern(sentinel, 4096u, 0x71u) != TFS_OK) {
        failf(cn, "checkpoint remount failed rc=%d is_cp=%d",
              rc, g_dev.is_checkpointed);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_high_occupancy_unmount_checkpoint(void)
{
    const char *cn = "high_occupancy_unmount_checkpoint";
    tfs_obj_t *sentinel;
    tfs_obj_t *bulk;
    uint32_t reads_before;
    uint32_t mount_reads;
    uint32_t full_scan_reads;
    int writes;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BIG_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    sentinel = tfs_create_obj(&g_dev, g_dev.root_dir, "sample.bin",
                              TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    bulk = tfs_create_obj(&g_dev, g_dev.root_dir, "bulk.bin",
                          TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!sentinel || !bulk ||
        write_obj_pattern(sentinel, 0, 4096u, 0x81u) != TFS_OK)
        fail++;
    writes = fill_to_reserved_watermark(bulk, 0x8200u);
    if (writes <= 0)
        fail++;
    rc = tfs_core_unmount(&g_dev);
    if (rc != TFS_OK)
        fail++;
    reads_before = g_dev.n_page_reads;
    full_scan_reads = (g_dev.param.geo.end_block -
                       g_dev.param.geo.start_block + 1u) *
                      g_dev.param.geo.chunks_per_block;
    rc = tfs_core_mount(&g_dev);
    mount_reads = g_dev.n_page_reads - reads_before;
    sentinel = tfs_core_find_by_name(&g_dev, g_dev.root_dir, "sample.bin");
    if (rc != TFS_OK || !g_dev.is_checkpointed ||
        mount_reads >= full_scan_reads / 4 ||
        verify_obj_pattern(sentinel, 4096u, 0x81u) != TFS_OK) {
        failf(cn, "rc=%d is_cp=%d reads=%u full=%u",
              rc, g_dev.is_checkpointed,
              (unsigned int)mount_reads, (unsigned int)full_scan_reads);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_high_occupancy_download_delta(void)
{
    const char *cn = "high_occupancy_download_delta";
    tfs_obj_t *fill;
    tfs_obj_t *app_dir;
    tfs_obj_t *app;
    uint32_t reads_before;
    uint32_t mount_reads;
    uint32_t full_scan_reads;
    int writes;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BIG_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    fill = tfs_create_obj(&g_dev, g_dev.root_dir, "fill.bin",
                          TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    writes = fill_to_reserved_watermark(fill, 0x9100u);
    if (writes <= 0 || tfs_core_sync(&g_dev) != TFS_OK)
        fail++;
    app_dir = tfs_create_obj(&g_dev, g_dev.root_dir, "app",
                             TFS_S_IFDIR | 0755, TFS_OBJ_TYPE_DIR);
    app = app_dir ? tfs_create_obj(&g_dev, app_dir, "download.lua",
                                   TFS_S_IFREG | 0644,
                                   TFS_OBJ_TYPE_FILE) : NULL;
    if (!app || write_obj_pattern(app, 0, 4096u, 0x92u) != TFS_OK ||
        g_dev.is_checkpointed)
        fail++;
    simulate_power_cycle_without_sync();
    reads_before = g_dev.n_page_reads;
    full_scan_reads = (g_dev.param.geo.end_block -
                       g_dev.param.geo.start_block + 1u) *
                      g_dev.param.geo.chunks_per_block;
    rc = tfs_core_mount(&g_dev);
    mount_reads = g_dev.n_page_reads - reads_before;
    app_dir = tfs_core_find_by_name(&g_dev, g_dev.root_dir, "app");
    app = app_dir ? tfs_core_find_by_name(&g_dev, app_dir, "download.lua")
                  : NULL;
    if (rc != TFS_OK || mount_reads >= full_scan_reads / 2 ||
        verify_obj_pattern(app, 4096u, 0x92u) != TFS_OK) {
        failf(cn, "rc=%d is_cp=%d reads=%u full=%u delta=%d",
              rc, g_dev.is_checkpointed,
              (unsigned int)mount_reads, (unsigned int)full_scan_reads,
              g_dev.checkpt_delta_chunks);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_checkpoint_anchor_start(void)
{
    const char *cn = "checkpoint_anchor_start";
    tfs_ext_tags_t ext;
    int i;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    for (i = 0; i < 48; i++) {
        char name[32];
        tfs_obj_t *obj;

        snprintf(name, sizeof(name), "anchor_%02d.bin", i);
        obj = tfs_create_obj(&g_dev, g_dev.root_dir, name,
                             TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
        if (!obj || write_obj_pattern(obj, 0, 128u, (uint32_t)i) != TFS_OK) {
            fail++;
            break;
        }
    }
    rc = tfs_core_sync(&g_dev);
    memset(&ext, 0, sizeof(ext));
    if (rc != TFS_OK || !g_dev.is_checkpointed ||
        g_dev.checkpt_page_seq <= 1 || !g_nand->anchor_valid ||
        tfs_chunk_read(&g_dev, (int)g_nand->anchor_chunk, NULL, 0, &ext) !=
            TFS_OK ||
        !ext.chunk_used || ext.obj_id != TFS_OBJ_ID_CHECKPT ||
        ext.chunk_id != 0) {
        failf(cn, "bad anchor rc=%d pages=%d anchor=%d obj=%u chunk=%u",
              rc, g_dev.checkpt_page_seq, g_nand->anchor_valid,
              (unsigned int)ext.obj_id, (unsigned int)ext.chunk_id);
        fail++;
    }
    simulate_power_cycle_without_sync();
    rc = tfs_core_mount(&g_dev);
    if (rc != TFS_OK || !g_dev.is_checkpointed)
        fail++;
    teardown_device();
    return fail ? -1 : 0;
}

static int case_anchor_publish_failure_keeps_old(void)
{
    const char *cn = "anchor_publish_failure_keeps_old";
    tfs_obj_t *base;
    tfs_obj_t *app;
    tfs_obj_t *found;
    uint32_t old_chunk;
    uint32_t old_seq;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    base = tfs_create_obj(&g_dev, g_dev.root_dir, "base.bin",
                          TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!base || write_obj_pattern(base, 0, 2048u, 0xa1u) != TFS_OK ||
        tfs_core_sync(&g_dev) != TFS_OK || !g_nand->anchor_valid)
        fail++;
    old_chunk = g_nand->anchor_chunk;
    old_seq = g_nand->anchor_seq;
    app = tfs_create_obj(&g_dev, g_dev.root_dir, "anchor_fail.lua",
                         TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    if (!app || write_obj_pattern(app, 0, 2048u, 0xa2u) != TFS_OK ||
        g_dev.is_checkpointed)
        fail++;
    nand_fail_anchor_write(g_nand, 3, TFS_EFLASH);
    rc = tfs_core_sync(&g_dev);
    if (rc == TFS_OK || !g_nand->anchor_valid ||
        g_nand->anchor_chunk != old_chunk || g_nand->anchor_seq != old_seq) {
        failf(cn, "anchor replaced rc=%d anchor=%u/%u old=%u/%u",
              rc, (unsigned int)g_nand->anchor_chunk,
              (unsigned int)g_nand->anchor_seq,
              (unsigned int)old_chunk, (unsigned int)old_seq);
        fail++;
    }
    simulate_power_cycle_without_sync();
    rc = tfs_core_mount(&g_dev);
    found = tfs_core_find_by_name(&g_dev, g_dev.root_dir, "anchor_fail.lua");
    if (rc != TFS_OK || verify_obj_pattern(found, 2048u, 0xa2u) != TFS_OK) {
        failf(cn, "delta recovery failed rc=%d", rc);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_auto_checkpoint_close_batch(void)
{
    const char *cn = "auto_checkpoint_close_batch";
    uint32_t reads_before;
    uint32_t mount_reads;
    uint32_t full_scan_reads;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 0, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    if (tfs_core_sync(&g_dev) != TFS_OK || !g_dev.is_checkpointed)
        fail++;
#if TFS_CFG_AUTOCHECKPOINT_CLOSES > 0
    {
        int i;
        for (i = 0; i < TFS_CFG_AUTOCHECKPOINT_CLOSES; i++) {
            char path[64];
            char payload[96];
            int fd;

            snprintf(path, sizeof(path), "/ram0/auto_cp_%02d.lua", i);
            snprintf(payload, sizeof(payload), "return %d\n", i);
            fd = tfs_open(path, TFS_O_CREAT | TFS_O_TRUNC | TFS_O_WRONLY,
                          0644);
            if (fd < 0 ||
                tfs_write(fd, payload, (int)strlen(payload)) !=
                    (int)strlen(payload) ||
                tfs_close(fd) != 0) {
                fail++;
                if (fd >= 0)
                    tfs_close(fd);
                break;
            }
        }
    }
    if (!g_dev.is_checkpointed ||
        g_dev.checkpt_dirty_chunks != 0 ||
        g_dev.checkpt_dirty_closes != 0) {
        failf(cn, "auto checkpoint not clean is_cp=%d dirty=%u/%u",
              g_dev.is_checkpointed,
              (unsigned int)g_dev.checkpt_dirty_chunks,
              (unsigned int)g_dev.checkpt_dirty_closes);
        fail++;
    }
    simulate_power_cycle_without_sync();
    reads_before = g_dev.n_page_reads;
    full_scan_reads = (g_dev.param.geo.end_block -
                       g_dev.param.geo.start_block + 1u) *
                      g_dev.param.geo.chunks_per_block;
    rc = tfs_core_mount(&g_dev);
    mount_reads = g_dev.n_page_reads - reads_before;
    if (rc != TFS_OK || !g_dev.is_checkpointed ||
        mount_reads >= full_scan_reads / 4) {
        failf(cn, "rc=%d is_cp=%d reads=%u full=%u",
              rc, g_dev.is_checkpointed,
              (unsigned int)mount_reads, (unsigned int)full_scan_reads);
        fail++;
    }
#endif
    teardown_device();
    return fail ? -1 : 0;
}

static int case_bad_block_read_failure(void)
{
    const char *cn = "bad_block_read_failure";
    uint32_t fail_block = 10;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BLOCKS, 0, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    if (tfs_core_unmount(&g_dev) != TFS_OK)
        fail++;
    g_dev.param.skip_checkpt_rd = 1;
    nand_fail_read(g_nand, fail_block * TFS_UTEST_CPB, 1, TFS_EFLASH);
    rc = tfs_core_mount(&g_dev);
    if (rc != TFS_OK || !g_nand->bad[fail_block] ||
        g_nand->fail_read_count != 0) {
        failf(cn, "rc=%d bad=%d fail_count=%u", rc,
              g_nand->bad[fail_block], g_nand->fail_read_count);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

static int case_full_scan_reclaims_checkpoint_blocks(void)
{
    const char *cn = "full_scan_reclaims_checkpoint_blocks";
    tfs_obj_t *sentinel;
    tfs_obj_t *bulk;
    int old_checkpt_blocks;
    int scan_gc_blocks;
    int writes;
    int fail = 0;
    int rc;

    rc = setup_device(TFS_UTEST_BIG_BLOCKS, 1, 1);
    if (rc != TFS_OK) {
        failf(cn, "setup failed rc=%d", rc);
        teardown_device();
        return -1;
    }
    sentinel = tfs_create_obj(&g_dev, g_dev.root_dir, "scan_sentinel.bin",
                              TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    bulk = tfs_create_obj(&g_dev, g_dev.root_dir, "scan_bulk.bin",
                          TFS_S_IFREG | 0644, TFS_OBJ_TYPE_FILE);
    writes = fill_to_reserved_watermark(bulk, 0xb100u);
    if (!sentinel || !bulk || writes <= 0 ||
        write_obj_pattern(sentinel, 0, 4096u, 0xb2u) != TFS_OK)
        fail++;
    rc = tfs_checkpt_write(&g_dev);
    old_checkpt_blocks = (int)g_dev.blocks_in_checkpt;
    if (rc != TFS_OK || old_checkpt_blocks <= 0)
        fail++;
    simulate_power_cycle_without_sync();
    g_dev.param.skip_checkpt_rd = 1;
    rc = tfs_core_mount(&g_dev);
    scan_gc_blocks = count_gc_prioritised_blocks();
    if (rc != TFS_OK || g_dev.is_checkpointed ||
        scan_gc_blocks < old_checkpt_blocks) {
        failf(cn, "scan rc=%d is_cp=%d old=%d gc=%d",
              rc, g_dev.is_checkpointed, old_checkpt_blocks,
              scan_gc_blocks);
        fail++;
    }
    g_dev.param.skip_checkpt_rd = 0;
    if (tfs_core_sync(&g_dev) != TFS_OK || !g_dev.is_checkpointed ||
        count_checkpoint_blocks() <= 0)
        fail++;
    simulate_power_cycle_without_sync();
    rc = tfs_core_mount(&g_dev);
    sentinel = tfs_core_find_by_name(&g_dev, g_dev.root_dir,
                                     "scan_sentinel.bin");
    if (rc != TFS_OK || !g_dev.is_checkpointed ||
        verify_obj_pattern(sentinel, 4096u, 0xb2u) != TFS_OK) {
        failf(cn, "final remount rc=%d is_cp=%d", rc, g_dev.is_checkpointed);
        fail++;
    }
    teardown_device();
    return fail ? -1 : 0;
}

typedef int (*tfs_utest_fn_t)(void);

typedef struct {
    const char *name;
    tfs_utest_fn_t fn;
} tfs_utest_case_t;

static const tfs_utest_case_t g_cases[] = {
    {"format_mount_remount", case_format_mount_remount},
    {"inband_tags_persistence", case_inband_tags_persistence},
    {"mkfs_powercycle_generation", case_mkfs_powercycle_generation},
    {"unlink_powercycle_no_resurrect", case_unlink_powercycle_no_resurrect},
    {"flush_without_close_delta_replay", case_flush_without_close_delta_replay},
    {"closed_download_delta_replay", case_closed_download_delta_replay},
    {"checkpoint_reserve_enospc", case_checkpoint_reserve_enospc},
    {"high_occupancy_unmount_checkpoint", case_high_occupancy_unmount_checkpoint},
    {"high_occupancy_download_delta", case_high_occupancy_download_delta},
    {"checkpoint_anchor_start", case_checkpoint_anchor_start},
    {"anchor_publish_failure_keeps_old", case_anchor_publish_failure_keeps_old},
    {"auto_checkpoint_close_batch", case_auto_checkpoint_close_batch},
    {"bad_block_read_failure", case_bad_block_read_failure},
    {"full_scan_reclaims_checkpoint_blocks", case_full_scan_reclaims_checkpoint_blocks},
};

static int run_all_cases(void)
{
    size_t i;
    int fails = 0;

    for (i = 0; i < sizeof(g_cases) / sizeof(g_cases[0]); i++) {
        int rc;

        infof("c_layer_selftests", "running %s", g_cases[i].name);
        rc = g_cases[i].fn();
        if (rc != 0) {
            failf("c_layer_selftests", "%s failed", g_cases[i].name);
            fails++;
        }
    }
    if (fails == 0)
        infof("c_layer_selftests", "all %u cases passed",
              (unsigned int)(sizeof(g_cases) / sizeof(g_cases[0])));
    return fails ? -1 : 0;
}

int luat_tfs_utest(lua_State *L, const char *case_name)
{
    size_t i;

    (void)L;
    if (!case_name || case_name[0] == '\0' ||
        strcmp(case_name, "c_layer_selftests") == 0) {
        return run_all_cases();
    }

    for (i = 0; i < sizeof(g_cases) / sizeof(g_cases[0]); i++) {
        if (strcmp(case_name, g_cases[i].name) == 0)
            return g_cases[i].fn();
    }

    failf("dispatch", "unknown case '%s'", case_name);
    return -1;
}

static int l_tfs_utest(lua_State *L)
{
    const char *case_name = luaL_optstring(L, 1, "c_layer_selftests");

    lua_pushboolean(L, luat_tfs_utest(L, case_name) == 0);
    return 1;
}

static const rotable_Reg_t reg_tfs[] = {
    {"utest", ROREG_FUNC(l_tfs_utest)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_tfs(lua_State *L)
{
    luat_newlib2(L, reg_tfs);
    return 1;
}
