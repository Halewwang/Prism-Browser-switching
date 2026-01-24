
import React from 'react';
import { Activity, Clock, ArrowRight, Bot, Sliders, MousePointer2, Zap, LayoutGrid, Trash2 } from 'lucide-react';
import { BrowserApp, HistoryLog } from '../types';
import { getBrowserIcon, APP_ICONS } from '../constants';

interface DashboardViewProps {
  history: HistoryLog[];
  browsers: BrowserApp[];
  onClearHistory?: () => void;
}

const DashboardView: React.FC<DashboardViewProps> = ({ history, browsers, onClearHistory }) => {
  const getMethodBadge = (method: string) => {
    switch(method) {
      case 'AI': return <span className="flex items-center gap-1 text-xs font-medium text-blue-600 bg-blue-50 px-2 py-0.5 rounded-md border border-blue-200"><Bot size={10} /> AI</span>;
      case 'Rule': return <span className="flex items-center gap-1 text-xs font-medium text-indigo-600 bg-indigo-50 px-2 py-0.5 rounded-md border border-indigo-200"><Sliders size={10} /> 规则</span>;
      default: return <span className="flex items-center gap-1 text-xs font-medium text-gray-600 bg-gray-50 px-2 py-0.5 rounded-md border border-gray-200">手动</span>;
    }
  };

  const formatTime = (date: Date) => {
    const diff = Math.floor((new Date().getTime() - date.getTime()) / 60000);
    if (diff < 1) return 'JUST NOW';
    if (diff < 60) return `${diff}M AGO`;
    return `${Math.floor(diff / 60)}H AGO`;
  };

  return (
    <div className="h-full flex flex-col bg-white overflow-hidden">

      {/* History Section */}
      <div className="flex-1 bg-white border border-gray-200 rounded-lg shadow-sm overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
          <div className="flex items-center gap-2">
            <Clock className="w-5 h-5 text-gray-500" />
            <span className="text-sm font-semibold text-gray-900">最近路由历史</span>
          </div>
          <button 
            className="text-sm font-medium text-red-600 hover:text-red-700 flex items-center gap-1"
            onClick={onClearHistory}
          >
            <Trash2 size={14} />
            清除记录
          </button>
        </div>

        <div className="flex-1 overflow-y-auto">
          {history.length === 0 ? (
            <div className="p-12 text-center text-gray-500">
              <p>暂无路由历史记录</p>
            </div>
          ) : (
            <div className="divide-y divide-gray-100">
              {history.map((log) => {
                const targetBrowser = browsers.find(b => b.id === log.routedToBrowserId);
                return (
                  <div key={log.id} className="px-6 py-4 flex items-center gap-4 hover:bg-gray-50 transition-colors">
                    <div className="w-10 h-10 rounded-lg bg-white border border-gray-200 flex items-center justify-center shrink-0">
                      {log.sourceApp && APP_ICONS[log.sourceApp] ? APP_ICONS[log.sourceApp] : <Zap size={16} className="text-gray-300" />}
                    </div>
                    
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-3 mb-1">
                        <span className="text-sm font-medium text-gray-900">{log.sourceApp || '外部应用'}</span>
                        <span className="text-xs text-gray-500">{formatTime(log.timestamp)}</span>
                      </div>
                      <div className="text-sm text-gray-500 truncate max-w-full">
                        {log.url}
                      </div>
                    </div>

                    <div className="flex items-center gap-4 shrink-0">
                      {getMethodBadge(log.method)}
                      <ArrowRight size={14} className="text-gray-400" />
                      <div className="flex items-center gap-2 px-3 py-1.5 bg-white border border-gray-200 rounded-lg">
                        {targetBrowser && getBrowserIcon(targetBrowser.type, 4)}
                        <span className="text-sm font-medium text-gray-700">{targetBrowser?.name}</span>
                      </div>
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
