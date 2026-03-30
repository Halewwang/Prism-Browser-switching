export interface IconAlias {
  slug: string;
  names?: string[];
  bundleIds?: string[];
  types?: string[];
}

export const ICON_ALIASES: IconAlias[] = [
  {
    slug: 'arc',
    names: ['arc', 'the browser company'],
    bundleIds: ['company.thebrowser.Browser'],
    types: ['arc'],
  },
  {
    slug: 'google-chrome',
    names: ['chrome', 'google chrome', 'chrome canary'],
    bundleIds: ['com.google.Chrome', 'com.google.Chrome.canary'],
    types: ['chrome'],
  },
  {
    slug: 'safari',
    names: ['safari'],
    bundleIds: ['com.apple.Safari'],
    types: ['safari'],
  },
  {
    slug: 'firefox',
    names: ['firefox', 'firefox developer edition', 'firefox nightly'],
    bundleIds: ['org.mozilla.firefox', 'org.mozilla.firefoxdeveloperedition', 'org.mozilla.nightly'],
    types: ['firefox'],
  },
  {
    slug: 'microsoft-edge',
    names: ['edge', 'microsoft edge', 'edge canary'],
    bundleIds: ['com.microsoft.edgemac', 'com.microsoft.edgemac.Canary'],
    types: ['edge'],
  },
  {
    slug: 'brave',
    names: ['brave'],
    bundleIds: ['com.brave.Browser'],
    types: ['brave'],
  },
  {
    slug: 'vivaldi',
    names: ['vivaldi'],
    bundleIds: ['com.vivaldi.Vivaldi'],
    types: ['vivaldi'],
  },
  {
    slug: 'opera',
    names: ['opera', 'opera gx'],
    bundleIds: ['com.operasoftware.Opera', 'com.operasoftware.OperaGX'],
    types: ['opera', 'opera-gx'],
  },
  {
    slug: 'chromium',
    names: ['chromium'],
    bundleIds: ['org.chromium.Chromium'],
    types: ['chromium'],
  },
  {
    slug: 'wechat',
    names: ['wechat', 'weixin', '微信'],
    bundleIds: ['com.tencent.xinWeChat'],
  },
  {
    slug: 'dingtalk',
    names: ['dingtalk', 'ding talk', '钉钉'],
    bundleIds: ['com.alibaba.DingTalkMac'],
  },
  {
    slug: 'feishu',
    names: ['feishu', '飞书'],
    bundleIds: ['com.bytedance.feishu'],
  },
  {
    slug: 'lark',
    names: ['lark'],
    bundleIds: ['com.bytedance.ee.lark'],
  },
  {
    slug: 'slack',
    names: ['slack'],
    bundleIds: ['com.tinyspeck.slackmacgap'],
  },
  {
    slug: 'microsoft-teams',
    names: ['teams', 'microsoft teams'],
    bundleIds: ['com.microsoft.teams', 'com.microsoft.teams2'],
  },
  {
    slug: 'telegram',
    names: ['telegram'],
    bundleIds: ['ru.keepcoder.Telegram'],
  },
  {
    slug: 'discord',
    names: ['discord'],
    bundleIds: ['com.hnc.Discord'],
  },
  {
    slug: 'chatgpt',
    names: ['chatgpt', 'chatgpt atlas'],
    bundleIds: ['com.openai.chat', 'com.openai.chatgpt'],
  },
];
