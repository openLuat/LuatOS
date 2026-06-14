/*
 * components/utest/mobile/luat_mobile_rfcal_utest.c
 *
 * C-layer utest cases for luat_mobile_rfcal_*() PC simulator stubs.
 *
 * Scope: PC ONLY. The 6 cases below exercise the EC7xx RF-calibration
 * state-machine contract that lives in `luat_mobile_rfcal_*()`. While
 * Task 1's stubs in `bsp/pc/port/luat_mobile_pc.c` still return -1, every
 * case below returns -1 as well -- this is the EXPECTED TDD "red" state
 * that Task 3 will flip to green by implementing real PC simulation.
 *
 * Build-gating:
 *   - `bsp/pc/xmake.lua` adds `components/utest/**.c` only when
 *     `LUAT_USE_UTEST=y` is set.
 *   - The Lua-side bridge in `components/mobile/luat_lib_mobile.c`
 *     (`l_mobile_utest`) is wrapped in `#ifdef LUAT_USE_UTEST`.
 */

#include "luat_base.h"
#include "luat_mobile.h"
#include <string.h>
#include <stdio.h>

/*
 * Cases:
 *   NULL or "rfcal_npi_bit_rw"        -- exercise npi_get / npi_set round-trip
 *   "rfcal_state_machine"             -- exercise at_dispatch driving get_state
 *   "rfcal_imei_inject"               -- exercise set_imei + CGSN response
 *   "rfcal_at_handshake"              -- exercise AT / ATE0 OK path
 *   "rfcal_rfnst_known"               -- exercise AT+ECRFNST known-input path
 *   "rfcal_reset_clears_state"        -- exercise reset clears state + NPI
 *
 * Return: 0 on pass, -1 on fail / unknown case name.
 */
int luat_mobile_rfcal_utest(lua_State *L, const char *case_name) {
    char resp[256] = {0};
    int v = 0;
    int r = -1;
    (void)L;

    if (!case_name || strcmp(case_name, "rfcal_npi_bit_rw") == 0) {
        r = luat_mobile_rfcal_reset();
        if (r != 0) return -1;
        r = luat_mobile_rfcal_npi_set("rfCaliDone", 1);
        if (r != 0) return -1;
        r = luat_mobile_rfcal_npi_get("rfCaliDone", &v);
        if (r != 0 || v != 1) return -1;
        r = luat_mobile_rfcal_npi_set("rfCaliDone", 0);
        if (r != 0) return -1;
        r = luat_mobile_rfcal_npi_get("rfCaliDone", &v);
        if (r != 0 || v != 0) return -1;
        return 0;
    }

    if (strcmp(case_name, "rfcal_state_machine") == 0) {
        luat_mobile_rfcal_reset();
        luat_mobile_rfcal_at_dispatch("AT+CGSN=1", resp, sizeof(resp));
        if (luat_mobile_rfcal_get_state() != 1) return -1;
        luat_mobile_rfcal_at_dispatch("AT+ECNPICFG=rfCaliDone,1", resp, sizeof(resp));
        if (luat_mobile_rfcal_get_state() != 4) return -1;
        luat_mobile_rfcal_at_dispatch("AT+ECNPICFG=rfNSTDone,1", resp, sizeof(resp));
        if (luat_mobile_rfcal_get_state() != 6) return -1;
        return 0;
    }

    if (strcmp(case_name, "rfcal_imei_inject") == 0) {
        luat_mobile_rfcal_set_imei("864317081553409");
        luat_mobile_rfcal_at_dispatch("AT+CGSN=1", resp, sizeof(resp));
        if (!strstr(resp, "864317081553409")) return -1;
        return 0;
    }

    if (strcmp(case_name, "rfcal_at_handshake") == 0) {
        luat_mobile_rfcal_at_dispatch("AT", resp, sizeof(resp));
        if (!strstr(resp, "OK")) return -1;
        luat_mobile_rfcal_at_dispatch("ATE0", resp, sizeof(resp));
        if (!strstr(resp, "OK")) return -1;
        return 0;
    }

    if (strcmp(case_name, "rfcal_rfnst_known") == 0) {
        char out[256] = {0};
        luat_mobile_rfcal_rfnst("020408000000000000000000", out, sizeof(out));
        if (strncmp(out, "MT", 2) != 0) return -1;
        if (out[2] != '0' || out[3] != '2' || out[4] != '0' || out[5] != '4') return -1;
        return 0;
    }

    if (strcmp(case_name, "rfcal_reset_clears_state") == 0) {
        luat_mobile_rfcal_at_dispatch("AT+ECNPICFG=rfCaliDone,1", resp, sizeof(resp));
        luat_mobile_rfcal_reset();
        if (luat_mobile_rfcal_get_state() != 0) return -1;
        luat_mobile_rfcal_npi_get("rfCaliDone", &v);
        if (v != 0) return -1;
        return 0;
    }

    return -1;
}
