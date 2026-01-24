import React, { useState } from 'react';
import { BrowserApp, RoutingRule } from '../types';
import { Cpu, ListFilter, Info } from 'lucide-react';
import RulesView from './RulesView';

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
                  <span className="text-sm font-medium text-gray-900">1.2.5</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-sm text-gray-500">Build Version</span>
                  <span className="text-sm font-medium text-gray-900">9021</span>
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