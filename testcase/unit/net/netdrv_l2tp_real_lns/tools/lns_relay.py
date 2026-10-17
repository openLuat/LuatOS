#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
L2TP relay / protocol tracer.

Sits between the LuatOS L2TP client and a real LNS, forwarding UDP packets
verbatim while decoding the L2TP control plane and the PPP frames carried in
L2TP data packets.  Purely passive w.r.t. the protocol (no rewriting), so the
negotiation result is exactly what the client and LNS would produce directly.

Usage:
  python relay_lns.py --listen 1701 --host 58.213.164.4 --port 1701
"""

import argparse
import socket
import struct
import sys
import threading
import time

LOCK = threading.Lock()


def ts():
    return time.strftime("%H:%M:%S")


def log(*a):
    with LOCK:
        print("[%s] %s" % (ts(), " ".join(str(x) for x in a)), flush=True)


# ---------------------------------------------------------------- decoding
AVP_NAMES = {
    0: "MessageType", 1: "ResultCode", 2: "ProtocolVersion", 3: "FramingCap",
    4: "BearerCap", 5: "TieBreaker", 6: "FirmwareRev", 7: "HostName",
    8: "VendorName", 9: "AssignedTunnelID", 10: "RecvWindowSize",
    11: "Challenge", 13: "ChallengeResponse", 14: "AssignedSessionID",
    15: "CallSerialNumber", 16: "MinimumBPS", 17: "MaximumBPS",
    18: "BearerType", 19: "FramingType", 20: "CalledNumber",
    21: "CallingNumber", 22: "SubAddress", 23: "TxConnectSpeed",
    24: "PhysicalChannelID", 25: "InitialRecvLCPREQ", 26: "LastSentLCPREQ",
    27: "LastRecvLCPREQ", 28: "ProxyAuthenType", 29: "ProxyAuthenName",
    30: "ProxyAuthenChallenge", 31: "ProxyAuthenID", 32: "ProxyAuthenResponse",
}

MSG_NAMES = {
    1: "SCCRQ", 2: "SCCRP", 3: "SCCCN", 4: "StopCCN", 5: "Reserved",
    6: "HELLO", 7: "OCRQ", 8: "OCRP", 9: "OCCN", 10: "ICRQ", 11: "ICRP",
    12: "ICCN", 13: "Reserved", 14: "CDN",
}

PPP_NAMES = {
    0x0021: "IP", 0x0057: "IPv6", 0xC021: "LCP", 0x8021: "IPCP",
    0x8057: "IPV6CP", 0xC023: "PAP", 0xC223: "CHAP", 0xC025: "LQR",
    0xC029: "LQR2", 0xC227: "EAP", 0x80FD: "CCP", 0x80FB: "BAP",
    0xC05D: "Multilink", 0x8023: "OSINLCP", 0x8281: "MPLSCP",
}

LCP_OPT_NAMES = {
    1: "MRU", 2: "ACCM", 3: "AuthProto", 4: "Quality", 5: "MagicNumber",
    7: "PFC", 8: "ACFC", 9: "FCS-Alternatives", 10: "Self-Describing-Pad",
    11: "Numbered-Mode", 12: "Multi-Link-Procedure", 13: "Callback",
    14: "Connect-Time", 15: "Compound-Frames", 16: "Nominal-Load",
    17: "Max-Receive-Unit", 18: "Async-Control-Char-Map",
    19: "Authentication-Protocol", 20: "Quality-Protocol",
}

AUTH_PROTO_NAMES = {0xC023: "PAP", 0xC223: "CHAP", 0xC227: "EAP", 0xC05D: "SPAP"}
CHAP_ALG_NAMES = {5: "CHAP-MD5", 0x80: "MS-CHAPv1", 0x81: "MS-CHAPv2"}


def parse_avps(data, off=12):
    """RFC 2661 AVP header: word(2)=M|H|rsvd|Length(10b), VendorID(2), AttrType(2), Value"""
    out = []
    while off + 6 <= len(data):
        word = struct.unpack("!H", data[off:off + 2])[0]
        length = word & 0x03FF
        if length < 6 or off + length > len(data):
            break
        if word & 0x4000:
            out.append(((word & 0x3FFF), b"<hidden>"))
            off += length
            continue
        attr = struct.unpack("!H", data[off + 4:off + 6])[0]
        out.append((attr, data[off + 6:off + length]))
        off += length
    return out


def decode_l2tp(data, direction):
    """returns (kind, summary) where kind is 'ctrl'/'data'/'unknown'"""
    if len(data) < 12:
        return "unknown", "short packet %d bytes: %s" % (len(data), data.hex())
    flags, length = struct.unpack("!HH", data[0:4])
    tunnel_id, session_id = struct.unpack("!HH", data[4:8])
    ns, nr = struct.unpack("!HH", data[8:12])
    ver = flags & 0x000F

    if flags & 0x8000:      # control
        parts = []
        mtype = None
        for attr, val in parse_avps(data):
            name = AVP_NAMES.get(attr, "AVP%d" % attr)
            if attr == 0 and len(val) == 2:
                mtype = struct.unpack("!H", val)[0]
            if attr in (9, 14, 10, 5, 2, 6, 19, 23) and len(val) in (2, 4):
                v = struct.unpack("!H" if len(val) == 2 else "!I", val)[0]
                parts.append("%s=%d" % (name, v))
            elif attr in (7, 8):
                parts.append("%s=%s" % (name, val.decode("utf-8", "replace")))
            elif attr == 1:
                parts.append("%s=%s" % (name, val.hex()))
            else:
                parts.append("%s(%dB)" % (name, len(val)))
        mname = MSG_NAMES.get(mtype, "msg%s" % mtype) if mtype is not None else "msg?"
        if mtype is None:
            parts.append("RAW=" + data.hex())
        return "ctrl", "tun=%d sess=%d ns=%d nr=%d %s | %s" % (
            tunnel_id, session_id, ns, nr, mname, " ".join(parts))

    # data packet: PPP frame follows the 6/8-byte L2TP header
    off = 6 if not (flags & 0x0200) else 8
    if flags & 0x4000:
        off += 0  # length already consumed
    off = 6
    ppp = data[off:]
    if len(ppp) >= 2 and ppp[0:2] == b"\xff\x03":
        ppp = ppp[2:]
    if len(ppp) < 2:
        return "data", "tun=%d sess=%d ns=%d nr=%d <short ppp>" % (tunnel_id, session_id, ns, nr)
    proto = struct.unpack("!H", ppp[0:2])[0]
    body = ppp[2:]
    name = PPP_NAMES.get(proto, "proto=0x%04x" % proto)
    detail = ""

    if proto in (0xC021, 0x8021) and len(body) >= 4:      # LCP / IPCP
        code, pid, plen = struct.unpack("!BBH", body[0:4])
        codes = {1: "ConfReq", 2: "ConfAck", 3: "ConfNak", 4: "ConfRej",
                 5: "TermReq", 6: "TermAck", 7: "CodeRej", 8: "ProtoRej",
                 9: "EchoReq", 10: "EchoRep", 11: "DiscReq"}
        opts = []
        o = 4
        while o + 2 <= min(plen, len(body)):
            otype, olen = body[o], body[o + 1]
            if olen < 2 or o + olen > len(body):
                opts.append("opt%d(bad len %d)" % (otype, olen))
                break
            oval = body[o + 2:o + olen]
            oname = LCP_OPT_NAMES.get(otype, "opt%d" % otype)
            if proto == 0xC021 and otype == 3 and len(oval) >= 2:
                ap = struct.unpack("!H", oval[0:2])[0]
                extra = ""
                if len(oval) > 2:
                    alg = oval[2]
                    extra = " alg=0x%02x(%s)" % (alg, CHAP_ALG_NAMES.get(alg, "?"))
                opts.append("%s=%s%s" % (oname, AUTH_PROTO_NAMES.get(ap, "0x%04x" % ap), extra))
            elif proto == 0x8021 and otype in (3, 129, 130, 131, 132) and len(oval) == 4:
                nm = {3: "IPAddr", 129: "PriDNS", 130: "PriNBNS",
                      131: "SecDNS", 132: "SecNBNS"}[otype]
                opts.append("%s=%s" % (nm, socket.inet_ntoa(oval)))
            elif otype in (1, 5) and len(oval) == 2:
                opts.append("%s=%d" % (oname, struct.unpack("!H", oval)[0]))
            elif otype in (2, 18) and len(oval) == 4:
                opts.append("%s=0x%08x" % (oname, struct.unpack("!I", oval)[0]))
            elif otype in (3, 129, 131) and len(oval) == 4:
                opts.append("%s=%s" % ("IPAddr" if otype == 3 else ("PriDNS" if otype == 129 else "SecDNS"),
                                       socket.inet_ntoa(oval)))
            else:
                opts.append("%s=%s" % (oname, oval.hex()))
            o += olen
        detail = "%s id=%d len=%d %s" % (codes.get(code, "code%d" % code), pid, plen, " ".join(opts))

    elif proto == 0xC023 and len(body) >= 4:              # PAP
        code, pid, plen = struct.unpack("!BBH", body[0:4])
        pd = body[4:plen]
        if code == 1 and len(pd) >= 1:
            ulen = pd[0]
            user = pd[1:1 + ulen].decode("utf-8", "replace")
            detail = "AuthReq id=%d user=%s passwd_len=%d" % (pid, user, max(0, len(pd) - 1 - ulen))
        elif code == 2:
            detail = "AuthAck id=%d msg=%r" % (pid, pd[1:].decode("utf-8", "replace"))
        elif code == 3:
            detail = "AuthNak id=%d msg=%r" % (pid, pd[1:].decode("utf-8", "replace"))
        else:
            detail = "code=%d id=%d" % (code, pid)

    elif proto == 0xC223 and len(body) >= 4:              # CHAP
        code, pid, plen = struct.unpack("!BBH", body[0:4])
        pd = body[4:plen]
        if code in (1, 2) and len(pd) >= 1:
            vlen = pd[0]
            val = pd[1:1 + vlen]
            nm = pd[1 + vlen:].decode("utf-8", "replace")
            alg = val[0] if val else -1
            detail = "%s id=%d alg=0x%02x(%s) value=%s name=%s" % (
                "Challenge" if code == 1 else "Response", pid, alg,
                CHAP_ALG_NAMES.get(alg, "?"), val.hex(), nm)
        elif code == 3:
            detail = "Success id=%d msg=%r" % (pid, pd[1:].decode("utf-8", "replace"))
        elif code == 4:
            detail = "Failure id=%d msg=%r" % (pid, pd[1:].decode("utf-8", "replace"))
        else:
            detail = "code=%d id=%d" % (code, pid)

    elif proto == 0x80FD and len(body) >= 4:              # CCP
        code, pid, plen = struct.unpack("!BBH", body[0:4])
        detail = "CCP code=%d id=%d body=%s" % (code, pid, body[4:plen].hex())

    elif proto == 0x0021 and len(body) >= 20:             # IPv4
        ihl = (body[0] & 0x0F) * 4
        proto_ip = body[9]
        src = socket.inet_ntoa(body[12:16])
        dst = socket.inet_ntoa(body[16:20])
        detail = "%s -> %s ipproto=%d len=%d" % (src, dst, proto_ip, len(body))

    else:
        detail = body[:32].hex()

    return "data", "tun=%d sess=%d %s | %s" % (tunnel_id, session_id, name, detail)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=int, default=1701)
    ap.add_argument("--host", default="58.213.164.4")
    ap.add_argument("--port", type=int, default=1701)
    ap.add_argument("--quiet-ip", action="store_true", help="do not log inner IPv4 packets")
    args = ap.parse_args()

    front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    front.bind(("0.0.0.0", args.listen))
    front.settimeout(1.0)

    back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    back.bind(("0.0.0.0", 0))
    back.settimeout(1.0)
    back.connect((args.host, args.port))
    log("relay listening on udp/%d -> %s:%d (local port %d)"
        % (args.listen, args.host, args.port, back.getsockname()[1]))

    client_addr = [None]
    stop = threading.Event()

    def back_thread():
        while not stop.is_set():
            try:
                data, addr = back.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            if client_addr[0] is None:
                continue
            try:
                kind, txt = decode_l2tp(data, "s2c")
            except Exception as e:
                kind, txt = "?", "decode error %s" % e
            if not (args.quiet_ip and txt.startswith("tun=") and " | IP |" in txt):
                log("LNS -> LAC  %-4s %5dB  %s" % (kind, len(data), txt))
            front.sendto(data, client_addr[0])

    t = threading.Thread(target=back_thread, daemon=True)
    t.start()

    log("waiting for the LAC to send the first SCCRQ ...")
    try:
        while True:
            try:
                data, addr = front.recvfrom(4096)
            except socket.timeout:
                continue
            if client_addr[0] != addr:
                client_addr[0] = addr
                log("LAC endpoint = %s:%d" % addr)
            try:
                kind, txt = decode_l2tp(data, "c2s")
            except Exception as e:
                kind, txt = "?", "decode error %s" % e
            if not (args.quiet_ip and txt.startswith("tun=") and " | IP |" in txt):
                log("LAC -> LNS  %-4s %5dB  %s" % (kind, len(data), txt))
            back.send(data)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        front.close()
        back.close()


if __name__ == "__main__":
    sys.exit(main())
