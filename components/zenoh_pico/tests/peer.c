/* SPDX-License-Identifier: MIT */
/* 独立C对端经真实router回显二进制，测试不以发送返回值代替实收。 */
#include "zenoh-pico.h"
#include <stdio.h>
#include <string.h>
static z_owned_session_t session;
static char output[256];
static int done, failed;
static unsigned received;
static void stop(z_loaned_sample_t *sample, void *context) { (void)sample; (void)context; done = 1; }
static void echo(z_loaned_sample_t *sample, void *context) {
    (void)context;
    z_owned_bytes_t value; z_owned_slice_t slice;
    if (z_bytes_to_slice(z_sample_payload(sample), &slice) < 0) { failed = 1; return; }
    if (z_slice_len(z_loan(slice)) == 10 && !memcmp(z_slice_data(z_loan(slice)), "__delete__", 10)) {
        z_view_keyexpr_t key; z_view_keyexpr_from_str(&key, output);
        if (z_delete(z_loan(session), z_loan(key), NULL) < 0) failed = 1;
        else { received++; printf("DELETE %u\n", received); fflush(stdout); }
        z_drop(z_move(slice)); return;
    }
    if (z_bytes_copy_from_buf(&value, z_slice_data(z_loan(slice)), z_slice_len(z_loan(slice))) < 0) {
        z_drop(z_move(slice)); failed = 1; return;
    }
    z_drop(z_move(slice)); z_view_keyexpr_t key;
    if (z_view_keyexpr_from_str(&key, output) < 0 || z_put(z_loan(session), z_loan(key), z_move(value), NULL) < 0) failed = 1;
    else { received++; printf("ECHO %u %zu\n", received, z_bytes_len(z_sample_payload(sample))); fflush(stdout); }
}
int main(int argc, char **argv) {
    if (argc != 3 || strlen(argv[2]) > 200) return 2;
    z_owned_config_t config; if (z_config_default(&config) < 0) return 2;
    zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, "client");
    zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, argv[1]);
    if (z_open(&session, z_move(config), NULL) < 0) return 3;
    char input[256], finish[256];
    snprintf(input, sizeof(input), "%s/in", argv[2]); snprintf(output, sizeof(output), "%s/out", argv[2]);
    snprintf(finish, sizeof(finish), "%s/stop", argv[2]);
    z_view_keyexpr_t ik, sk; z_view_keyexpr_from_str(&ik, input); z_view_keyexpr_from_str(&sk, finish);
    z_owned_closure_sample_t ec, sc; z_closure(&ec, echo, NULL, NULL); z_closure(&sc, stop, NULL, NULL);
    z_owned_subscriber_t es, ss;
    if (z_declare_subscriber(z_loan(session), &es, z_loan(ik), z_move(ec), NULL) < 0) { z_drop(z_move(session)); return 4; }
    if (z_declare_subscriber(z_loan(session), &ss, z_loan(sk), z_move(sc), NULL) < 0) { z_drop(z_move(es)); z_drop(z_move(session)); return 4; }
    printf("READY\n"); fflush(stdout);
    z_clock_t start = z_clock_now();
    while (!done && !failed && z_clock_elapsed_ms(&start) < 60000) { zp_spin_once(z_loan(session)); z_sleep_ms(5); }
    z_drop(z_move(ss)); z_drop(z_move(es)); z_drop(z_move(session));
    printf("PEER_DONE received=%u\n", received); return done && !failed && received ? 0 : 5;
}
