import React, { useState } from 'react';
import { BrowserApp, RoutingRule } from '../types';
import { Cpu, ListFilter, Info, RefreshCcw } from 'lucide-react';
import RulesView from './RulesView';
import { checkForUpdates } from '../utils/updater';

// 安全地获取ipcRenderer
const getIpcRenderer = () => {
  if (typeof window === 'undefined') return null;
  
  // 1. 尝试通过 contextBridge 获取 (预加载脚本方式)
  if ((window as any).electron?.ipcRenderer) {
    return (window as any).electron.ipcRenderer;
  }
  
  // 2. 尝试通过 window.require 获取 (nodeIntegration: true 方式)
  if ((window as any).require) {
    try {
      const electron = (window as any).require('electron');
      return electron.ipcRenderer;
    } catch (error) {
      console.error('Failed to require electron:', error);
    }
  }
  
  return null;
};

interface SettingsViewProps {
  rules?: RoutingRule[];
  browsers?: BrowserApp[];
  installedIMApps?: Array<{ id: string; name: string; path: string }>;
  onAddRule?: (rule: RoutingRule) => void;
  onDeleteRule?: (id: string) => void;
}

const SettingsView: React.FC<SettingsViewProps> = ({ 
  rules = [], 
  browsers = [], 
  installedIMApps = [], 
  onAddRule = () => {}, 
  onDeleteRule = () => {} 
}) => {
  const [activeTab, setActiveTab] = useState<'general' | 'rules'>('rules');
  const [autoStart, setAutoStart] = useState(true);
  const [isCheckingUpdate, setIsCheckingUpdate] = useState(false);
  const [updateStatus, setUpdateStatus] = useState<string>('');
  
  const [appVersion, setAppVersion] = useState<string>('Loading...');
  const [buildInfo, setBuildInfo] = useState<string>('Loading...');

  React.useEffect(() => {
      const fetchInfo = async () => {
          const ipcRenderer = getIpcRenderer();
          if (ipcRenderer) {
              try {
                  const version = await ipcRenderer.invoke('get-app-version');
                  setAppVersion(version);
                  // Since we don't have a real build number in package.json, we can use a timestamp or just repeat version
                  // Or we can try to get it if we add a handler. For now, let's use a placeholder or derived value.
                  setBuildInfo('2026.01.25'); 
              } catch (e) {
                  console.error("Failed to get app info", e);
                  setAppVersion('Unknown');
                  setBuildInfo('Unknown');
              }
          }
      };
      fetchInfo();
  }, []);

  const handleCheckUpdate = async () => {
    setIsCheckingUpdate(true);
    setUpdateStatus('Checking...');
    
    try {
      const ipcRenderer = getIpcRenderer();
      if (!ipcRenderer) {
        setUpdateStatus('Error: IPC not available');
        return;
      }

      const currentVersion = await ipcRenderer.invoke('get-app-version');
      const info = await checkForUpdates(currentVersion);
      
      if (info.hasUpdate) {
        // If update found, the main App component will handle the modal via state lift or event
        // But here we can also just trigger the download if we want, or show a message
        // For better UX, we'll let the user know an update is available and maybe trigger the modal
        // Since the App component also checks on startup, we might want to expose setUpdateInfo to here
        // or just let the user know.
        // Simplified approach: Re-trigger the startup check logic by reloading or sending an event
        // Or better: pass a callback prop `onCheckUpdate` from App.tsx. 
        // For now, let's just show status text.
        setUpdateStatus(`New version v${info.latestVersion} available!`);
        // Trigger the update modal in App.tsx by re-fetching there or using IPC
        // To keep it simple without refactoring props too much:
        // We will invoke the same logic as App.tsx if possible, or just open the download link
        if(confirm(`New version v${info.latestVersion} available! Download now?`)) {
             ipcRenderer.send('start-download-update', info.downloadUrl);
        }
      } else {
        setUpdateStatus('You are up to date.');
      }
    } catch (e) {
      setUpdateStatus('Failed to check for updates.');
      console.error(e);
    } finally {
      setIsCheckingUpdate(false);
    }
  };

  // Simple Toggle Switch Component
  const ToggleSwitch = ({ active, onClick, label }: { active: boolean; onClick: () => void; label: string }) => (
    <div className="flex items-center justify-between py-3 border-b border-gray-100 last:border-b-0">
      <div>
        <h4 className="text-sm font-medium text-gray-900">{label}</h4>
      </div>
      <button 
        onClick={onClick}
        className={`
          relative inline-flex h-6 w-11 items-center rounded-full transition-colors duration-200
          ${active ? 'bg-black' : 'bg-gray-200'}
        `}>
        <span 
          className={`
            inline-block h-4 w-4 transform rounded-full bg-white transition-transform duration-200
            ${active ? 'translate-x-6' : 'translate-x-1'}
          `}
        />
      </button>
    </div>
  );

  return (
    <div className="h-full flex flex-col max-w-5xl mx-auto w-full">
      {/* Tabs Header */}
      <div className="flex space-x-1 bg-[#F8F8F8] p-1 rounded-full border border-[#E1E1E1] w-fit mb-6">
        <button
          onClick={() => setActiveTab('rules')}
          className={`
            px-4 py-1.5 rounded-full text-sm font-medium transition-all duration-200 flex items-center gap-2
            ${activeTab === 'rules' 
              ? 'bg-white text-black shadow-sm border border-[#E1E1E1]' 
              : 'text-gray-500 hover:text-gray-900'}
          `}
        >
          <ListFilter size={16} />
          路由规则
        </button>
        <button
          onClick={() => setActiveTab('general')}
          className={`
            px-4 py-1.5 rounded-full text-sm font-medium transition-all duration-200 flex items-center gap-2
            ${activeTab === 'general' 
              ? 'bg-white text-black shadow-sm border border-[#E1E1E1]' 
              : 'text-gray-500 hover:text-gray-900'}
          `}
        >
          <Cpu size={16} />
          通用设置
        </button>
      </div>

      {/* Content Area */}
      <div className="flex-1 overflow-hidden">
        {activeTab === 'rules' ? (
          <RulesView 
            rules={rules}
            browsers={browsers}
            installedIMApps={installedIMApps}
            onAddRule={onAddRule}
            onDeleteRule={onDeleteRule}
          />
        ) : (
          <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-300">
            {/* General Settings */}
            <div className="bg-[#F8F8F8] border border-[#E1E1E1] rounded-[15px] p-6">
              <div className="flex items-center gap-2 mb-4 pb-4 border-b border-[#E1E1E1]">
                <Cpu size={18} className="text-gray-600" />
                <h3 className="text-lg font-semibold text-gray-900">系统设置</h3>
              </div>
              
              <div>
                <ToggleSwitch 
                  active={autoStart} 
                  onClick={() => setAutoStart(!autoStart)} 
                  label="开机自动启动"
                />
                
                {/* Update Check */}
                <div className="flex items-center justify-between py-3 border-b border-gray-100 last:border-b-0">
                  <div>
                    <h4 className="text-sm font-medium text-gray-900">检查更新</h4>
                    {updateStatus && (
                      <p className="text-xs text-gray-500 mt-1">{updateStatus}</p>
                    )}
                  </div>
                  <button 
                    onClick={handleCheckUpdate}
                    disabled={isCheckingUpdate}
                    className="px-3 py-1.5 bg-white border border-gray-300 rounded-md text-sm font-medium hover:bg-gray-50 active:bg-gray-100 transition-colors flex items-center gap-2 disabled:opacity-50"
                  >
                    <RefreshCcw size={14} className={isCheckingUpdate ? 'animate-spin' : ''} />
                    {isCheckingUpdate ? 'Checking...' : 'Check'}
                  </button>
                </div>
              </div>
            </div>

            {/* About Section */}
            <div className="bg-[#F8F8F8] border border-[#E1E1E1] rounded-[15px] p-6">
              <div className="flex items-center gap-2 mb-4 pb-4 border-b border-[#E1E1E1]">
                <Info size={18} className="text-gray-600" />
                <h3 className="text-lg font-semibold text-gray-900">关于</h3>
              </div>
              
              <div className="space-y-3">
                <div className="flex justify-between">
                  <span className="text-sm text-gray-500">Prism for macOS</span>
                  <span className="text-sm font-medium text-gray-900">{appVersion}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-sm text-gray-500">Build Version</span>
                  <span className="text-sm font-medium text-gray-900">{buildInfo}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-sm text-gray-500">License</span>
                  <span className="text-sm font-medium text-gray-900">MIT</span>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default SettingsView;