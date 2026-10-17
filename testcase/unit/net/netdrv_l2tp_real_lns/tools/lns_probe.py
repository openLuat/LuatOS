#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Diagnostic probe for an unknown LNS (target: 58.213.164.4).

Answers two questions:
  1. does the server answer a PLAIN L2TPv2 SCCRQ on UDP/1701 (i.e. no IPsec)?
  2. does the server answer an IKEv1 main-mode SA on UDP/500 (i.e. IPsec present)?

Usage:
  python probe_lns.py --host 58.213.164.4
  python probe_lns.py --host 58.213.164.4 --what l2tp
  python probe_lns.py --host 58.213.164.4 --what ike
"""

import argparse
import os
import socket
import struct
import sys
import time

# ------------------------------------------------------------ helpers
def u16(v):
    return struct.pack("!H", v & 0xFFFF)


def u32(v):
    return struct.pack("!I", v & 0xFFFFFFFF)


def hexdump(data, prefix="    "):
    for i in range(0, len(data), 16):
        chunk = data[i:i + 16]
        hx = " ".join("%02x" % b for b in chunk)
        tx = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        print("%s%04x  %-47s  %s" % (prefix, i, hx, tx))


# ------------------------------------------------------------ L2TP (RFC 2661)
AVP_MESSAGE = 0
AVP_VERSION = 2
AVP_FRAMING_CAP = 3
AVP_BEARER_CAP = 4
AVP_TIEBREAKER = 5
AVP_FW_REV = 6
AVP_HOSTNAME = 7
AVP_VENDOR = 8
AVP_TUNNEL_ID = 9
AVP_RECV_WIN = 10

MSG_NAMES = {
    1: "SCCRQ", 2: "SCCRP", 3: "SCCCN", 4: "StopCCN",
    6: "HELLO", 10: "ICRQ", 11: "ICRP", 12: "ICCN",
    14: "CDN", 15: "WEN", 16: "SLI",
}


def avp(attr, value, mandatory=True, vendor=0):
    """RFC 2661 AVP: M|H|rsvd|Length(10b) | VendorID(2) | AttrType(2) | Value.
    Length counts the whole AVP, hence 6 + len(value)."""
    total = 6 + len(value)
    word = (0x8000 if mandatory else 0) | (total & 0x03FF)
    return u16(word) + u16(vendor) + u16(attr) + value


def build_sccrq(hostname="LuatOS", tunnel_id=None):
    if tunnel_id is None:
        tunnel_id = struct.unpack("!H", os.urandom(2))[0] or 1
    body = b""
    body += avp(AVP_MESSAGE, u16(1))                     # SCCRQ
    body += avp(AVP_FRAMING_CAP, u32(3))                 # async + sync
    body += avp(AVP_BEARER_CAP, u32(3))                  # analog + digital
    body += avp(AVP_FW_REV, u16(0x0100), mandatory=False)
    body += avp(AVP_HOSTNAME, hostname.encode())
    body += avp(AVP_VENDOR, b"LuatOS")
    body += avp(AVP_TUNNEL_ID, u16(tunnel_id))
    body += avp(AVP_RECV_WIN, u16(8))
    body += avp(AVP_VERSION, u16(0x0100), mandatory=False)

    flags = 0x8000 | 0x4000 | 0x0800 | 0x0002           # ctrl|len|seq|ver2
    # L2TP control header is 12 bytes: flags, length, tunnel-id, session-id, Ns, Nr
    header = u16(flags) + u16(len(body) + 12) + u16(0) + u16(0) + u16(0) + u16(0)
    return header + body


def parse_avps(data, off=12):
    """RFC 2661 AVP header: word(2)=M|H|rsvd|Length(10b), VendorID(2), AttrType(2), Value"""
    out = []
    while off + 6 <= len(data):
        word = struct.unpack("!H", data[off:off + 2])[0]
        length = word & 0x03FF
        if length < 6 or off + length > len(data):
            break
        if word & 0x4000:      # hidden AVP, cannot decode without secret
            out.append(((word & 0x3FFF), b"<hidden>"))
            off += length
            continue
        attr = struct.unpack("!H", data[off + 4:off + 6])[0]
        val = data[off + 6:off + length]
        out.append((attr, val))
        off += length
    return out


def probe_l2tp(host, port, timeout, tries):
    msg = build_sccrq()
    print("== L2TP plain-UDP probe: %s:%d ==" % (host, port))
    print("   SCCRQ %d bytes:" % len(msg))
    hexdump(msg)

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        for i in range(1, tries + 1):
            try:
                s.sendto(msg, (host, port))
            except OSError as e:
                print("   [%d] send error: %s" % (i, e))
                return None
            t0 = time.time()
            try:
                data, addr = s.recvfrom(2048)
            except socket.timeout:
                print("   [%d] no reply within %.1fs" % (i, timeout))
                continue
            dt = (time.time() - t0) * 1000
            print("   [%d] REPLY from %s:%d in %.0f ms, %d bytes"
                  % (i, addr[0], addr[1], dt, len(data)))
            hexdump(data)
            if len(data) >= 12 and struct.unpack("!H", data[2:4])[0] & 0x8000:
                mt = None
                for attr, val in parse_avps(data):
                    if attr == AVP_MESSAGE and len(val) == 2:
                        mt = struct.unpack("!H", val)[0]
                    elif attr == AVP_TUNNEL_ID:
                        print("       AVP tunnel-id  = %d" % struct.unpack("!H", val)[0])
                    elif attr == AVP_HOSTNAME:
                        print("       AVP host-name  = %s" % val.decode("utf-8", "replace"))
                    elif attr == AVP_VENDOR:
                        print("       AVP vendor     = %s" % val.decode("utf-8", "replace"))
                    elif attr == AVP_RECV_WIN:
                        print("       AVP recv-window= %d" % struct.unpack("!H", val)[0])
                    elif attr == 1:      # result code
                        print("       AVP result-code= %s" % val.hex())
                print("       --> message type = %s (%s)"
                      % (mt, MSG_NAMES.get(mt, "?")))
            return data
    finally:
        s.close()
    return None


# ------------------------------------------------------------ IKEv1 (RFC 2408/2409)
IKE_V1 = 0x10
EXCH_MAIN = 2
NEXT_SA = 1

TRANSFORM_ATTR = {
    "ENCRYPTION_ALGORITHM": 1,
    "HASH_ALGORITHM": 2,
    "AUTHENTICATION_METHOD": 3,
    "GROUP_DESCRIPTION": 4,
    "LIFE_TYPE": 11,
    "LIFE_DURATION": 12,
}


def ike_attr(t, v):
    return u16(0x8000 | t) + u16(v)


def payload(nxt, body):
    """generic ISAKMP payload: next(1) reserved(1) length(2) + body"""
    return bytes([nxt, 0]) + u16(4 + len(body)) + body


def build_ike_main_sa(enc=7, hash_=2, auth=1, group=2, life=28800):
    # transform: KEY_IKE  (enc/hash/auth/group/life configurable)
    attrs = b""
    attrs += ike_attr(TRANSFORM_ATTR["ENCRYPTION_ALGORITHM"], enc)
    attrs += ike_attr(TRANSFORM_ATTR["HASH_ALGORITHM"], hash_)
    attrs += ike_attr(TRANSFORM_ATTR["AUTHENTICATION_METHOD"], auth)
    attrs += ike_attr(TRANSFORM_ATTR["GROUP_DESCRIPTION"], group)
    attrs += ike_attr(TRANSFORM_ATTR["LIFE_TYPE"], 1)
    attrs += struct.pack("!I", life)

    # transform: hdr(4) + transform#(1) transform-id(1) reserved(2) + attrs
    transform = payload(0, bytes([1, 1, 0, 0]) + attrs)
    # proposal: hdr(4) + proposal#(1) proto-id(1) spi-size(1) num-transforms(1) + transforms
    proposal = payload(0, bytes([1, 1, 0, 1]) + transform)
    # SA: hdr(4) + DOI(4) situation(4) + proposal
    sa_payload = payload(0, u32(1) + u32(1) + proposal)

    isakmp = os.urandom(8) + b"\x00" * 8 \
        + bytes([NEXT_SA, IKE_V1, EXCH_MAIN, 0]) \
        + u32(0) + u32(28 + len(sa_payload))
    return isakmp + sa_payload


def probe_ike(host, port, timeout, tries):
    msg = build_ike_main_sa()
    print("== IKEv1 main-mode probe: %s:%d ==" % (host, port))
    print("   SA init %d bytes:" % len(msg))
    hexdump(msg)

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        for i in range(1, tries + 1):
            try:
                s.sendto(msg, (host, port))
            except OSError as e:
                print("   [%d] send error: %s" % (i, e))
                return None
            t0 = time.time()
            try:
                data, addr = s.recvfrom(4096)
            except socket.timeout:
                print("   [%d] no reply within %.1fs" % (i, timeout))
                continue
            dt = (time.time() - t0) * 1000
            print("   [%d] REPLY from %s:%d in %.0f ms, %d bytes"
                  % (i, addr[0], addr[1], dt, len(data)))
            hexdump(data)
            if len(data) >= 28:
                nxt, ver, exch, fl = data[16], data[17], data[18], data[19]
                print("       next=%d version=0x%02x exchange=%d flags=0x%02x"
                      % (nxt, ver, exch, fl))
                if fl & 0x20:
                    print("       --> NOTIFY payload in reply (likely NO_PROPOSAL_CHOSEN"
                          " or INVALID_COOKIE)")
            return data
    finally:
        s.close()
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="58.213.164.4")
    ap.add_argument("--what", default="both", choices=["l2tp", "ike", "both"])
    ap.add_argument("--timeout", type=float, default=3.0)
    ap.add_argument("--tries", type=int, default=3)
    args = ap.parse_args()

    result = {}
    if args.what in ("l2tp", "both"):
        result["l2tp"] = probe_l2tp(args.host, 1701, args.timeout, args.tries)
        print()
    if args.what in ("ike", "both"):
        result["ike500"] = probe_ike(args.host, 500, args.timeout, args.tries)
        print()
        result["ike4500"] = probe_ike(args.host, 4500, args.timeout, args.tries)
        print()

    print("== summary ==")
    print("   plain L2TP (udp/1701) reply : %s"
          % ("YES" if result.get("l2tp") else "no"))
    print("   IKE (udp/500) reply         : %s"
          % ("YES" if result.get("ike500") else "no"))
    print("   IKE NAT-T (udp/4500) reply  : %s"
          % ("YES" if result.get("ike4500") else "no"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
