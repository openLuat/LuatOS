local sms_test = {}

-- 提取meta中的值, 兼容不同字段命名
local function pick(meta, keys)
    if type(meta) ~= "table" then return nil end
    local function try(tbl)
        for _, key in ipairs(keys) do
            if tbl[key] ~= nil then
                return tbl[key]
            end
        end
    end
    local value = try(meta)
    if value ~= nil then return value end
    for _, subKey in ipairs({"concat", "udh", "udhi", "info"}) do
        local sub = meta[subKey]
        if type(sub) == "table" then
            if #sub > 0 then
                for _, item in ipairs(sub) do
                    value = try(item)
                    if value ~= nil then return value end
                end
            else
                value = try(sub)
                if value ~= nil then return value end
            end
        end
    end
    return nil
end

-- 单条短信解析验证
function sms_test.test_single_sms_unpack()
    local pdu = "07919761989900F0040B919761564321F60000911060317391800AE8329BFD4697D9EC37"
    local phone, text, meta = sms.unpack(pdu)

    assert(phone == "+79166534126" or phone == "79166534126", "号码解析错误:" .. tostring(phone))
    assert(text == "hellohello", "文本解析错误:" .. tostring(text))
    assert(type(meta) == "table", "meta缺失")
end

-- 长短信5段重新排序并合并
function sms_test.test_long_sms_reassembly()
    local pdus = {
        "0891683108200955F1640AA001568800030008621070819583238B060804BC200503FF0C67096548671F518553EF968F65F690008BA2FF0C5982970090008BA28BF762E86253003100300030003800365BA2670D70ED7EBF6216901A8FC7652F4ED85B9D53CC00564F1A54585C0F7A0B5E8F90008BA2FF0C90008BA2540E4EA754C16B2167088D775931654830024EA754C1670D52A15305542B901A75286D4191CF65E55305",
        "0891683108200955F1640AA001568800030008621070819583238B060804BC200502004A0054003200300037003600360037FF09FF0C8BA28D2D6210529F540E7ACB5373751F6548FF0C8D448D390031002E003900395143002F6708FF0C4EA754C167096548671F00335E74FF0C598253CC65B9572867096548671F5C4A6EE1524D65E05F028BAEFF0C67096548671F81EA52A87EED5C55FF0C6BCF6B217EED5C5500335E74",
        "0891683108200955F1640AA001568800030008621070819583238B060804BC20050453CA751F6D3B793C5238FF0C51774F534EE5987597625C55793A4E3A51C63002672C4EA754C165E054087EA663467ED1FF0C90008BA2002F95006237002F643A8F6C7B4965E09700627F62C58FDD7EA68D234EFB30024EE54E0A9A8C8BC1780100355206949F518567096548FF0C8BF752FF6CC4973262168F6C53D14ED64EBA30023010",
        "0891683108200955F1640AA001568800030008621070819583238B060804BC20050130109A8C8BC15BC67801301160A876849A8C8BC178014E3A003100340031003730025C0A656C76845BA26237FF0C60A86B6357284E2D56FD79FB52A876847EBF4E0A6E2090538BA28D2D4E2D56FD79FB52A8002D652F4ED85B9D53CC00564F1A54585C0A4EAB674376CAFF088BDD8D39652F4ED87248FF09FF087F1653F7FF1A00320035",
        "0891683108200955F1640AA0015688000300086210708195832321060804BC2005054E2D56FD79FB52A80058652F4ED85B9D53CC00564F1A54583011"
    }
    local expected_full = "【验证密码】您的验证码为1417。尊敬的客户，您正在中国移动的线上渠道订购中国移动-支付宝双V会员尊享权益（话费支付版）（编号：25JT207667），订购成功后立即生效，资费1.99元/月，产品有效期3年，如双方在有效期届满前无异议，有效期自动续展，每次续展3年，有效期内可随时退订，如需退订请拨打10086客服热线或通过支付宝双V会员小程序退订，退订后产品次月起失效。产品服务包含通用流量日包及生活礼券，具体以页面展示为准。本产品无合约捆绑，退订/销户/携转等无需承担违约责任。以上验证码5分钟内有效，请勿泄露或转发他人。【中国移动X支付宝双V会员】"

    local parts = {}
    local ref_value
    for _, pdu in ipairs(pdus) do
        local phone, text, meta = sms.unpack(pdu)
        assert(phone == "1065880030", "号码解析错误:" .. tostring(phone))
        assert(type(text) == "string" and #text > 0, "长短信分片文本为空")
        assert(type(meta) == "table", "meta缺失")

        -- 兼容不同固件的字段命名, 已知meta示例: {"tz":0,"min":59,"seqNum":3,"refNum":48160,"year":26,"sec":38,"maxNum":5,"mon":1,"hour":18,"day":7}
        local seq = pick(meta, {"seq", "part", "index", "no", "csms_no", "segment", "number", "seqNum"})
        local total = pick(meta, {"total", "parts", "count", "csms_total", "maxNum"})
        local ref = pick(meta, {"ref", "csms_ref", "reference", "concat_ref", "refNum"})

        assert(total == 5, "分片数量解析异常:" .. tostring(total))
        assert(seq and seq >= 1 and seq <= total, "分片序号解析异常:" .. tostring(seq))
        ref_value = ref_value or ref
        if ref_value then
            assert(ref == nil or ref == ref_value, "分片参考号不一致")
        end
        parts[seq] = text
    end

    for i = 1, 5 do
        assert(parts[i], "缺少分片" .. i)
    end

    local combined = table.concat(parts)
    assert(combined == expected_full, "长短信内容组装不一致")
end

-- 长英文短信(2段, UCS2)重新排序并合并
function sms_test.test_long_english_sms_reassembly()
    local pdus = {
        -- Part 1/2, ref=0x6A, seq=1
        "00040A912143658709000862107021000000800500036A02010054006800690073002000690073002000610020006C006F006E006700200045006E0067006C00690073006800200053004D00530020006D006500730073006100670065002000740068006100740020007300700061006E0073002000740077006F002000700061007200740073002E00200050006100720074",
        -- Part 2/2, ref=0x6A, seq=2
        "00040A912143658709000862107021000000820500036A020200200031002F0032003A0020004C006F00720065006D00200069007000730075006D00200064006F006C006F0072002000730069007400200061006D00650074002C00200063006F006E00730065006300740065007400750072002000610064006900700069007300630069006E006700200065006C00690074002E"
    }

    local expected_full = "This is a long English SMS message that spans two parts. Part 1/2: Lorem ipsum dolor sit amet, consectetur adipiscing elit."

    local parts = {}
    local ref_value
    for _, pdu in ipairs(pdus) do
        local phone, text, meta = sms.unpack(pdu)
        assert(phone == "+1234567890" or phone == "1234567890", "号码解析错误:" .. tostring(phone))
        assert(type(text) == "string" and #text > 0, "长英文分片文本为空")
        assert(type(meta) == "table", "meta缺失")

        local seq = pick(meta, {"seq", "part", "index", "no", "csms_no", "segment", "number", "seqNum"})
        local total = pick(meta, {"total", "parts", "count", "csms_total", "maxNum"})
        local ref = pick(meta, {"ref", "csms_ref", "reference", "concat_ref", "refNum"})

        assert(total == 2, "分片数量解析异常:" .. tostring(total))
        assert(seq and seq >= 1 and seq <= total, "分片序号解析异常:" .. tostring(seq))
        ref_value = ref_value or ref
        if ref_value then
            assert(ref == nil or ref == ref_value, "分片参考号不一致")
        end
        parts[seq] = text
    end

    for i = 1, 2 do
        assert(parts[i], "缺少英文分片" .. i)
    end

    local combined = table.concat(parts)
    assert(combined == expected_full, "长英文内容组装不一致")
end

-- 非法PDU解析应当失败
function sms_test.test_invalid_pdu_returns_error()
    local invalid = "00112233"
    local ok, phone, text, meta = pcall(sms.unpack, invalid)
    if ok then
        assert(phone == nil and text == nil, "非法PDU不应返回有效结果")
    end
end

-- 多语种 UCS2 内容解析验证（中/日/韩/俄）
function sms_test.test_multilang_ucs2_unpack()
    -- 这些PDU均为SMS-DELIVER格式, 采用UCS2编码, SMSC长度为0以便脱离运营商配置直接测试解包
    local cases = {
        { -- Russian: "Привет"
            pdu = "00040B911732547698F00008621070819583000C041F04400438043204350442",
            number = "+71234567890",
            text = "Привет"
        },
        { -- Japanese: "こんににち"
            pdu = "00040C911809214365870008621070819583000A30533093306B306B3061",
            number = "+819012345678",
            text = "こんににち"
        },
        { -- Korean: "안녕하세요"
            pdu = "00040C912801214365870008621070819583000AC548B155D558C138C694",
            number = "+821012345678",
            text = "안녕하세요"
        }
    }

    for _, case in ipairs(cases) do
        local phone, text = sms.unpack(case.pdu)
        assert(phone == case.number or phone == case.number:gsub("^%+", ""), "号码解析错误:" .. tostring(phone))
        log.info("解析文本:", text, "期望文本:", case.text)
        assert(text == case.text, "多语种文本解析错误:" .. tostring(text), case.text)
    end
end

return sms_test
