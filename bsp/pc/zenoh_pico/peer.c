/* SPDX-License-Identifier: MIT */
/* 独立C对端经真实router回显二进制，测试不以发送返回值代替实收。 */
#include "zenoh-pico.h"
#include <stdio.h>
#include <string.h>
static z_owned_session_t session;
static char output[256];
static int done, failed;
static unsigned received;
static void peer_fail(int line) { failed = 1; fprintf(stderr, "PEER_FAIL line=%d\n", line); fflush(stderr); }
static int two_rounds, get_mode;
static unsigned get_received, device_get_count;
static char status_key[256], device_key[256];
static z_owned_query_t held[4];
static int held_used[4];
static z_clock_t held_at[4];
static unsigned device_replies;
static int device_pending;
static void stop(z_loaned_sample_t *sample, void *context) { (void)sample; (void)context; done = 1; }
static void echo(z_loaned_sample_t *sample, void *context) {
    (void)context;
    z_owned_bytes_t value; z_owned_slice_t slice;
    if (two_rounds) {
        static const unsigned char first[] = "LuatOS\0zenoh-pico\377:1";
        static const unsigned char second[] = "LuatOS\0zenoh-pico\377:2";
        const unsigned char *expected = received == 0 ? first : second;
        if (received >= 2 || z_bytes_to_slice(z_sample_payload(sample), &slice) < 0) { peer_fail(__LINE__); return; }
        int exact = z_slice_len(z_loan(slice)) == sizeof(first)-1 &&
                    !memcmp(z_slice_data(z_loan(slice)), expected, sizeof(first)-1);
        z_drop(z_move(slice));
        if (!exact) { peer_fail(__LINE__); return; }
    }
    if (z_bytes_to_slice(z_sample_payload(sample), &slice) < 0) { peer_fail(__LINE__); return; }
    if (z_slice_len(z_loan(slice)) == 10 && !memcmp(z_slice_data(z_loan(slice)), "__delete__", 10)) {
        z_view_keyexpr_t key; z_view_keyexpr_from_str(&key, output);
        if (z_delete(z_loan(session), z_loan(key), NULL) < 0) peer_fail(__LINE__);
        else { received++; printf("DELETE %u\n", received); fflush(stdout); }
        z_drop(z_move(slice)); return;
    }
    if (z_bytes_copy_from_buf(&value, z_slice_data(z_loan(slice)), z_slice_len(z_loan(slice))) < 0) {
        z_drop(z_move(slice)); peer_fail(__LINE__); return;
    }
    z_drop(z_move(slice)); z_view_keyexpr_t key;
    if (z_view_keyexpr_from_str(&key, output) < 0 || z_put(z_loan(session), z_loan(key), z_move(value), NULL) < 0) peer_fail(__LINE__);
    else { received++; printf("ECHO %u %zu\n", received, z_bytes_len(z_sample_payload(sample))); fflush(stdout);
        if (two_rounds && received == 2) done = 1; }
}

/* 固定真实Queryable：二进制双回复、错误回复和持有到期的无回复路径。 */
static void query_server(z_loaned_query_t *query, void *context) {
    const char *mode = context;
    get_received++;
    printf("GET_RECEIVED %u %s\n", get_received, mode); fflush(stdout);
    if (!strcmp(mode, "silent")) {
        for (int i = 0; i < 4; ++i) if (!held_used[i]) {
            if (z_query_take_from_loaned(&held[i], query) < 0) { peer_fail(__LINE__); return; }
            held_used[i] = 1; held_at[i] = z_clock_now();
            printf("HOLD %d 1500\n", i); fflush(stdout); return;
        }
        printf("HOLD_FULL\n"); fflush(stdout); return;
    }
    if (!strcmp(mode, "error")) {
        z_owned_bytes_t value;
        if (z_bytes_copy_from_buf(&value, (const unsigned char *)"peer-error", 10) < 0 ||
            z_query_reply_err(query, z_move(value), NULL) < 0) peer_fail(__LINE__);
        return;
    }
    const z_loaned_bytes_t *payload = z_query_payload(query);
    z_owned_slice_t bytes;
    if (!payload || z_bytes_to_slice(payload, &bytes) < 0) { peer_fail(__LINE__); return; }
    for (int i = 0; i < 2; ++i) {
        z_owned_bytes_t value;
        if (z_bytes_copy_from_buf(&value, z_slice_data(z_loan(bytes)), z_slice_len(z_loan(bytes))) < 0 ||
            z_query_reply(query, z_query_keyexpr(query), z_move(value), NULL) < 0) peer_fail(__LINE__);
    }
    z_drop(z_move(bytes));
}
static void device_reply(z_loaned_reply_t *reply, void *context) {
    (void)context;
    static const unsigned char expected[] = "peer\0query\377";
    if (!z_reply_is_ok(reply)) {
        z_owned_slice_t error;
        if (z_bytes_to_slice(z_reply_err_payload(z_reply_err(reply)), &error) == 0) {
            fprintf(stderr, "DEVICE_GET_ERROR %.*s\n", (int)z_slice_len(z_loan(error)), z_slice_data(z_loan(error)));
            z_drop(z_move(error));
        }
        peer_fail(__LINE__); return;
    }
    z_owned_slice_t value;
    if (z_bytes_to_slice(z_sample_payload(z_reply_ok(reply)), &value) < 0) { peer_fail(__LINE__); return; }
    if (z_slice_len(z_loan(value)) != sizeof(expected)-1 ||
        memcmp(z_slice_data(z_loan(value)), expected, sizeof(expected)-1)) peer_fail(__LINE__);
    else device_replies++;
    z_drop(z_move(value));
}
static void device_done(void *context) {
    (void)context;
    char text[64]; int length = snprintf(text, sizeof(text), "DEVICE_GET_DONE:%u", device_replies);
    z_view_keyexpr_t key; z_view_keyexpr_from_str(&key, status_key);
    z_owned_bytes_t value;
    if (z_bytes_copy_from_buf(&value, (const unsigned char *)text, (size_t)length) < 0 ||
        z_put(z_loan(session), z_loan(key), z_move(value), NULL) < 0) peer_fail(__LINE__);
    device_get_count++; device_pending = 0;
}
static void control_get(z_loaned_sample_t *sample, void *context) {
    (void)context;
    if (device_pending) { peer_fail(__LINE__); return; }
    z_view_keyexpr_t key; z_view_keyexpr_from_str(&key, device_key);
    z_owned_closure_reply_t closure; z_closure(&closure, device_reply, device_done, NULL);
    z_get_options_t options; z_get_options_default(&options);
    /* 对端期限须晚于被测owned-query的5秒清场，避免先被router超时。 */
    options.timeout_ms = 7000; options.consolidation = z_query_consolidation_none();
    static const unsigned char request[] = "peer\0query\377";
    z_owned_bytes_t value; if (z_bytes_copy_from_buf(&value, request, sizeof(request)-1) < 0) { peer_fail(__LINE__); return; }
    options.payload = z_move(value); device_replies = 0; device_pending = 1;
    (void)sample;
    if (z_get(z_loan(session), z_loan(key), "source=peer", z_move(closure), &options) < 0) peer_fail(__LINE__);
}

int main(int argc, char **argv) {
    if ((argc != 3 && argc != 4) || strlen(argv[2]) > 200) return 2;
    if (argc == 4) {
        if (!strcmp(argv[3], "--two-rounds")) two_rounds = 1;
        else if (!strcmp(argv[3], "--get")) get_mode = 1;
        else return 2;
    }
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

    z_owned_queryable_t queryables[3];
    z_owned_subscriber_t controller;
    if (get_mode) {
        const char *suffix[] = {"peer", "silent", "error"};
        for (int i = 0; i < 3; ++i) {
            char target[256]; snprintf(target, sizeof(target), "%s/%s", argv[2], suffix[i]);
            z_view_keyexpr_t key; z_view_keyexpr_from_str(&key, target);
            z_owned_closure_query_t closure; z_closure(&closure, query_server, NULL, (void *)suffix[i]);
            if (z_declare_queryable(z_loan(session), &queryables[i], z_loan(key), z_move(closure), NULL) < 0) return 4;
        }
        char target[256]; snprintf(target, sizeof(target), "%s/control", argv[2]);
        snprintf(status_key, sizeof(status_key), "%s/status", argv[2]);
        snprintf(device_key, sizeof(device_key), "%s/device", argv[2]);
        z_view_keyexpr_t key; z_view_keyexpr_from_str(&key, target);
        z_owned_closure_sample_t closure; z_closure(&closure, control_get, NULL, NULL);
        if (z_declare_subscriber(z_loan(session), &controller, z_loan(key), z_move(closure), NULL) < 0) return 4;
    }

    printf("READY\n"); fflush(stdout);
    z_clock_t start = z_clock_now();
    while (!done && !failed && z_clock_elapsed_ms(&start) < ((two_rounds || get_mode) ? 240000 : 60000)) {
        zp_spin_once(z_loan(session)); z_sleep_ms(5);
        for (int i = 0; i < 4; ++i) if (held_used[i] && z_clock_elapsed_ms(&held_at[i]) >= 1500) {
            printf("HOLD_DROP %d\n", i); fflush(stdout);
            z_drop(z_move(held[i])); held_used[i] = 0;
        }
    }
    if (two_rounds && done && !failed) {
        z_clock_t drain = z_clock_now();
        while (z_clock_elapsed_ms(&drain) < 200) { zp_spin_once(z_loan(session)); z_sleep_ms(5); }
    }
    if (get_mode) {
        for (int i = 0; i < 4; ++i) if (held_used[i]) z_drop(z_move(held[i]));
        z_drop(z_move(controller));
        for (int i = 0; i < 3; ++i) z_drop(z_move(queryables[i]));
    }
    z_drop(z_move(ss)); z_drop(z_move(es)); z_drop(z_move(session));
    printf("PEER_DONE received=%u get_received=%u device_get=%u\n", received, get_received, device_get_count);
    return done && !failed && (get_mode ? (get_received && device_get_count) : received) ? 0 : 5;
}
