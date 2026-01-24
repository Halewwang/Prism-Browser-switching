
import React from 'react';
import { AppView } from '../types';
import { LayoutGrid, Shuffle, SlidersHorizontal, PlayCircle, Zap } from 'lucide-react';

interface SidebarProps {
  currentView: AppView;
  onChangeView: (view: AppView) => void;
}

const Sidebar: React.FC<SidebarProps> = ({ currentView, onChangeView }) => {
  const menuItems = [
    { id: AppView.RULES, label: '规则', icon: Shuffle },
    { id: AppView.SETTINGS, label: '设置', icon: SlidersHorizontal },
  ];

  return (
    <div className="w-64 bg-gray-50 border-r border-gray-200 h-full flex flex-col pt-6 pb-6 overflow-hidden">
      {/* Brand Section */}
      <div className="px-6 mb-8 flex items-center gap-3">
        <div className="w-8 h-8 bg-gray-900 rounded-lg flex items-center justify-center">
          <Zap className="text-white w-5 h-5" fill="currentColor" />
        </div>
        <div className="flex flex-col">
          <span className="text-sm font-semibold text-gray-900 leading-none">LinkMaster</span>
          <span className="text-xs text-gray-500 mt-0.5">Utility Pro</span>
        </div>
      </div>

      {/* Navigation Menu */}
      <nav className="flex-1 px-3 space-y-1 overflow-y-auto">
        {menuItems.map((item) => {
          const Icon = item.icon;
          const isActive = currentView === item.id;
          return (
            <button
              key={item.id}
              onClick={() => onChangeView(item.id)}
              className={`
                w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all duration-200
                ${isActive 
                  ? 'bg-blue-50 text-blue-700 border border-blue-200' 
                  : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'}
              `}
            >
              <Icon size={16} className={isActive ? 'text-blue-600' : 'text-gray-500'} />
              {item.label}
            </button>
          );
        })}
      </nav>
    </div>
  );
};

export default Sidebar;
