PROJECT = "OTHELLO_ONLINE"
VERSION = "1.0.0"


log.info("main", PROJECT, VERSION)

require "auto_play"
require "game_othello_online_win"
require "othello_online"

-- 默认打开联网对战主菜单
sys.publish("OPEN_OTHELLO_ONLINE")

sys.run()