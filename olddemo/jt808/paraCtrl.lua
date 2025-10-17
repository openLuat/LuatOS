local paraCtrl = {}

--终端自身的手机号码
function paraCtrl.getTerminalNum()
    return "13937000000"
end


--省域ID
function paraCtrl.getProvinceId()
    return 0
end

--区县ID
function paraCtrl.getCityId()
    return 0
end

--制造商ID
function paraCtrl.getManufactureId()
    return "00001"
end

--终端型号
function paraCtrl.getTerminalModule()
    return "GT808"..string.rep(string.char(0),20-("GT808"):len())
end

--终端ID
function paraCtrl.getTerminalId()
    --return ("12341234001".."000"):fromHex()
    return ("00000000000000"):fromHex()
end

--车辆颜色
function paraCtrl.getCarColor()
    return 0
end

--车辆标识
function paraCtrl.getCarNumber()
    return "41048063212"
end




function paraCtrl.setPara(id,len,data)
    local value
    if len==1 then
        value = data:byte(1)
    elseif len==2 then
        _,value = pack.unpack(data,">H")
    elseif len==4 then
        _,value = pack.unpack(data,">i")
    end

    local numberPara =
    {
        [JT808Prot.PARA_HEART_FREQ] = "heartFreq",
        [JT808Prot.PARA_TCP_RSP_TIMEOUT] = "tcpSndTimeout",
        [JT808Prot.PARA_TCP_RESEND_CNT] = "tcpResendMaxCnt",
        [JT808Prot.PARA_LOC_RPT_STRATEGY] = "locRptStrategy",
        [JT808Prot.PARA_LOC_RPT_MODE] = "locRptMode",
        [JT808Prot.PARA_SLEEP_LOC_RPT_FREQ] = "sleepLocRptFreq",
        [JT808Prot.PARA_ALARM_LOC_RPT_FREQ] = "alarmLocRptFreq",
        [JT808Prot.PARA_WAKE_LOC_RPT_FREQ] = "wakeLocRptFreq",
        [JT808Prot.PARA_WAKE_LOC_RPT_DISTANCE] = "sleepLocRptDistance",
        [JT808Prot.PARA_SLEEP_LOC_RPT_DISTANCE] = "alarmLocRptDistance",
        [JT808Prot.PARA_ALARM_LOC_RPT_DISTANCE] = "wakeLocRptDistance",
        [JT808Prot.PARA_FENCE_RADIS] = "fenceRadis",
        [JT808Prot.PARA_ALARM_FILTER] = "alarmFilter",
        [JT808Prot.PARA_KEY_FLAG] = "keyFlag",
        [JT808Prot.PARA_SPEED_LIMIT] = "speedLimit",
        [JT808Prot.PARA_SPEED_EXCEED_TIME] = "speedExceedTime",
    }

    if numberPara[id] then
        fskv.set(numberPara[id],value)
        return true
    end

    return false
end

return paraCtrl
