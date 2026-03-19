#include <stdio.h>
#include <stdlib.h>

extern int test_bitstream(void);
extern int test_sps_pps(void);
extern int test_cavlc(void);
extern int test_integration(void);

int main(void) {
    int pass = 0, fail = 0;

#define RUN(name, fn) do { \
    printf("Running %-20s ... ", #name); fflush(stdout); \
    if (fn() == 0) { printf("PASS\n"); pass++; } \
    else           { printf("FAIL\n"); fail++; } \
} while(0)

    RUN(bitstream,   test_bitstream);
    RUN(sps_pps,     test_sps_pps);
    RUN(cavlc,       test_cavlc);
    RUN(integration, test_integration);

    printf("\n%d passed, %d failed\n", pass, fail);
    return fail > 0 ? 1 : 0;
}
