
import React, { useState, useEffect } from 'react';
import { AppView, BrowserApp, RoutingRule, RuleType } from './types';
import { MOCK_RULES } from './constants';
import Sidebar from './components/Sidebar';
import SelectorPopup from './components/SelectorPopup';
import RulesView from './components/RulesView';
import SettingsView from './components/SettingsView';
import DashboardView from './components/DashboardView';

// 安全地获取ipcRenderer，避免直接使用window.require
const getIpcRenderer = () => {
  if (typeof window === 'undefined') return null;
  
  console.log('Checking for ipcRenderer...');
  
  // 在渲染进程中，electron的ipcRenderer应该通过contextBridge暴露
  // 如果没有配置预加载脚本，尝试使用window.require（仅用于开发环境）
  if ((window as any).electron?.ipcRenderer) {
    console.log('Found ipcRenderer via contextBridge');
    return (window as any).electron.ipcRenderer;
  }
  
  // 开发环境下的兼容处理
  if ((window as any).require) {
    try {
      const electron = (window as any).require('electron');
      console.log('Found ipcRenderer via window.require');
      return electron.ipcRenderer;
    } catch (error) {
      console.error('Failed to require electron:', error);
      return null;
    }
  }
  
  console.warn('ipcRenderer not found!');
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

  const [history, setHistory] = useState<any[]>(() => {
    try {
      const savedHistory = localStorage.getItem('routingHistory');
      return savedHistory ? JSON.parse(savedHistory) : [];
    } catch (error) {
      console.error('Failed to load history from localStorage:', error);
      return [];
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

  // 监听历史记录变化，保存到localStorage
  useEffect(() => {
    try {
      localStorage.setItem('routingHistory', JSON.stringify(history));
    } catch (error) {
      console.error('Failed to save history to localStorage:', error);
    }
  }, [history]);
  
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
       
       addToHistory(activeUrl, activeSource, browserId, 'Manual');

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

  const handleClose = () => {
    if (ipcRenderer) ipcRenderer.send('close-window');
  };

  const handleMinimize = () => {
    if (ipcRenderer) ipcRenderer.send('minimize-window');
  };

  const handleMaximize = () => {
    if (ipcRenderer) ipcRenderer.send('maximize-window');
  };

  const addToHistory = (url: string, source: string, browserId: string, method: 'Manual' | 'Rule' | 'AI' | 'Default') => {
    const newLog = {
      id: Date.now().toString(),
      timestamp: new Date(),
      url,
      sourceApp: source,
      routedToBrowserId: browserId,
      method
    };
    setHistory(prev => [newLog, ...prev].slice(0, 100)); // Keep last 100 entries
  };

  const clearHistory = () => {
    setHistory([]);
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
    <div className="h-screen w-screen flex items-center justify-center bg-transparent font-sans antialiased p-4">
      {/* Container with Shadow - Matching Figma Design */}
      <div className="flex overflow-hidden bg-white rounded-[15px] shadow-[0px_5px_20px_0px_rgba(0,0,0,0.3)] w-full h-full">
        {/* Sidebar */}
        <Sidebar 
          currentView={currentView} 
          onChangeView={setCurrentView} 
          onClose={handleClose}
          onMinimize={handleMinimize}
          onMaximize={handleMaximize}
        />
        
        {/* Main Content Area */}
        <main className="flex-1 flex flex-col overflow-hidden min-w-0 bg-white">
          {/* Content */}
          <div className="flex-1 overflow-hidden">
            {currentView === AppView.DASHBOARD && (
              <DashboardView 
                history={history} 
                browsers={browsers} 
                onClearHistory={clearHistory}
              />
            )}
            {currentView === AppView.SETTINGS && (
              <div className="h-full overflow-y-auto p-6">
                 <h1 className="text-[25px] font-normal text-black font-['SF_Pro_Display'] leading-tight mb-6">General</h1>
                 <SettingsView 
                    rules={rules}
                    browsers={browsers}
                    installedIMApps={installedIMApps}
                    onAddRule={r => setRules(prev => [...prev, r])}
                    onDeleteRule={id => setRules(prev => prev.filter(x => x.id !== id))}
                  />
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  );
};

export default App;
