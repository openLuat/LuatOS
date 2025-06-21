
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "cryptodemo"
VERSION = "1.0.0"

-- 定义串行口及其波特率
local uart_id = 1
local uart_baud = 115200
-- 输出项目目名称及版本号
log.info("main", PROJECT, VERSION)


--初始化
--[[uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)
]]

--配置并且打开串口
uart.setup(uart_id,uart_baud,8,1)

--注册串口的数据发送通知函数
uart.on(uart_id,"receive",function() 
    log.info("uart "," uart received ")
    sys.publish("UART_RECEIVE") 
end)
--uart.on(uart_id,"sent",writeOK)

--将数据写入串行口
function write_pack(s)
    --log.info("write_pack", s )
    uart.write(uart_id,s.."\r\n")
end

-- 参数说明
-- cry_name 具体的加密方法，如md5。
-- func 具体的执行函数如 crypto.md5。
-- buff 串行口接收到的数据
function  crypto_todo( cry_name, func ,buff )
    local   cry_start,cry_end = buff:find( cry_name )
    
    if cry_start ~= nil then
    -- 取得尾部字符
        items_data = buff:sub( cry_end+1 , -1 )
        -- 为了简便起见，就不通过串行口发送密钥了，毕竟这不是一个串行口数据解析的演示
        log.info( cry_name, func( items_data ) )
        write_pack( cry_name.." <==> code [ "..func( items_data ).." ]" )
    end
end

-- 参数说明
-- cry_name 具体的加密方法，如md5。
-- func 具体的执行函数如 crypto.md5。
-- buff 串行口接收到的数据
function  crypto_todo_hmac( cry_name, func ,buff )
    local password
    local cry_start,cry_end = buff:find( "password" )
    if cry_start == nil then
        password = "1234567890"
    else
        password = buff:sub( cry_end+1 , -1 )
        buff = buff:sub( 1, cry_start-1)
        --log.info("password ",password,buff)
    end
    cry_start,cry_end = buff:find( cry_name )
   
    if cry_start ~= nil then
    -- 取得尾部字符
        items_data = buff:sub( cry_end+1 , -1 )
        -- 为了简便起见，就不通过串行口发送密钥了，毕竟这不是一个串行口数据解析的演示
        log.info( cry_name, func( items_data , password ) )
        write_pack( cry_name.." <==> password [ "..password.." ]   code [ "..func( items_data , password ).." ]\r\n" )
    end
end

function todo_cihper_ecb(name_full ,padding , items_data , password)
    log.info("-------------------------" , name_full , padding , items_data , password )

    data_encrypt = crypto.cipher_encrypt( name_full , padding , items_data , password )

    log.info("-------------------------")
    if data_encrypt ~= nil then
        write_pack( name_full.." encrypt <==> ["..padding.."] password [ "..password.." ]   code [ "..data_encrypt.." ]\r\n" )
        write_pack( name_full.." encrypt <==> ["..padding.."] password [ "..password.." ]   code_HEX [ "..data_encrypt:toHex().." ]\r\n" )
        
        data_encrypt = crypto.cipher_decrypt(name_full, padding, data_encrypt, password )
    
        write_pack( name_full.." decrypt <==> ["..padding.."] password [ "..password.." ]   code [ "..data_encrypt.." ]\r\n" )
    else
        write_pack( name_full.." encrypt <==> ["..padding.."] password [ "..password.." ]   code [ data_encrypt error ]\r\n" )
    end
end

function todo_cihper_not_ecb(name_full , padding , items_data , password , iv)
    log.info("-------------------------" , name_full ,padding , items_data , password , iv )
    data_encrypt = crypto.cipher_encrypt( name_full , padding , items_data , password , iv ) 
    log.info("-------------------------")
    
    if data_encrypt ~= nil then
        -- 输出原码与输出HEX各一组，方便比较
        write_pack( name_full.." encrypt <==> ["..padding.."] password [ "..password.." ] IV [ "..iv.." ]  code [ "..data_encrypt.." ]\r\n" )
        write_pack( name_full.." encrypt <==> ["..padding.."] password [ "..password.." ] IV [ "..iv.." ]  code_HEX [ "..data_encrypt:toHex().." ]\r\n" )
        data_encrypt = crypto.cipher_decrypt(name_full, padding, data_encrypt, password,iv) 
    
        write_pack( name_full.." decrypt <==> ["..padding.."] password [ "..password.." ]   code [ "..data_encrypt.." ]\r\n" )
    else
        write_pack( name_full.." encrypt <==> ["..padding.."] password [ "..password.." ] IV [ "..iv.." ]  code [ data_encrypt error ]\r\n" ) 
    end
end
-- AES 加密解密
-- cryname 加密名称+对齐方式+加密字符串
function  crypto_todo_cipher( cry_name , padding , buff )
    local password
    local cry_start,cry_end = buff:find( "password" )
    if cry_start == nil then
        password = ""
    else
        password = buff:sub( cry_end+1 , -1 )
        buff = buff:sub( 1,cry_start-1)
        --log.info("1 password ",password,buff)
    end

    -- 匹配查找
    cry_start,cry_end = buff:find( cry_name )  
    -- 找到加密名称
    if cry_start ~= nil then
        -- 取得加密方法名称
        local name_full = buff:sub(cry_start,cry_end)
        log.info( "<----->",name_full )
        -- 取得尾部字符
        cry_start,cry_end = buff:find( padding )
        -- 找到对齐方式
        if cry_start ~= nil then
            local data_encrypt
            local iv
            local password_len

            name_full = name_full:upper()
            padding = padding:upper()

                -- 取得加密数据
            items_data = buff:sub( cry_end+1 , -1 )

            --[[
            参数
            name_full         算法名称, 例如 AES-128-ECB/AES-128-CBC, 可查阅crypto.cipher_list()
            padding           对齐方式, 支持PKCS7/ZERO/ONE_AND_ZEROS/ZEROS_AND_LEN/NONE
            items_data        需要加密的数据
            HZBIT@WLW/YSBKEY  密钥,需要对应算法的密钥长度
            IV                非ECB算法需要]]

            cry_end = buff:find("des")
            -- 进行DES 加密 处理
            if cry_end ~= nil then
                if password == "" then
                    cry_start = buff:find( "ede3" )
                    if cry_start ~= nil  then
                        password = "123456781234567812345678"
                    else
                        password = "12345678"
                    end
                end
                cry_start,cry_end = buff:find( "ecb" )
                if cry_start ~= nil then
                    -- 应当也是有密码长度规范的，但为此处不再进行判定处理。
                    -- 如果导致出错，请注意是不是密码长度引起。
                    todo_cihper_ecb( name_full , padding , items_data , password )  
                else
                    todo_cihper_not_ecb( name_full , padding , items_data , password , "12345678")  
                end

            else
                -- 进行字符串匹配 取得开始位置及加密长度 可以是 128、192、256等值
                -- 一般来说，密钥的长度就是加密长度，比如128，就表示16个字节长度
                cry_start,cry_end,password_len = buff:find( "aes[-](%d+)[-]%a%a%a" )

                if password_len == nil then
                    password_len = "0"
                end

                --如果密码为空，则截取合适的长度字串作为密码
                if password == "" then
                    password = "abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                    password = password:sub(1, tonumber(password_len)/8 )
                end
                if  tonumber(password_len) / 8 == password:len() then
                    log.info( "-----","password ok", password , name_full , padding)
                    cry_start = buff:find( "ecd" )                    
                    if cry_start ~= nil then
                        todo_cihper_ecb( name_full , padding , items_data , password )  
                    else
                        todo_cihper_not_ecb( name_full , padding , items_data , password , "1234567890666666" )  
                    end                    
                else
                    log.info("-----","password error")
                    write_pack( "password length error ==="..password_len.."\r\n" )
                end
            end
        end
    end
end

-- 文件测试
function todo_md_file(buff)
    local password
    local cry_start,cry_end = buff:find( "password" )
    if cry_start == nil then
        password = ""
    else
        password = buff:sub( cry_end+1 , -1 )
        buff = buff:sub( 1, cry_start-1)
        log.info("md_file password ",password,buff)
    end

    log.info("文件hash值测试")
    if crypto.md_file then
        local md_file =crypto.md_file( "MD5" , "/luadb/luatos_uploadFile.txt" )
        write_pack( "md_file encrypt MD5 <==> code [ "..md_file.." ]\r\n" )
        
        md_file =crypto.md_file( "SHA1" , "/luadb/luatos_uploadFile.txt" )
        write_pack( "md_file encrypt SHA1 <==> code [ "..md_file.." ]\r\n" )
        
        md_file =crypto.md_file( "SHA256" , "/luadb/luatos_uploadFile.txt" )
        write_pack( "md_file encrypt SHA256 <==> code [ "..md_file.." ]\r\n" )
     
        md_file =crypto.md_file("MD5" , "/luadb/luatos_uploadFile.txt" , password )
        write_pack( "md_file encrypt hmac_md5 <==> password [ "..password.." ] code [ "..md_file.." ]\r\n" )

        md_file =crypto.md_file("SHA1" , "/luadb/luatos_uploadFile.txt" , password )
        write_pack( "md_file encrypt hmac_sha1 <==> password [ "..password.." ] code [ "..md_file.." ]\r\n" )

        md_file =crypto.md_file("SHA256" , "/luadb/luatos_uploadFile.txt" , password )
        write_pack( "md_file encrypt hmac_sha256 <==> password [ "..password.." ] code [ "..md_file.." ]\r\n" )
    else
        log.info("文件hash值测试", "当前固件不支持crypto.md_file")
    end
end

function todo_checksum(buff)
    local cry_start,cry_end = buff:find("checksum")
    if cry_start ~= nil then
        local cry_text = buff:sub(cry_end+1,-1)

        if crypto.checksum then
            write_pack( "checksum encrypt <==>text [ "..cry_text.." ]  code [ "..string.char(crypto.checksum( cry_text ) ):toHex().." ]\r\n" )
            write_pack( "checksum encrypt <==>text [ "..cry_text.." ]  code [ "..string.char(crypto.checksum( cry_text , 1 ) ):toHex().." ]\r\n" )
        else
            log.info("checksum", "当前固件不支持crypto.checksum")
        end
    end
end

-- 流数据校验演示
function toto_hash_init( cry_name , method , buff )
    local password
    local cry_start,cry_end = buff:find("password")
    if cry_start ~= nil then
        --  读取密码
        password = buff:sub(cry_end+1,-1)
        buff = buff:sub( 1 , cry_start-1 );
    else
        password = ""
    end
     
    -- 本过程不再对拼接后的完整数据进行校验，如果有需要，请使用单独的MD5或SHA1加密方法进行验证即可。
    -- 比如 MD5 的流校验操作，假如使用的文本是 "123456456"，则验证可通过串行口发送
    -- md5123456456123456456123456456123456456 来验证。这是因为演示就是连续操作四次发送的文本，来
    -- 模拟流操作的过程，以演示累积的加密处理方法。
    cry_start,cry_end = buff:find( cry_name..method )
    if cry_start ~= nil then
       local cry_text = buff:sub(cry_end+1,-1)
       
       log.info("md5-----", cry_text, password , method)
       if password == ""  then
            -- 转化为大写
            local md5_obj = crypto.hash_init( method:upper() )
            crypto.hash_update(md5_obj, cry_text)
            crypto.hash_update(md5_obj, cry_text)
            crypto.hash_update(md5_obj, cry_text)
            crypto.hash_update(md5_obj, cry_text)
            local md5_result = crypto.hash_finish(md5_obj)
            
            write_pack( "stream encrypt <==>name [ "..cry_name.." ] method [ "..method.." ] text [ "..cry_text.." ] result [ "..md5_result.." ]\r\n" )
            log.info("md5_stream", md5_result)
       else
            local md5_obj = crypto.hash_init( method:upper() , password )
            crypto.hash_update(md5_obj, cry_text , password )
            crypto.hash_update(md5_obj, cry_text , password )
            crypto.hash_update(md5_obj, cry_text , password )
            crypto.hash_update(md5_obj, cry_text , password )
            local md5_result = crypto.hash_finish(md5_obj)
            write_pack( "stream encrypt <==>password ["..password.."] name [ "..cry_name.." ] method [ hmac_"..method.." ] text [ "..cry_text.." ] result [ "..md5_result.." ]\r\n" )
            log.info("md5_stream", md5_result)
       end
    end
end

sys.taskInit(function()

    -- 数据接收缓冲区
    -- 使用缓冲区的目的是为了接收全部数据后再分析
    local cacheData = ""
    
    local data2_encrypt = crypto.cipher_encrypt("DES-ECB", "PKCS7", "abcdefg", "12345678")

    sys.wait(1000)
    while true do

        ::continue::
        local s = uart.read(uart_id,1024)

        if s == "" then
            if cacheData == "" then
                sys.waitUntil("UART_RECEIVE" , 500)
                goto continue
            end

            -- 定义变量
            local cry_str
            local items_data
            local cry_start,cry_end

            -- 测试一下串行口
            cry_start,cry_end = cacheData:find( "uart" )
            if cry_start ~= nil then
                write_pack( "test uart[baud=115200,8,0,1]\r\n" )
            end

            cry_start,cry_end = cacheData:find( "md_file" )
            if cry_start ~= nil then
                todo_md_file( cacheData ) 
            end

            --校验和
            todo_checksum( cacheData )

            cry_start,cry_end = cacheData:find( "list" )
            if cry_start ~= nil then
                -- 打印所有支持的cipher
                if crypto.cipher_list then
                    log.info("cipher", "list", json.encode(crypto.cipher_list()))
                    --write_pack("cipher list [ " json.encode(crypto.cipher_list()).." ]" )
                else
                    log.info("cipher", "当前固件不支持crypto.cipher_list")
                end
            end

            cry_start,cry_end = cacheData:find( "suites" )
            if cry_start ~= nil then
                -- 打印所有支持的cipher
                if crypto.cipher_list then
                    log.info("cipher", "suites", json.encode(crypto.cipher_suites()) )
                    --write_pack("cipher suites [ " json.encode(crypto.cipher_suites()).." ]" )
                else
                    log.info( "cipher", "当前固件不支持crypto.cipher_suites" )
                end
            end

            cry_start,cry_end = cacheData:find( "base64" )
            if cry_start ~= nil then
                -- 打印所有支持的cipher
                if crypto.base64_encode then
                    local in_text = cacheData:sub( cry_end + 1 , -1 );
                    local bas_text = crypto.base64_encode( in_text )

                    write_pack("cipher base64 encode data [ "..in_text.." ] code [ " .. bas_text .. " ]" )
                    write_pack("cipher base64 decode data [ "..bas_text.." ] code [ " .. crypto.base64_decode( bas_text ).." ]" )
                else
                    log.info( "cipher", "当前固件不支持 base64 " )
                end
            end

            cry_start,cry_end = cacheData:find( "base64_decode" )
            if cry_start ~= nil then
                -- 打印所有支持的cipher
                if crypto.base64_encode then
                    local in_text = cacheData:sub( cry_end + 1 , -1 );
                    local bas_text = crypto.base64_decode( in_text )
                    
                    write_pack("cipher base64 decode data [ "..in_text.." ] code [ " .. bas_text .." ]" )
                else
                    log.info( "cipher", "当前固件不支持 base64 " )
                end
            end
            -- 输出 MD5 编码
            -- 当收到 hmac_md5 时，也会执行一次 md5，因只是作一个加密演示，作为演示
            -- 不想做过于复杂的逻辑判断，因而就让其输出吧，关系也不大。
            -- 下面遇到类似情况就不再作说明了，请知悉！
            crypto_todo("md5" , crypto.md5 , cacheData )
   
            -- 输出hmac_md5
            crypto_todo_hmac("hmac_md5" , crypto.hmac_md5 , cacheData )

            -- 输出 sha1 编码
            crypto_todo("sha1" , crypto.sha1 , cacheData )

            -- 输出 hmac_sha1 编码
            crypto_todo_hmac("hmac_sha1" , crypto.hmac_sha1 , cacheData )

            -- 输出sha256
            crypto_todo("sha256" , crypto.sha256 , cacheData )

            -- 输出hmac_sha256
            crypto_todo_hmac("hmac_sha256" , crypto.hmac_sha256 , cacheData )

            -- 输出sha512
            crypto_todo("sha512" , crypto.sha512 , cacheData )

            -- 输出hmac_sha512
            crypto_todo_hmac("hmac_sha512" , crypto.hmac_sha512 , cacheData )

            toto_hash_init("hash_init" , "md5" , cacheData )
            toto_hash_init("hash_init" , "sha1" , cacheData )
            toto_hash_init("hash_init" , "sha256" , cacheData )
            toto_hash_init("hash_init" , "sha512" , cacheData )

            -- 对称加密算法
            crypto_todo_cipher( "aes[-](%d+)[-]ecb", "zero",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]cbc", "zero",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ctr", "zero",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]xts", "zero",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]gcm", "zero",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ccm", "zero",cacheData)

            crypto_todo_cipher( "aes[-](%d+)[-]ecb", "pkcs7",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]cbc", "pkcs7",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ctr", "pkcs7",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]xts", "pkcs7",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]gcm", "pkcs7",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ccm", "pkcs7",cacheData)

            crypto_todo_cipher( "aes[-](%d+)[-]ecb", "one_and_zeros",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]cbc", "one_and_zeros",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ctr", "one_and_zeros",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]xts", "one_and_zeros",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]gcm", "one_and_zeros",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ccm", "one_and_zeros",cacheData)
                        
            crypto_todo_cipher( "aes[-](%d+)[-]ecb", "zeros_and_len",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]cbc", "zeros_and_len",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ctr", "zeros_and_len",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]xts", "zeros_and_len",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]gcm", "zeros_and_len",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ccm", "zeros_and_len",cacheData)

            crypto_todo_cipher( "aes[-](%d+)[-]ecb", "none",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]cbc", "none",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ctr", "none",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]xts", "none",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]gcm", "none",cacheData)
            crypto_todo_cipher( "aes[-](%d+)[-]ccm", "none",cacheData)

            crypto_todo_cipher( "des[-]ecb" , "pkcs7", cacheData )
            crypto_todo_cipher( "des[-]ede[-]ecb" , "pkcs7", cacheData )
            crypto_todo_cipher( "des[-]ede3[-]ecb" , "pkcs7", cacheData )
            crypto_todo_cipher( "des[-]cbc" , "pkcs7", cacheData )
            crypto_todo_cipher( "des[-]ede[-]cbc" , "pkcs7", cacheData )
            crypto_todo_cipher( "des[-]ede3[-]cbc" , "pkcs7", cacheData )

            crypto_todo_cipher( "des[-]ecb" , "zero", cacheData )
            crypto_todo_cipher( "des[-]ede[-]ecb" , "zero", cacheData )
            crypto_todo_cipher( "des[-]ede3[-]ecb" , "zero", cacheData )
            crypto_todo_cipher( "des[-]cbc" , "zero", cacheData )
            crypto_todo_cipher( "des[-]ede[-]cbc" , "zero", cacheData )
            crypto_todo_cipher( "des[-]ede3[-]cbc" , "zero", cacheData )

            -- 处理完成后清空缓冲区

            log.info("cacheData ",cacheData )
            cacheData = ""
        else
            cacheData = cacheData..s
        end 
    end

    --[[
    log.info("随机数测试")
    for i=1, 10 do
        sys.wait(100)
        log.info("crypto", "真随机数",string.unpack("I",crypto.trng(4)))
        -- log.info("crypto", "伪随机数",math.random()) -- 输出的是浮点数,不推荐
        -- log.info("crypto", "伪随机数",math.random(1, 65525)) -- 不推荐
    end

    -- totp的密钥
    log.info("totp的密钥")
    local secret = "VK54ZXPO74ISEM2E"
    --写死时间戳用来测试
    local ts = 1646796576
    --生成十分钟的动态码验证下
    for i=1,600,30 do
        local r = crypto.totp(secret,ts+i)
        local time = os.date("*t",ts+i + 8*3600)--东八区
        log.info("totp", string.format("%06d" ,r),time.hour,time.min,time.sec)
    end

    log.info("crc7测试")
    if crypto.crc7 then
        local result = crypto.crc7(string.char(0xAA), 0xE5, 0x00)
        log.info("crc7测试", result, string.format("%02X", result))
    else
        log.info("crypto", "当前固件不支持crypto.crc7")
    end

    log.info("crypto", "ALL Done")
   --]]
   sys.wait(100000)
   
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
