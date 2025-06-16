-- main.lua文件

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fs_demo"
VERSION = "1.0.0"

log.info("---------------------文件创建---------------")  
local ret, errio = io.mkdir("/data/")
if ret then       
       log.info("文件夹创建成功")  
   else    
       log.error("文件夹创建失败")  
end
--[[
-- 方法1：使用io.open创建空文件（如果文件已存在，则覆盖）  
local fd = io.open("/newfile.txt", "w")  
if fd then
  -- 文件已成功创建（或覆盖），此时文件为空    
  fd:close()   
    log.info("文件创建成功（空文件）")  
else  
   log.error("文件创建失败")  
end  
]]
-- 方法2：通过写入内容创建文件  

log.info("---------------------文件创建---------------")  

local content = "这是文件的内容"  
local fd = io.open("/data/newfile_with_content.txt", "w")  
if fd then    
fd:write(content)   
fd:close()    
    log.info("文件创建成功并写入内容")  
else    
    log.error("文件创建失败")  
end


log.info("-------------------文件追加---------------")  
-- 打开文件以追加模式  
local fd = io.open("/data/newfile_with_content.txt", "rb")  
if fd then    -- 写入内容   
 local data_old = fd:read("*a")  
 log.info("文件创建初始内容：",data_old)  
 -- 关闭文件   
 fd:close() 
 local fd1 = io.open("/data/newfile_with_content.txt", "a")  
 fd1:write("我是追加的内容\n")    
 -- 关闭文件   
 fd1:close() 
 local fd2 = io.open("/data/newfile_with_content.txt", "rb") 
 local data_new = fd2:read("*a")  
 log.info("文件追加之后的内容：",data_new)  
 -- 关闭文件   
 fd2:close() 
end


log.info("----------------命名文件---------------")  
-- 重命名文件  
local success, err = os.rename("/data/newfile_with_content.txt", "/data/newname.txt")  
if success then    
log.info("文件重命名成功")  
else   
 log.error("文件重命名失败：" .. err)  
end

log.info("----------------文件拷贝---------------")  
---文件拷贝
-- 读取源文件内容  
local fd_src = io.open("/data/newname.txt", "rb")  
if fd_src then   
    local content = fd_src:read("*a")  
    fd_src:close()  
    -- 写入目标文件  
   local fd_dest = io.open("/data/destination.txt", "wb")   
    if fd_dest then       
       fd_dest:write(content)       
       fd_dest:close()       
       log.info("文件拷贝成功")   
   else       
       log.error("无法打开目标文件")  
   end  
else   
  log.error("无法打开源文件")  
end

log.info("----------------移动文件---------------")  
local ret, errio = io.mkdir("/destination/")
if ret then       
       log.info("文件夹创建成功")  
   else    
       log.error("文件夹创建失败")  
end
-- 移动文件：重命名（适用于同一文件系统）  
local success, err = os.rename("/data/newname.txt", "/destination/source.txt")  
if success then   
   log.info("文件移动成功（重命名）")  
else   
 log.error("文件移动失败（重命名）：" .. err)  
end  

-- 获取文件大小  
local size = io.fileSize("/data/newname.txt")  
if size then   
 log.info("文件大小：" .. size .. " 字节")  
else   
 log.error("无法获取文件大小")  
end


-- 列出目录下的文件  

local ret, data = io.lsdir("/data/",10,0)  
if ret then
   log.info("fs", "lsdir", json.encode(data))
 else
   log.info("fs", "lsdir", "fail", ret, data)
 end

-- 删除文件  
local success, err = os.remove("/destination/source.txt")  
if success then   
   log.info("文件删除成功")  
else   
   log.error("文件删除失败：" .. err)  
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
