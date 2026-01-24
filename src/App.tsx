
import React, { useState, useEffect } from 'react';
import { AppView, BrowserApp, RoutingRule, RuleType } from './types';
import { MOCK_RULES } from './constants';
import Sidebar from './components/Sidebar';
import SelectorPopup from './components/SelectorPopup';
import RulesView from './components/RulesView';
import SettingsView from './components/SettingsView';

// 安全地获取ipcRenderer，避免直接使用window.require
const getIpcRenderer = () => {
  if (typeof window === 'undefined') return null;
  
  // 在渲染进程中，electron的ipcRenderer应该通过contextBridge暴露
  // 如果没有配置预加载脚本，尝试使用window.require（仅用于开发环境）
  if ((window as any).electron?.ipcRenderer) {
    return (window as any).electron.ipcRenderer;
  }
  
  // 开发环境下的兼容处理
  if ((window as any).require) {
    try {
      return (window as any).require('electron').ipcRenderer;
    } catch (error) {
      console.error('Failed to require electron:', error);
      return null;
    }
  }
  
  return null;
};

const ipcRenderer = getIpcRenderer();

const App: React.FC = () => {
  const [currentView, setCurrentView] = useState<AppView>(AppView.DASHBOARD);
  const [viewMode, setViewMode] = useState<'dashboard' | 'popup'>('dashboard');
  
  // 使用扫描得到的已安装浏览器列表
  const [browsers, setBrowsers] = useState<BrowserApp[]>([]);
  // 从localStorage加载规则，没有则使用默认规则
  const [rules, setRules] = useState<RoutingRule[]>(() => {
    try {
      const savedRules = localStorage.getItem('routingRules');
      return savedRules ? JSON.parse(savedRules) : MOCK_RULES;
    } catch (error) {
      console.error('Failed to load rules from localStorage:', error);
      return MOCK_RULES;
    }
  });
  
  const [activeUrl, setActiveUrl] = useState('');
  const [activeSource, setActiveSource] = useState('');
  const [showPopupOverlay, setShowPopupOverlay] = useState(false);
  const [pendingDeepLink, setPendingDeepLink] = useState<{url: string, source: string} | null>(null);
  
  // 监听规则变化，保存到localStorage
  useEffect(() => {
    try {
      localStorage.setItem('routingRules', JSON.stringify(rules));
    } catch (error) {
      console.error('Failed to save rules to localStorage:', error);
    }
  }, [rules]);
  
  // 添加已安装IM应用的状态
  const [installedIMApps, setInstalledIMApps] = useState<Array<{ id: string; name: string; path: string }>>([]);
  
  // 获取已安装的浏览器列表
  useEffect(() => {
    if (!ipcRenderer) return;
    
    // 请求已安装的浏览器列表
    ipcRenderer.send('get-installed-browsers');
    
    // 监听已安装浏览器列表的响应
    ipcRenderer.on('installed-browsers', (event, installedBrowsers: BrowserApp[]) => {
      console.log('Received installed browsers:', installedBrowsers);
      setBrowsers(installedBrowsers);
    });
    
    return () => {
      ipcRenderer.removeAllListeners('installed-browsers');
    };
  }, []);
  
  // 获取已安装的IM应用列表
  useEffect(() => {
    if (!ipcRenderer) return;
    
    // 请求已安装的IM应用列表
    ipcRenderer.send('get-installed-im-apps');
    
    // 监听已安装IM应用列表的响应
    ipcRenderer.on('installed-im-apps', (event, installedIMApps) => {
      console.log('Received installed IM apps:', installedIMApps);
      setInstalledIMApps(installedIMApps);
    });
    
    return () => {
      ipcRenderer.removeAllListeners('installed-im-apps');
    };
  }, []);

  // 智能路由选择逻辑已移至deep-link事件处理中，此函数保留用于兼容性

  const handleSelectBrowser = (browserId: string, remember: boolean = false) => {
    const browser = browsers.find(b => b.id === browserId);
    if (ipcRenderer && browser && browser.path) {
       ipcRenderer.send('open-in-browser', { url: activeUrl, browserPath: browser.path });
       
       // 如果是弹窗模式，处理完后关闭窗口
       if (viewMode === 'popup') {
         console.log('Closing popup window after browser selection');
         ipcRenderer.send('close-window');
       }
    }
  };

  const handleCancel = () => {
    if (viewMode === 'popup' && ipcRenderer) {
      ipcRenderer.send('close-window');
    }
  };

  const addToHistory = (url: string, source: string, browserId: string, method: 'Manual' | 'Rule' | 'AI' | 'Default') => {
    // Implementation of history logging (placeholder for now or actual implementation)
    console.log('Adding to history:', { url, source, browserId, method });
    // In a real app, you might save this to localStorage or send to main process
  };

  // 核心路由逻辑
  const processRouting = (url: string, source: string) => {
    console.log('Processing routing for:', { url, source });
    console.log('Current rules:', rules);
    console.log('Installed browsers:', browsers);
    
    // 规范化sourceApp名称
    const normalizedSource = source.replace(/\.app$/i, '').trim().toLowerCase();
    // 规范化URL
    const normalizedUrl = url.toLowerCase();
    
    let matchedRule = null;
    
    // 1. 检查源应用规则
    if (normalizedSource) {
      matchedRule = rules.find(rule => {
        if (!rule.active || rule.type !== RuleType.SOURCE_APP) return false;
        const ruleValue = rule.value.replace(/\.app$/i, '').trim().toLowerCase();
        return ruleValue && normalizedSource.includes(ruleValue);
      });
    }
    
    // 2. 检查URL模式规则
    if (!matchedRule) {
      matchedRule = rules.find(rule => {
        if (!rule.active || rule.type !== RuleType.URL_PATTERN) return false;
        const ruleValue = rule.value.trim().toLowerCase();
        return ruleValue && normalizedUrl.includes(ruleValue);
      });
    }
    
    if (matchedRule) {
      console.log('Rule matched:', matchedRule);
      const targetBrowser = browsers.find(b => b.id === matchedRule.targetBrowserId);
      if (targetBrowser && targetBrowser.path) {
        if (ipcRenderer) {
          ipcRenderer.send('open-in-browser', { url, browserPath: targetBrowser.path });
        }
        addToHistory(url, source, matchedRule.targetBrowserId, 'Rule');
      } else {
        console.log('No browser found for rule, showing popup');
        setActiveUrl(url);
        setActiveSource(source);
        setShowPopupOverlay(false);
      }
    } else {
      console.log('No rule matched, showing popup');
      setActiveUrl(url);
      setActiveSource(source);
      setShowPopupOverlay(false);
    }
  };

  // 处理待处理的Deep Link
  useEffect(() => {
    if (pendingDeepLink && browsers.length > 0) {
      console.log('Processing pending deep link');
      processRouting(pendingDeepLink.url, pendingDeepLink.source);
      setPendingDeepLink(null);
    }
  }, [browsers, pendingDeepLink, rules]);

  // 处理deep-link事件
  useEffect(() => {
    if (!ipcRenderer) return;
    
    ipcRenderer.on('view-mode-change', (_: any, mode: 'dashboard' | 'popup') => {
      console.log('View mode changed:', mode);
      setViewMode(mode);
      if (mode === 'popup') {
        setShowPopupOverlay(false);
      }
    });
    
    if (ipcRenderer) {
      ipcRenderer.send('update-window-style', viewMode === 'popup');
    }
    
    ipcRenderer.on('deep-link', (_: any, data: any) => {
      const { url, source } = data;
      console.log('Deep link received:', { url, source });
      
      if (browsers.length === 0) {
        console.log('Browsers not loaded yet, queueing deep link');
        setPendingDeepLink({ url, source });
        return;
      }
      
      processRouting(url, source);
    });
    
    return () => {
      ipcRenderer.removeAllListeners('view-mode-change');
      ipcRenderer.removeAllListeners('deep-link');
    };
  }, [rules, browsers, installedIMApps]);

  // Standalone Popup Interface
  if (viewMode === 'popup') {
    return (
      <div className="h-screen w-screen flex items-center justify-center bg-transparent select-none overflow-hidden p-4">
        <div className="w-full flex justify-center">
          <SelectorPopup 
            url={activeUrl}
            sourceApp={activeSource}
            browsers={browsers}
            onSelect={handleSelectBrowser}
            onCancel={handleCancel}
            isStandalone={true} 
          />
        </div>
      </div>
    );
  }

  // Main Interface
  return (
    <div className="h-screen w-screen flex overflow-hidden bg-white font-sans antialiased">
      {/* Sidebar */}
      <Sidebar currentView={currentView} onChangeView={setCurrentView} />
      
      {/* Main Content Area */}
      <main className="flex-1 flex flex-col overflow-hidden min-w-0">
        {/* Header */}
        <header className="bg-white border-b border-gray-200 px-6 py-4">
          <h1 className="text-xl font-semibold text-gray-900">
            {currentView === AppView.RULES && '规则'}
            {currentView === AppView.SETTINGS && '设置'}
          </h1>
        </header>
        
        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6">
          {currentView === AppView.RULES && (
             <RulesView 
               rules={rules} 
               browsers={browsers} 
               installedIMApps={installedIMApps}
               onAddRule={r => setRules([...rules, r])} 
               onDeleteRule={id => setRules(rules.filter(x => x.id !== id))} 
             />
          )}
          {currentView === AppView.SETTINGS && <SettingsView />}
        </div>
      </main>
    </div>
  );
};

export default App;
