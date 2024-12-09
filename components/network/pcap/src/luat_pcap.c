#include "luat_base.h"
#include "luat_pcap.h"
#include "luat_mcu.h"

typedef struct luat_pcap_ctx {
    luat_pcap_output output;
    void *arg;
}luat_pcap_ctx_t;

/* pcap文件头结构体 */
typedef struct pcap_file_header {
    uint32_t magic;         /* 标识文件开始，用来识别字节顺序 */
    uint16_t version_major; /* 主要版本号 */
    uint16_t version_minor; /* 次要版本号 */
    uint32_t r0;
    uint32_t r1;
    uint32_t snaplen;       /* 最大捕获长度 */
    uint32_t linktype;      /* 链路类型 */
}pcap_file_header_t;

/* pcap数据包头结构体 */
typedef struct pcap_pkthdr {
    uint32_t ts_sec;        /* 时间戳（秒） */
    uint32_t ts_usec;       /* 时间戳（微秒） */
    uint32_t caplen;        /* 捕获长度 */
    uint32_t len;           /* 实际长度 */
}pcap_pkthdr_t;


static luat_pcap_ctx_t ctx;

int luat_pcap_init(luat_pcap_output output, void *arg) {
    ctx.output = output;
    ctx.arg = arg;
    return 0;
}
int luat_pcap_write_head(void) {
    pcap_file_header_t head = {0};
    head.magic = 0xa1b2c3d4;
    head.version_major = 2;
    head.version_minor = 4;
    head.snaplen = 65535; // 64k
    head.linktype = 1; // 1: ethernet
    ctx.output(ctx.arg, &head, sizeof(pcap_file_header_t));
    return 0;
}

int luat_pcap_write_macpkg(const void *data, size_t len) {
    uint64_t ts = luat_mcu_tick64_ms();
    pcap_pkthdr_t head = {0};
    head.ts_sec = ts / 1000;
    head.ts_usec = (ts % 1000) * 1000;
    head.caplen = len;
    head.len = len;
    ctx.output(ctx.arg, &head, sizeof(pcap_pkthdr_t));
    ctx.output(ctx.arg, data, len);
    return 0;
}
