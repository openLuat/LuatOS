# IKEv2/IPsec Client (netdrv submodule)

IKEv2/IPsec tunnel-mode client for the LuatOS `netdrv` framework
(strongSwan-compatible, verified against `ipsec.air32.cn`).

## Layout

```
ipsec/
├── include/ipsec/
│   ├── ipsec_ike.h          # IKEv2 state machine API
│   ├── ipsec_esp.h          # ESP tunnel encapsulate/decap
│   ├── ipsec_crypto.h       # PRF+ / DH / key derivation / AUTH / X.509
│   ├── ipsec_vendor_md4.h   # vendored MD4
│   └── ipsec_vendor_chap_ms.h  # MS-CHAPv2 (EAP-MSK path)
└── src/
    ├── ipsec_ike.c          # IKEv2 state machine + virtual netif I/O
    ├── ipsec_esp.c          # ESP AES-CBC + HMAC, replay window
    ├── ipsec_crypto.c       # crypto helpers
    ├── ipsec_vendor_md4.c   # vendored MD4
    ├── ipsec_vendor_chap_ms.c  # MS-CHAPv2
    └── luat_netdrv_ipsec.c  # netdrv glue (setup/ctrl/dhcp/debug)
```

## Docs

- Design: `docs/ipsec-design.md`
- Test: `testcase/unit/net/netdrv_ipsec_basic/` (needs external gateway)
