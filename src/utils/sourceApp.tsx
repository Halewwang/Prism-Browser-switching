import React from 'react';
import { AppWindow } from 'lucide-react';

import wechatIcon from '../assets/apps/wechat.svg';
import dingtalkIcon from '../assets/apps/dingtalk.svg';
import slackIcon from '../assets/apps/slack.svg';
import telegramIcon from '../assets/apps/telegram.svg';
import teamsIcon from '../assets/apps/teams.svg';
import larkIcon from '../assets/apps/lark.svg';

interface AppDetails {
  name: string;
  icon: React.ReactNode;
}

export const getSourceAppDetails = (sourceApp: string): AppDetails => {
  // Normalize the source app name
  // Remove .app extension and trim
  const normalized = (sourceApp || '').replace(/\.app$/i, '').trim();
  const lower = normalized.toLowerCase();

  const iconClass = "w-full h-full object-contain rounded-md";

  // Map known apps
  if (lower.includes('wechat') || lower.includes('微信')) {
    return {
      name: '微信',
      icon: <img src={wechatIcon} alt="WeChat" className={iconClass} />
    };
  }

  if (lower.includes('dingtalk') || lower.includes('钉钉')) {
    return {
      name: '钉钉',
      icon: <img src={dingtalkIcon} alt="DingTalk" className={iconClass} />
    };
  }

  if (lower.includes('slack')) {
    return {
      name: 'Slack',
      icon: <img src={slackIcon} alt="Slack" className={iconClass} />
    };
  }

  if (lower.includes('telegram')) {
    return {
      name: 'Telegram',
      icon: <img src={telegramIcon} alt="Telegram" className={iconClass} />
    };
  }

  if (lower.includes('teams') || lower.includes('microsoft teams')) {
    return {
      name: 'Teams',
      icon: <img src={teamsIcon} alt="Teams" className={iconClass} />
    };
  }

  if (lower.includes('lark') || lower.includes('feishu') || lower.includes('飞书')) {
    return {
      name: '飞书',
      icon: <img src={larkIcon} alt="Lark" className={iconClass} />
    };
  }
  
  if (lower.includes('qq')) {
      // Fallback for QQ if no SVG yet, or use text
      return {
          name: 'QQ',
          icon: <div className="w-full h-full bg-blue-500 rounded-md flex items-center justify-center text-white font-bold text-xs">QQ</div>
      };
  }

  // Default fallback
  return {
    name: normalized || 'External Link',
    icon: <AppWindow size={14} className="text-gray-500" />
  };
};
