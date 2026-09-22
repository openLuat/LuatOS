/* assets/js/config.js —— 由 index.html 内联脚本拆出（原行区间 3027-3094），内容未改动 */
/* =========================================================
   App.config —— 公开常量、真实接口表、appId、应用 base path
   ========================================================= */
window.App = window.App || {};
App.config = (function(){
  var SDK = window.LuatSDK;
  var path = window.location.pathname;
  var slash = path.lastIndexOf('/');
  var basePath = (slash >= 0) ? path.slice(0, slash + 1) : '/';
  var m = path.match(/\/ai_app\/luatos\/([^\/?#]+)/i);
  var APP_ID_FALLBACK = '';
  var appId = (m && m[1]) ? m[1] : APP_ID_FALLBACK;
  return {
    APP_ID: appId,
    BASE_PATH: basePath,
    API_HOST: SDK.config.API_HOST,
    BASE_HOST: SDK.config.BASE_HOST,
    API_BASE: SDK.config.API_BASE,
    OAUTH_AUTHORIZE_URL: SDK.config.OAUTH_AUTHORIZE_URL,
    OAUTH_LOGIN_URL: SDK.config.OAUTH_LOGIN_URL,
    PAGE: document.body.getAttribute('data-page') || '',
    AUTH: document.body.getAttribute('data-auth') || 'public',
    API: {
      PROJECTS: '/open_api/list_my_projects',
      SEARCH_DEVICES: '/open_api/search_my_devices',
      LIST_BY_TAGS: '/open_api/aircloud/list_by_tags',
      LATEST_LOCATION: '/open_api/aircloud/latest_location',
      SEND_CMD: '/open_api/aircloud/send_cmd',
      /* 告警通知的「服务端中继」（可选；留空 = 浏览器直连渠道 Webhook）
         —— 留空：浏览器直接 POST 钉钉/飞书/企微 Webhook，受跨域限制读不到渠道回执，
                  只能确认「已提交」，且必须页面开着才会推送；
         —— 填写后：由服务端转发，可拿到真实回执，也能做到页面关着也推送。
         中继契约：POST { channel, url, secret, payload } → { ok:true } 或 { code:0 } 表示成功 */
      NOTIFY_RELAY: ''
    },
    TAGS: {
      /* 与设备端 protocol_app.lua 的字段表严格一致：
         19=控制命令(下行) 20=控制回应(上行) 25=运维日志上传请求(下行)
         265=工作状态 799=实际电压 800=设定电压 783=SIM卡ICCID
         798=设备号(IMEI) 1027=固件版本号 512=经度 513=纬度
         781=联网方式（1=4G / 2=WiFi / 3=以太网）
         782=信号强度（统一 0~31 刻度：4G=CSQ 原值，99=无信号/不可测；
                        WiFi=RSSI 折算：≥-50→31、≤-100→0、中间按比例）
         注意：781/782 是设备端新增字段，随周期上报纸文一起发（不是单独报文）；
              老固件不上报 → 界面显示「未上报」，绝不把缺失数据伪装成 0 */
      WORK_STATUS: 265, VOLTAGE: 799, SET_VOLTAGE: 800, ICCID: 783,
      DEVICE_ID: 798, VERSION: 1027, REPORT_TIME: 1280,
      LNG: 512, LAT: 513,
      NETWORK_TYPE: 781, SIGNAL: 782,
      CTRL_CMD: 19, CTRL_RESP: 20, MTN_LOG_REQ: 25
    },
    TAG_META: {
      19: { name: '控制命令', type: '嵌套TLV', cat: '控制信令（下行）' },
      20: { name: '控制回应', type: '嵌套TLV', cat: '控制信令（上行）' },
      25: { name: '运维日志上传请求', type: '字节', cat: '控制信令（下行）' },
      265: { name: '工作状态', type: '整数', cat: '传感数据（1开机/0关机/255未同步）' },
      512: { name: '经度', type: 'ASCII', cat: '定位数据（基站定位LBS）' },
      513: { name: '纬度', type: 'ASCII', cat: '定位数据（基站定位LBS）' },
      781: { name: '联网方式', type: '整数', cat: '网络数据（1=4G/2=WiFi/3=以太网）' },
      782: { name: '信号强度', type: '整数', cat: '网络数据（统一0~31；4G=CSQ，99=无信号）' },
      783: { name: 'ICCID', type: '整数', cat: '设备参数' },
      798: { name: '设备号（IMEI）', type: '整数', cat: '设备参数' },
      799: { name: '实际电压', type: '整数', cat: '传感数据（V）' },
      800: { name: '设定电压', type: '整数', cat: '设备参数（V）' },
      1027: { name: '固件版本号', type: 'ASCII', cat: '软件数据' }
    },
    BIZ: {
      VOLTAGE_MIN: 0, VOLTAGE_MAX: 6000, VOLTAGE_STEP: 100,
      DEFAULT_SET_VOLTAGE: 3500, ONLINE_WINDOW_MS: 300000,
      CONTROL_TAG: 19, DEVICE_MODEL: 'Air8301 · 电场发生器通讯控制板',
      /* Tag 781 取值 → 文案（0/缺省=老固件未上报，不编造） */
      NET_TYPE_TEXT: { 1: '4G', 2: 'WiFi', 3: '以太网' }
    },
    /* 上报类 Tag：周期 60s 一次；此外设备在电压等发生变化时会即时上报（excloud trigger_report），
   所以前端可以按秒跟进最新一条（实际电压 / 工作状态 / 设定电压 / 联网方式 / 信号强度）
       —— 781/782 必须并进这一次查询：平台限频规则是"查询频率 ≈ 设备上报频率"，
          单独为它们再查一次会被直接拒绝（实测：请求过于频繁） */
    /* 周期 Tag：实际电压 / 工作状态 / 设定电压 / 联网方式 / 信号强度，
     外加设备上报的经纬度（512/513）——它们在同一条周期报文里（仅定位有效时追加），
     并进来不增加请求，却能避免"位置只靠 latest_location、一被限频就停在旧值" */
  DEVICE_TAGS: [799, 265, 800, 781, 782, 512, 513],
    /* 设备信息 Tag（鉴权成功后开机上报一次）：设备号 IMEI / ICCID / 固件版本
       —— 它们不在周期报文里，必须单独按较长时间窗查询，否则永远取不到 */
    INFO_TAGS: [798, 783, 1027]
  };
})();

