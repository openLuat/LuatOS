--[[
@module  netdrv_multiple
@summary 澶氱綉鍗★紙4G缃戝崱銆侀€氳繃SPI澶栨寕CH390H鑺墖鐨勪互澶綉鍗★級椹卞姩妯″潡
@version 1.0
@date    2025.07.24
@author  椹ⅵ闃?
@usage
鏈枃浠朵负澶氱綉鍗￠┍鍔ㄦā鍧?锛屾牳蹇冧笟鍔￠€昏緫涓猴細
1銆佽皟鐢╡xnetif.set_priority_order閰嶇疆澶氱綉鍗＄殑鎺у埗鍙傛暟浠ュ強浼樺厛绾э紱

閫氳繃SPI澶栨寕CH390H鑺墖鐨勪互澶綉鍗★細
Air780EXX鏍稿績鏉垮拰AirETH_1000閰嶄欢鏉跨殑纭欢鎺ョ嚎鏂瑰紡涓?
鏍稿績鏉块€氳繃TYPE-C USB鍙ｄ緵鐢碉紙TYPE-C USB鍙ｆ梺杈圭殑ON/OFF鎷ㄥ姩寮€鍏虫嫧鍒癘N涓€绔級锛?
濡傛灉娴嬭瘯鍙戠幇杞欢閲嶅惎锛屽苟涓旀棩蹇椾腑鍑虹幇  poweron reason 0锛岃〃绀轰緵鐢典笉瓒筹紝姝ゆ椂鍐嶉€氳繃鐩存祦绋冲帇鐢垫簮瀵规牳蹇冩澘鐨?V绠¤剼杩涜5V渚涚數锛?
| Air780EXX鏍稿績鏉? |  AirETH_1000閰嶄欢鏉?|
| --------------- | ----------------- |
| 3V3             | 3.3v              |
| gnd             | gnd               |
| 86/SPI0CLK      | SCK               |
| 83/SPI0CS       | CSS               |
| 84/SPI0MISO     | SDO               |
| 85/SPI0MOSI     | SDI               |
| 22/GPIO1      | INT               |

鏈枃浠舵病鏈夊澶栨帴鍙ｏ紝鐩存帴鍦ㄥ叾浠栧姛鑳芥ā鍧椾腑require "netdrv_multiple"灏卞彲浠ュ姞杞借繍琛岋紱
]]


local exnetif = require "exnetif"

-- 缃戝崱鐘舵€佸彉鍖栭€氱煡鍥炶皟鍑芥暟
-- 褰揺xnetif涓娴嬪埌缃戝崱鍒囨崲鎴栬€呮墍鏈夌綉鍗￠兘鏂綉鏃讹紝浼氳Е鍙戣皟鐢ㄦ鍥炶皟鍑芥暟
-- 褰撶綉鍗″垏鎹㈠垏鎹㈡椂锛?
--     net_type锛歴tring绫诲瀷锛岃〃绀哄綋鍓嶄娇鐢ㄧ殑缃戝崱瀛楃涓?
--     adapter锛歯umber绫诲瀷锛岃〃绀哄綋鍓嶄娇鐢ㄧ殑缃戝崱id
-- 褰撴墍鏈夌綉鍗℃柇缃戞椂锛?
--     net_type锛氫负nil
--     adapter锛歯umber绫诲瀷锛屼负-1
local function netdrv_multiple_notify_cbfunc(net_type,adapter)
    -- 鍦ㄤ綅缃?鍜?璁剧疆鑷畾涔夌殑DNS鏈嶅姟鍣╥p鍦板潃锛?
    -- "223.5.5.5"锛岃繖涓狣NS鏈嶅姟鍣↖P鍦板潃鏄樋閲屼簯鎻愪緵鐨凞NS鏈嶅姟鍣↖P鍦板潃锛?
    -- "114.114.114.114"锛岃繖涓狣NS鏈嶅姟鍣↖P鍦板潃鏄浗鍐呴€氱敤鐨凞NS鏈嶅姟鍣↖P鍦板潃锛?
    -- 鍙互鍔犱笂浠ヤ笅涓よ浠ｇ爜锛屽湪鑷姩鑾峰彇鐨凞NS鏈嶅姟鍣ㄥ伐浣滀笉绋冲畾鐨勬儏鍐典笅锛岃繖涓や釜鏂板鐨凞NS鏈嶅姟鍣ㄤ細浣緿NS鏈嶅姟鏇村姞绋冲畾鍙潬锛?
    -- 濡傛灉浣跨敤涓撶綉鍗★紝涓嶈浣跨敤杩欎袱琛屼唬鐮侊紱
    -- 濡傛灉浣跨敤鍥藉鐨勭綉缁滐紝涓嶈浣跨敤杩欎袱琛屼唬鐮侊紱
    socket.setDNS(adapter, 1, "223.5.5.5")
    socket.setDNS(adapter, 2, "114.114.114.114")
    
    if type(net_type)=="string" then
        log.info("netdrv_multiple_notify_cbfunc", "use new adapter", net_type, adapter)
    elseif type(net_type)=="nil" then
        log.warn("netdrv_multiple_notify_cbfunc", "no available adapter", net_type, adapter)
    else
        log.warn("netdrv_multiple_notify_cbfunc", "unknown status", net_type, adapter)
    end
end

local function netdrv_multiple_task_func()
    --璁剧疆缃戝崱浼樺厛绾?
    exnetif.set_priority_order(
        {
            -- 鈥滈€氳繃SPI澶栨寕CH390H鑺墖鈥濈殑浠ュお缃戝崱锛屼娇鐢ˋir780EXX鏍稿績鏉块獙璇?
            {
                ETHERNET = {
                    -- 鏈琩emo娴嬭瘯浣跨敤鐨勬槸Air780EXX鏍稿績鏉?
                    -- 鏍稿績鏉跨殑VDD 3V3绠¤剼瀵笰irETH_1000閰嶄欢鏉胯繘琛屼緵鐢?
                    -- 3V3绠¤剼鏄綔涓篖DO 3.3V杈撳嚭锛屼緵娴嬭瘯鐢ㄧ殑锛屼粎鍦ㄤ娇鐢―CDC渚涚數鏃舵湁杈撳嚭锛岄粯璁ゆ墦寮€锛屾棤闇€鎺у埗
                    -- 渚涚數浣胯兘GPIO
                    pwrpin = nil,
                    -- 璁剧疆鐨勫涓?宸茬粡IP READY锛屼絾鏄繕娌℃湁ping閫?缃戝崱锛屽惊鐜墽琛宲ing鍔ㄤ綔鐨勯棿闅旓紙鍗曚綅姣锛屽彲閫夛級
                    -- 濡傛灉娌℃湁浼犲叆姝ゅ弬鏁帮紝exnetif浼氫娇鐢ㄩ粯璁ゅ€?0绉?
                    ping_time = 3000,

                    -- 杩為€氭€ф娴媔p(閫夊～鍙傛暟)锛?
                    -- 濡傛灉娌℃湁浼犲叆ip鍦板潃锛宔xnetif涓細榛樿浣跨敤httpdns鑳藉惁鎴愬姛鑾峰彇baidu.com鐨刬p浣滀负鏄惁杩為€氱殑鍒ゆ柇鏉′欢锛?
                    -- 濡傛灉浼犲叆锛屼竴瀹氳浼犲叆鍙潬鐨勫苟涓斿彲浠ing閫氱殑ip鍦板潃锛?
                    -- ping_ip = "濉叆鍙潬鐨勫苟涓斿彲浠ing閫氱殑ip鍦板潃",

                    -- 缃戝崱鑺墖鍨嬪彿(閫夊～鍙傛暟)锛屼粎spi鏂瑰紡澶栨寕浠ュお缃戞椂闇€瑕佸～鍐欍€?
                    -- INT涓柇寮曡剼锛屼娇鐢ㄤ腑鏂ā寮忔彁楂樺搷搴旈€熷害, 鑻ヤ笉濉鍙傛暟锛岄粯璁や笉浣跨敤涓柇妯″紡鑰屾槸浣跨敤杞妯″紡
                    tp = netdrv.CH390,
                    opts = {spi=0, cs=8, irq = 1}
                }
            },

            -- 4G缃戝崱
            {
                LWIP_GP = true
            }
        }
    )    
end

-- 璁剧疆缃戝崱鐘舵€佸彉鍖栭€氱煡鍥炶皟鍑芥暟netdrv_multiple_notify_cbfunc
exnetif.notify_status(netdrv_multiple_notify_cbfunc)

-- 濡傛灉瀛樺湪udp缃戠粶搴旂敤锛屽苟涓攗dp缃戠粶搴旂敤涓紝鏍规嵁搴旂敤灞傜殑蹇冭烦鑳藉鍒ゆ柇鍑烘潵udp鏁版嵁閫氫俊鍑虹幇浜嗗紓甯革紱
-- 鍙互鍦ㄥ垽鏂嚭鐜板紓甯哥殑浣嶇疆锛岃皟鐢ㄤ竴娆xnetif.check_network_status()鎺ュ彛锛屽己鍒跺褰撳墠姝ｅ紡浣跨敤鐨勭綉鍗¤繘琛屼竴娆¤繛閫氭€ф娴嬶紱
-- 濡傛灉瀛樺湪tcp缃戠粶搴旂敤锛屼笉闇€瑕佺敤鎴疯皟鐢╡xnetif.check_network_status()鎺ュ彛鍘绘帶鍒讹紝exnetif浼氬湪tcp缃戠粶搴旂敤閫氫俊寮傚父鏃惰嚜鍔ㄥ褰撳墠浣跨敤鐨勭綉鍗¤繘琛岃繛閫氭€ф娴嬨€?


-- 鍚姩涓€涓猼ask锛宼ask鐨勫鐞嗗嚱鏁颁负netdrv_multiple_task_func
-- 鍦ㄥ鐞嗗嚱鏁颁腑璋冪敤exnetif.set_priority_order璁剧疆缃戝崱浼樺厛绾?
-- 鍥犱负exnetif.set_priority_order瑕佹眰蹇呴』鍦╰ask涓璋冪敤锛屾墍浠ユ澶勫惎鍔ㄤ竴涓猼ask
sys.taskInit(netdrv_multiple_task_func)
