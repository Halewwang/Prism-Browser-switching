import React from 'react';
import { ArrowRight, Clock, History } from 'lucide-react';
import { BrowserApp, HistoryLog } from '../types';
import { getSourceAppDetails } from '../utils/sourceApp';
import { useI18n } from '../i18n';

interface DashboardViewProps {
  history: HistoryLog[];
  browsers: BrowserApp[];
  onClearHistory?: () => void;
}

const DashboardView: React.FC<DashboardViewProps> = ({ history, browsers, onClearHistory }) => {
  const { t } = useI18n();

  const formatTime = (date: Date) => {
    const now = new Date();
    const diff = Math.floor((now.getTime() - new Date(date).getTime()) / 60000);
    if (diff < 1) return t.dashboard.justNow;
    if (diff < 60) return `${diff}m ${t.dashboard.ago}`;
    const hours = Math.floor(diff / 60);
    if (hours < 24) return `${hours}h ${t.dashboard.ago}`;
    return `1d ${t.dashboard.ago}`;
  };

  return (
    <div className="h-full flex flex-col max-w-5xl mx-auto w-full">
      {/* Main Card */}
      <div className="bg-[#F8F8F8] border border-[#E1E1E1] rounded-[15px] flex flex-col overflow-hidden animate-in fade-in slide-in-from-bottom-4 duration-300 h-full p-6">
        
        {/* Header */}
        <div className="flex items-center gap-2 mb-4 pb-4 border-b border-[#E1E1E1]">
           <History size={18} className="text-gray-600" />
           <h3 className="text-lg font-semibold text-gray-900">{t.dashboard.history}</h3>
           {history.length > 0 && (
             <button 
               onClick={onClearHistory}
               className="ml-auto text-xs font-medium text-gray-500 hover:text-red-600 transition-colors px-2 py-1 hover:bg-red-50 rounded-md"
             >
               {t.dashboard.clearAll}
             </button>
           )}
        </div>

        {/* List Content */}
        <div className="flex-1 overflow-y-auto p-0">
          {history.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-gray-400 pb-20">
               <div className="w-16 h-16 bg-white border border-[#E1E1E1] rounded-2xl flex items-center justify-center mb-4 shadow-sm">
                 <Clock size={32} className="opacity-20 text-black" />
               </div>
               <p className="text-sm font-medium opacity-60">{t.dashboard.noHistory}</p>
            </div>
          ) : (
            <div className="divide-y divide-[#E1E1E1]">
              {history.map((log) => {
                const targetBrowser = browsers.find(b => b.id === log.routedToBrowserId);
                const sourceAppDetails = getSourceAppDetails(log.sourceApp || 'Unknown', log.sourceAppIcon);
                
                return (
                  <div key={log.id} className="px-6 py-4 hover:bg-white transition-colors flex items-center justify-between group">
                    <div className="flex items-center gap-3 overflow-hidden">
                       {/* Simplified Text Layout */}
                       <div className="flex items-center gap-2 text-sm font-medium text-gray-900 truncate">
                          <span className="truncate max-w-[120px]" title={sourceAppDetails.name}>{sourceAppDetails.name}</span>
                          <ArrowRight size={14} className="text-gray-400 shrink-0" />
                          <span className="truncate max-w-[120px]" title={targetBrowser?.name}>{targetBrowser?.name || 'Browser'}</span>
                       </div>
                    </div>

                    <div className="flex items-center gap-4 shrink-0">
                       <span className="text-xs text-gray-400 font-medium whitespace-nowrap">
                          {formatTime(log.timestamp)}
                       </span>
                    </div>
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

export default DashboardView;