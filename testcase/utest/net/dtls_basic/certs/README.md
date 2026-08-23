# DTLS utest 证书资产

本目录存放 PC 端 DTLS utest 闭环运行所需的预生成 PEM 证书 / 私钥。

## 文件清单

| 文件 | 用途 |
|------|------|
| `ca.crt` / `ca.key` | 自签根 CA,CN=`LuatOS DTLS Test CA`,签发 server / client 证书 |
| `server.crt` / `server.key` | 由 `ca` 签发的服务端证书,SAN=`IP:127.0.0.1,DNS:localhost` |
| `client.crt` / `client.key` | 由 `ca` 签发的客户端证书,用于 mTLS 双向认证场景 |
| `wrong_ca.crt` / `wrong_ca.key` | 第二个自签 CA(独立密钥),与 `ca` 不互信 |
| `wrong_server.crt` / `wrong_server.key` | 由 `wrong_ca` 签发的服务端证书,用于「CA 不匹配被拒」场景 |

## 用途与对应 utest case

| 测试用例 | helper 端 | client 端 (LuatOS) | 期望结果 |
|----------|-----------|-------------------|----------|
| `dtls_loopback_cert` | `ca` + `server.*`,`require_client_cert=0` | `ca.crt` | 握手成功 + echo |
| `dtls_loopback_cert_mismatch` | `wrong_ca` + `wrong_server.*`,`require_client_cert=0` | `ca.crt` | `connect` 失败 |
| `dtls_loopback_mtls` | `ca` + `server.*`,`require_client_cert=1` | `ca.crt` + `client.crt` + `client.key` | 握手成功 + echo |
| `dtls_cert_parse_boundary` | (无 helper) | 各种坏 PEM 字符串 | `socket.config`/`connect` 失败,不崩溃 |

## 重新生成

```bash
cd testcase/utest/net/dtls_basic/certs
bash gen_certs.sh
```

`gen_certs.sh` 用 OpenSSL 生成,有效期 5 年(1825 天),RSA-2048。
Git-Bash on Windows 已设置 `MSYS_NO_PATHCONV=1` 防止 `/CN=...` subject 被
误判为路径。

## 注意

- **不要**把 `ca.key` / `server.key` / `client.key` / `wrong_ca.key` / `wrong_server.key`
  用到任何生产 / 联网环境 —— 这是 **测试用自签证书**,仅服务于 PC 模拟器
  DTLS 闭环。
- 仓库迁移到其他路径时,C 端 helper 用相对 runner cwd 的相对路径
  `../../testcase/utest/net/dtls_basic/certs/<file>`,不会因仓库移动而失效。
