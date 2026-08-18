# OpenVPN Client (netdrv submodule)

OpenVPN 2.x client (TLS control channel + AES-256-GCM data channel) for the
LuatOS `netdrv` framework.  The outer UDP transport runs on the LuatOS network
adapter (`network_ctrl_t`), key derivation uses TLS-EKM (`EXPORTER-OpenVPN-
datakeys`) with a TLS 1.0 PRF fallback.

## Layout

```
openvpn/
├── include/ovpn/
│   ├── ovpn_client.h        # public client API + protocol constants
│   ├── ovpn_pkt.h           # internal wire-format prototypes
│   ├── ovpn_rel.h           # internal reliable-window prototypes
│   ├── ovpn_ctl.h           # internal control-channel prototypes
│   ├── ovpn_tls.h           # internal TLS-channel prototypes
│   └── ovpn_crypto.h        # internal data-channel crypto prototypes
└── src/
    ├── ovpn_client.c        # lifecycle / state machine / transport / netif
    ├── ovpn_pkt.c           # header build/parse + byte helpers
    ├── ovpn_rel.c           # reliable send/recv windows
    ├── ovpn_ctl.c           # control packets, key_method_2, PUSH_REPLY
    ├── ovpn_tls.c           # mbedTLS setup / BIO callbacks / feed loop
    ├── ovpn_crypto.c        # PRF helpers + TLS-EKM key derivation
    └── luat_netdrv_openvpn.c  # netdrv glue (setup/ctrl/dhcp/debug)
```

## Docs

- Test: `testcase/func/openvpn/` (Docker-based OpenVPN server)
