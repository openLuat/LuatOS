#include <string.h>
#include <ctype.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_webc_codec.h"

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

int luat_webc_decode_payload(const char* encoding, const char* payload, uint8_t** out_data, size_t* out_len, const char** out_errmsg) {
    uint8_t* buff = NULL;
    size_t cap;
    size_t w = 0;
    const char* p;
    if (out_data) *out_data = NULL;
    if (out_len) *out_len = 0;
    if (out_errmsg) *out_errmsg = "invalid payload";
    if (!out_data || !out_len || !encoding || !payload) {
        return -1;
    }
    cap = strlen(payload) + 1;
    buff = luat_heap_malloc(cap);
    if (!buff) {
        if (out_errmsg) *out_errmsg = "no memory";
        return -1;
    }
    if (!strcmp(encoding, "utf8") || !strcmp(encoding, "utf-8")) {
        *out_len = strlen(payload);
        if (*out_len) {
            memcpy(buff, payload, *out_len);
        }
        *out_data = buff;
        return 0;
    }
    if (strcmp(encoding, "hex") && strcmp(encoding, "hex_escape")) {
        if (out_errmsg) *out_errmsg = "encoding must be utf8 or hex";
        luat_heap_free(buff);
        return -1;
    }

    p = payload;
    while (*p) {
        int hi = -1;
        int lo = -1;
        if (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n' || *p == ',' || *p == ';' || *p == '_') {
            p++;
            continue;
        }
        if (*p == '\\') {
            p++;
            if (*p == 'x' || *p == 'X') {
                p++;
                hi = hex_nibble(*p++);
                lo = hex_nibble(*p++);
            }
            else if (*p == 'n') {
                buff[w++] = '\n';
                p++;
                continue;
            }
            else if (*p == 'r') {
                buff[w++] = '\r';
                p++;
                continue;
            }
            else if (*p == 't') {
                buff[w++] = '\t';
                p++;
                continue;
            }
            else if (*p == '\\') {
                buff[w++] = '\\';
                p++;
                continue;
            }
            else {
                if (out_errmsg) *out_errmsg = "bad escape sequence";
                luat_heap_free(buff);
                return -1;
            }
        }
        else {
            if (*p == '0' && (p[1] == 'x' || p[1] == 'X')) {
                p += 2;
            }
            hi = hex_nibble(*p++);
            lo = hex_nibble(*p++);
        }
        if (hi < 0 || lo < 0) {
            if (out_errmsg) *out_errmsg = "hex payload has odd or invalid digits";
            luat_heap_free(buff);
            return -1;
        }
        buff[w++] = (uint8_t)((hi << 4) | lo);
    }

    *out_data = buff;
    *out_len = w;
    return 0;
}

char* luat_webc_encode_hex_escape(const uint8_t* data, size_t len) {
    static const char HEX[] = "0123456789ABCDEF";
    size_t out_len = len * 4;
    char* out = luat_heap_malloc(out_len + 1);
    if (!out) return NULL;
    for (size_t i = 0; i < len; i++) {
        out[i * 4] = '\\';
        out[i * 4 + 1] = 'x';
        out[i * 4 + 2] = HEX[(data[i] >> 4) & 0x0F];
        out[i * 4 + 3] = HEX[data[i] & 0x0F];
    }
    out[out_len] = 0;
    return out;
}

static int utf8_seq_len(const uint8_t* p, size_t left) {
    if (left == 0) return 0;
    if (p[0] < 0x80) return 1;
    if ((p[0] & 0xE0) == 0xC0) {
        if (left < 2 || (p[1] & 0xC0) != 0x80 || p[0] < 0xC2) return 0;
        return 2;
    }
    if ((p[0] & 0xF0) == 0xE0) {
        if (left < 3 || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80) return 0;
        return 3;
    }
    if ((p[0] & 0xF8) == 0xF0) {
        if (left < 4 || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80 || (p[3] & 0xC0) != 0x80) return 0;
        return 4;
    }
    return 0;
}

char* luat_webc_encode_utf8_display(const uint8_t* data, size_t len) {
    static const char HEX[] = "0123456789ABCDEF";
    char* out = luat_heap_malloc(len * 4 + 1);
    size_t w = 0;
    size_t i = 0;
    if (!out) return NULL;
    while (i < len) {
        int n = utf8_seq_len(data + i, len - i);
        if (n > 1) {
            memcpy(out + w, data + i, (size_t)n);
            w += (size_t)n;
            i += (size_t)n;
            continue;
        }
        if (n == 1 && data[i] >= 0x20 && data[i] <= 0x7E && data[i] != '\\') {
            out[w++] = (char)data[i++];
            continue;
        }
        if (n == 1 && data[i] == '\\') {
            out[w++] = '\\';
            out[w++] = '\\';
            i++;
            continue;
        }
        if (data[i] == '\r') {
            out[w++] = '\\';
            out[w++] = 'r';
            i++;
            continue;
        }
        if (data[i] == '\n') {
            out[w++] = '\\';
            out[w++] = 'n';
            i++;
            continue;
        }
        if (data[i] == '\t') {
            out[w++] = '\\';
            out[w++] = 't';
            i++;
            continue;
        }
        out[w++] = '\\';
        out[w++] = 'x';
        out[w++] = HEX[(data[i] >> 4) & 0x0F];
        out[w++] = HEX[data[i] & 0x0F];
        i++;
    }
    out[w] = 0;
    return out;
}
