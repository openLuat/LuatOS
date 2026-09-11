/* Standalone harness for p256_ct.c — cross-check against python-generated vectors. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "luat_p256.h"

static int hex2bin(const char *hex, uint8_t *out, int len)
{
    if ((int)strlen(hex) != len * 2) return -1;
    for (int i = 0; i < len; i++) {
        unsigned v;
        if (sscanf(hex + 2 * i, "%02x", &v) != 1) return -1;
        out[i] = (uint8_t)v;
    }
    return 0;
}

#include "p256_tv.h"

static int fails = 0;

int main(void)
{
    uint8_t k[32], pt[64], out[64], exp[64];
    uint8_t u1[32], u2[32];
    int rc;
    size_t i;

    for (i = 0; i < sizeof(mulg) / sizeof(mulg[0]); i++) {
        rc = hex2bin(mulg[i].k, k, 32);
        rc = luat_p256_mul_g(out, k);
        if (mulg[i].rc != rc || (rc == 0 && (hex2bin(mulg[i].xy, exp, 64) || memcmp(out, exp, 64)))) {
            printf("FAIL mulg[%zu] rc=%d want %d\n", i, rc, mulg[i].rc);
            fails++;
        }
    }
    for (i = 0; i < sizeof(mulv) / sizeof(mulv[0]); i++) {
        hex2bin(mulv[i].k, k, 32);
        hex2bin(mulv[i].pt, pt, 64);
        rc = luat_p256_mul(out, k, pt);
        if (mulv[i].rc != rc || (rc == 0 && (hex2bin(mulv[i].xy, exp, 64) || memcmp(out, exp, 64)))) {
            printf("FAIL mulv[%zu] rc=%d want %d\n", i, rc, mulv[i].rc);
            fails++;
        }
    }
    for (i = 0; i < sizeof(madd) / sizeof(madd[0]); i++) {
        hex2bin(madd[i].u1, u1, 32);
        hex2bin(madd[i].u2, u2, 32);
        hex2bin(madd[i].q, pt, 64);
        rc = luat_p256_muladd(out, u1, u2, pt);
        if (madd[i].rc != rc || (rc == 0 && (hex2bin(madd[i].xy, exp, 64) || memcmp(out, exp, 64)))) {
            printf("FAIL madd[%zu] rc=%d want %d\n", i, rc, madd[i].rc);
            fails++;
        }
    }
    for (i = 0; i < sizeof(ecdh) / sizeof(ecdh[0]); i++) {
        uint8_t q1[64], q2[64], z1[64], z2[64];
        hex2bin(ecdh[i].d1, u1, 32);
        hex2bin(ecdh[i].d2, u2, 32);
        /* Q1 = d1*G, Q2 = d2*G, z1 = d1*Q2, z2 = d2*Q1 */
        if (luat_p256_mul_g(q1, u1) || luat_p256_mul_g(q2, u2)) { printf("FAIL ecdh[%zu] gen\n", i); fails++; continue; }
        if (luat_p256_mul(z1, u1, q2) || luat_p256_mul(z2, u2, q1)) { printf("FAIL ecdh[%zu] mul\n", i); fails++; continue; }
        if (memcmp(z1, z2, 64) || hex2bin(ecdh[i].z, exp, 64) || memcmp(z1, exp, 64)) {
            printf("FAIL ecdh[%zu] shared mismatch\n", i);
            fails++;
        }
    }

    printf(fails ? "RESULT: %d FAILURES\n" : "RESULT: ALL PASS (%zu+%zu+%zu+%zu vectors)\n",
           fails ? fails : 0, sizeof(mulg)/sizeof(mulg[0]), sizeof(mulv)/sizeof(mulv[0]),
           sizeof(madd)/sizeof(madd[0]), sizeof(ecdh)/sizeof(ecdh[0]));
    return fails ? 1 : 0;
}
