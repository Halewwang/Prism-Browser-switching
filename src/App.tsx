import React, { useState, useEffect, Suspense, lazy } from 'react';
import { I18nProvider } from './i18n';
import { AppView, BrowserApp, RoutingRule, RuleType } from './types';
import { MOCK_RULES } from './constants';
import Sidebar from './components/Sidebar';
import SelectorPopup from './components/SelectorPopup';

// Lazy load large components
const RulesView = lazy(() => import('./components/RulesView'));
const SettingsView = lazy(() => import('./components/SettingsView'));
const DashboardView = lazy(() => import('./components/DashboardView'));

import UpdateModal from './components/UpdateModal';
import { checkForUpdates, UpdateInfo } from './utils/updater';
import { RoutingService } from './services/routingService';
import { getPrism } from './utils/prism';

// Loading Component
const LoadingFallback = () => (
  <div className="flex items-center justify-center h-full w-full">
    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-400"></div>
  </div>
);

const prism = getPrism();

const AppContent: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'dashboard' | 'rules' | 'settings'>('dashboard');
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
  const [activeSourceIcon, setActiveSourceIcon] = useState<string | undefined>(undefined);
  const [activeSourceBundleId, setActiveSourceBundleId] = useState<string | undefined>(undefined);
  const [showPopupOverlay, setShowPopupOverlay] = useState(false);
  const [pendingDeepLink, setPendingDeepLink] = useState<{url: string, source: string, sourceIcon?: string, sourceBundleId?: string} | null>(null);
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [isCheckingUpdate, setIsCheckingUpdate] = useState(false);
  const [isDownloadingUpdate, setIsDownloadingUpdate] = useState(false);
  
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
  
  // 获取已安装的浏览器列表
  useEffect(() => {
    if (!prism) return;
    
    // 请求已安装的浏览器列表
    prism.send('get-installed-browsers');
    
    // 监听已安装浏览器列表的响应
    const cleanup = prism.on<BrowserApp[]>('installed-browsers', (installedBrowsers) => {
      console.log('Received installed browsers:', installedBrowsers);
      setBrowsers(installedBrowsers);
    });
    
    return () => {
      cleanup();
    };
  }, []);
  
  // Check for updates on startup
  useEffect(() => {
    const checkUpdate = async () => {
      if (!prism) return;
      
      const currentVersion = await prism.invoke<string>('get-app-version');
      const info = await checkForUpdates(currentVersion);
      
      if (info.hasUpdate) {
        setUpdateInfo(info);
      }
    };
    
    checkUpdate();
  }, []);

  const handleStartUpdate = async () => {
    if (!updateInfo || !prism) return;

    setIsDownloadingUpdate(true);
    try {
      await prism.invoke('start-download-update', {
        downloadUrl: updateInfo.downloadUrl,
        fileName: updateInfo.fileName,
        sha256: updateInfo.sha256,
      });
      setUpdateInfo(null);
    } catch (error: any) {
      console.error('Failed to download update:', error);
      alert(`Failed to download update: ${error?.message || 'Unknown error'}`);
    } finally {
      setIsDownloadingUpdate(false);
    }
  };

  const handleSelectBrowser = (browserId: string, remember: boolean = false) => {
    const browser = browsers.find(b => b.id === browserId);
    if (prism && browser && browser.path) {
       prism.send('open-in-browser', { url: activeUrl, browserPath: browser.path });
       
       addToHistory(activeUrl, activeSource, browserId, 'Manual');

       // 如果是弹窗模式，处理完后关闭窗口
       if (viewMode === 'popup') {
         console.log('Closing popup window after browser selection');
         prism.send('close-window');
       }
    }
  };

  const handleCancel = () => {
    if (viewMode === 'popup' && prism) {
      prism.send('close-window');
    }
  };

  const addToHistory = (url: string, source: string, browserId: string, method: 'Manual' | 'Rule' | 'AI' | 'Default', sourceIcon?: string) => {
    const newLog = {
      id: Date.now().toString(),
      timestamp: new Date(),
      url,
      sourceApp: source,
      sourceBundleId: activeSourceBundleId,
      sourceAppIcon: sourceIcon,
      routedToBrowserId: browserId,
      method
    };
    setHistory(prev => [newLog, ...prev].slice(0, 100)); // Keep last 100 entries
  };

  const clearHistory = () => {
    setHistory([]);
  };

  // 核心路由逻辑
  const processRouting = (url: string, source: string, sourceIcon?: string, sourceBundleId?: string) => {
    console.log('Processing routing for:', { url, source, sourceBundleId, hasIcon: !!sourceIcon });
    
    const matchedRule = RoutingService.matchRule(url, source, sourceBundleId, rules);
    
    if (matchedRule) {
      console.log('Rule matched:', matchedRule);
      const success = RoutingService.executeRouting(url, matchedRule.targetBrowserId, browsers, prism);
      
      if (success) {
        addToHistory(url, source, matchedRule.targetBrowserId, 'Rule', sourceIcon);
      } else {
        console.log('No browser found for rule, showing popup');
        setActiveUrl(url);
        setActiveSource(source);
        setActiveSourceIcon(sourceIcon);
        setActiveSourceBundleId(sourceBundleId);
        setShowPopupOverlay(false);
      }
    } else {
      console.log('No rule matched, showing popup');
      setActiveUrl(url);
      setActiveSource(source);
      setActiveSourceIcon(sourceIcon);
      setActiveSourceBundleId(sourceBundleId);
      setShowPopupOverlay(false);
    }
  };

  // 处理待处理的Deep Link
  useEffect(() => {
    if (pendingDeepLink && browsers.length > 0) {
      console.log('Processing pending deep link');
      processRouting(pendingDeepLink.url, pendingDeepLink.source, pendingDeepLink.sourceIcon, pendingDeepLink.sourceBundleId);
      setPendingDeepLink(null);
    }
  }, [browsers, pendingDeepLink, rules]);

  // 处理deep-link事件
  useEffect(() => {
    if (!prism) return;
    
    const cleanupViewMode = prism.on<'dashboard' | 'popup'>('view-mode-change', (mode) => {
      console.log('View mode changed:', mode);
      setViewMode(mode);
      if (mode === 'popup') {
        setShowPopupOverlay(false);
      }
    });
    
    prism.send('update-window-style', viewMode === 'popup');
    
    const cleanupDeepLink = prism.on<any>('deep-link', (data) => {
      const { url, source, sourceIcon, sourceBundleId } = data;
      console.log('Deep link received:', { url, source, sourceBundleId, hasIcon: !!sourceIcon });
      
      if (browsers.length === 0) {
        console.log('Browsers not loaded yet, queueing deep link');
        setPendingDeepLink({ url, source, sourceIcon, sourceBundleId });
        return;
      }
      
      processRouting(url, source, sourceIcon, sourceBundleId);
    });
    
    return () => {
      cleanupViewMode();
      cleanupDeepLink();
    };
  }, [rules, browsers]);

  // Standalone Popup Interface
  if (viewMode === 'popup') {
    return (
      <div className="h-screen w-screen flex items-center justify-center bg-transparent select-none overflow-hidden p-4">
        <div className="w-full flex justify-center">
          <SelectorPopup 
            url={activeUrl}
            sourceApp={activeSource}
            sourceAppIcon={activeSourceIcon}
            sourceBundleId={activeSourceBundleId}
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
      {updateInfo && (
        <UpdateModal 
          updateInfo={updateInfo} 
          onClose={() => setUpdateInfo(null)} 
          onUpdate={handleStartUpdate}
          isDownloading={isDownloadingUpdate}
        />
      )}
      {/* Container with Shadow - Matching Figma Design */}
      <div className="flex flex-col overflow-hidden bg-white rounded-[15px] shadow-[0px_5px_20px_0px_rgba(0,0,0,0.3)] w-full h-full relative">
        {/* Global Drag Region - Covers Top Area */}
        <div className="absolute top-0 left-0 right-0 h-10 drag-region z-50 pointer-events-none"></div>

        <div className="flex flex-1 overflow-hidden z-0">
          {/* Sidebar */}
          <Sidebar 
            activeTab={activeTab} 
            onTabChange={setActiveTab} 
          />
          
          {/* Main Content Area */}
          <main className="flex-1 flex flex-col overflow-hidden min-w-0 bg-white">
            {/* Content */}
            <div className="flex-1 overflow-hidden p-6">
              {activeTab === 'dashboard' && (
                <Suspense fallback={<LoadingFallback />}>
                  <DashboardView 
                    history={history} 
                    browsers={browsers} 
                    onClearHistory={clearHistory}
                  />
                </Suspense>
              )}
              {activeTab === 'rules' && (
                 <div className="h-full overflow-y-auto">
                   <Suspense fallback={<LoadingFallback />}>
                     <RulesView 
                        rules={rules}
                        browsers={browsers}
                        onAddRule={r => setRules(prev => [...prev, r])}
                        onDeleteRule={id => setRules(prev => prev.filter(x => x.id !== id))}
                      />
                   </Suspense>
                 </div>
              )}
              {activeTab === 'settings' && (
                <div className="h-full overflow-y-auto">
                   <Suspense fallback={<LoadingFallback />}>
                     <SettingsView 
                        browsers={browsers}
                        onRescan={() => prism && prism.send('get-installed-browsers')}
                        isCheckingUpdate={isCheckingUpdate}
                        onCheckUpdate={async () => {
                            if (!prism) return;
                            
                            setIsCheckingUpdate(true);
                            try {
                                const currentVersion = await prism.invoke<string>('get-app-version');
                                const info = await checkForUpdates(currentVersion);
                                if (info.hasUpdate) {
                                  setUpdateInfo(info);
                                } else {
                                  // Simple feedback using native alert, can be improved to Toast later
                                  alert('You are up to date!');
                                }
                            } catch (e: any) {
                                console.error(e);
                                const msg = e.message || 'Unknown error';
                                if (msg.includes('403')) {
                                    alert('Update check failed: GitHub API Rate Limit Exceeded.\n\nPlease wait a while before checking again, or visit the GitHub repository to download manually.');
                                } else {
                                    alert(`Failed to check for updates: ${msg}`);
                                }
                            } finally {
                                setIsCheckingUpdate(false);
                            }
                        }}
                        updateInfo={updateInfo}
                      />
                   </Suspense>
                </div>
              )}
            </div>
          </main>
        </div>
      </div>
    </div>
  );
};

const App: React.FC = () => {
  return (
    <I18nProvider>
      <AppContent />
    </I18nProvider>
  );
};

export default App;
