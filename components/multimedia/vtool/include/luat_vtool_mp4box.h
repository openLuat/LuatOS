#ifndef LUAT_VTOOL_MP4BOX_H
#define LUAT_VTOOL_MP4BOX_H

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_rtos.h"

#define LUAT_VTOOL_MP4BOX_MAX_CLIENT 8
#define LUAT_VTOOL_MP4BOX_PATH_MAX 255

typedef struct mp4box
{
	size_t len;
	uint8_t tp[8];
	struct mp4box* mboxs[LUAT_VTOOL_MP4BOX_MAX_CLIENT];
	size_t self_data_len;
	uint8_t *data;
}mp4box_t;


typedef struct mp4_ctx {
    FILE* fd; // 文件句柄
    char path[LUAT_VTOOL_MP4BOX_PATH_MAX + 1];
    uint32_t frame_id; // 当前帧的id
    uint64_t prev_frame_time; // 上一帧的时间, 单位ms
    uint32_t frame_w; // 宽
    uint32_t frame_h; // 高
    uint32_t frame_fps; // 帧率

    uint32_t* iframe_ids; // iframe的id列表
    uint32_t iframe_id_index;
    uint32_t iframe_id_len;

    uint32_t* frame_offsets; // 帧的偏移列表
    uint32_t frame_offset_index;
    uint32_t frame_offset_len;

    uint32_t* frame_sizes; // 帧的偏移列表
    uint32_t frame_size_index;
    uint32_t frame_size_len;

    uint32_t* frame_durs; // 帧的时长列表,暂时不使用
    uint32_t frame_dur_index;
    uint32_t frame_dur_len;

    uint64_t prev_frame_tms; // 上一帧的时间戳, 单位ms
    uint64_t start_time; // 开始时间戳, 单位ms

    uint8_t* sps;
    uint32_t sps_len;

    uint8_t* pps;
    uint32_t pps_len;

    uint32_t mdat_offset; // mdat的偏移

    // box列表
    // 只填充必要的box, 其他box一概不加
    // 这里是扁平的结构
    // 后面用代码整理成树形结构
    mp4box_t box_moov;
    mp4box_t box_mvhd;
    mp4box_t box_trak;
    mp4box_t box_tkhd;
    mp4box_t box_mdia;
    mp4box_t box_mdhd;
    mp4box_t box_hdlr;
    mp4box_t box_minf;
    mp4box_t box_vmhd;
    mp4box_t box_dinf;
    mp4box_t box_dref;
    mp4box_t box_url;
    mp4box_t box_stbl;
    mp4box_t box_avcc;
    mp4box_t box_avc1;
    mp4box_t box_stsd;
    mp4box_t box_stts;
    mp4box_t box_stsc;
    mp4box_t box_stsz;
    mp4box_t box_stco;
    mp4box_t box_stss;

    char* box_buff;
    size_t box_buff_size;
    size_t box_buff_offset;

    uint64_t first_frame_tms; // 第一帧的时间戳, 单位ms
    uint64_t last_frame_tms; // 最后一帧的时间戳, 单位ms
}mp4_ctx_t;

mp4_ctx_t* luat_vtool_mp4box_creare(const char* path, uint32_t frame_w, uint32_t frame_h, uint32_t frame_fps);
int luat_vtool_mp4box_write_frame(mp4_ctx_t* ctx, uint8_t* data, size_t len);
int luat_vtool_mp4box_close(mp4_ctx_t* ctx);

#include "luat_mcu.h"

#endif
