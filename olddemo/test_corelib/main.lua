
PROJECT = "test"
VERSION = "1.0.0"

log.style(1)

log.info("main", PROJECT, VERSION)

local coreall = {
"adc",
"audio",
"bit64",
"camera",
"can",
"cc",
"codec",
"crypto",
"dac",
"eink",
"ercoap",
"errDump",
"fastlz",
"fatfs",
"fonts",
"fota",
"fs",
"fskv",
"ftp",
"gmssl",
"gpio",
"gtfont",
"hmeta",
"ht1621",
"http",
"httpsrv",
"i2c",
"i2s",
"iconv",
"io",
"ioqueue",
"iotauth",
"iperf",
"ir",
"json",
"keyboard",
"lcd",
"lcdseg",
"libcoap",
"libgnss",
"little_flash",
"log",
"lora",
"lora2",
"lvgl",
"max30102",
"mcu",
"miniz",
"mlx90640",
"mobile",
"mqtt",
"nes",
"netdrv",
"onewire",
"os",
"otp",
"pack",
"pm",
"protobuf",
"pwm",
"repl",
"rsa",
"rtc",
"rtos",
"sdio",
"sfd",
"sfud",
"sms",
"socket",
"softkb",
"spi",
"statem",
"string",
"sys",
"sysplus",
"timer",
"tp",
"u8g2",
"uart",
"w5500",
"wdt",
"websocket",
"wlan",
"xxtea",
"yhm27xx",
"ymodem",
"zbuff"
}

local moduleall = {}

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function contains(arr, val)
  for _, v in ipairs(arr) do
    if v == val then
      return true
    end
  end
  return false
end

local function getmoduleall()
  local s1
  for k, v in pairs(_G) do
    s1 = trim(k)
    table.insert(moduleall,s1)
  end
end

local function getcorelist()
  local s1,s3
  local bn = 0
  for _, s1 in ipairs(coreall) do
    bn = 16 - #s1
    s3 = s1 .. string.rep(" ", bn)
    if contains(moduleall, s1) then
      s3 = s3 .. "YES"
    else
      s3 = s3 .. "NOT"
    end
    log.info(s3)
  end
end

local function task1()
  log.info("task1 ")
  local sid = 0
  sys.wait(1000)
  while true do
    if sid == 0 then
      getmoduleall()
    elseif sid == 1 then
      getcorelist()
    end

    sid = sid + 1
    log.info("sid: ", sid)

    if sid < 3 then
      sys.wait(1000)
    else
      sys.wait(100000)
    end
  end
end

sysplus.taskInitEx(task1, "corelib")

sys.run()


