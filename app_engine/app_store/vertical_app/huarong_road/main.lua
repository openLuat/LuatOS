PROJECT = "HUARONG_ROAD"
VERSION = "1.0.0"


log.info("main", PROJECT, VERSION)

require "game_huarong_win"

sys.publish("OPEN_GAME_HUARONG_WIN")

sys.run()