import React from 'react';
import { ArrowRight, Zap, Trash2, Clock } from 'lucide-react';
import { BrowserApp, HistoryLog } from '../types';
import { getBrowserIcon } from '../constants';
import { getSourceAppDetails } from '../utils/sourceApp';

interface DashboardViewProps {
  history: HistoryLog[];
  browsers: BrowserApp[];
  onClearHistory?: () => void;
}

const DashboardView: React.FC<DashboardViewProps> = ({ history, browsers, onClearHistory }) => {
  const formatTime = (date: Date) => {
    const now = new Date();
    const diff = Math.floor((now.getTime() - new Date(date).getTime()) / 60000);
    if (diff < 1) return 'Just now';
    if (diff < 60) return `${diff}m ago`;
    const hours = Math.floor(diff / 60);
    if (hours < 24) return `${hours}h ago`;
    return '1d ago';
  };

  return (
    <div className="h-full flex flex-col overflow-hidden w-full bg-white">
      {/* Header */}
      <div className="pt-6 pb-6 px-5 flex justify-between items-end">
        <h1 className="text-[25px] font-normal text-black font-['SF_Pro_Display'] leading-tight">History</h1>
        {history.length > 0 && (
           <button 
             onClick={onClearHistory}
             className="text-xs text-gray-400 hover:text-red-500 transition-colors pb-1"
           >
             Clear All
           </button>
        )}
      </div>

      {/* History List */}
      <div className="flex-1 overflow-y-auto px-5 pb-6">
        {history.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center text-gray-400 pb-20">
             <Clock size={32} className="opacity-20 mb-3" />
             <p className="text-sm opacity-50">No history yet</p>
          </div>
        ) : (
          <div className="space-y-[7px]">
            {history.map((log) => {
              const targetBrowser = browsers.find(b => b.id === log.routedToBrowserId);
              const sourceAppDetails = getSourceAppDetails(log.sourceApp);

              return (
                <div key={log.id} className="flex items-center gap-[7px] group">
                  {/* Main Info Pill */}
                  <div className="flex-1 h-[40px] bg-[#F8F8F8] border border-[#E1E1E1] rounded-[10px] flex items-center px-4 min-w-0">
                    {/* Source */}
                    <div className="flex items-center gap-2 min-w-[80px] shrink-0">
                       <div className="w-4 h-4 flex items-center justify-center">
                          {sourceAppDetails.icon}
                       </div>
                       <span className="text-[12px] font-[590] text-black truncate max-w-[80px]">
                         {sourceAppDetails.name}
                       </span>
                    </div>

                    {/* Arrow */}
                    <div className="flex items-center justify-center px-3 text-gray-300">
                       <ArrowRight size={12} strokeWidth={2} />
                    </div>

                    {/* Target */}
                    <div className="flex items-center gap-2 min-w-[80px] shrink-0">
                        <div className="w-4 h-4 flex items-center justify-center">
                            {targetBrowser?.iconDataURL ? (
                            <img src={targetBrowser.iconDataURL} alt={targetBrowser.name} className="w-3.5 h-3.5 object-contain" />
                            ) : (
                            targetBrowser && getBrowserIcon(targetBrowser.type, 3.5)
                            )}
                        </div>
                        <span className="text-[12px] font-[590] text-black truncate max-w-[100px]">
                            {targetBrowser?.name || 'Browser'}
                        </span>
                    </div>
                    
                    {/* URL (Optional, maybe hidden or truncated heavily as per design which doesn't show URL) */}
                    {/* The design doesn't explicitly show the URL, but it might be useful. 
                        I'll hide it to match the clean design or show it very subtly if there is space. 
                        Design shows "Lark -> Chrome", no URL. I will omit URL for fidelity.
                    */}
                    <div className="flex-1"></div>
                    
                    {/* Time */}
                    <span className="text-[9px] text-gray-400 font-medium">
                        {formatTime(log.timestamp)}
                    </span>
                  </div>

                  {/* Delete Button (Separate Pill) */}
                  <button 
                    className="h-[40px] w-[70px] bg-[#F8F8F8] border border-[#E1E1E1] rounded-[10px] flex items-center justify-center hover:bg-[#FFEAEA] hover:border-[#FFD0D0] hover:text-red-500 transition-colors group-hover:opacity-100 opacity-100"
                    // In design it seems always visible, but maybe better on hover? 
                    // Design has it fully opaque. I'll keep it visible.
                  >
                    <span className="text-[12px] font-normal text-black group-hover:text-red-500">删除</span>
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};

export default DashboardView;