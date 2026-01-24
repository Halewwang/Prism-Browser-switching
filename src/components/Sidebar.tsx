
import React from 'react';
import { AppView } from '../types';
import { Clock, Settings, Info, Zap } from 'lucide-react';

interface SidebarProps {
  currentView: AppView;
  onChangeView: (view: AppView) => void;
  onClose?: () => void;
  onMinimize?: () => void;
  onMaximize?: () => void;
}

const Sidebar: React.FC<SidebarProps> = ({ currentView, onChangeView, onClose, onMinimize, onMaximize }) => {
  const menuItems = [
    { id: AppView.DASHBOARD, label: '历史记录', icon: Clock },
    { id: AppView.SETTINGS, label: '通用设置', icon: Settings },
  ];

  return (
    <div className="w-[107px] bg-[#F8F8F8] border-r border-[#E5E5E5] h-full flex flex-col items-center py-4 drag-region shrink-0">
      {/* Brand/Logo */}
      <div className="mt-10 mb-8 flex flex-col items-center gap-2 no-drag-region">
        <div className="w-8 h-8 flex items-center justify-center">
            {/* Prism Logo */}
           <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M12 4V20" stroke="black" strokeWidth="3" strokeLinecap="round"/>
              <path d="M4 12H20" stroke="black" strokeWidth="3" strokeLinecap="round"/>
              <path d="M6.34 6.34L17.66 17.66" stroke="black" strokeWidth="3" strokeLinecap="round"/>
              <path d="M6.34 17.66L17.66 6.34" stroke="#4ADE80" strokeWidth="3" strokeLinecap="round"/>
            </svg>
        </div>
        <span className="text-[16px] font-normal text-black font-['SF_Pro_Display'] tracking-tight">Prism</span>
      </div>

      {/* Navigation Menu */}
      <nav className="flex-1 w-full px-[15px] space-y-4 flex flex-col items-center">
        {menuItems.map((item) => {
          const Icon = item.icon;
          // Map ABOUT to Settings for now if clicked, or just visually
          const viewId = item.id === 'ABOUT' as any ? AppView.SETTINGS : item.id;
          const isActive = currentView === viewId && (item.id !== 'ABOUT' as any || currentView === 'ABOUT' as any); // Simplification

          // In the design, History is active. 
          // If we are in Dashboard, History is active.
          // If we are in Settings, General is active.
          
          const isItemActive = (item.id === AppView.DASHBOARD && currentView === AppView.DASHBOARD) ||
                               (item.id === AppView.SETTINGS && currentView === AppView.SETTINGS && item.label === 'GENERAL');

          return (
            <button
              key={item.label}
              onClick={() => onChangeView(item.id === 'ABOUT' as any ? AppView.SETTINGS : item.id)}
              className={`
                flex flex-col items-center gap-1.5 p-2 rounded-[5px] w-[77px] transition-all duration-200 no-drag-region group
                ${isItemActive 
                  ? 'bg-transparent border border-[#E1E1E1] shadow-sm' 
                  : 'bg-transparent border border-transparent hover:bg-gray-200/50'}
              `}
            >
              <div className={`p-1 rounded-md ${isItemActive ? 'bg-transparent' : ''}`}>
                 <Icon size={18} className="text-black stroke-[1.5]" />
              </div>
              <span className="text-[9px] font-medium text-black tracking-wider leading-none">
                {item.label}
              </span>
            </button>
          );
        })}
      </nav>
    </div>
  );
};

export default Sidebar;
