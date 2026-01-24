import React, { useState } from 'react';
import { ShieldCheck, Cpu } from 'lucide-react';

const SettingsView: React.FC = () => {
  const [autoStart, setAutoStart] = useState(true);
  const [enableAi, setEnableAi] = useState(true);

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
          ${active ? 'bg-blue-600' : 'bg-gray-200'}
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
    <div className="h-full flex flex-col">
      {/* Settings Sections */}
      <div className="space-y-6">
        {/* General Settings */}
        <div className="bg-white border border-gray-200 rounded-lg shadow-sm p-6">
          <div className="flex items-center gap-2 mb-4 pb-4 border-b border-gray-200">
            <Cpu size={18} className="text-gray-600" />
            <h3 className="text-lg font-semibold text-gray-900">系统设置</h3>
          </div>
          
          <div>
            <ToggleSwitch 
              active={autoStart} 
              onClick={() => setAutoStart(!autoStart)} 
              label="开机自动激活服务"
            />
          </div>
        </div>

        {/* AI Settings */}
        <div className="bg-white border border-gray-200 rounded-lg shadow-sm p-6">
          <div className="flex items-center gap-2 mb-4 pb-4 border-b border-gray-200">
            <ShieldCheck size={18} className="text-gray-600" />
            <h3 className="text-lg font-semibold text-gray-900">智能增强</h3>
          </div>
          
          <div>
            <ToggleSwitch 
              active={enableAi} 
              onClick={() => setEnableAi(!enableAi)} 
              label="Gemini 路由语义分析"
            />
            
            {enableAi && (
              <div className="mt-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center">
                    <ShieldCheck size={16} className="text-green-600" />
                  </div>
                  <div>
                    <p className="text-sm font-medium text-gray-900">智能感知服务已连接</p>
                    <p className="text-xs text-gray-500 mt-1">基于 Gemini 技术的智能路由推荐</p>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* About Section */}
        <div className="bg-white border border-gray-200 rounded-lg shadow-sm p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">关于</h3>
          
          <div className="space-y-3">
            <div className="flex justify-between">
              <span className="text-sm text-gray-500">版本</span>
              <span className="text-sm font-medium text-gray-900">1.2.5</span>
            </div>
            <div className="flex justify-between">
              <span className="text-sm text-gray-500">构建号</span>
              <span className="text-sm font-medium text-gray-900">9021</span>
            </div>
            <div className="flex justify-between">
              <span className="text-sm text-gray-500">许可证</span>
              <span className="text-sm font-medium text-gray-900">MIT</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default SettingsView;