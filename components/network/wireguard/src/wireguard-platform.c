
#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_mcu.h"

#include "wireguard/wireguard-platform.h"

#include <stdlib.h>
#include "wireguard/crypto.h"
#include "lwip/sys.h"

#define LUAT_LOG_TAG "netdrv.wg"
#include "luat_log.h"

// This file contains a sample Wireguard platform integration

// DO NOT USE THIS FUNCTION - IMPLEMENT A BETTER RANDOM BYTE GENERATOR IN YOUR IMPLEMENTATION
void wireguard_random_bytes(void *bytes, size_t size) {
	luat_crypto_trng((char*)bytes, size);
}

uint32_t wireguard_sys_now() {
	return sys_now();
}

// CHANGE THIS TO GET THE ACTUAL UNIX TIMESTMP IN MILLIS - HANDSHAKES WILL FAIL IF THIS DOESN'T INCREASE EACH TIME CALLED
void wireguard_tai64n_now(uint8_t *output) {
	// See https://cr.yp.to/libtai/tai64.html
	// 64 bit seconds from 1970 = 8 bytes
	// 32 bit nano seconds from current second

	time_t t = time(NULL);
	uint32_t ticks = luat_mcu_ticks();

	uint64_t seconds = 0x400000000000000aULL + t;
	uint32_t nanos = ticks;
	// LLOGD("seconds %llu nanos %u", seconds, nanos);
	U64TO8_BIG(output + 0, seconds);
	U32TO8_BIG(output + 8, nanos);
}

bool wireguard_is_under_load() {
	return false;
}

