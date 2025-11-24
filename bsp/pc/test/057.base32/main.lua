LOG_TAG = "test"
function tc0203_str_ext_base64_base32_illegal_param()
    -- Base64/Base32解码测试自动补全填充符'='
    -- 不支持补全填充符？不检查长度？
    local encoded = "SGVsbG8"  -- 缺少填充符
    local decoded = string.fromBase64(encoded)
    log.info(LOG_TAG,"decoded:", decoded)
    --assert(decoded == "Hel", "Base64 decode fail")

    encoded = "JR2WC5DPOM"  -- 缺少填充符
    decoded = string.fromBase32(encoded)
    log.info(LOG_TAG,"decoded:", decoded)
    --assert(decoded == "Luatos", "Base32 decode fail")

    -- Base64/Base32解码测试异常字符参数
    encoded = "SGsb*G8!"  -- 非法字符
    decoded = string.fromBase64(encoded)
    log.info(LOG_TAG,"decoded:", decoded)
    -- 解码失败应该返回空字符串
    --assert(decoded == "", "Base64 igllegal param")

    encoded = "JR2W*08C5DP!"  -- 非法字符 
    decoded = string.fromBase32(encoded)  -- 这里会出错
    log.info(LOG_TAG,"decoded:", decoded)
    -- 解码失败应该返回空字符串
    --assert(decoded == "", "Base32 igllegal param")
end

function tc0110_str_ext_split()
    local text = "/hello,///world,**/luatos//2025*/"
    -- 默认分隔符',',不保留空白片段
    local table1 = string.split(text) --第二三参数可不填，默认值
    log.info(LOG_TAG, #table1, table1[1], table1[2], table1[3])
    --assert(table1[1] == "/hello" and table1[2] == "///world" and table1[3] == "**/luatos//2025*/")

    -- 分隔符'/',保留空白片段,字符串中有连续的分隔符视为分隔两个空字符串,开始和结束有分隔符则分别都有空字符串
    local table2 = string.split(text,'/', true)
    log.info(LOG_TAG, #table2, json.encode(table2))
    --assert(table2[1] == "" and table2[2] == "hello," and table2[3] == ""
            --and table2[4] == "" and table2[5] == "world,**"
            --and table2[6] == "luatos" and table2[7] == ""
            --and table2[8] == "2025*" and table2[9] == "")

    -- 分隔符'*',保留空白片段,采用':'调用函数，text当作第一个实参传递给函数，等同string.split(text)
    local table3 = text:split('*', true)
    log.info(LOG_TAG, #table3, json.encode(table3))
    --assert(table3[1] == "/hello,///world," and table3[2] == "" and table3[3] == "/luatos//2025" and table3[4] == "/")
    
    -- 分隔符'o', 不保留空白片段
    local table4 = text:split('o')
    log.info(LOG_TAG, #table4, json.encode(table4))
    --assert(table4[1] == "/hell" and table4[2] == ",///w" and table4[3] == "rld,**/luat" and table4[4] == "s//2025*/")
end

tc0203_str_ext_base64_base32_illegal_param()
tc0110_str_ext_split()
