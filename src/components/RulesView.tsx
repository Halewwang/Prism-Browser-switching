import React, { useState } from 'react';
import { BrowserApp, RoutingRule, RuleType } from '../types';
import { Trash2, Plus, AppWindow, Globe, Search, ArrowRight, Sliders } from 'lucide-react';
import { getBrowserIcon } from '../constants';
import { useI18n } from '../i18n';

interface RulesViewProps {
  rules: RoutingRule[];
  browsers: BrowserApp[];
  onAddRule: (rule: RoutingRule) => void;
  onDeleteRule: (id: string) => void;
}

const RulesView: React.FC<RulesViewProps> = ({ rules, browsers, onAddRule, onDeleteRule }) => {
  const { t } = useI18n();
  const [newType, setNewType] = useState<RuleType>(RuleType.SOURCE_APP);
  const [newValue, setNewValue] = useState('');
  const [selectedApp, setSelectedApp] = useState<{name: string, bundleId: string, icon: string} | null>(null);
  const [isCustomInput, setIsCustomInput] = useState(false);
  const [newTargetId, setNewTargetId] = useState(browsers[0]?.id || '');
  const [searchTerm, setSearchTerm] = useState('');

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
              }
          } catch (e) {
              console.error("Failed to select app", e);
          }
      }
  };

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
      <div className="bg-[#F8F8F8] border border-[#E1E1E1] rounded-[15px] p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
          <Plus className="w-5 h-5 text-gray-400" />
          {t.rules.addRule}
        </h3>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
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

          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">
              {newType === RuleType.SOURCE_APP ? t.rules.sourceApp : t.rules.urlPattern}
            </label>
            
            {newType === RuleType.SOURCE_APP && !isCustomInput ? (
              <div className="flex gap-2">
                 <button
                    onClick={handleSelectApp}
                    className="flex-1 px-3 py-2 bg-white border border-[#E1E1E1] rounded-lg text-sm text-left flex items-center gap-2 hover:bg-gray-50 transition-colors shadow-sm"
                 >
                    {selectedApp ? (
                        <>
                           {selectedApp.icon ? (
                               <img src={selectedApp.icon} className="w-4 h-4 object-contain" alt="" />
                           ) : (
                               <AppWindow size={16} />
                           )}
                           <span className="truncate font-medium text-black">{selectedApp.name}</span>
                           <span className="text-xs text-gray-400 ml-auto truncate max-w-[100px]">{selectedApp.bundleId}</span>
                        </>
                    ) : (
                        <span className="text-gray-500">{t.rules.selectApp}</span>
                    )}
                 </button>
              </div>
            ) : (
              <div className="relative">
                 <input
                  type="text"
                  value={newValue}
                  onChange={(e) => setNewValue(e.target.value)}
                  placeholder={newType === RuleType.SOURCE_APP ? t.rules.inputApp : t.rules.inputKeyword}
                  className="w-full px-3 py-2 bg-white border border-[#E1E1E1] rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-black/5 focus:border-black/20 transition-all"
                  autoFocus={isCustomInput}
                />
                {isCustomInput && (
                  <button 
                    onClick={() => setIsCustomInput(false)}
                    className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-blue-600 hover:text-blue-700 font-medium"
                  >
                    {t.popup.cancel}
                  </button>
                )}
              </div>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">{t.rules.targetBrowser}</label>
            <div className="relative">
              <select
                value={newTargetId}
                onChange={(e) => setNewTargetId(e.target.value)}
                className="w-full px-3 py-2 pl-9 bg-white border border-[#E1E1E1] rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-black/5 focus:border-black/20 transition-all appearance-none"
              >
                {browsers.map(b => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </select>
              <div className="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none w-4 h-4 flex items-center justify-center">
                 {(() => {
                    const selectedBrowser = browsers.find(b => b.id === newTargetId);
                    if (selectedBrowser?.iconDataURL) {
                        return (
                          <img 
                            src={selectedBrowser.iconDataURL} 
                            alt="" 
                            className="w-full h-full object-contain"
                            onError={(e) => {
                              // Fallback if image fails to load
                              e.currentTarget.style.display = 'none';
                            }} 
                          />
                        );
                    }
                    return selectedBrowser ? getBrowserIcon(selectedBrowser.type, 4) : null;
                 })()}
              </div>
            </div>
          </div>

          <div className="flex items-end justify-end">
            <button
              onClick={handleAdd}
              disabled={!newValue}
              className="w-full md:w-auto px-6 py-2 bg-black text-white rounded-lg text-sm font-medium hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed transition-all flex items-center justify-center gap-2 shadow-sm"
            >
              <Plus size={16} /> {t.rules.addRule}
            </button>
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
                      <div className={`w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 border border-[#E1E1E1] shadow-sm bg-white text-black overflow-hidden`}>
                        {rule.appIcon ? (
                            <img src={rule.appIcon} className="w-full h-full object-contain" alt="" />
                        ) : (
                            rule.type === RuleType.SOURCE_APP ? <AppWindow size={18} /> : <Globe size={18} />
                        )}
                      </div>
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