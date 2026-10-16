#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mock L2TPv2 LNS for the netdrv_l2tp_basic testcase.

Implements just enough of RFC 2661 (LAC side) + PPP (LCP/PAP/CHAP-MD5/IPCP)
and a minimal IPv4/TCP echo server so that the LuatOS L2TP client can:
  - establish a tunnel + session (SCCRQ/SCCRP/SCCCN/ICRQ/ICRP/ICCN/ZLB)
  - authenticate with PAP or CHAP(MD5)
  - receive an IP via IPCP (with DNS options)
  - exchange TCP data through the tunnel

Usage:
  python mock_lns.py --port 1701 --auth pap --user testuser --pass testpass
  python mock_lns.py --port 1702 --auth chap --user testuser --pass testpass
  python mock_lns.py --port 1703 --reject-auth   # auth always fails
  python mock_lns.py --port 1701 --drop-after 8  # kill session after 8s
"""

import argparse
import hashlib
import os
import random
import socket
import struct
import sys
import threading
import time

# MS-CHAPv2 校验需要 MD4(NT 口令哈希) + DES(挑战应答) + SHA1(Authenticator Response)。
# 只在这一个场景用到, 所以做成可选依赖: 缺了就在启动时明确报错退出, 不要静默降级。
try:
    from Crypto.Cipher import DES as _DES
    from Crypto.Hash import MD4 as _MD4
    from Crypto.Hash import SHA1 as _SHA1
    HAVE_CRYPTO = True
except Exception:  # pragma: no cover - 取决于运行环境
    HAVE_CRYPTO = False

# ---------------------------------------------------------------- L2TP AVP
AVP_MESSAGE = 0
AVP_VERSION = 2
AVP_FRAMING_CAP = 3
AVP_BEARER_CAP = 4
AVP_HOSTNAME = 7
AVP_VENDOR = 8
AVP_TUNNEL_ID = 9
AVP_RECV_WIN = 10
AVP_CHALLENGE = 11
AVP_CHALLENGE_RESP = 13
AVP_SESSION_ID = 14
AVP_RESULTCODE = 1

MSG_SCCRQ = 1
MSG_SCCRP = 2
MSG_SCCCN = 3
MSG_STOPCCN = 4
MSG_ICRQ = 10
MSG_ICRP = 11
MSG_ICCN = 12

FLAG_CONTROL = 0x8000
FLAG_LENGTH = 0x4000
FLAG_SEQUENCE = 0x0800
FLAG_VERSION = 0x0002

# ---------------------------------------------------------------- PPP proto
PPP_LCP = 0xC021
PPP_PAP = 0xC023
PPP_CHAP = 0xC223
PPP_IPCP = 0x8021
PPP_IP = 0x0021


# ---------------------------------------------------------------- MS-CHAPv2
# RFC 2759 / RFC 3079 里 LNS 侧需要的那几步(独立于被测客户端实现, 用于交叉验证)
MAGIC1 = b"Magic server to client signing constant"
MAGIC2 = b"Pad to make it do more than one iteration"


def _str_to_key(key7):
    """56bit -> 64bit DES 密钥(补奇偶位), 与 pppcrypt_56_to_64_bit_key 等价"""
    k = bytes(key7) + b"\x00"

    def get7(start):
        word = (k[start // 8] << 8) | k[start // 8 + 1]
        word >>= 15 - (start % 8 + 7)
        return word & 0xFE

    return bytes([get7(0), get7(7), get7(14), get7(21), get7(28), get7(35), get7(42), get7(49)])


def _des_ecb_encrypt(data8, key7):
    return _DES.new(_str_to_key(key7), _DES.MODE_ECB).encrypt(data8)


def _nt_password_hash(password):
    """MD4(UTF-16LE(password)); 传入 bytes 时按原样哈希(用于 PasswordHashHash)"""
    if isinstance(password, str):
        password = password.encode("utf-16-le")
    return _MD4.new(password).digest()


def _challenge_hash(peer_challenge, auth_challenge, username):
    """SHA1(PeerChallenge | AuthenticatorChallenge | UserName)[0:8]"""
    h = _SHA1.new(peer_challenge + auth_challenge + username.encode("utf-8")).digest()
    return h[:8]


def _challenge_response(challenge8, password):
    """3xDES(ChallengeHash, NT-Password-Hash 补到 21 字节) -> 24 字节 NT-Response"""
    z = _nt_password_hash(password) + b"\x00" * 5      # 16 -> 21
    return (_des_ecb_encrypt(challenge8, z[0:7])
            + _des_ecb_encrypt(challenge8, z[7:14])
            + _des_ecb_encrypt(challenge8, z[14:21]))


def _generate_authenticator_response(password, nt_response, peer_challenge,
                                     auth_challenge, username):
    """RFC 2759 的 Authenticator Response, 40 个十六进制大写字符(客户端会互验)。
    注意第二步哈希的是 8 字节 ChallengeHash, 不是原始 AuthenticatorChallenge
    (lwIP chap_ms.c:675-682 / RFC 2759 §8.7 原文)。"""
    pw_hash_hash = _nt_password_hash(_nt_password_hash(password))
    digest = _SHA1.new(pw_hash_hash + nt_response + MAGIC1).digest()
    challenge8 = _challenge_hash(peer_challenge, auth_challenge, username)
    return _SHA1.new(digest + challenge8 + MAGIC2).digest().hex().upper()


def u16(v):
    return struct.pack("!H", v & 0xFFFF)


def u32(v):
    return struct.pack("!I", v & 0xFFFFFFFF)


def ip4(s):
    return socket.inet_aton(s)


def checksum(data):
    if len(data) % 2:
        data += b"\x00"
    s = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def tcp_checksum(src, dst, tcp):
    pseudo = ip4(src) + ip4(dst) + b"\x00\x06" + struct.pack("!H", len(tcp))
    return checksum(pseudo + tcp)


class LNS:
    def __init__(self, args):
        self.args = args
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", args.port))
        self.sock.settimeout(0.5)

        self.client_addr = None      # (ip, port) of the LAC
        self.phase = "INIT"          # SCCRQ_SENT/SCCRP_SENT/ICRQ_SENT/DATA
        self.client_tunnel_id = 0    # tunnel id proposed by the client
        self.our_tunnel_id = 0x1000
        self.client_session_id = 0
        self.our_session_id = 0x2000
        self.client_ns = 0
        self.our_ns = 0
        self.secret = args.secret.encode() if args.secret else None
        self.challenge = None
        self.auth_done = False
        self.lcp_options = b""
        self.offer_chap = (args.auth in ("chap", "mschapv2"))
        # CHAP 算法: 0x05 = CHAP-MD5, 0x81 = MS-CHAPv2 (LCP CI_AUTHTYPE 里带)
        self.chap_alg = 0x81 if args.auth == "mschapv2" else 0x05
        self.our_confreq_sent = False
        self.chap_sent = False
        self.our_magic = random.getrandbits(32)
        self.ipcp_confreq_sent = False
        self.dropped = False

        self.tcp_states = {}
        self.running = True
        self.started_at = time.time()

    # ------------------------------------------------------------ log
    def log(self, msg):
        if self.args.log:
            print("[lns:%d] %s" % (self.args.port, msg), flush=True)

    # -------------------------------------------------------- L2TP build
    def ctrl_msg(self, ns, nr, tunnel_id, session_id, avps):
        body = b"".join(avps)
        total = 12 + len(body)
        hdr = (u16(FLAG_CONTROL | FLAG_LENGTH | FLAG_SEQUENCE | FLAG_VERSION)
               + u16(total) + u16(tunnel_id) + u16(session_id)
               + u16(ns) + u16(nr))
        return hdr + body

    def avp(self, attr, value):
        flags = 0x8000 | (6 + len(value))
        return u16(flags) + u16(0) + u16(attr) + value

    # -------------------------------------------------------- L2TP parse
    def parse_ctrl(self, data):
        """Parse a control datagram: return (ns, nr, [(attr, value), ...], msgtype)"""
        if len(data) < 12:
            return None
        flags, length, tunnel_id, session_id, ns, nr = struct.unpack("!HHHHHH", data[:12])
        avps = []
        msgtype = None
        pos = 12
        while pos + 6 <= len(data):
            aflags, vendor, attr = struct.unpack("!HHH", data[pos:pos + 6])
            alen = aflags & 0x03FF
            if alen < 6 or pos + alen > len(data):
                break
            value = data[pos + 6:pos + alen]
            if vendor == 0 and attr == AVP_MESSAGE and len(value) == 2:
                msgtype = struct.unpack("!H", value)[0]
            avps.append((attr, value))
            pos += alen
        return (ns, nr, avps, msgtype)

    def avp_value(self, avps, attr):
        for a, v in avps:
            if a == attr:
                return v
        return None

    # --------------------------------------------------------- PPP build
    def ppp_send(self, proto, payload):
        frame = u16(proto) + payload
        return self.l2tp_data(frame)

    def l2tp_data(self, ppp_frame):
        # Data packets must carry the tunnel/session IDs assigned by the
        # client (lwip pppol2tp validates them against its remote_*_id).
        hdr = u16(FLAG_VERSION) + u16(self.client_tunnel_id) + u16(self.client_session_id)
        return hdr + ppp_frame

    # ------------------------------------------------------- TCP echo path
    def handle_ip(self, pkt):
        if len(pkt) < 20:
            return
        ver_ihl = pkt[0]
        if (ver_ihl >> 4) != 4:
            return
        ihl = (ver_ihl & 0x0F) * 4
        if len(pkt) < ihl + 20:
            return
        proto = pkt[9]
        src = socket.inet_ntoa(pkt[12:16])
        dst = socket.inet_ntoa(pkt[16:20])
        if proto == 6:
            self.handle_tcp(src, dst, pkt[ihl:])

    def handle_tcp(self, src, dst, tcp):
        if len(tcp) < 20:
            return
        sport, dport, seq, ack, off_flags, window, chk, urg = struct.unpack(
            "!HHIIHHHH", tcp[:20])
        offset = ((off_flags >> 12) & 0x0F) * 4
        flags = off_flags & 0x1FF
        payload = tcp[offset:]
        key = (src, sport, dport)
        self.log("TCP pkt %s:%d -> %d flags=0x%02x seq=%d ack=%d plen=%d" %
                 (src, sport, dport, flags, seq, ack, len(payload)))

        if flags & 0x02 and not (flags & 0x10):  # SYN
            our_isn = random.randint(1000, 0x7FFFFFFF)
            self.tcp_states[key] = {
                "state": "SYN_SENT", "seq": our_isn, "ack": (seq + 1) & 0xFFFFFFFF,
                "their_seq": seq,
            }
            self.tcp_send(dst, src, dport, sport, our_isn,
                          (seq + 1) & 0xFFFFFFFF, 0x12, b"")
            self.log("TCP SYN %s:%d -> %d" % (src, sport, dport))
            return

        st = self.tcp_states.get(key)
        if st is None:
            return

        if flags & 0x04:  # RST
            self.tcp_states.pop(key, None)
            return

        if flags & 0x01:  # FIN
            self.tcp_send(dst, src, dport, sport, st["seq"],
                          (seq + len(payload) + 1) & 0xFFFFFFFF, 0x11, b"")
            self.tcp_states.pop(key, None)
            self.log("TCP FIN from %s:%d" % (src, sport))
            return

        if st["state"] == "SYN_SENT":
            st["state"] = "EST"
            st["seq"] = (st["seq"] + 1) & 0xFFFFFFFF
            self.log("TCP established %s:%d" % (src, sport))

        if payload:
            # ACK the received data, then echo it back
            new_ack = (seq + len(payload)) & 0xFFFFFFFF
            self.tcp_send(dst, src, dport, sport, st["seq"], new_ack, 0x10, b"")
            self.tcp_send(dst, src, dport, sport, st["seq"], new_ack, 0x18, payload)
            st["seq"] = (st["seq"] + len(payload)) & 0xFFFFFFFF
            st["ack"] = new_ack
            self.log("TCP echo %d bytes %s:%d" % (len(payload), src, sport))

    def tcp_send(self, src, dst, sport, dport, seq, ack, flags, payload):
        src_b = ip4(src)
        dst_b = ip4(dst)
        tcp = struct.pack("!HHIIHHHH", sport, dport, seq & 0xFFFFFFFF,
                          ack & 0xFFFFFFFF, 0x5000 | flags, 8192, 0, 0) + payload
        chk = tcp_checksum(src, dst, tcp)
        tcp = tcp[:16] + struct.pack("!H", chk) + tcp[18:]
        ihl = 5
        total = ihl * 4 + len(tcp)
        ip_hdr = struct.pack("!BBHHHBBH4s4s", 0x45, 0, total, 0, 0, 64, 6, 0,
                             src_b, dst_b)
        ip_chk = checksum(ip_hdr)
        ip_hdr = ip_hdr[:10] + struct.pack("!H", ip_chk) + ip_hdr[12:]
        self.udp_send_to_client(self.l2tp_data(u16(PPP_IP) + ip_hdr + tcp))

    # ---------------------------------------------------------- PPP engine
    def handle_ppp(self, frame):
        if len(frame) < 2:
            return
        proto = struct.unpack("!H", frame[:2])[0]
        payload = frame[2:]

        if proto == PPP_LCP:
            self.handle_lcp(payload)
        elif proto == PPP_PAP:
            self.handle_pap(payload)
        elif proto == PPP_CHAP:
            self.handle_chap(payload)
        elif proto == PPP_IPCP:
            self.handle_ipcp(payload)
        elif proto == PPP_IP:
            self.handle_ip(payload)

    def handle_lcp(self, p):
        if len(p) < 4:
            return
        code, ident, length = struct.unpack("!BBH", p[:4])
        body = p[4:length] if length <= len(p) else p[4:]
        if code == 1:  # Configure-Request
            self.lcp_options = body
            self.log("LCP ConfReq id=%d len=%d opts=%s" % (ident, length, body.hex()))
            ack = struct.pack("!BBH", 2, ident, length) + body
            self.udp_send_to_client(self.ppp_send(PPP_LCP, ack))
            self.log("LCP ConfAck id=%d len=%d hex=%s" % (ident, len(ack), ack.hex()))
            # LCP is symmetric: we must also send our own Configure-Request.
            # This carries the Authentication-Protocol option (PAP or CHAP-MD5),
            # which the lwIP client then accepts and acts upon.
            if not self.our_confreq_sent:
                self.our_confreq_sent = True
                magic = random.getrandbits(32)
                opts = struct.pack("!BBH", 1, 4, 1500)          # MRU
                opts += struct.pack("!BBI", 5, 6, magic)        # Magic-Number
                if self.offer_chap:
                    opts += struct.pack("!BBHB", 3, 5, PPP_CHAP, self.chap_alg)
                else:
                    opts += struct.pack("!BBH", 3, 4, PPP_PAP)  # PAP
                req = struct.pack("!BBH", 1, ident + 10, 4 + len(opts)) + opts
                self.udp_send_to_client(self.ppp_send(PPP_LCP, req))
                self.log("LCP our ConfReq hex=%s" % req.hex())
        elif code == 2:  # Configure-Ack (of our request)
            self.log("LCP our ConfAck received")
            if self.offer_chap and not self.chap_sent:
                self.chap_sent = True
                chal = bytes(random.getrandbits(8) for _ in range(16))
                self.challenge = chal
                cid = random.randint(1, 255)
                pkt = struct.pack("!BBH", 1, cid, 4 + 1 + 16 + len(b"MockLNS"))
                pkt += bytes([16]) + chal + b"MockLNS"
                self.udp_send_to_client(self.ppp_send(PPP_CHAP, pkt))
                self.log("CHAP Challenge sent id=%d" % cid)
        elif code == 9:  # Echo-Request
            # Reply with OUR magic number (not the client's); lwIP ignores
            # Echo-Replies that carry its own magic.
            self.udp_send_to_client(self.ppp_send(PPP_LCP,
                                    struct.pack("!BBH", 10, ident, 8)
                                    + struct.pack("!I", self.our_magic)))
            self.log("LCP Echo-Reply")
        elif code == 5:  # Terminate-Request
            self.udp_send_to_client(self.ppp_send(PPP_LCP,
                                    struct.pack("!BBH", 6, ident, 4)))
            self.log("LCP Terminate-Ack")

    def handle_pap(self, p):
        if len(p) < 4:
            return
        code, ident, length = struct.unpack("!BBH", p[:4])
        if code == 1:  # Auth-Request
            body = p[4:length] if length <= len(p) else p[4:]
            if len(body) >= 1:
                ulen = body[0]
                user = body[1:1 + ulen].decode("latin1")
                rest = body[1 + ulen:]
                plen = rest[0] if rest else 0
                passwd = rest[1:1 + plen].decode("latin1")
            else:
                user, passwd = "", ""
            ok = (user == self.args.user and passwd == self.args.password
                  and not self.args.reject_auth)
            if ok:
                self.auth_done = True
                self.udp_send_to_client(self.ppp_send(
                    PPP_PAP, struct.pack("!BBH", 2, ident, 5) + b"\x00OK"))
                self.log("PAP auth ok (%s)" % user)
            else:
                self.udp_send_to_client(self.ppp_send(
                    PPP_PAP, struct.pack("!BBH", 3, ident, 6) + b"\x01ERR"))
                self.log("PAP auth FAILED (%s)" % user)

    def handle_chap(self, p):
        if len(p) < 4:
            return
        code, ident, length = struct.unpack("!BBH", p[:4])
        body = p[4:length] if length <= len(p) else p[4:]
        if code == 1:  # Challenge (client -> us means we initiated? Actually client only responds)
            pass
        elif code == 2:  # Response
            if self.chap_alg == 0x81:
                self.handle_chap_mschapv2(ident, body)
                return
            if len(body) >= 17:
                rlen = body[0]
                resp = body[1:1 + 16]
                name = body[17:].decode("latin1", "replace")
                if self.challenge:
                    # CHAP secret == PPP password (client uses settings.passwd)
                    expect = hashlib.md5(bytes([ident]) + self.args.password.encode()
                                         + self.challenge).digest()
                    ok = (resp == expect and not self.args.reject_auth)
                else:
                    ok = False
                if ok:
                    self.auth_done = True
                    self.udp_send_to_client(self.ppp_send(
                        PPP_CHAP, struct.pack("!BBH", 3, ident, 5) + b"\x00OK"))
                    self.log("CHAP auth ok (%s)" % name)
                else:
                    self.udp_send_to_client(self.ppp_send(
                        PPP_CHAP, struct.pack("!BBH", 4, ident, 7) + b"\x03ERR"))
                    self.log("CHAP auth FAILED (%s)" % name)

    def check_challenge_response(self, avps):
        """RFC 2661 §4.4.2: ChallengeResponse = MD5(MessageType(SCCCN) | Secret | Challenge)"""
        rv = self.avp_value(avps, AVP_CHALLENGE_RESP)
        if not rv or len(rv) != 16 or self.challenge is None:
            return False
        expect = hashlib.md5(bytes([MSG_SCCCN]) + self.secret + self.challenge).digest()
        return rv == expect

    def handle_chap_mschapv2(self, ident, body):
        """MS-CHAPv2 Response 线格式(RFC 2759 §4):
             Value-Size(1)=49 | PeerChallenge(16) | Reserved(8) | NT-Response(24) | Flags(1) | Name
           校验 NT-Response 后回 Success, 且必须带上 Authenticator Response
           (lwIP 客户端会互验, 算错就掉线 —— 这正是"独立实现交叉验证"的价值)。"""
        if len(body) < 50:
            self.log("MSCHAPv2 response too short: %d" % len(body))
            return
        rlen = body[0]
        peer_challenge = body[1:17]
        reserved = body[17:25]
        nt_response = body[25:49]
        flags = body[49]
        name = body[50:].decode("latin1", "replace")

        ok, why = False, ""
        if rlen != 49:
            why = "value-size=%d != 49" % rlen
        elif reserved != b"\x00" * 8:
            why = "reserved not zero: %s" % reserved.hex()
        elif flags != 0:
            why = "flags=0x%02x" % flags
        elif self.args.reject_auth:
            why = "reject-auth"
        else:
            ch = _challenge_hash(peer_challenge, self.challenge, name)
            expect = _challenge_response(ch, self.args.password)
            if expect != nt_response:
                why = "NT-Response mismatch (expect %s got %s)" % (expect.hex(), nt_response.hex())
            else:
                auth_resp = _generate_authenticator_response(
                    self.args.password, nt_response, peer_challenge, self.challenge, name)
                ok = True

        if ok:
            self.auth_done = True
            if self.args.bad_auth_response:
                # 故意算错: 客户端必须互验出来并拒绝这条链路
                auth_resp = ("0" if auth_resp[0] != "0" else "1") + auth_resp[1:]
            msg = ("S=%s M=Welcome" % auth_resp).encode()
            self.udp_send_to_client(self.ppp_send(
                PPP_CHAP, struct.pack("!BBH", 3, ident, 4 + len(msg)) + msg))
            self.log("MSCHAPv2 auth ok (%s) S=%s%s"
                     % (name, auth_resp, " [CORRUPTED]" if self.args.bad_auth_response else ""))
        else:
            msg = b"E=691 R=0 M=Authentication failed"
            self.udp_send_to_client(self.ppp_send(
                PPP_CHAP, struct.pack("!BBH", 4, ident, 4 + len(msg)) + msg))
            self.log("MSCHAPv2 auth FAILED (%s): %s" % (name, why))

    def handle_ipcp(self, p):
        if len(p) < 4:
            return
        code, ident, length = struct.unpack("!BBH", p[:4])
        body = p[4:length] if length <= len(p) else p[4:]
        if code == 1:  # Configure-Request
            opts = self.parse_ipcp_options(body)
            req_ip = opts.get(3)
            if req_ip == ip4(self.args.ip):
                self.udp_send_to_client(self.ppp_send(
                    PPP_IPCP, struct.pack("!BBH", 2, ident, length) + body))
                self.log("IPCP Configure-Ack (%s)" % self.args.ip)
            else:
                opts = b"\x03\x06" + ip4(self.args.ip)
                opts += b"\x81\x06" + ip4(self.args.dns1)
                opts += b"\x83\x06" + ip4(self.args.dns2)
                nak = struct.pack("!BBH", 3, ident, 4 + len(opts)) + opts
                self.udp_send_to_client(self.ppp_send(PPP_IPCP, nak))
                self.log("IPCP Configure-Nak -> %s" % self.args.ip)
            # IPCP is symmetric: send our own Configure-Request so the
            # client's FSM can leave ACKRCVD and open IPCP.
            if not self.ipcp_confreq_sent:
                self.ipcp_confreq_sent = True
                o = b"\x03\x06" + ip4("192.168.8.1")
                req = struct.pack("!BBH", 1, 9, 4 + len(o)) + o
                self.udp_send_to_client(self.ppp_send(PPP_IPCP, req))
                self.log("IPCP our ConfReq (%s)" % "192.168.8.1")
        elif code == 2:  # Configure-Ack (of our request)
            self.log("IPCP our ConfAck received")
        elif code == 4:  # Configure-Reject (of our request)
            self.log("IPCP our ConfReq rejected, resending without addr")
            req = struct.pack("!BBH", 1, 9, 4)
            self.udp_send_to_client(self.ppp_send(PPP_IPCP, req))
        elif code == 5:  # Terminate-Request
            self.udp_send_to_client(self.ppp_send(
                PPP_IPCP, struct.pack("!BBH", 6, ident, 4)))

    def parse_ipcp_options(self, body):
        opts = {}
        pos = 0
        while pos + 2 <= len(body):
            t, l = body[pos], body[pos + 1]
            if l < 2 or pos + l > len(body):
                break
            opts[t] = body[pos + 2:pos + l]
            pos += l
        return opts

    # ------------------------------------------------------------- driver
    def udp_send_to_client(self, data):
        if self.client_addr:
            self.sock.sendto(data, self.client_addr)

    def handle_datagram(self, data, addr):
        # Always track the current peer address: after a reconnect the client
        # may use a fresh source port.
        self.client_addr = addr
        if len(data) < 6:
            return
        flags = struct.unpack("!H", data[:2])[0]

        if flags & FLAG_CONTROL:
            parsed = self.parse_ctrl(data)
            if parsed is None:
                return
            ns, nr, avps, msgtype = parsed
            self.client_ns = ns
            self.handle_control(msgtype, ns, nr, avps)
            return

        # Data packet
        tunnel_id, session_id = struct.unpack("!HH", data[2:6])
        if self.phase != "DATA":
            # After a forced drop we still ACK LCP Terminate-Requests so the
            # client's link-down detection finishes promptly.
            ppp = data[6:]
            if ppp[:2] == b"\xff\x03":
                ppp = ppp[2:]
            if len(ppp) >= 4 and struct.unpack("!H", ppp[:2])[0] == PPP_LCP \
                    and ppp[2] == 5:
                ident = ppp[3]
                self.udp_send_to_client(self.ppp_send(
                    PPP_LCP, struct.pack("!BBH", 6, ident, 4)))
            return
        if tunnel_id != self.our_tunnel_id or session_id != self.our_session_id:
            self.log("data id mismatch t=%x s=%x" % (tunnel_id, session_id))
            return
        ppp = data[6:]
        if ppp[:2] == b"\xff\x03":
            ppp = ppp[2:]
        self.handle_ppp(ppp)

    def handle_control(self, msgtype, ns, nr, avps):
        if msgtype == MSG_SCCRQ:
            tv = self.avp_value(avps, AVP_TUNNEL_ID)
            if tv and len(tv) == 2:
                self.client_tunnel_id = struct.unpack("!H", tv)[0]
            self.phase = "SCCRP_SENT"
            # RFC 2661: the first control message from each side has NS=0,
            # so the SCCRP reply carries our_ns (starts at 0).
            avps_out = [
                self.avp(AVP_MESSAGE, u16(MSG_SCCRP)),
                self.avp(AVP_VERSION, u16(0x0100)),
                self.avp(AVP_FRAMING_CAP, u32(0x03)),
                self.avp(AVP_BEARER_CAP, u32(0x03)),
                self.avp(AVP_HOSTNAME, b"MockLNS"),
                self.avp(AVP_VENDOR, b"MockLNS"),
                self.avp(AVP_TUNNEL_ID, u16(self.our_tunnel_id)),
                self.avp(AVP_RECV_WIN, u16(4)),
            ]
            if self.secret is not None:
                self.challenge = bytes(random.getrandbits(8) for _ in range(16))
                avps_out.append(self.avp(AVP_CHALLENGE, self.challenge))
            self.udp_send_to_client(self.ctrl_msg(
                self.our_ns, self.client_ns + 1, self.client_tunnel_id, 0, avps_out))
            self.our_ns += 1
            self.log("SCCRQ -> SCCRP (tunnel 0x%x)" % self.our_tunnel_id)

        elif msgtype == MSG_SCCCN:
            # 隧道认证(共享密钥): 客户端在 SCCCN 里带回 ChallengeResponse,
            # 校验不过就按 RFC 2661 回 StopCCN(result=2 general error) 结束隧道。
            if self.secret is not None and not self.check_challenge_response(avps):
                self.udp_send_to_client(self.ctrl_msg(
                    self.our_ns, self.client_ns + 1, self.client_tunnel_id, 0, [
                        self.avp(AVP_MESSAGE, u16(MSG_STOPCCN)),
                        self.avp(AVP_RESULTCODE, struct.pack("!HH", 2, 0)),
                    ]))
                self.our_ns += 1
                self.phase = "INIT"
                self.log("SCCCN tunnel-auth FAILED -> StopCCN")
                return
            if self.secret is not None:
                self.log("SCCCN tunnel-auth ok")
            # ZLB ack: shares the next real message's NS slot, so our_ns
            # is NOT incremented (lwip pppol2tp does not advance peer_ns on ZLB).
            self.udp_send_to_client(self.ctrl_msg(
                self.our_ns, self.client_ns + 1, self.client_tunnel_id, 0, []))
            self.log("SCCCN acked")

        elif msgtype == MSG_ICRQ:
            self.phase = "ICRQ_SENT"
            sv = self.avp_value(avps, AVP_SESSION_ID)
            if sv and len(sv) == 2:
                self.client_session_id = struct.unpack("!H", sv)[0]
                self.log("client session id 0x%x" % self.client_session_id)
            avps_out = [
                self.avp(AVP_MESSAGE, u16(MSG_ICRP)),
                self.avp(AVP_SESSION_ID, u16(self.our_session_id)),
            ]
            self.udp_send_to_client(self.ctrl_msg(
                self.our_ns, self.client_ns + 1, self.client_tunnel_id, 0, avps_out))
            self.our_ns += 1
            self.log("ICRQ -> ICRP (session 0x%x)" % self.our_session_id)

        elif msgtype == MSG_ICCN:
            self.phase = "DATA"
            # ZLB ack: NS slot not consumed.
            self.udp_send_to_client(self.ctrl_msg(
                self.our_ns, self.client_ns + 1, self.client_tunnel_id, 0, []))
            self.log("ICCN acked -> DATA")

        elif msgtype == MSG_STOPCCN:
            self.phase = "INIT"
            self.log("STOPCCN received")

    def run(self):
        self.log("listening on 127.0.0.1:%d auth=%s" %
                 (self.args.port, self.args.auth))
        while self.running:
            try:
                data, addr = self.sock.recvfrom(2048)
            except socket.timeout:
                if self.args.drop_after and self.client_addr and not self.dropped:
                    if time.time() - self.started_at > self.args.drop_after:
                        self.dropped = True
                        self.log("drop-after: sending StopCCN and resetting")
                        # Tell the client the session is gone, then keep
                        # listening so the client can re-establish.
                        self.udp_send_to_client(self.ctrl_msg(
                            self.our_ns, self.client_ns + 1,
                            self.client_tunnel_id, 0,
                            [self.avp(AVP_MESSAGE, u16(MSG_STOPCCN)),
                             self.avp(AVP_TUNNEL_ID, u16(self.our_tunnel_id)),
                             self.avp(AVP_RESULTCODE, u16(1))]))
                        self.phase = "INIT"
                        self.client_tunnel_id = 0
                        self.client_session_id = 0
                        self.client_ns = 0
                        self.our_ns = 0
                        self.auth_done = False
                        self.our_confreq_sent = False
                        self.chap_sent = False
                        self.ipcp_confreq_sent = False
                continue
            self.log("UDP rx %d bytes from %s:%d flags=0x%04x" %
                     (len(data), addr[0], addr[1],
                      struct.unpack("!H", data[:2])[0] if len(data) >= 2 else 0))
            try:
                self.handle_datagram(data, addr)
            except Exception as e:  # never let one bad packet kill the LNS
                self.log("handler error: %r" % e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=1701)
    ap.add_argument("--auth", choices=["pap", "chap", "mschapv2"], default="pap")
    ap.add_argument("--user", default="testuser")
    ap.add_argument("--pass", dest="password", default="testpass")
    ap.add_argument("--secret", default=None)
    ap.add_argument("--ip", default="192.168.8.2")
    ap.add_argument("--dns1", default="192.168.8.1")
    ap.add_argument("--dns2", default="8.8.8.8")
    ap.add_argument("--reject-auth", action="store_true")
    ap.add_argument("--bad-auth-response", action="store_true",
                    help="MSCHAPv2: 故意回一个算错的 Authenticator Response")
    ap.add_argument("--drop-after", type=float, default=0)
    ap.add_argument("--log", action="store_true")
    args = ap.parse_args()
    if args.auth == "mschapv2" and not HAVE_CRYPTO:
        print("--auth mschapv2 需要 pycryptodome (MD4/DES/SHA1): pip install pycryptodome",
              file=sys.stderr)
        return 2
    lns = LNS(args)
    lns.run()
    return 0


if __name__ == "__main__":
    main()
