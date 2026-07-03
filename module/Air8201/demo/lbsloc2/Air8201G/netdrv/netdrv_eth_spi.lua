--[[
@module  netdrv_eth_spi
@summary 鈥滈€氳繃SPI澶栨寕CH390H鑺墖鐨勪互澶綉鍗♀€濋┍鍔ㄦā鍧?
@version 1.0
@date    2025.07.24
@author  椹ⅵ闃?
@usage
鏈枃浠朵负鈥滈€氳繃SPI澶栨寕CH390H鑺墖鐨勪互澶綉鍗♀€濋┍鍔ㄦā鍧楋紝鏍稿績涓氬姟閫昏緫涓猴細
1銆侀粯璁ゅ紑鍚疉irETH_1000閰嶄欢鏉夸緵鐢靛紑鍏筹紱
2銆佸垵濮嬪寲spi0锛屽垵濮嬪寲浠ュお缃戝崱锛屽苟涓斿湪浠ュお缃戝崱涓婂紑鍚疍HCP(鍔ㄦ€佷富鏈洪厤缃崗璁?锛?
3銆佷互澶綉鍗＄殑杩炴帴鐘舵€佸彂鐢熷彉鍖栨椂锛屽湪鏃ュ織涓繘琛屾墦鍗帮紱

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

鏈枃浠舵病鏈夊澶栨帴鍙ｏ紝鐩存帴鍦ㄥ叾浠栧姛鑳芥ā鍧椾腑require "netdrv_eth_spi"灏卞彲浠ュ姞杞借繍琛岋紱
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)    
    if adapter == socket.LWIP_ETH then
        -- 鍦ㄤ綅缃?鍜?璁剧疆鑷畾涔夌殑DNS鏈嶅姟鍣╥p鍦板潃锛?
        -- "223.5.5.5"锛岃繖涓狣NS鏈嶅姟鍣↖P鍦板潃鏄樋閲屼簯鎻愪緵鐨凞NS鏈嶅姟鍣↖P鍦板潃锛?
        -- "114.114.114.114"锛岃繖涓狣NS鏈嶅姟鍣↖P鍦板潃鏄浗鍐呴€氱敤鐨凞NS鏈嶅姟鍣↖P鍦板潃锛?
        -- 鍙互鍔犱笂浠ヤ笅涓よ浠ｇ爜锛屽湪鑷姩鑾峰彇鐨凞NS鏈嶅姟鍣ㄥ伐浣滀笉绋冲畾鐨勬儏鍐典笅锛岃繖涓や釜鏂板鐨凞NS鏈嶅姟鍣ㄤ細浣緿NS鏈嶅姟鏇村姞绋冲畾鍙潬锛?
        -- 濡傛灉浣跨敤涓撶綉鍗★紝涓嶈浣跨敤杩欎袱琛屼唬鐮侊紱
        -- 濡傛灉浣跨敤鍥藉鐨勭綉缁滐紝涓嶈浣跨敤杩欎袱琛屼唬鐮侊紱
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_eth_spi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_ETH))
    end
end

local function ip_lose_func(adapter)    
    if adapter == socket.LWIP_ETH then
        log.warn("netdrv_eth_spi.ip_lose_func", "IP_LOSE")
    end
end


-- 浠ュお缃戣仈缃戞垚鍔燂紙鎴愬姛杩炴帴璺敱鍣紝骞朵笖鑾峰彇鍒颁簡IP鍦板潃锛夊悗锛屽唴鏍稿浐浠朵細浜х敓涓€涓?IP_READY"娑堟伅
-- 鍚勪釜鍔熻兘妯″潡鍙互璁㈤槄"IP_READY"娑堟伅瀹炴椂澶勭悊浠ュお缃戣仈缃戞垚鍔熺殑浜嬩欢
-- 涔熷彲浠ュ湪浠讳綍鏃跺埢璋冪敤socket.adapter(socket.LWIP_ETH)鏉ヨ幏鍙栦互澶綉鏄惁杩炴帴鎴愬姛

-- 浠ュお缃戞柇缃戝悗锛屽唴鏍稿浐浠朵細浜х敓涓€涓?IP_LOSE"娑堟伅
-- 鍚勪釜鍔熻兘妯″潡鍙互璁㈤槄"IP_LOSE"娑堟伅瀹炴椂澶勭悊浠ュお缃戞柇缃戠殑浜嬩欢
-- 涔熷彲浠ュ湪浠讳綍鏃跺埢璋冪敤socket.adapter(socket.LWIP_ETH)鏉ヨ幏鍙栦互澶綉鏄惁杩炴帴鎴愬姛

--姝ゅ璁㈤槄"IP_READY"鍜?IP_LOSE"涓ょ娑堟伅
--鍦ㄦ秷鎭殑澶勭悊鍑芥暟涓紝浠呬粎鎵撳嵃浜嗕竴浜涗俊鎭紝渚夸簬瀹炴椂瑙傚療鈥滈€氳繃SPI澶栨寕CH390H鑺墖鐨勪互澶綉鍗♀€濈殑杩炴帴鐘舵€?
--涔熷彲浠ユ牴鎹嚜宸辩殑椤圭洰闇€姹傦紝鍦ㄦ秷鎭鐞嗗嚱鏁颁腑澧炲姞鑷繁鐨勪笟鍔￠€昏緫鎺у埗锛屼緥濡傚彲浠ュ湪杩炵綉鐘舵€佸彂鐢熸敼鍙樻椂鏇存柊缃戠粶鍥炬爣
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


local function netdrv_eth_spi_task_func()
-- 閰嶇疆SPI澶栨帴浠ュお缃戣姱鐗嘋H390H鐨勫崟缃戝崱锛宔xnetif.set_priority_order浣跨敤鐨勭綉鍗＄紪鍙蜂负socket.LWIP_ETH
-- 鏈琩emo浣跨敤Air780EHM/EHV/EGH鏍稿績鏉?AirETH_1000閰嶄欢鏉挎祴璇曪紝鏍稿績鏉夸笂鐨勭‖浠堕厤缃负锛?
-- 鏍稿績鏉跨殑VDD 3V3绠¤剼瀵笰irETH_1000閰嶄欢鏉胯繘琛屼緵鐢碉紱3V3绠¤剼鏄綔涓篖DO 3.3V杈撳嚭锛屼緵娴嬭瘯鐢ㄧ殑锛屼粎鍦ㄤ娇鐢―CDC渚涚數鏃舵湁杈撳嚭锛岄粯璁ゆ墦寮€锛屾棤闇€鎺у埗
-- 浣跨敤spi0锛岀墖閫夊紩鑴氫娇鐢℅PIO8
-- 濡傛灉浣跨敤鐨勭‖浠跺拰浠ヤ笂鎻忚堪鐨勭幆澧冧笉鍚岋紝鏍规嵁鑷繁鐨勭‖浠堕厤缃慨鏀逛互涓嬪弬鏁?
-- INT涓柇寮曡剼锛屼娇鐢ㄤ腑鏂ā寮忔彁楂樺搷搴旈€熷害锛屾鍙傛暟涓哄彲閫夊弬鏁帮紝鑻ヤ笉濉粯璁や笉浣跨敤涓柇妯″紡鑰屾槸浣跨敤杞妯″紡
    exnetif.set_priority_order({
        {
            ETHERNET = {
                pwrpin = nil,
                tp = netdrv.CH390,
                opts = {spi = 0, cs = 8,irq = 1}
            }
        }
    })
end

-- 鍚姩涓€涓猼ask锛宼ask鐨勫鐞嗗嚱鏁颁负netdrv_eth_spi_task_func
-- 鍦ㄥ鐞嗗嚱鏁颁腑璋冪敤exnetif.set_priority_order璁剧疆缃戝崱浼樺厛绾?
-- 鍥犱负exnetif.set_priority_order瑕佹眰蹇呴』鍦╰ask涓璋冪敤锛屾墍浠ユ澶勫惎鍔ㄤ竴涓猼ask
sys.taskInit(netdrv_eth_spi_task_func)