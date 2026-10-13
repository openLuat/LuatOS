-- GB28181 SIP 黄金报文：由 C 的 gb28181.sip_build 生成后冻结。
-- 迁移到 exgb28181sip 后用它保证逐字节不变；改它就是改预期，务必与真实平台联调后再动。
return {
    register =
        "REGISTER sip:35020000002000000001@3502000000 SIP/2.0\r\nVia: SIP/2.0/UDP 192.168.0.13:5160;rport;bra" ..
        "nch=1234567890abcdef\r\nFrom: <sip:35020000001320000001@3502000000>;tag=abcdef01\r\nTo: <sip:3502000" ..
        "0001320000001@3502000000>\r\nCall-ID: 0123456789abcdef@192.168.0.13\r\nCSeq: 1 REGISTER\r\nContact: " ..
        "<sip:35020000001320000001@192.168.0.13:5160>\r\nMax-Forwards: 70\r\nUser-Agent: LuatOS-GB28181\r\nEx" ..
        "pires: 3600\r\nAuthorization: Digest username=\"35020000001320000001\", realm=\"3502000000\", nonce=" ..
        "\"abc\", uri=\"sip:x\", response=\"deadbeef\"\r\nContent-Length: 0\r\n\r\n",
    message_manscdp =
        "MESSAGE sip:35020000002000000001@3502000000 SIP/2.0\r\nVia: SIP/2.0/UDP 192.168.0.13:5160;rport;bran" ..
        "ch=1234567890abcdef\r\nFrom: <sip:35020000001320000001@3502000000>;tag=abcdef01\r\nTo: <sip:35020000" ..
        "001320000001@3502000000>\r\nCall-ID: c1@192.168.0.13\r\nCSeq: 2 MESSAGE\r\nContact: <sip:35020000001" ..
        "320000001@192.168.0.13:5160>\r\nMax-Forwards: 70\r\nUser-Agent: LuatOS-GB28181\r\nContent-Type: Appl" ..
        "ication/MANSCDP+xml\r\nContent-Length: 70\r\n\r\n<?xml version=\"1.0\"?>\r\n<Notify><CmdType>Keepali" ..
        "ve</CmdType></Notify>\r\n",
    invite_subject =
        "INVITE sip:35020000002000000001@3502000000 SIP/2.0\r\nVia: SIP/2.0/UDP 192.168.0.13:5160;rport;branc" ..
        "h=1234567890abcdef\r\nFrom: <sip:35020000001320000001@3502000000>;tag=abcdef01\r\nTo: <sip:350200000" ..
        "02000000001@3502000000>\r\nCall-ID: c2@192.168.0.13\r\nCSeq: 3 INVITE\r\nContact: <sip:3502000000132" ..
        "0000001@192.168.0.13:5160>\r\nMax-Forwards: 70\r\nUser-Agent: LuatOS-GB28181\r\nContent-Type: applic" ..
        "ation/sdp\r\nSubject: 34020000001320000001:talk,34020000001320000001:0\r\nContent-Length: 61\r\n\r\n" ..
        "v=0\r\no=35020000001320000001 0 0 IN IP4 192.168.0.13\r\ns=Talk\r\n",
    ack =
        "ACK sip:35020000002000000001@3502000000 SIP/2.0\r\nVia: SIP/2.0/UDP 192.168.0.13:5160;rport;branch=1" ..
        "234567890abcdef\r\nFrom: <sip:35020000001320000001@3502000000>;tag=abcdef01\r\nTo: <sip:350200000020" ..
        "00000001@3502000000>;tag=plat01\r\nCall-ID: c3@192.168.0.13\r\nCSeq: 4 ACK\r\nContact: <sip:35020000" ..
        "001320000001@192.168.0.13:5160>\r\nMax-Forwards: 70\r\nUser-Agent: LuatOS-GB28181\r\nContent-Length:" ..
        " 0\r\n\r\n",
    ok_single_via =
        "SIP/2.0 200 OK\r\nVia: SIP/2.0/UDP 192.168.0.4:8160;branch=z9hG4bKplat\r\nFrom: <sip:350200000020000" ..
        "00001@3502000000>;tag=platfrom\r\nTo: <sip:35020000001320000001@3502000000>\r\nCall-ID: c4@192.168.0" ..
        ".4\r\nCSeq: 7 MESSAGE\r\nUser-Agent: LuatOS-GB28181\r\nContent-Length: 0\r\n\r\n",
    ok_multi_via =
        "SIP/2.0 200 OK\r\nVia: SIP/2.0/UDP 192.168.0.4:8160;branch=z9hG4bKa\r\nVia: SIP/2.0/UDP 192.168.0.9:" ..
        "8160;branch=z9hG4bKb\r\nFrom: <sip:35020000002000000001@3502000000>;tag=pf\r\nTo: <sip:3502000000132" ..
        "0000001@3502000000>;tag=dev\r\nCall-ID: c5@192.168.0.4\r\nCSeq: 8 SUBSCRIBE\r\nUser-Agent: LuatOS-GB" ..
        "28181\r\nExpires: 3600\r\nEvent: Catalog\r\nContent-Length: 0\r\n\r\n",
    tcp_register =
        "REGISTER sip:35020000002000000001@3502000000 SIP/2.0\r\nVia: SIP/2.0/TCP 192.168.0.13:5160;branch=12" ..
        "34567890abcdef\r\nFrom: <sip:35020000001320000001@3502000000>;tag=abcdef01\r\nTo: <sip:3502000000132" ..
        "0000001@3502000000>\r\nCall-ID: c6@192.168.0.13\r\nCSeq: 9 REGISTER\r\nContact: <sip:350200000013200" ..
        "00001@192.168.0.13:5160;transport=tcp>\r\nMax-Forwards: 70\r\nUser-Agent: LuatOS-GB28181\r\nExpires:" ..
        " 3600\r\nContent-Length: 0\r\n\r\n",
    gone_with_body =
        "SIP/2.0 410 Gone\r\nVia: SIP/2.0/UDP 192.168.0.4:8160;branch=z9hG4bKc\r\nFrom: <sip:a@b>;tag=f\r\nTo" ..
        ": <sip:c@d>;tag=t\r\nCall-ID: c7@x\r\nCSeq: 10 INVITE\r\nUser-Agent: LuatOS-GB28181\r\nContent-Type:" ..
        " Application/MANSCDP+xml\r\nContent-Length: 47\r\n\r\n<Response><CmdType>Catalog</CmdType></Response" ..
        ">",
}
