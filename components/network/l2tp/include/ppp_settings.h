/*
 * ppp_settings.h - port settings hook for the vendored lwIP 2.2.1 PPP stack.
 *
 * components/network/lwip22/include/arch/cc.h unconditionally defines
 * PPP_INCLUDE_SETTINGS_HEADER, so ppp_impl.h always tries to include this
 * file.  The lwIP PPP sources only use it as a port override hook; the
 * LuatOS L2TP build keeps all options in luat_ppp_opts_override.h, so this
 * file is intentionally empty.
 */
#ifndef LUAT_PPP_SETTINGS_H
#define LUAT_PPP_SETTINGS_H

#endif /* LUAT_PPP_SETTINGS_H */
