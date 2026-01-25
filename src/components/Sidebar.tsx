
import React from 'react';
import { LayoutDashboard, Settings, GitFork } from 'lucide-react';
import { useI18n } from '../i18n';

interface SidebarProps {
  activeTab: 'dashboard' | 'rules' | 'settings';
  onTabChange: (tab: 'dashboard' | 'rules' | 'settings') => void;
}

const Sidebar: React.FC<SidebarProps> = ({ activeTab, onTabChange }) => {
  const { t } = useI18n();
  
  const menuItems = [
    { id: 'dashboard', icon: LayoutDashboard, label: t.nav.dashboard },
    { id: 'rules', icon: GitFork, label: t.nav.rules },
    { id: 'settings', icon: Settings, label: t.nav.settings },
  ] as const;

  return (
    <div className="w-[107px] bg-[#F8F8F8] border-r border-[#E5E5E5] h-full flex flex-col items-center py-4 shrink-0">
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
      <nav className="flex-1 w-full px-[15px] space-y-4 flex flex-col items-center z-50">
        {menuItems.map((item) => {
          const Icon = item.icon;
          const isItemActive = item.id === activeTab;

          return (
            <button
              key={item.id}
              onClick={() => onTabChange(item.id)}
              className={`
                flex flex-col items-center gap-1.5 p-2 rounded-[5px] w-[77px] transition-all duration-200 no-drag-region group focus:outline-none
                ${isItemActive 
                  ? 'bg-transparent border border-[#E1E1E1] shadow-sm' 
                  : 'bg-transparent border border-transparent hover:bg-gray-200/50 active:scale-95 active:bg-gray-200'}
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
