-- MIC-only Air1103 parser. Resynchronize without discarding later valid frames.
local M={}
function M.new(callback)
    local buffer=""
    local s={frames=0,discarded=0,checksum_errors=0}
    local parser={}
    function parser.reset() buffer="" end
    function parser.stats()
        return {frames=s.frames,discarded=s.discarded,checksum_errors=s.checksum_errors,pending=#buffer}
    end
    function parser.feed(data)
        -- Chunk processing bounds the retained buffer even for a noisy UART.
        for offset=1,#data,1024 do
            buffer=buffer..data:sub(offset,offset+1023)
            while #buffer>=2 do
                local pos=buffer:find("\x55\xAA",1,true)
                if not pos then
                    local keep=buffer:sub(-1)=="\x55" and 1 or 0
                    s.discarded=s.discarded+#buffer-keep
                    buffer=keep==1 and "\x55" or ""
                    break
                end
                if pos>1 then s.discarded=s.discarded+pos-1;buffer=buffer:sub(pos) end
                if #buffer<6 then break end
                -- MIC frames have exactly 512 PCM bytes and command 20 80.
                if buffer:sub(3,6)~="\x02\x00\x20\x80" then
                    s.discarded=s.discarded+1;buffer=buffer:sub(2)
                elseif #buffer<519 then break
                else
                    -- 和校验 1..518：原逐字节 buffer:byte(i) 是 518 次 C 边界调用，
                    -- 上行 64 帧/秒 = 3.3 万次/秒，工厂固件任务多时会把 CPU 占满导致
                    -- 播放/回放卡顿。改 4 字节分块累加（129 组 + 末 2 字节），
                    -- 与 air1103.frame_sum 同思路，C 调用降到 130 次。
                    local sum=0
                    for i=1,513,4 do
                        local a,b,c,d=buffer:byte(i,i+3)
                        sum=sum+a+b+c+d
                    end
                    local a,b=buffer:byte(517,518)
                    sum=(sum+a+b)%256
                    if sum==buffer:byte(519) then
                        local pcm=buffer:sub(7,518)
                        buffer=buffer:sub(520);s.frames=s.frames+1
                        callback(pcm)
                    else
                        s.checksum_errors=s.checksum_errors+1
                        s.discarded=s.discarded+1;buffer=buffer:sub(2)
                    end
                end
            end
        end
    end
    return parser
end
return M
