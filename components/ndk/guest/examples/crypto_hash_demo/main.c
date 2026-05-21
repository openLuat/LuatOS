#include <stdint.h>

#define NDK_RAM_BASE        0x80000000u
#define NDK_EXCHANGE        0x11110000u
#define NDK_SYSCON          0x11100000u
#define NDK_DONE_MARKER     0x5555u
#define NDK_CMD_MD5         1u
#define NDK_CMD_CRC32       2u
#define NDK_STATUS_OK       0u
#define NDK_STATUS_BAD_CMD  1u

static uint32_t ndk_memory_size(void) {
    uint32_t size = 0;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13B" : "=r"(size));
    return size;
}

static uint32_t load32_le(const uint8_t *p) {
    return ((uint32_t)p[0]) |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static void store32_le(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static uint32_t rol32(uint32_t v, uint32_t s) {
    return (v << s) | (v >> (32u - s));
}

static const uint32_t md5_s[64] = {
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
};

static const uint32_t md5_k[64] = {
    0xd76aa478u, 0xe8c7b756u, 0x242070dbu, 0xc1bdceeeu,
    0xf57c0fafu, 0x4787c62au, 0xa8304613u, 0xfd469501u,
    0x698098d8u, 0x8b44f7afu, 0xffff5bb1u, 0x895cd7beu,
    0x6b901122u, 0xfd987193u, 0xa679438eu, 0x49b40821u,
    0xf61e2562u, 0xc040b340u, 0x265e5a51u, 0xe9b6c7aau,
    0xd62f105du, 0x02441453u, 0xd8a1e681u, 0xe7d3fbc8u,
    0x21e1cde6u, 0xc33707d6u, 0xf4d50d87u, 0x455a14edu,
    0xa9e3e905u, 0xfcefa3f8u, 0x676f02d9u, 0x8d2a4c8au,
    0xfffa3942u, 0x8771f681u, 0x6d9d6122u, 0xfde5380cu,
    0xa4beea44u, 0x4bdecfa9u, 0xf6bb4b60u, 0xbebfbc70u,
    0x289b7ec6u, 0xeaa127fau, 0xd4ef3085u, 0x04881d05u,
    0xd9d4d039u, 0xe6db99e5u, 0x1fa27cf8u, 0xc4ac5665u,
    0xf4292244u, 0x432aff97u, 0xab9423a7u, 0xfc93a039u,
    0x655b59c3u, 0x8f0ccc92u, 0xffeff47du, 0x85845dd1u,
    0x6fa87e4fu, 0xfe2ce6e0u, 0xa3014314u, 0x4e0811a1u,
    0xf7537e82u, 0xbd3af235u, 0x2ad7d2bbu, 0xeb86d391u
};

static uint32_t md5_words[16];
static uint8_t md5_tail[128];

static void md5_transform(uint32_t state[4], const uint8_t block[64]) {
    uint32_t a = state[0];
    uint32_t b = state[1];
    uint32_t c = state[2];
    uint32_t d = state[3];
    for (uint32_t i = 0; i < 16; ++i) {
        md5_words[i] = load32_le(block + (i * 4u));
    }

    for (uint32_t i = 0; i < 64; ++i) {
        uint32_t f;
        uint32_t g;
        if (i < 16u) {
            f = (b & c) | (~b & d);
            g = i;
        } else if (i < 32u) {
            f = (d & b) | (~d & c);
            g = (5u * i + 1u) & 15u;
        } else if (i < 48u) {
            f = b ^ c ^ d;
            g = (3u * i + 5u) & 15u;
        } else {
            f = c ^ (b | ~d);
            g = (7u * i) & 15u;
        }

        uint32_t temp = d;
        d = c;
        c = b;
        uint32_t sum = a + f + md5_k[i] + md5_words[g];
        b = b + rol32(sum, md5_s[i]);
        a = temp;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
}

static void md5_compute(const uint8_t *data, uint32_t len, uint8_t out[16]) {
    uint32_t state[4] = {
        0x67452301u,
        0xefcdab89u,
        0x98badcfeu,
        0x10325476u
    };
    uint32_t remaining = len;
    uint32_t offset = 0;

    while (remaining >= 64u) {
        md5_transform(state, data + offset);
        offset += 64u;
        remaining -= 64u;
    }

    for (uint32_t i = 0; i < 128u; ++i) {
        md5_tail[i] = 0;
    }
    for (uint32_t i = 0; i < remaining; ++i) {
        md5_tail[i] = data[offset + i];
    }
    md5_tail[remaining] = 0x80u;

    if (remaining >= 56u) {
        md5_transform(state, md5_tail);
        for (uint32_t i = 0; i < 64u; ++i) {
            md5_tail[i] = 0;
        }
    }

    store32_le(md5_tail + 56u, len << 3);
    store32_le(md5_tail + 60u, len >> 29);
    md5_transform(state, md5_tail);

    store32_le(out + 0, state[0]);
    store32_le(out + 4, state[1]);
    store32_le(out + 8, state[2]);
    store32_le(out + 12, state[3]);
}

static uint32_t crc32_table[256];
static uint32_t crc32_ready = 0;

static void crc32_init(void) {
    for (uint32_t i = 0; i < 256u; ++i) {
        uint32_t crc = i;
        for (uint32_t j = 0; j < 8u; ++j) {
            if (crc & 1u) {
                crc = (crc >> 1) ^ 0xEDB88320u;
            } else {
                crc >>= 1;
            }
        }
        crc32_table[i] = crc;
    }
    crc32_ready = 1;
}

static uint32_t crc32_compute(const uint8_t *data, uint32_t len) {
    if (!crc32_ready) {
        crc32_init();
    }

    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < len; ++i) {
        crc = crc32_table[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}

static int main(void) {
    volatile uint32_t *ex = (volatile uint32_t *)NDK_EXCHANGE;
    uint32_t cmd = ex[0];
    uint32_t len = ex[1];
    uint32_t input_offset = ex[2];
    uint32_t output_offset = ex[3];
    const uint8_t *input = (const uint8_t *)(NDK_EXCHANGE + input_offset);
    uint8_t *output = (uint8_t *)(NDK_EXCHANGE + output_offset);

    ex[4] = NDK_STATUS_OK;
    ex[5] = len;

    if (cmd == NDK_CMD_MD5) {
        md5_compute(input, len, output);
        ex[6] = 16u;
    } else if (cmd == NDK_CMD_CRC32) {
        uint32_t crc = crc32_compute(input, len);
        store32_le(output, crc);
        ex[6] = 4u;
    } else {
        ex[4] = NDK_STATUS_BAD_CMD;
        ex[6] = 0u;
    }

    *(volatile uint32_t *)NDK_SYSCON = NDK_DONE_MARKER;
    return 0;
}

__attribute__((noreturn)) void _start(void) {
    uintptr_t sp_top = (uintptr_t)(NDK_RAM_BASE + ndk_memory_size() - 16u);
    __asm__ volatile("mv sp, %0" :: "r"(sp_top));
    (void)main();
    while (1) {
        __asm__ volatile("wfi");
    }
}
