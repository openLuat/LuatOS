/* AI-MANAGED: true */
/* SPDX-License-Identifier: EPL-2.0 OR Apache-2.0 */
#ifndef ZENOH_PICO_SESSION_DROP_SCOPE_H
#define ZENOH_PICO_SESSION_DROP_SCOPE_H
#include "zenoh-pico/config.h"
/* Drop callbacks run synchronously inside the single LuatOS worker. */
#ifdef ZP_QUERY_DROP_SCOPE
const char *ZP_QUERY_DROP_SCOPE(const char *source);
#define _Z_DROP_SCOPE_ENTER(source) const char *previous_source = ZP_QUERY_DROP_SCOPE(source)
#define _Z_DROP_SCOPE_LEAVE() ((void)ZP_QUERY_DROP_SCOPE(previous_source))
#else
#define _Z_DROP_SCOPE_ENTER(source) ((void)0)
#define _Z_DROP_SCOPE_LEAVE() ((void)0)
#endif
#endif
