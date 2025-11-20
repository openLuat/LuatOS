
#include "luat_base.h"
#include "luat_vtool_mp4box.h"
#include "luat_mem.h"
#include "luat_fs.h"


#define LUAT_LOG_TAG "mp4box"
#include "luat_log.h"

// 256KB 写缓冲大小
#define MP4BOX_WRITE_BUFFER_SIZE (256 * 1024)

// 写缓冲：初始化/写入/刷新/逻辑偏移
static int buffered_init(mp4_ctx_t* ctx, size_t size) {
    if (ctx->box_buff) {
        return 0;
    }
    ctx->box_buff = luat_heap_malloc(size);
    if (!ctx->box_buff) {
        LLOGE("alloc write buffer failed size=%d", (int)size);
        return -1;
    }
    ctx->box_buff_size = size;
    ctx->box_buff_offset = 0;
    return 0;
}

static int buffered_flush(mp4_ctx_t* ctx) {
    int size = ctx->box_buff_offset;
    LLOGI("start flush buffer %d bytes %p", size, ctx->box_buff);
    if (ctx->box_buff && ctx->box_buff_offset > 0) {
        // 每次最多写入64KB
        #define FLUSH_CHUNK_SIZE (64 * 1024)
        size_t offset = 0;
        while (offset < (size_t)size) {
            size_t chunk = ((size_t)size - offset);
            if (chunk > FLUSH_CHUNK_SIZE) {
                chunk = FLUSH_CHUNK_SIZE;
            }
            int ret = luat_fs_fwrite((uint8_t*)ctx->box_buff + offset, 1, chunk, ctx->fd);
            if (ret != (int)chunk) {
                LLOGE("flush buffer failed %d/%d at offset %d", ret, (int)chunk, (int)offset);
                ctx->box_buff_offset = 0; // 即便失败了也清空缓冲区
                return -1;
            }
            offset += chunk;
        }
        ctx->box_buff_offset = 0;
    }
    return 0;
}

static int buffered_write(mp4_ctx_t* ctx, const void* data, size_t len) {
    if (len == 0) return 0;
    if (!ctx->box_buff) {
        int r = buffered_init(ctx, MP4BOX_WRITE_BUFFER_SIZE);
        if (r) return r;
    }
    const uint8_t* p = (const uint8_t*)data;
    while (len > 0) {
        size_t cap = ctx->box_buff_size - ctx->box_buff_offset;
        if (cap == 0) {
            int r = buffered_flush(ctx);
            if (r) return r;
            cap = ctx->box_buff_size;
        }
        size_t chunk = len < cap ? len : cap;
        memcpy((uint8_t*)ctx->box_buff + ctx->box_buff_offset, p, chunk);
        ctx->box_buff_offset += chunk;
        p += chunk;
        len -= chunk;
        if (ctx->box_buff_offset == ctx->box_buff_size) {
            int r = buffered_flush(ctx);
            if (r) return r;
        }
    }
    return 0;
}

static size_t buffered_tell(mp4_ctx_t* ctx) {
    int pos = luat_fs_ftell(ctx->fd);
    if (pos < 0) pos = 0;
    return (size_t)pos + ctx->box_buff_offset;
}

static void prepare_box_tree(mp4_ctx_t* ctx) {
	// moov下有mvhd和trak
    memcpy(ctx->box_moov.tp, "moov", 4);
    memcpy(ctx->box_mvhd.tp, "mvhd", 4);
    memcpy(ctx->box_trak.tp, "trak", 4);
    memcpy(ctx->box_tkhd.tp, "tkhd", 4);
    memcpy(ctx->box_mdia.tp, "mdia", 4);
    memcpy(ctx->box_mdhd.tp, "mdhd", 4);
    memcpy(ctx->box_hdlr.tp, "hdlr", 4);
    memcpy(ctx->box_minf.tp, "minf", 4);
    memcpy(ctx->box_vmhd.tp, "vmhd", 4);
    memcpy(ctx->box_dinf.tp, "dinf", 4);
    memcpy(ctx->box_dref.tp, "dref", 4);
    memcpy(ctx->box_stbl.tp, "stbl", 4);
    memcpy(ctx->box_avcc.tp, "avcC", 4);
    memcpy(ctx->box_avc1.tp, "avc1", 4);
    memcpy(ctx->box_stsd.tp, "stsd", 4);
    memcpy(ctx->box_stts.tp, "stts", 4);
    memcpy(ctx->box_stsc.tp, "stsc", 4);
    memcpy(ctx->box_stsz.tp, "stsz", 4);
    memcpy(ctx->box_stco.tp, "stco", 4);
    memcpy(ctx->box_stss.tp, "stss", 4);
    memcpy(ctx->box_url.tp, "url\x00", 4);

	ctx->box_moov.mboxs[0] = &ctx->box_mvhd;
	ctx->box_moov.mboxs[1] = &ctx->box_trak;

	ctx->box_trak.mboxs[0] = &ctx->box_tkhd;
	ctx->box_trak.mboxs[1] = &ctx->box_mdia;

	ctx->box_mdia.mboxs[0] = &ctx->box_mdhd;
	ctx->box_mdia.mboxs[1] = &ctx->box_hdlr;
	ctx->box_mdia.mboxs[2] = &ctx->box_minf;

	ctx->box_minf.mboxs[0] = &ctx->box_vmhd;
	ctx->box_minf.mboxs[1] = &ctx->box_dinf;
	ctx->box_minf.mboxs[2] = &ctx->box_stbl;

	ctx->box_dinf.mboxs[0] = &ctx->box_dref;
    ctx->box_dref.mboxs[0] = &ctx->box_url;

	ctx->box_stbl.mboxs[0] = &ctx->box_stsd;
	ctx->box_stbl.mboxs[1] = &ctx->box_stts;
	ctx->box_stbl.mboxs[2] = &ctx->box_stss;
	ctx->box_stbl.mboxs[3] = &ctx->box_stsc;
	ctx->box_stbl.mboxs[4] = &ctx->box_stsz;
	ctx->box_stbl.mboxs[5] = &ctx->box_stco;

    ctx->box_stsd.mboxs[0] = &ctx->box_avc1;
    ctx->box_avc1.mboxs[0] = &ctx->box_avcc;

}

static void write_be(uint8_t* data, uint32_t value) {
    data[0] = (value >> 24) & 0xff;
    data[1] = (value >> 16) & 0xff;
    data[2] = (value >> 8) & 0xff;
    data[3] = (value >> 0) & 0xff;
}

static void write_be_short(uint8_t* data, uint32_t value) {
    data[0] = (value >> 8) & 0xff;
    data[1] = (value >> 0) & 0xff;
}

// stbl 系列的box

// 先准备avc1 和 avcc
static void prepare_box_avcc(mp4_ctx_t* ctx) {
    ctx->box_avcc.self_data_len = 1 + 3 + 1 + 1 + 2 + ctx->sps_len + 1 + 2 + ctx->pps_len;
    uint8_t* data = luat_heap_malloc(ctx->box_avcc.self_data_len);
    data[0] = 0x01;
    memcpy(data +1, ctx->sps + 1, 3);
    data[4] = 0xFF;

    data[5] = 0x01;
    data[6] = (ctx->sps_len >> 8) & 0xFF;
    data[7] = ctx->sps_len & 0xff;
    memcpy(data + 8, ctx->sps, ctx->sps_len);

    data[8 + ctx->sps_len] = 0x01;
    data[8 + ctx->sps_len + 1] = (ctx->pps_len >> 8) & 0xFF;
    data[8 + ctx->sps_len + 2] = ctx->pps_len & 0xff;
    memcpy(data + 8 + ctx->sps_len + 3, ctx->pps, ctx->pps_len);
    ctx->box_avcc.data = data;
    // LLOGD("avcC len 0x%02X", ctx->box_avcc.self_data_len);
    // LLOGD("SPS数据长度 %d", ctx->sps_len);
    // LLOGD("PPS数据长度 %d", ctx->pps_len);
}

static void prepare_box_avc1(mp4_ctx_t* ctx) {
    uint8_t* data = luat_heap_malloc(78);
    ctx->box_avc1.self_data_len = 78;
    ctx->box_avc1.data = data;

    write_be(data, 0); // reserved
    write_be(data + 4, 0x01); // data reference index
    write_be(data + 8, 0);
    write_be(data + 12, 0);
    write_be(data + 16, 0);
    write_be(data + 20, 0);
    write_be(data + 24, (ctx->frame_w << 16) + ctx->frame_h);
    write_be(data + 28, 0x00480000); // horiz resolution (72 dpi)
    write_be(data + 32, 0x00480000); // vert resolution (72 dpi)
    write_be(data + 36, 0); // reserved
    write_be(data + 38, ctx->frame_id); // 移动2个字节
    memcpy(data + 42, "AVC Coding", strlen("AVC Coding")+1);
    write_be(data + 74, (0x18 << 16) + 0xffff); // depth

    prepare_box_avcc(ctx);
}

static void prepare_box_stsd(mp4_ctx_t* ctx) {
    prepare_box_avc1(ctx);
    // 准备自己的数据
    uint32_t entry_size = 1;
    uint8_t* data = luat_heap_malloc(4 + 4);
    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, entry_size);
    ctx->box_stsd.data = data;
    ctx->box_stsd.self_data_len = 4 + 4;
}

static void prepare_box_stts(mp4_ctx_t* ctx) {
    // 每帧对应的播放时长, 当前先固定写死
    uint32_t entry_size = ctx->frame_id;
    uint8_t* data = luat_heap_malloc(4 + 4 + entry_size * 8);
    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, entry_size);

    for (size_t i = 0; i < entry_size; i++)
    {
        write_be(data+8 + i*8, 1);
        write_be(data+12 + i*8, ctx->frame_durs[i]);
    }
   
    ctx->box_stts.data = data;
    ctx->box_stts.self_data_len = 4 + 4 + entry_size * 8;
}

static void prepare_box_stss(mp4_ctx_t* ctx) {
    // 关键帧的索引
    uint32_t entry_size = ctx->iframe_id_index;
    uint8_t* data = luat_heap_malloc(4 + 4 + entry_size * 4);
    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, entry_size);

    for (size_t i = 0; i < entry_size; i++)
    {
        write_be(data + 4 + 4 + i*4, ctx->iframe_ids[i]);
    }
    
    ctx->box_stss.data = data;
    ctx->box_stss.self_data_len = 4 + 4 + entry_size * 4;
}

static void prepare_box_stsc(mp4_ctx_t* ctx) {
    // 采样到chunk的映射, 固定一个chunk
    uint32_t entry_size = 1;
    uint8_t* data = luat_heap_malloc(4 + 4 + entry_size * 12);
    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, entry_size);

    write_be(data+8, 1);
    write_be(data+12, ctx->frame_id);
    write_be(data+16, 1);

    ctx->box_stsc.data = data;
    ctx->box_stsc.self_data_len = 4 + 4 + entry_size * 12;
}

static void prepare_box_stsz(mp4_ctx_t* ctx) {
    // 帧的大小
    uint32_t entry_size = ctx->frame_offset_index;
    uint8_t* data = luat_heap_malloc(12 + entry_size * 4);
    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, 0);
    write_be(data+8, entry_size);

    for (size_t i = 0; i < entry_size; i++)
    {
        write_be(data + 12 + i*4, ctx->frame_sizes[i]);
    }
    
    ctx->box_stsz.data = data;
    ctx->box_stsz.self_data_len = 12 + entry_size * 4;
}

static void prepare_box_stco(mp4_ctx_t* ctx) {
    // chunk偏移, 当前固定一个
    uint32_t entry_size = 1;
    uint8_t* data = luat_heap_malloc(4 + 4 + entry_size * 4);
    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, entry_size);

    write_be(data+8, ctx->frame_offsets[0]);

    ctx->box_stco.data = data;
    ctx->box_stco.self_data_len = 4 + 4 + entry_size * 4;
}

static void prepare_box_stbl(mp4_ctx_t* ctx) {
    prepare_box_stsd(ctx);
    prepare_box_stts(ctx);
    prepare_box_stss(ctx);
    prepare_box_stsc(ctx);
    prepare_box_stsz(ctx);
    prepare_box_stco(ctx);
}


static void prepare_box_mvhd(mp4_ctx_t* ctx) {
    uint8_t* data = luat_heap_malloc(128);
    ctx->box_mvhd.data = data; // 固定长度
    ctx->box_mvhd.self_data_len = 100; // 固定长度

    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, 0);  // creation time
    write_be(data+8, 0);  // modification time
    write_be(data+12, 1000);  // timescale
    uint64_t time_duration = luat_mcu_tick64_ms() - ctx->start_time;
    if (time_duration < ctx->frame_id * (uint64_t)(1000 / ctx->frame_fps)) {
        time_duration = ctx->frame_id * (uint64_t)(1000 / ctx->frame_fps);
    }
    write_be(data+16, (uint32_t)time_duration);  // duration
    write_be(data+20, 0x00010000);  // rate (1.0)
    write_be_short(data+24, 0x0100);  // volume (1.0)
    write_be_short(data+26, 0);  // reserved
    write_be(data+28, 0);  // reserved
    write_be(data+32, 0);  // reserved+1

    // matrix
    write_be(data+36, 0x10000);  // matrix
    write_be(data+40, 0);  // matrix
    write_be(data+44, 0);  // matrix

    write_be(data+48, 0);  // matrix
    write_be(data+52, 0x10000);  // matrix
    write_be(data+56, 0);  // matrix

    write_be(data+60, 0);  // matrix
    write_be(data+64, 0);  // matrix
    write_be(data+68, 0x40000000);  // matrix

    write_be(data+72, 0);  // preview time
    write_be(data+76, 0);  // preview duration
    write_be(data+80, 0);  // poster time
    write_be(data+84, 0);  // selection time
    write_be(data+88, 0);  // selection duration
    write_be(data+92, 0);  // current time

    write_be(data+96, 2);  // next track ID
}

static void prepare_box_tkhd(mp4_ctx_t* ctx) {
    uint8_t* data = luat_heap_malloc(0x5C - 8);
    ctx->box_tkhd.data = data; // 固定长度
    ctx->box_tkhd.self_data_len = 0x5C - 8; // 固定长度

    write_be(data, 0x00000007); // version = 0, flags = 0
    write_be(data+4, 0);  // creation time
    write_be(data+8, 0);  // modification time
    write_be(data+12, 1);  // track ID
    write_be(data+16, 0);  // reserved
    write_be(data+20, ctx->frame_id * (1000 / ctx->frame_fps));  // duration
    write_be(data+24, 0);  // reserved
    write_be(data+28, 0);  // reserved
    write_be_short(data+32, 0);  // layer
    write_be_short(data+34, 0);  // alternate group
    write_be_short(data+36, 0);  // volume
    write_be_short(data+38, 0);  // reserved

    // matrix
    write_be(data+40, 0x10000);  // matrix
    write_be(data+44, 0);  // matrix
    write_be(data+48, 0);  // matrix

    write_be(data+52, 0);  // matrix
    write_be(data+56, 0x10000);  // matrix
    write_be(data+60, 0);  // matrix

    write_be(data+64, 0);  // matrix
    write_be(data+68, 0);  // matrix
    write_be(data+72, 0x40000000);  // matrix

    write_be(data+76, ctx->frame_w << 16);
    write_be(data+80, ctx->frame_h << 16);
}

static void prepare_box_mdhd(mp4_ctx_t* ctx) {
    uint8_t* data = luat_heap_malloc(0x20 - 8);
    ctx->box_mdhd.data = data; // 固定长度
    ctx->box_mdhd.self_data_len = 0x20 - 8; // 固定长度

    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, 0);  // creation time
    write_be(data+8, 0);  // modification time
    write_be(data+12, 1000);  // timescale
    write_be(data+16, ctx->frame_id * (1000 / ctx->frame_fps));  // duration
    write_be_short(data+20, 0x55c4);  // language (und)
    write_be_short(data+22, 0);  // language (und)
}

static void prepare_box_hdlr(mp4_ctx_t* ctx) {
    uint8_t* data = luat_heap_malloc(0x2D - 8);
    ctx->box_hdlr.data = data; // 固定长度
    ctx->box_hdlr.self_data_len = 0x2D - 8; // 固定长度

    write_be(data, 0); // version = 0, flags = 0
    write_be(data+4, 0); // component type
    memcpy(data+8, "vide", 4); // component subtype
    write_be(data+12, 0); // component manufacturer
    write_be(data+16, 0); // component flags
    write_be(data+20, 0); // component flags mask
    memcpy(data+24, "VideoHandler\x00", 12); // name
}

static void prepare_box_vmhd(mp4_ctx_t* ctx) {
    // 视频媒体头
    uint8_t* data = luat_heap_malloc(0x14 - 8);
    ctx->box_vmhd.data = data; // 固定长度
    ctx->box_vmhd.self_data_len = 0x14 - 8; // 固定长度

    memset(data, 0, ctx->box_vmhd.self_data_len);
    write_be(data, 1);
}

static void prepare_box_dinf(mp4_ctx_t* ctx) {
    // 视频媒体头

    // dref直接实现了
    ctx->box_dref.data = luat_heap_malloc(8);
    ctx->box_dref.self_data_len = 8;
    write_be(ctx->box_dref.data, 0); // version = 0, flags = 0
    write_be(ctx->box_dref.data+4, 1); // entry count

    ctx->box_url.data = luat_heap_malloc(4);
    ctx->box_url.self_data_len = 4; // 固定长度
    write_be(ctx->box_url.data, 1); // version = 0, flags = 0
}

static int prepare_box(mp4_ctx_t* ctx) {
	// 准备好所有box的数据
	if (ctx->box_moov.mboxs[0] == NULL) {
		prepare_box_tree(ctx);
	}
    if (ctx->frame_id == 0) {
        LLOGD("一帧都没有呀");
        return -1;
    }
    if (ctx->iframe_id_index == 0) {
        LLOGD("一个id帧都没有呀");
        return -1;
    }

    // 先处理stbl及子box
    prepare_box_stbl(ctx);

    // 然后是 mdif/dinf/vmhd
    prepare_box_mdhd(ctx);
    prepare_box_hdlr(ctx);
    prepare_box_vmhd(ctx);
    prepare_box_dinf(ctx);

    // 然后是 trak/tkhd
    prepare_box_tkhd(ctx);

    // 最后是 mvhd
    prepare_box_mvhd(ctx);

    return 0;
}

static int write_box(mp4_ctx_t* ctx, mp4box_t* box) {
    // LLOGD("写入box %s len 0x%04X", box->tp, box->len);
    uint8_t tmp[4];
    tmp[0] = (box->len >> 24) & 0xff;
    tmp[1] = (box->len >> 16) & 0xff;
    tmp[2] = (box->len >> 8) & 0xff;
    tmp[3] = (box->len >> 0) & 0xff;
    int r = 0;
    r = buffered_write(ctx, tmp, 4);
    if (r) return r;
    r = buffered_write(ctx, box->tp, 4);
    if (r) return r;

    if (box->data) {
        r = buffered_write(ctx, box->data, box->self_data_len);
        if (r) return r;
    }
    for (size_t i = 0; i < LUAT_VTOOL_MP4BOX_MAX_CLIENT; i++)
    {
        if (box->mboxs[i] == NULL) {
            continue;
        }
        r = write_box(ctx, box->mboxs[i]);
        if (r) return r;
    }
    
    return 0;
}

static void flush_box(mp4_ctx_t* ctx) {
    // 与通用写缓冲一致，统一调用buffered_flush
    buffered_flush(ctx);
}

static void clean_box(mp4box_t* box) {
    if (box == NULL) {
        return;
    }
    if (box->data) {
        luat_heap_free(box->data);
        box->data = NULL;
    }
    for (size_t i = 0; i < LUAT_VTOOL_MP4BOX_MAX_CLIENT; i++)
    {
        if (box->mboxs[i] != NULL) {
            clean_box(box->mboxs[i]);
            box->mboxs[i] = NULL;
        }
    }
}

// 重新计算box的大小
static void cal_box(mp4box_t* box) {
    if (box == NULL) {
        return;
    }
    for (size_t i = 0; i < LUAT_VTOOL_MP4BOX_MAX_CLIENT; i++)
    {
        if (box->mboxs[i] != NULL) {
            cal_box(box->mboxs[i]);
        }
    }
    // 子box已经更新完了, 更新自己的
    box->len = 8 + box->self_data_len;
    for (size_t i = 0; i < LUAT_VTOOL_MP4BOX_MAX_CLIENT; i++)
    {
        if (box->mboxs[i] != NULL) {
            box->len += box->mboxs[i]->len;
        }
    }
}

static void print_box(mp4box_t* box, uint8_t level) {
    if (box == NULL) {
        return;
    }
    char tmp[16] = {0};
    for (size_t i = 0; i < level; i++) {
        tmp[i] = ' ';
    }
    for (size_t i = 0; i < LUAT_VTOOL_MP4BOX_MAX_CLIENT; i++) {
        if (box->mboxs[i] != NULL) {
            print_box(box->mboxs[i], level + 1);
        }
    }
    LLOGD("%s %s %d", tmp, box->tp, box->len);
}

// 将一个box树序列化到内存缓冲（一次性生成moov数据）
static int serialize_box_to_mem(mp4box_t* box, uint8_t* out, size_t cap, size_t* off) {
    if (box == NULL) return 0;
    if (*off + box->len > cap) {
        LLOGE("serialize overflow, need=%d cap=%d", (int)(*off + box->len), (int)cap);
        return -1;
    }
    write_be(out + *off, (uint32_t)box->len);
    memcpy(out + *off + 4, box->tp, 4);
    *off += 8;
    if (box->self_data_len && box->data) {
        memcpy(out + *off, box->data, box->self_data_len);
        *off += box->self_data_len;
    }
    for (size_t i = 0; i < LUAT_VTOOL_MP4BOX_MAX_CLIENT; i++) {
        if (box->mboxs[i] != NULL) {
            int r = serialize_box_to_mem(box->mboxs[i], out, cap, off);
            if (r) return r;
        }
    }
    return 0;
}

mp4_ctx_t* luat_vtool_mp4box_creare(const char* path, uint32_t frame_w, uint32_t frame_h, uint32_t frame_fps) {
    // 防御path太长
    if (strlen(path) >= LUAT_VTOOL_MP4BOX_PATH_MAX) {
        LLOGE("path too long %s", path);
        return NULL;
    }
    FILE* fd = luat_fs_fopen(path, "w+");
    if (fd < 0) {
        LLOGE("open %s failed", path);
        return NULL;
    }
    mp4_ctx_t* ctx = luat_heap_malloc(sizeof(mp4_ctx_t));
    if (ctx == NULL) {
        LLOGE("malloc mp4 ctx failed");
        luat_fs_fclose(fd);
        return NULL;
    }
    memset(ctx, 0, sizeof(mp4_ctx_t));
    ctx->frame_w = frame_w;
    ctx->frame_h = frame_h;
    ctx->frame_fps = frame_fps;
    ctx->fd = fd;
    memcpy(ctx->path, path, strlen(path)+1);

    luat_rtos_mutex_create(&ctx->lock);

    prepare_box_tree(ctx);

    // 初始化256KB写缓冲
    if (buffered_init(ctx, MP4BOX_WRITE_BUFFER_SIZE)) {
        LLOGE("init write buffer failed");
        luat_fs_fclose(fd);
        luat_heap_free(ctx);
        return NULL;
    }

    // 写入ftyp
    uint8_t data[64] = {0};
    memcpy(data, "isom", 4);
    memcpy(data + 4, "\x00\x00\x02\x00", 4);
    memcpy(data + 8, "isom", 4);
    memcpy(data + 12, "iso2", 4);
    memcpy(data + 16, "avc1", 4);
    memcpy(data + 20, "mp41", 4);
    mp4box_t ftyp = {.tp = "ftyp", .len = 8 + 24, .data = data, .self_data_len = 24};
    write_box(ctx, &ftyp);
    // 对齐ffmpeg的做法, 再加一个free box
    mp4box_t free = {.tp = "free", .len = 8, .data = data, .self_data_len = 0};
    write_box(ctx, &free);
    // 记录mdat头部写入位置（逻辑偏移）
    ctx->mdat_offset = (uint32_t)buffered_tell(ctx);
    LLOGD("mdat offset 0x%08X", ctx->mdat_offset);

    // 写入mdat的头部信息
    mp4box_t mdat = {.tp = "mdat", .len = 8, .data = NULL, .self_data_len = 0};
    write_box(ctx, &mdat);
    return ctx;
}

static void next_nalu(uint8_t* data, size_t limit, size_t* len) {
    *len = 0;
    if (limit < 8) {
        return;
    }
    size_t index = 4;
    while (index < limit - 4) {
        if (data[index] == 0x00 && data[index + 1] == 0x00 && data[index + 2] == 0x00&& data[index + 3] == 0x01) {
            *len = index;
            return;
        }
        index++;
    }
    // 没有找到, 说明是最后一个
    if (data[0] == 0x00 && data[1] == 0x00 && data[2] == 0x00&& data[3] == 0x01) {
        *len = limit;
        return;
    }
}

static int check_frame_data_size(mp4_ctx_t* ctx) {
    uint32_t* ptr = NULL;
    if (ctx->frame_offset_len - ctx->frame_offset_index < 16) {
        ptr = luat_heap_realloc(ctx->frame_offsets, (ctx->frame_offset_len + 16) * sizeof(uint32_t));
        if (ptr == NULL) {
            LLOGE("realloc frame offsets failed %d %d", ctx->frame_offset_len, ctx->frame_offset_len + 16);
            return -1;
        }
        ctx->frame_offset_len += 16;
        ctx->frame_offsets = ptr;
    }
    if (ctx->frame_size_len - ctx->frame_size_index < 16) {
        ptr = luat_heap_realloc(ctx->frame_sizes, (ctx->frame_size_len + 16) * sizeof(uint32_t));
        if (ptr == NULL) {
            LLOGE("realloc frame sizes failed %d %d", ctx->frame_size_len, ctx->frame_size_len + 16);
            return -1;
        }
        ctx->frame_size_len += 16;
        ctx->frame_sizes = ptr;
    }
    if (ctx->iframe_id_len - ctx->iframe_id_index < 16) {
        ptr = luat_heap_realloc(ctx->iframe_ids, (ctx->iframe_id_len + 16) * sizeof(uint32_t));
        if (ptr == NULL) {
            LLOGE("realloc iframe ids failed %d %d", ctx->iframe_id_len, ctx->iframe_id_len + 16);
            return -1;
        }
        ctx->iframe_id_len += 16;
        ctx->iframe_ids = ptr;
    }
    // frame_durs 也要放
    if (ctx->frame_dur_len - ctx->frame_dur_index < 16) {
        ptr = luat_heap_realloc(ctx->frame_durs, (ctx->frame_dur_len + 16) * sizeof(uint32_t));
        if (ptr == NULL) {
            LLOGE("realloc frame durs failed %d %d", ctx->frame_dur_len, ctx->frame_dur_len + 16);
            return -1;
        }
        ctx->frame_dur_len += 16;
        ctx->frame_durs = ptr;
    }
    return 0;
}

static int append_frame(mp4_ctx_t* ctx, uint8_t* nalu, size_t len) {
    // 记录一下当前的偏移量
    size_t offset = buffered_tell(ctx);
    int ret = check_frame_data_size(ctx);
    if (ret) {
        LLOGE("检查帧缓存大小失败 %d", ret);
        return ret;
    }
    ctx->frame_offsets[ctx->frame_offset_index] = offset;
    ctx->frame_offset_index++;
    ctx->frame_sizes[ctx->frame_size_index] = len; // 使用长度32bit替代
    ctx->frame_size_index++;

    // 计算一下时长
    if (ctx->prev_frame_tms == 0) {
        // 第一帧0, 时长设置为100ms
        ctx->frame_durs[ctx->frame_dur_index] = 1000 / ctx->frame_fps;
        ctx->start_time = luat_mcu_tick64_ms();
    }
    else {
        uint32_t time_used = (uint32_t)(luat_mcu_tick64_ms() - ctx->prev_frame_tms);
        if (time_used > 1000) {
            time_used = 1000;
        }
        else if (time_used < (1000 / ctx->frame_fps)) {
            time_used = 1000 / ctx->frame_fps;
        }
        ctx->frame_durs[ctx->frame_dur_index] = (uint32_t)time_used;
    }
    // LLOGD("帧时长 %d", ctx->frame_durs[ctx->frame_dur_index]);
    ctx->prev_frame_tms = luat_mcu_tick64_ms();
    ctx->frame_dur_index++;

    // LLOGD("添加帧数据 %d %d %d %d", (nalu[4] & 0x1F), ctx->frame_id, offset, len);
    if ((nalu[4] & 0x1F) == 0x05) {
        // LLOGD("发现I帧 %d", ctx->frame_id);
        ctx->iframe_ids[ctx->iframe_id_index] = ctx->frame_id + 1;
        ctx->iframe_id_index++;
    }
    // 直接添加到mdat的末尾
    uint8_t tmp[4];
    uint32_t tmplen = len - 4;
    tmp[0] = (tmplen >> 24) & 0xff;
    tmp[1] = (tmplen >> 16) & 0xff;
    tmp[2] = (tmplen >> 8) & 0xff;
    tmp[3] = (tmplen >> 0) & 0xff;
    ret = buffered_write(ctx, tmp, 4);
    if (ret) {
        LLOGE("写入NALU头失败 %d", ret);
        return ret;
    }
    // LLOGD("写入NALU数据长度 %d", len - 4);
    ret = buffered_write(ctx, nalu + 4, len - 4);
    if (ret) {
        LLOGE("写入NALU数据失败 %d", ret);
        return ret;
    }

    // 更新偏移量表, 更新帧id
    ctx->frame_id ++;

    // 打印当前文件大小
    ret = (int)buffered_tell(ctx);
    // LLOGD("当前文件大小 %d frame %d", ret, ctx->frame_id);
    return 0;
}

int luat_vtool_mp4box_write_frame(mp4_ctx_t* ctx, uint8_t* data, size_t len) {
    // 首先, 分析NALU
    // LLOGD("开始分析NALU %p %d %02X%02X%02X%02X", data, len, data[0], data[1], data[2], data[3]);
    size_t nalu_len = 0;
    uint8_t* nalu = data;
    uint8_t nalu_tp = 0;;
    int ret = 0;
    while (1) {
        next_nalu(nalu, len, &nalu_len);
        if (nalu_len == 0) {
            break;
        }
        nalu_tp = nalu[4] & 0x1f;
        // LLOGD("nalu tp %d len %d", nalu_tp, nalu_len);
        // 如果是SPS/PPS, 保存起来
        if (nalu_tp == 7) {
            if (ctx->sps == NULL) {
                // LLOGI("save sps %d", nalu_len - 4);
                ctx->sps = luat_heap_malloc(nalu_len - 4);
                memcpy(ctx->sps, nalu + 4, nalu_len - 4);
                ctx->sps_len = nalu_len - 4;
            }
        }
        else if (nalu_tp == 8) {
            if (ctx->pps == NULL) {
                // LLOGI("save pps %d", nalu_len - 4);
                ctx->pps = luat_heap_malloc(nalu_len - 4);
                memcpy(ctx->pps, nalu + 4, nalu_len - 4);
                ctx->pps_len = nalu_len - 4;
            }
        }
        else if (nalu_tp == 1 || nalu_tp == 5) {
            // 如果是I帧P帧, 保存起来
            ret = append_frame(ctx, nalu, nalu_len);
        }
        else {
            // LLOGD("nalu tp %d len %d, ignore", nalu_tp, nalu_len);
        }
        nalu += nalu_len;
        len -= nalu_len;
    }
    return ret;
}

int luat_vtool_mp4box_close(mp4_ctx_t* ctx) {
    int ret = 0;
    if (ctx == NULL) {
        LLOGE("ctx is NULL");
        return -1;
    }
    if (ctx->lock == NULL) {
        LLOGE("ctx lock is NULL");
        ret = -3;
        goto clean;
    }
    // luat_rtos_mutex_lock(ctx->lock, LUAT_WAIT_FOREVER);
    // 刷新缓冲，确保文件大小正确
    buffered_flush(ctx);
    // 然后, 把文件关掉, 重新打开
    // luat_fs_fclose(ctx->fd);
    // LLOGI("重新打开文件 %s 原本的fd %d", ctx->path, ctx->fd);
    // ctx->fd = luat_fs_fopen(ctx->path, "r+b");
    // LLOGI("重新打开文件 %s 重新打开的fd %d", ctx->path, ctx->fd);
    luat_fs_fseek(ctx->fd, 0, SEEK_END);
    // 把mdat的box大小更新一下
    ret = luat_fs_ftell(ctx->fd);
    LLOGI("文件当前长度 %d", ret);
    long int pos = ctx->mdat_offset;
    size_t mdat_len = ret - ctx->mdat_offset;
    LLOGI("mdat 长度更新为 %d 目标偏移量 %d sizeof(int) %d sizeof(long int) %d", mdat_len, ctx->mdat_offset, sizeof(int), sizeof(long int));
    ret = luat_fs_fseek(ctx->fd, pos, SEEK_SET); // fypt头部的数据长度是固定的
    if (ret != 0) {
        LLOGE("seek mdat offset failed %d", ret);
    }
    ret = luat_fs_ftell(ctx->fd);
    LLOGD("当前fd偏移量位置 %d 期望 %d", ret, ctx->mdat_offset);
    if (ret != (int)ctx->mdat_offset) {
        LLOGE("seek mdat offset failed %d", ret);
        ret = -1;
        goto clean;
    }
    uint8_t tmp[4] = {0};
    uint8_t tmp2[4] = {0};
    tmp[0] = (mdat_len >> 24) & 0xff;
    tmp[1] = (mdat_len >> 16) & 0xff;
    tmp[2] = (mdat_len >> 8) & 0xff;
    tmp[3] = (mdat_len >> 0) & 0xff;
    ret = luat_fs_fwrite(tmp, 1, 4, ctx->fd);
    LLOGI("写入mdat长度结果 %d", ret);
    if (ret != 4) {
        LLOGE("更新mdat长度失败 %d", ret);
        ret = -1;
        goto clean;
    }
    ret = luat_fs_ftell(ctx->fd);
    LLOGD("当前fd偏移量位置 %d", ret);
    // 回归到原本的位置, 读出来进行判断
    luat_fs_fseek(ctx->fd, ctx->mdat_offset, SEEK_SET);
    ret = luat_fs_fread(tmp2, 1, 4, ctx->fd);
    LLOGI("读回mdat长度结果 %d", ret);
    // 数据对比判断
    if (tmp2[0] != tmp[0] || tmp2[1] != tmp[1] || tmp2[2] != tmp[2] || tmp2[3] != tmp[3]) {
        LLOGE("mdat长度写入后读回数据不对!!!");
        ret = -1;
        goto clean;
    }
    else {
        LLOGI("mdat长度写入后读回数据正确");
        luat_fs_fflush(ctx->fd);
    }
    // 切换到文件末尾, 准备写入moov box
    luat_fs_fseek(ctx->fd, 0, SEEK_END);

    ret = prepare_box(ctx);
    if (ret) {
        LLOGE("box数据不对呀 %d", ret);
        goto clean;
    }
    else {
        cal_box(&ctx->box_moov);
        size_t moov_len = ctx->box_moov.len;
        uint8_t* moov_buf = (uint8_t*)luat_heap_malloc(moov_len);
        if (!moov_buf) {
            LLOGE("alloc moov buffer failed size=%d", (int)moov_len);
            ret = -1;
            goto clean;
        }
        size_t moov_off = 0;
        ret = serialize_box_to_mem(&ctx->box_moov, moov_buf, moov_len, &moov_off);
        if (ret || moov_off != moov_len) {
            LLOGE("serialize moov failed ret=%d off=%d len=%d", ret, (int)moov_off, (int)moov_len);
            luat_heap_free(moov_buf);
            ret = -1;
            goto clean;
        }
        // 一次性写入moov
        // 保证文件指针在末尾且缓冲为空
        buffered_flush(ctx);
        luat_fs_fseek(ctx->fd, 0, SEEK_END);
        int w = luat_fs_fwrite(moov_buf, 1, moov_len, ctx->fd);
        luat_heap_free(moov_buf);
        if (w != (int)moov_len) {
            LLOGE("write moov failed %d/%d", w, (int)moov_len);
            ret = -1;
            goto clean;
        }
        luat_fs_fflush(ctx->fd);
        LLOGI("总帧数 %d, 关键帧数 %d", ctx->frame_id, ctx->iframe_id_index);
    }

clean:
    if (ctx->fd) {
        if (ret  == 0) {
            // 最终确保缓冲写入
            buffered_flush(ctx);
            luat_fs_fseek(ctx->fd, 0, SEEK_END);
            luat_fs_fflush(ctx->fd);
            ret = luat_fs_ftell(ctx->fd);
            LLOGI("写入完成, 文件最终长度 %d", ret);
            ret = 0;
            luat_fs_fclose(ctx->fd);
        }
        else {
            luat_fs_fclose(ctx->fd);
        }
        ctx->fd = 0;
    }
    else {
        LLOGE("文件句柄为空!!!");
        ret = -10;
    }
    LLOGD("释放mp4资源, 释放内存");
    // 释放全部资源
    if (ctx->sps) {
        luat_heap_free(ctx->sps);
        ctx->sps = NULL;
    }
    if (ctx->pps) {
        luat_heap_free(ctx->pps);
        ctx->pps = NULL;
    }
    if (ctx->frame_offsets) {
        luat_heap_free(ctx->frame_offsets);
        ctx->frame_offsets = NULL;
        ctx->frame_offset_index = 0;
        ctx->frame_offset_len = 0;
    }
    if (ctx->frame_sizes) {
        luat_heap_free(ctx->frame_sizes);
        ctx->frame_sizes = NULL;
        ctx->frame_size_index = 0;
        ctx->frame_size_len = 0;
    }
    if (ctx->iframe_ids) {
        luat_heap_free(ctx->iframe_ids);
        ctx->iframe_ids = NULL;
        ctx->iframe_id_index = 0;
        ctx->iframe_id_len = 0;
    }
    if (ctx->frame_durs) {
        luat_heap_free(ctx->frame_durs);
        ctx->frame_durs = NULL;
        ctx->frame_dur_index = 0;
        ctx->frame_dur_len = 0;
    }
    if (ctx->box_buff) {
        luat_heap_free(ctx->box_buff);
        ctx->box_buff = NULL;
        ctx->box_buff_size = 0;
        ctx->box_buff_offset = 0;
    }
    if (ctx->lock) {
        luat_rtos_mutex_delete(ctx->lock);
        ctx->lock = NULL;
    }
    clean_box(&ctx->box_moov);
    luat_heap_free(ctx);
    LLOGI("mp4文件关闭完成, box写入结束, 文件已关闭");
    return ret;
}
