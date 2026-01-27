import React, { useState, useEffect } from 'react';
import { BrowserApp, RoutingRule, RuleType } from '../types';
import { Trash2, Plus, Globe, Search, ArrowRight, Sliders, Check } from 'lucide-react';
import { useI18n } from '../i18n';
import AppIcon from './AppIcon';

interface RulesViewProps {
  rules: RoutingRule[];
  browsers: BrowserApp[];
  onAddRule: (rule: RoutingRule) => void;
  onDeleteRule: (id: string) => void;
}

const PRESET_SOURCE_APPS = [
    { name: 'Feishu', id: 'feishu' },
    { name: 'DingTalk', id: 'dingtalk' },
    { name: 'Lark', id: 'lark' },
    { name: 'Teams', id: 'teams' },
    { name: 'Slack', id: 'slack' },
    { name: 'WeChat', id: 'wechat' },
];

const PRESET_TARGET_BROWSERS = [
    { name: 'Chrome', id: 'chrome' },
    { name: 'Arc', id: 'arc' },
    { name: 'Comet', id: 'comet' },
    { name: 'Edge', id: 'edge' },
    { name: 'Safari', id: 'safari' },
];

const RulesView: React.FC<RulesViewProps> = ({ rules, browsers, onAddRule, onDeleteRule }) => {
  const { t } = useI18n();
  const [newType, setNewType] = useState<RuleType>(RuleType.SOURCE_APP);
  const [newValue, setNewValue] = useState('');
  const [selectedApp, setSelectedApp] = useState<{name: string, bundleId: string, icon: string} | null>(null);
  const [isCustomInput, setIsCustomInput] = useState(false);
  const [newTargetId, setNewTargetId] = useState(browsers[0]?.id || '');
  const [searchTerm, setSearchTerm] = useState('');

  const [isSelectingSource, setIsSelectingSource] = useState(false);
  const [isSelectingTarget, setIsSelectingTarget] = useState(false);

  const handleSelectApp = async () => {
      const ipcRenderer = (window as any).electron?.ipcRenderer || (window as any).require?.('electron')?.ipcRenderer;
      if (ipcRenderer) {
          try {
              const result = await ipcRenderer.invoke('select-source-app');
              if (result) {
                  setSelectedApp({
                      name: result.name,
                      bundleId: result.bundleId,
                      icon: result.iconDataURL
                  });
                  setNewValue(result.bundleId);
                  setIsCustomInput(false);
                  setIsSelectingSource(false);
              }
          } catch (e) {
              console.error("Failed to select app", e);
          }
      }
  };

  const handleSelectTargetMore = async () => {
      const ipcRenderer = (window as any).electron?.ipcRenderer || (window as any).require?.('electron')?.ipcRenderer;
      if (ipcRenderer) {
          try {
              // Use the same picker as source app
              const result = await ipcRenderer.invoke('select-source-app');
              if (result) {
                  // Check if it's already in browsers
                  const existing = browsers.find(b => b.bundleId === result.bundleId || b.path === result.path);
                  if (existing) {
                      setNewTargetId(existing.id);
                  } else {
                      // Add as new custom browser
                      const newId = await ipcRenderer.invoke('add-custom-browser', result);
                      if (newId) {
                          setNewTargetId(newId);
                      } else {
                          alert("Failed to add browser.");
                      }
                  }
                  setIsSelectingTarget(false);
              }
          } catch (e) {
              console.error(e);
          }
      }
  }

  const handleAdd = () => {
    if (!newValue || !newTargetId) return;
    const newRule: RoutingRule = {
      id: Date.now().toString(),
      type: newType,
      value: newValue,
      targetBrowserId: newTargetId,
      active: true,
      description: t.rules.userRule,
      appName: newType === RuleType.SOURCE_APP ? (selectedApp?.name || newValue) : undefined,
      appIcon: newType === RuleType.SOURCE_APP ? selectedApp?.icon : undefined
    };
    onAddRule(newRule);
    setNewValue('');
    setSelectedApp(null);
    setIsCustomInput(false);
  };

  const filteredRules = rules.filter(r => 
    r.value.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="h-full flex flex-col space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-300">
      
      {/* Add Rule Card */}
      <div className="bg-[#F8F8F8] border border-[#E1E1E1] rounded-[15px] p-6 relative">
        <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900 flex items-center gap-2">
            <Plus className="w-5 h-5 text-gray-400" />
            {t.rules.addRule}
            </h3>
        </div>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Left Column: Trigger / Source App */}
          <div className="space-y-4">
             <div>
                <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">{t.rules.trigger}</label>
                <div className="flex bg-white border border-[#E1E1E1] p-1 rounded-lg">
                <button
                    onClick={() => { setNewType(RuleType.SOURCE_APP); setNewValue(''); setIsCustomInput(false); }}
                    className={`flex-1 py-1.5 px-3 rounded-md text-sm font-medium transition-all whitespace-nowrap ${newType === RuleType.SOURCE_APP ? 'bg-[#F8F8F8] text-black shadow-sm border border-[#E1E1E1]' : 'text-gray-500 hover:text-gray-700'}`}
                >
                    {t.rules.sourceApp}
                </button>
                <button
                    onClick={() => { setNewType(RuleType.URL_PATTERN); setNewValue(''); setIsCustomInput(false); }}
                    className={`flex-1 py-1.5 px-3 rounded-md text-sm font-medium transition-all whitespace-nowrap ${newType === RuleType.URL_PATTERN ? 'bg-[#F8F8F8] text-black shadow-sm border border-[#E1E1E1]' : 'text-gray-500 hover:text-gray-700'}`}
                >
                    {t.rules.urlPattern}
                </button>
                </div>
             </div>

             <div className="flex flex-col">
                <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">
                    {newType === RuleType.SOURCE_APP ? t.rules.sourceApp : t.rules.urlPattern}
                </label>
                <div className="relative flex-1 flex flex-col justify-end">
                {newType === RuleType.SOURCE_APP ? (
                    <div className="relative">
                        <button
                            onClick={() => { setIsSelectingSource(!isSelectingSource); setIsSelectingTarget(false); }}
                            className="w-full px-3 py-2 bg-white border border-[#E1E1E1] rounded-lg text-sm text-left flex items-center justify-between hover:bg-gray-50 transition-colors shadow-sm"
                        >
                            {selectedApp ? (
                                <div className="flex items-center gap-2">
                                    <AppIcon appName={selectedApp.name} size={16} />
                                    <span className="font-medium text-black">{selectedApp.name}</span>
                                </div>
                            ) : (
                                <span className="text-gray-500">{t.rules.selectApp}</span>
                            )}
                            <Sliders size={14} className="text-gray-400" />
                        </button>

                        {isSelectingSource && (
                            <div className="absolute top-full left-0 right-0 mt-2 bg-white border border-[#E1E1E1] rounded-xl shadow-xl z-20 overflow-hidden animate-in fade-in zoom-in-95 duration-200">
                                <div className="max-h-[200px] overflow-y-auto p-1">
                                    {PRESET_SOURCE_APPS.map(app => (
                                        <button
                                            key={app.id}
                                            onClick={() => {
                                                // Preset handling (mock for now, ideally scan for these)
                                                // Since we don't have real paths for presets without scanning, 
                                                // we might just trigger the file selector if it's a "preset" but not found?
                                                // Or just set the name and hope for fuzzy match?
                                                // Let's set name and try fuzzy match logic in App.tsx
                                                setNewValue(app.name); 
                                                setSelectedApp({ name: app.name, bundleId: '', icon: '' }); // No icon for presets yet
                                                setIsSelectingSource(false);
                                            }}
                                            className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50 rounded-lg flex items-center gap-2 text-gray-700"
                                        >
                                            <div className="w-4 h-4 bg-gray-100 rounded flex items-center justify-center text-[10px]">{app.name[0]}</div>
                                            {app.name}
                                        </button>
                                    ))}
                                    <div className="h-px bg-gray-100 my-1"></div>
                                    <button
                                        onClick={handleSelectApp}
                                        className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50 rounded-lg flex items-center gap-2 text-blue-600 font-medium"
                                    >
                                        <Plus size={14} />
                                        Select More...
                                    </button>
                                </div>
                            </div>
                        )}
                    </div>
                ) : (
                    <input
                        type="text"
                        value={newValue}
                        onChange={(e) => setNewValue(e.target.value)}
                        placeholder={t.rules.inputKeyword}
                        className="w-full px-3 py-2 bg-white border border-[#E1E1E1] rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-black/5 focus:border-black/20 transition-all"
                    />
                )}
                </div>
             </div>
          </div>

          {/* Right Column: Target Browser */}
          <div className="flex flex-col h-full">
            {/* Spacer Label to align with Left Column's "Trigger" label */}
            <label className="block text-xs font-medium text-transparent mb-1.5 uppercase tracking-wider select-none">&nbsp;</label>
            
            <div className="flex justify-end">
                <button
                onClick={handleAdd}
                disabled={!newValue}
                className="h-[42px] px-6 bg-black text-white rounded-lg text-sm font-medium hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed transition-all flex items-center gap-2 shadow-sm"
                >
                <Plus size={14} /> {t.rules.addRule}
                </button>
            </div>
            
            <div className="flex-1 flex flex-col justify-end">
                 <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">{t.rules.targetBrowser}</label>
                 <div className="relative">
                    <button
                        onClick={() => { setIsSelectingTarget(!isSelectingTarget); setIsSelectingSource(false); }}
                        className="w-full px-3 py-2 bg-white border border-[#E1E1E1] rounded-lg text-sm text-left flex items-center justify-between hover:bg-gray-50 transition-colors shadow-sm"
                    >
                        {(() => {
                            const selectedBrowser = browsers.find(b => b.id === newTargetId);
                            if (selectedBrowser) {
                                return (
                                    <div className="flex items-center gap-2">
                                        <AppIcon appName={selectedBrowser.name} size={16} />
                                        <span className="font-medium text-black">{selectedBrowser.name}</span>
                                    </div>
                                );
                            }
                            return <span className="text-gray-500">Select Browser...</span>;
                        })()}
                        <Sliders size={14} className="text-gray-400" />
                    </button>

                    {isSelectingTarget && (
                        <div className="absolute top-full left-0 right-0 mt-2 bg-white border border-[#E1E1E1] rounded-xl shadow-xl z-20 overflow-hidden animate-in fade-in zoom-in-95 duration-200">
                            <div className="max-h-[200px] overflow-y-auto p-1">
                                {browsers.map(b => (
                                    <button
                                        key={b.id}
                                        onClick={() => {
                                            setNewTargetId(b.id);
                                            setIsSelectingTarget(false);
                                        }}
                                        className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50 rounded-lg flex items-center gap-2 text-gray-700 justify-between group"
                                    >
                                        <div className="flex items-center gap-2">
                                            <AppIcon appName={b.name} size={16} />
                                            {b.name}
                                        </div>
                                        {newTargetId === b.id && <Check size={14} className="text-black" />}
                                    </button>
                                ))}
                                <div className="h-px bg-gray-100 my-1"></div>
                                <button
                                    onClick={handleSelectTargetMore}
                                    className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50 rounded-lg flex items-center gap-2 text-blue-600 font-medium"
                                >
                                    <Plus size={14} />
                                    Select More...
                                </button>
                            </div>
                        </div>
                    )}
                </div>
            </div>
          </div>
        </div>
      </div>

      {/* Rules List */}
      <div className="flex-1 bg-[#F8F8F8] border border-[#E1E1E1] rounded-[15px] flex flex-col overflow-hidden">
        {/* Search Header */}
        <div className="px-6 py-4 border-b border-[#E1E1E1] flex items-center gap-4">
            <div className="relative flex-1">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={16} />
                <input 
                    type="text" 
                    placeholder={t.rules.searchRules}
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    className="w-full pl-9 pr-4 py-1.5 bg-white border border-[#E1E1E1] rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-black/5 focus:border-black/20 transition-all"
                />
            </div>
            <div className="text-xs text-gray-400 font-medium">
                {filteredRules.length} {t.rules.rulesCount}
            </div>
        </div>

        <div className="flex-1 overflow-y-auto">
          {filteredRules.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-gray-400 pb-10">
               <div className="w-16 h-16 bg-white border border-[#E1E1E1] rounded-2xl flex items-center justify-center mb-4">
                <Sliders size={32} className="opacity-20 text-black" />
              </div>
              <p>{t.rules.noRules}</p>
            </div>
          ) : (
            <div className="divide-y divide-[#E1E1E1]">
              {filteredRules.map(rule => {
                const targetBrowser = browsers.find(b => b.id === rule.targetBrowserId);
                return (
                  <div key={rule.id} className="px-6 py-4 hover:bg-black/5 transition-colors group flex items-center justify-between">
                    <div className="flex items-center gap-4">
                      {rule.type === RuleType.SOURCE_APP ? (
                          <AppIcon appName={rule.appName || rule.value} size={40} className="rounded-[10px] shrink-0" />
                      ) : (
                          <div className="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 border border-[#E1E1E1] shadow-sm bg-white text-black">
                              <Globe size={18} />
                          </div>
                      )}
                      <div>
                        <div className="flex items-center gap-2 mb-0.5">
                          <span className="text-sm font-semibold text-black">{rule.appName || rule.value}</span>
                        </div>
                        <div className="text-xs text-gray-500 flex items-center gap-1">
                            {rule.type === RuleType.SOURCE_APP ? t.rules.sourceApp : t.rules.urlPattern}
                            <ArrowRight size={10} className="text-gray-300" />
                            <span className="text-gray-700 font-medium">{targetBrowser?.name || 'Unknown'}</span>
                        </div>
                      </div>
                    </div>

                    <button 
                        onClick={() => onDeleteRule(rule.id)}
                        className="p-2 text-gray-300 hover:text-red-500 hover:bg-red-50 rounded-lg transition-all opacity-0 group-hover:opacity-100"
                        aria-label={t.rules.delete}
                    >
                        <Trash2 size={16} />
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default RulesView;
