import React, { useState } from 'react';
import { BrowserApp, UpdateInfo } from '../types';
import { Cpu, Info, RefreshCcw } from 'lucide-react';
import { useI18n } from '../i18n';
import { getPrism } from '../utils/prism';

interface SettingsViewProps {
  browsers?: BrowserApp[];
  onRescan?: () => void;
  onCheckUpdate?: () => void;
  isCheckingUpdate?: boolean;
  updateInfo?: UpdateInfo | null;
}

const SettingsView: React.FC<SettingsViewProps> = ({ 
  browsers = [], 
  onRescan,
  onCheckUpdate,
  isCheckingUpdate,
  updateInfo
}) => {
  const { t, language, setLanguage } = useI18n();
  const [autoStart, setAutoStart] = useState(true);
  
  const [appVersion, setAppVersion] = useState<string>('Loading...');
  const [buildInfo, setBuildInfo] = useState<string>('Loading...');

  React.useEffect(() => {
      const fetchInfo = async () => {
          const prism = getPrism();
          if (prism) {
              try {
                  const version = await prism.invoke<string>('get-app-version');
                  setAppVersion(version);
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
      {/* Content Area */}
      <div className="flex-1 overflow-hidden">
          <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-300">
            {/* General Settings */}
            <div className="bg-[#F8F8F8] border border-[#E1E1E1] rounded-[15px] p-6">
              <div className="flex items-center gap-2 mb-4 pb-4 border-b border-[#E1E1E1]">
                <Cpu size={18} className="text-gray-600" />
                <h3 className="text-lg font-semibold text-gray-900">{t.settings.title}</h3>
              </div>
              
              <div>
                {/* Language Switch */}
                <div className="flex items-center justify-between py-3 border-b border-gray-100 last:border-b-0">
                  <div>
                    <h4 className="text-sm font-medium text-gray-900">{t.settings.language}</h4>
                    <p className="text-xs text-gray-500 mt-1">{t.settings.languageDesc}</p>
                  </div>
                  <div className="flex bg-white border border-[#E1E1E1] p-1 rounded-lg">
                    <button
                      onClick={() => setLanguage('en')}
                      className={`px-3 py-1 rounded-md text-xs font-medium transition-all ${language === 'en' ? 'bg-[#F8F8F8] text-black shadow-sm border border-[#E1E1E1]' : 'text-gray-500 hover:text-gray-700'}`}
                    >
                      English
                    </button>
                    <button
                      onClick={() => setLanguage('zh')}
                      className={`px-3 py-1 rounded-md text-xs font-medium transition-all ${language === 'zh' ? 'bg-[#F8F8F8] text-black shadow-sm border border-[#E1E1E1]' : 'text-gray-500 hover:text-gray-700'}`}
                    >
                      中文
                    </button>
                  </div>
                </div>

                <ToggleSwitch 
                  active={autoStart} 
                  onClick={() => setAutoStart(!autoStart)} 
                  label={t.settings.autoStart}
                />
                
                {/* Update Check */}
                <div className="flex items-center justify-between py-3 border-b border-gray-100 last:border-b-0">
                  <div>
                    <h4 className="text-sm font-medium text-gray-900">{t.settings.checkUpdate}</h4>
                    {updateInfo && (
                       <p className="text-xs text-gray-500 mt-1">
                          {updateInfo.hasUpdate ? t.settings.updateAvailable : t.settings.upToDate} (v{updateInfo.latestVersion})
                       </p>
                    )}
                  </div>
                  <button 
                    onClick={onCheckUpdate}
                    disabled={isCheckingUpdate}
                    className="px-3 py-1.5 bg-white border border-gray-300 rounded-md text-sm font-medium hover:bg-gray-50 active:bg-gray-100 transition-colors flex items-center gap-2 disabled:opacity-50"
                  >
                    <RefreshCcw size={14} className={isCheckingUpdate ? 'animate-spin' : ''} />
                    {isCheckingUpdate ? t.settings.checking : 'Check'}
                  </button>
                </div>
              </div>
            </div>

            {/* About Section */}
            <div className="bg-[#F8F8F8] border border-[#E1E1E1] rounded-[15px] p-6">
              <div className="flex items-center gap-2 mb-4 pb-4 border-b border-[#E1E1E1]">
                <Info size={18} className="text-gray-600" />
                <h3 className="text-lg font-semibold text-gray-900">About</h3>
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
      </div>
    </div>
  );
};

export default SettingsView;
