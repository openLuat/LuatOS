# L2TPv2 Client (netdrv submodule)

L2TPv2 (RFC 2661) LAC client for the LuatOS `netdrv` framework.  The outer
UDP transport runs on the LuatOS network adapter (`network_ctrl_t`), the
control plane follows `pppol2tp` semantics (SCCRQ/SCCRP/SCCCN/ICRQ/ICRP/ICCN,
ns/nr window, timeout retransmission), and the PPP session runs on the
vendored lwIP 2.2.1 PPP stack in `src/ppp/`.

## Layout

```
l2tp/
├── include/
│   ├── l2tp/l2tp_client.h   # public client API + protocol constants
│   ├── l2tp/l2tp_ctrl.h     # internal control-plane cross-file prototypes
│   ├── l2tp/l2tp_ppp.h      # internal PPP-glue cross-file prototypes
│   └── ppp_settings.h       # lwIP PPP_INCLUDE_SETTINGS_HEADER port hook
└── src/
    ├── l2tp_client.c        # lifecycle / timers / UDP transport / retry
    ├── l2tp_ctrl.c          # wire format / AVP parse+dispatch / senders
    ├── l2tp_ppp.c           # link_callbacks + PPP link-status callback
    ├── luat_netdrv_l2tp.c   # netdrv glue (setup/ctrl/dhcp/debug)
    └── ppp/                 # vendored lwIP 2.2.1 PPP (PAP + CHAP-MD5)
```

## Build

`bsp/pc/xmake.lua` compiles the L2TP core plus the vendored PPP sources with
`LUAT_L2TP_PPP_BUILD=1` (see `docs/l2tp-design.md` for the full wiring).

## Docs

- Design: `docs/l2tp-design.md`
- Test: `testcase/unit/net/netdrv_l2tp_basic/` (Python mock LNS)
