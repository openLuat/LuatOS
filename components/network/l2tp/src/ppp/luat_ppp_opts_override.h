/*
 * LuatOS L2TP PPP build option override.
 *
 * The vendored lwIP 2.2.1 PPP sources are compiled per-file (via
 * bsp/pc/xmake.lua) with -DLUAT_L2TP_PPP_BUILD=1.  This header MUST be
 * included AFTER "netif/ppp/ppp_opts.h" (i.e. after lwipopts.h has been
 * processed) because bsp/pc/include/lwipopts.h hard-codes PPP_SUPPORT=0
 * and would otherwise clobber the per-file command line defines.
 *
 * Feature set (L2TPv2 LAC, RFC 2661):
 *   - PPP over L2TP control plane lives in luat_netdrv_l2tp_client.c
 *   - PAP + CHAP(MD5) authentication
 *   - no PPPoS / PPPoE / L2TP-in-lwip / MPPE / EAP / CCP / IPv6CP / VJ
 *   - MD5 provided by the external mbedTLS library (LWIP_USE_EXTERNAL_MBEDTLS)
 */
#if defined(LUAT_L2TP_PPP_BUILD)

#undef PPP_SUPPORT
#define PPP_SUPPORT 1

/* pppdebug.h uses `PPP_DEBUG | LWIP_DBG_LEVEL_*` for its LOG_* levels,
 * so PPP_DEBUG must be defined even when debugging is off. */
#ifndef PPP_DEBUG
#define PPP_DEBUG LWIP_DBG_OFF
#endif

#undef PPPOL2TP_SUPPORT
#define PPPOL2TP_SUPPORT 0
#undef PPPOS_SUPPORT
#define PPPOS_SUPPORT 0
#undef PPPOE_SUPPORT
#define PPPOE_SUPPORT 0
#undef LWIP_PPP_API
#define LWIP_PPP_API 0

#undef PAP_SUPPORT
#define PAP_SUPPORT 1
#undef CHAP_SUPPORT
#define CHAP_SUPPORT 1
#undef MSCHAP_SUPPORT
#define MSCHAP_SUPPORT 0
#undef EAP_SUPPORT
#define EAP_SUPPORT 0
#undef CCP_SUPPORT
#define CCP_SUPPORT 0
#undef MPPE_SUPPORT
#define MPPE_SUPPORT 0
#undef VJ_SUPPORT
#define VJ_SUPPORT 0
#undef LQR_SUPPORT
#define LQR_SUPPORT 0
#undef PPP_SERVER
#define PPP_SERVER 0
#undef PPP_IPV4_SUPPORT
#define PPP_IPV4_SUPPORT (LWIP_IPV4)
#undef PPP_IPV6_SUPPORT
#define PPP_IPV6_SUPPORT 0

#undef LWIP_USE_EXTERNAL_MBEDTLS
#define LWIP_USE_EXTERNAL_MBEDTLS 1

/* netif/ppp/pppcrypt.h maps lwip_md5_* to mbedtls_md5_* but relies on the
 * port to provide the mbedTLS headers, so pull in md5.h here (it is included
 * after ppp_opts.h / lwipopts.h, before any pppcrypt.h usage). */
#include "mbedtls/md5.h"
#include "mbedtls/version.h"

/* mbedTLS 2.x builds with MBEDTLS_DEPRECATED_REMOVED (e.g. PC simulator
 * mbedtls_config_pc_mbedtls218.h) do not ship the deprecated
 * mbedtls_md5_starts/update/finish names; map them to the non-deprecated
 * _ret API, same as components/network/openvpn/src/ovpn_crypto.c. */
#if MBEDTLS_VERSION_NUMBER < 0x03000000
#define mbedtls_md5_starts mbedtls_md5_starts_ret
#define mbedtls_md5_update mbedtls_md5_update_ret
#define mbedtls_md5_finish mbedtls_md5_finish_ret
#endif

#undef MEMP_NUM_PPP_PCB
#define MEMP_NUM_PPP_PCB 1

/* ppp_opts.h defines the following inside its `#if PPP_SUPPORT` block,
 * which was evaluated (and skipped) before this override ran, so restore
 * the same defaults here. */
#ifndef FSM_DEFTIMEOUT
#define FSM_DEFTIMEOUT                  6
#endif
#ifndef FSM_DEFMAXTERMREQS
#define FSM_DEFMAXTERMREQS              2
#endif
#ifndef FSM_DEFMAXCONFREQS
#define FSM_DEFMAXCONFREQS              10
#endif
#ifndef FSM_DEFMAXNAKLOOPS
#define FSM_DEFMAXNAKLOOPS              5
#endif
#ifndef UPAP_DEFTIMEOUT
#define UPAP_DEFTIMEOUT                 6
#endif
#ifndef UPAP_DEFTRANSMITS
#define UPAP_DEFTRANSMITS               10
#endif
#ifndef CHAP_DEFTIMEOUT
#define CHAP_DEFTIMEOUT                 6
#endif
#ifndef CHAP_DEFTRANSMITS
#define CHAP_DEFTRANSMITS               10
#endif
#ifndef LCP_DEFLOOPBACKFAIL
#define LCP_DEFLOOPBACKFAIL             10
#endif
#ifndef LCP_ECHOINTERVAL
#define LCP_ECHOINTERVAL                0
#endif
#ifndef LCP_MAXECHOFAILS
#define LCP_MAXECHOFAILS                3
#endif
#ifndef PPP_MAXIDLEFLAG
#define PPP_MAXIDLEFLAG                 100
#endif
#ifndef PPP_MRU
#define PPP_MRU                         1500
#endif
#ifndef PPP_MAXMRU
#define PPP_MAXMRU                      1500
#endif
#ifndef PPP_MINMRU
#define PPP_MINMRU                      128
#endif
#ifndef MAXNAMELEN
#define MAXNAMELEN                      256
#endif
#ifndef MAXSECRETLEN
#define MAXSECRETLEN                    256
#endif

#endif /* LUAT_L2TP_PPP_BUILD */
