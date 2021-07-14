local symbol = {}

_G.LV_SYMBOL_AUDIO           =    "\xef\x80\x81"-- 61441, 0xF001
_G.LV_SYMBOL_VIDEO           =    "\xef\x80\x88"-- 61448, 0xF008
_G.LV_SYMBOL_LIST            =    "\xef\x80\x8b"-- 61451, 0xF00B
_G.LV_SYMBOL_OK              =    "\xef\x80\x8c"-- 61452, 0xF00C
_G.LV_SYMBOL_CLOSE           =    "\xef\x80\x8d"-- 61453, 0xF00D
_G.LV_SYMBOL_POWER           =    "\xef\x80\x91"-- 61457, 0xF011
_G.LV_SYMBOL_SETTINGS        =    "\xef\x80\x93"-- 61459, 0xF013
_G.LV_SYMBOL_HOME            =    "\xef\x80\x95"-- 61461, 0xF015
_G.LV_SYMBOL_DOWNLOAD        =    "\xef\x80\x99"-- 61465, 0xF019
_G.LV_SYMBOL_DRIVE           =    "\xef\x80\x9c"-- 61468, 0xF01C
_G.LV_SYMBOL_REFRESH         =    "\xef\x80\xa1"-- 61473, 0xF021
_G.LV_SYMBOL_MUTE            =    "\xef\x80\xa6"-- 61478, 0xF026
_G.LV_SYMBOL_VOLUME_MID      =    "\xef\x80\xa7"-- 61479, 0xF027
_G.LV_SYMBOL_VOLUME_MAX      =    "\xef\x80\xa8"-- 61480, 0xF028
_G.LV_SYMBOL_IMAGE           =    "\xef\x80\xbe"-- 61502, 0xF03E
_G.LV_SYMBOL_EDIT            =    "\xef\x8C\x84"-- 62212, 0xF304
_G.LV_SYMBOL_PREV            =    "\xef\x81\x88"-- 61512, 0xF048
_G.LV_SYMBOL_PLAY            =    "\xef\x81\x8b"-- 61515, 0xF04B
_G.LV_SYMBOL_PAUSE           =    "\xef\x81\x8c"-- 61516, 0xF04C
_G.LV_SYMBOL_STOP            =    "\xef\x81\x8d"-- 61517, 0xF04D
_G.LV_SYMBOL_NEXT            =    "\xef\x81\x91"-- 61521, 0xF051
_G.LV_SYMBOL_EJECT           =    "\xef\x81\x92"-- 61522, 0xF052
_G.LV_SYMBOL_LEFT            =    "\xef\x81\x93"-- 61523, 0xF053
_G.LV_SYMBOL_RIGHT           =    "\xef\x81\x94"-- 61524, 0xF054
_G.LV_SYMBOL_PLUS            =    "\xef\x81\xa7"-- 61543, 0xF067
_G.LV_SYMBOL_MINUS           =    "\xef\x81\xa8"-- 61544, 0xF068
_G.LV_SYMBOL_EYE_OPEN        =    "\xef\x81\xae"-- 61550, 0xF06E
_G.LV_SYMBOL_EYE_CLOSE       =    "\xef\x81\xb0"-- 61552, 0xF070
_G.LV_SYMBOL_WARNING         =    "\xef\x81\xb1"-- 61553, 0xF071
_G.LV_SYMBOL_SHUFFLE         =    "\xef\x81\xb4"-- 61556, 0xF074
_G.LV_SYMBOL_UP              =    "\xef\x81\xb7"-- 61559, 0xF077
_G.LV_SYMBOL_DOWN            =    "\xef\x81\xb8"-- 61560, 0xF078
_G.LV_SYMBOL_LOOP            =    "\xef\x81\xb9"-- 61561, 0xF079
_G.LV_SYMBOL_DIRECTORY       =    "\xef\x81\xbb"-- 61563, 0xF07B
_G.LV_SYMBOL_UPLOAD          =    "\xef\x82\x93"-- 61587, 0xF093
_G.LV_SYMBOL_CALL            =    "\xef\x82\x95"-- 61589, 0xF095
_G.LV_SYMBOL_CUT             =    "\xef\x83\x84"-- 61636, 0xF0C4
_G.LV_SYMBOL_COPY            =    "\xef\x83\x85"-- 61637, 0xF0C5
_G.LV_SYMBOL_SAVE            =    "\xef\x83\x87"-- 61639, 0xF0C7
_G.LV_SYMBOL_CHARGE          =    "\xef\x83\xa7"-- 61671, 0xF0E7
_G.LV_SYMBOL_PASTE           =    "\xef\x83\xAA"-- 61674, 0xF0EA
_G.LV_SYMBOL_BELL            =    "\xef\x83\xb3"-- 61683, 0xF0F3
_G.LV_SYMBOL_KEYBOARD        =    "\xef\x84\x9c"-- 61724, 0xF11C
_G.LV_SYMBOL_GPS             =    "\xef\x84\xa4"-- 61732, 0xF124
_G.LV_SYMBOL_FILE            =    "\xef\x85\x9b"-- 61787, 0xF158
_G.LV_SYMBOL_WIFI            =    "\xef\x87\xab"-- 61931, 0xF1EB
_G.LV_SYMBOL_BATTERY_FULL    =    "\xef\x89\x80"-- 62016, 0xF240
_G.LV_SYMBOL_BATTERY_3       =    "\xef\x89\x81"-- 62017, 0xF241
_G.LV_SYMBOL_BATTERY_2       =    "\xef\x89\x82"-- 62018, 0xF242
_G.LV_SYMBOL_BATTERY_1       =    "\xef\x89\x83"-- 62019, 0xF243
_G.LV_SYMBOL_BATTERY_EMPTY   =    "\xef\x89\x84"-- 62020, 0xF244
_G.LV_SYMBOL_USB             =    "\xef\x8a\x87"-- 62087, 0xF287
_G.LV_SYMBOL_BLUETOOTH       =    "\xef\x8a\x93"-- 62099, 0xF293
_G.LV_SYMBOL_TRASH           =    "\xef\x8B\xAD"-- 62189, 0xF2ED
_G.LV_SYMBOL_BACKSPACE       =    "\xef\x95\x9A"-- 62810, 0xF55A
_G.LV_SYMBOL_SD_CARD         =    "\xef\x9F\x82"-- 63426, 0xF7C2
_G.LV_SYMBOL_NEW_LINE        =    "\xef\xA2\xA2"-- 63650, 0xF8A2
_G.LV_SYMBOL_DUMMY           =    "\xEF\xA3\xBF"--
_G.LV_SYMBOL_BULLET          =    "\xE2\x80\xA2"-- 20042, 0x2022

return symbol





