
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sms_unpack"
VERSION = "1.0.0"


sys.taskInit(function()
    -- 测试sms.unpack函数
    local pdu_hex = "0891683108200955F1640AA001568800030008621070819583238B060804BC200503FF0C67096548671F518553EF968F65F690008BA2FF0C5982970090008BA28BF762E86253003100300030003800365BA2670D70ED7EBF6216901A8FC7652F4ED85B9D53CC00564F1A54585C0F7A0B5E8F90008BA2FF0C90008BA2540E4EA754C16B2167088D775931654830024EA754C1670D52A15305542B901A75286D4191CF65E55305"
    log.info("PDU Hex:", pdu_hex)
    local phone, txt, meta = sms.unpack(pdu_hex)

    log.info("phone", phone)
    log.info("txt", txt)
    log.info("meta:", json.encode(meta or {}))
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
