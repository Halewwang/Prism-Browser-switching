
import { BrowserApp, RoutingRule, RuleType, HistoryLog } from './types';
import React from 'react';
import { Chrome, Compass, Globe, Command, Box, Hash, MessageCircle, Github, Send, MessageSquare, Rocket, Shield, Zap } from 'lucide-react';
import arcIcon from './assets/browsers/arc.svg';
import chromeIcon from './assets/browsers/chrome.svg';
import safariIcon from './assets/browsers/safari.svg';
import edgeIcon from './assets/browsers/edge.svg';
import firefoxIcon from './assets/browsers/firefox.svg';

export const MOCK_BROWSERS: BrowserApp[] = [
  { id: 'b1', name: 'Arc', icon: 'arc', path: '/Applications/Arc.app', type: 'arc' },
  { id: 'b2', name: 'Google Chrome', icon: 'chrome', path: '/Applications/Google Chrome.app', type: 'chrome', isDefault: true },
  { id: 'b3', name: 'Safari', icon: 'safari', path: '/Applications/Safari.app', type: 'safari' },
  { id: 'b4', name: 'Firefox', icon: 'firefox', path: '/Applications/Firefox.app', type: 'firefox' },
  { id: 'b5', name: 'Microsoft Edge', icon: 'edge', path: '/Applications/Microsoft Edge.app', type: 'edge' },
  { id: 'b6', name: 'Brave', icon: 'brave', path: '/Applications/Brave Browser.app', type: 'brave' },
  { id: 'b7', name: 'Vivaldi', icon: 'vivaldi', path: '/Applications/Vivaldi.app', type: 'vivaldi' },
  { id: 'b8', name: 'Chrome Canary', icon: 'chrome', path: '/Applications/Google Chrome Canary.app', type: 'chrome' },
];

export const MOCK_RULES: RoutingRule[] = [
  { id: 'r1', type: RuleType.SOURCE_APP, value: 'Slack', targetBrowserId: 'b2', description: 'Work related links', active: true },
];

export const MOCK_HISTORY: HistoryLog[] = [
  { id: 'h1', timestamp: new Date(Date.now() - 1000 * 60 * 2), url: 'https://figma.com/file/xTk2...', sourceApp: 'Slack', routedToBrowserId: 'b1', method: 'Rule' },
  { id: 'h2', timestamp: new Date(Date.now() - 1000 * 60 * 15), url: 'https://github.com/facebook/react', sourceApp: 'Discord', routedToBrowserId: 'b2', method: 'AI' },
  { id: 'h3', timestamp: new Date(Date.now() - 1000 * 60 * 45), url: 'https://twitter.com/home', sourceApp: 'WeChat', routedToBrowserId: 'b3', method: 'Manual' },
  { id: 'h4', timestamp: new Date(Date.now() - 1000 * 60 * 120), url: 'http://localhost:3000', sourceApp: 'VS Code', routedToBrowserId: 'b2', method: 'Rule' },
  { id: 'h5', timestamp: new Date(Date.now() - 1000 * 60 * 300), url: 'https://news.ycombinator.com', sourceApp: 'Telegram', routedToBrowserId: 'b1', method: 'AI' },
];

export const APP_ICONS: Record<string, React.ReactNode> = {
  'Slack': <Hash className="w-3 h-3 text-purple-500" />,
  'Discord': <MessageCircle className="w-3 h-3 text-indigo-500" />,
  'VS Code': <Command className="w-3 h-3 text-blue-500" />,
  'Terminal': <Box className="w-3 h-3 text-slate-700" />,
  'GitHub Desktop': <Github className="w-3 h-3 text-slate-900" />,
  'Telegram': <Send className="w-3 h-3 text-blue-400" />,
  'WeChat': <MessageSquare className="w-3 h-3 text-green-500" />,
  '微信': <MessageSquare className="w-3 h-3 text-green-500" />,
  'DingTalk': <Send className="w-3 h-3 text-blue-600" />,
  '钉钉': <Send className="w-3 h-3 text-blue-600" />,
  'Postman': <Rocket className="w-3 h-3 text-orange-500" />,
};

export const getBrowserIcon = (type: string, size = 6) => {
  const cls = `w-${size} h-${size} object-contain rounded-full bg-white shadow-sm`;
  
  switch (type) {
    case 'chrome': 
      return <img src={chromeIcon} className={cls} alt="Chrome" />;
    case 'safari': 
      return <img src={safariIcon} className={cls} alt="Safari" />;
    case 'firefox': 
      return <img src={firefoxIcon} className={cls} alt="Firefox" />;
    case 'edge': 
      return <img src={edgeIcon} className={cls} alt="Edge" />;
    case 'arc': 
      return <img src={arcIcon} className={cls} alt="Arc" />;
    case 'brave': 
      // Fallback for Brave using simple div if no icon
      return <div className={`w-${size} h-${size} rounded-full bg-white flex items-center justify-center shadow-sm overflow-hidden p-0.5`}><div className="w-full h-full rounded-full bg-gradient-to-br from-orange-500 to-red-600 flex items-center justify-center text-white font-bold text-[10px]">B</div></div>;
    case 'vivaldi': 
      return <div className={`w-${size} h-${size} rounded-full bg-white flex items-center justify-center shadow-sm overflow-hidden p-0.5`}><div className="w-full h-full rounded-full bg-red-600 flex items-center justify-center text-white font-bold text-[10px]">V</div></div>;
    case 'opera': 
      return <div className={`w-${size} h-${size} rounded-full bg-white flex items-center justify-center shadow-sm overflow-hidden p-0.5`}><div className="w-full h-full rounded-full bg-red-600 flex items-center justify-center text-white font-bold text-[10px]">O</div></div>;
    default: 
      return <div className={`w-${size} h-${size} rounded-full bg-slate-100 flex items-center justify-center text-slate-400 font-bold text-[10px] shadow-sm`}>?</div>;
  }
};
