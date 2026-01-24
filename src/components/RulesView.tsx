import React, { useState } from 'react';
import { BrowserApp, RoutingRule, RuleType } from '../types';
import { Trash2, Plus, AppWindow, Globe, ArrowRight, Search } from 'lucide-react';
import { getBrowserIcon } from '../constants';

interface RulesViewProps {
  rules: RoutingRule[];
  browsers: BrowserApp[];
  installedIMApps: Array<{ id: string; name: string; path: string }>;
  onAddRule: (rule: RoutingRule) => void;
  onDeleteRule: (id: string) => void;
}

const RulesView: React.FC<RulesViewProps> = ({ rules, browsers, installedIMApps, onAddRule, onDeleteRule }) => {
  const [newType, setNewType] = useState<RuleType>(RuleType.SOURCE_APP);
  const [newValue, setNewValue] = useState('');
  const [newTargetId, setNewTargetId] = useState(browsers[0]?.id || '');
  const [searchTerm, setSearchTerm] = useState('');

  const handleAdd = () => {
    if (!newValue || !newTargetId) return;
    const newRule: RoutingRule = {
      id: Date.now().toString(),
      type: newType,
      value: newValue,
      targetBrowserId: newTargetId,
      active: true,
      description: '用户自定义规则'
    };
    onAddRule(newRule);
    setNewValue('');
  };

  const filteredRules = rules.filter(r => 
    r.value.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="h-full flex flex-col">
      {/* Search Bar */}
      <div className="mb-6">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={18} />
          <input 
            type="text" 
            placeholder="搜索已有规则..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2.5 bg-white border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
          />
        </div>
      </div>

      {/* Add Rule Form */}
      <div className="bg-white border border-gray-200 rounded-lg shadow-sm mb-6 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">添加路由规则</h3>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">路由触发条件</label>
            <div className="flex bg-gray-50 p-1 rounded-md border border-gray-200">
              <button
                onClick={() => setNewType(RuleType.SOURCE_APP)}
                className={`flex-1 py-2 px-3 rounded-md text-sm font-medium transition-all ${newType === RuleType.SOURCE_APP ? 'bg-white text-blue-700 border border-blue-200 shadow-sm' : 'text-gray-600 hover:bg-gray-100'}`}
              >
                来源应用
              </button>
              <button
                onClick={() => setNewType(RuleType.URL_PATTERN)}
                className={`flex-1 py-2 px-3 rounded-md text-sm font-medium transition-all ${newType === RuleType.URL_PATTERN ? 'bg-white text-blue-700 border border-blue-200 shadow-sm' : 'text-gray-600 hover:bg-gray-100'}`}
              >
                URL 匹配
              </button>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              {newType === RuleType.SOURCE_APP ? 'App 名称' : 
               newType === RuleType.URL_PATTERN ? 'URL 关键字' : '规则值'}
            </label>
            {newType === RuleType.SOURCE_APP ? (
              <select
                value={newValue}
                onChange={(e) => setNewValue(e.target.value)}
                className="w-full px-4 py-2.5 bg-white border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all appearance-none cursor-pointer"
              >
                <option value="">选择应用</option>
                {installedIMApps.map(app => (
                  <option key={app.id} value={app.name}>{app.name}</option>
                ))}
                <option value="">--- 手动输入 ---</option>
              </select>
            ) : (
              <input
                type="text"
                value={newValue}
                onChange={(e) => setNewValue(e.target.value)}
                placeholder="例如: google.com"
                className="w-full px-4 py-2.5 bg-white border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
              />
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">目标浏览器</label>
            <select
              value={newTargetId}
              onChange={(e) => setNewTargetId(e.target.value)}
              className="w-full px-4 py-2.5 bg-white border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all appearance-none cursor-pointer"
            >
              {browsers.map(b => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
          </div>

          <div className="flex items-end justify-end">
            <button
              onClick={handleAdd}
              disabled={!newValue}
              className="px-6 py-2.5 bg-blue-600 text-white rounded-lg font-semibold hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-all flex items-center gap-2"
            >
              <Plus size={16} /> 添加规则
            </button>
          </div>
        </div>
      </div>

      {/* Rules List */}
      <div className="flex-1 overflow-y-auto">
        {filteredRules.length === 0 ? (
          <div className="bg-white border border-gray-200 rounded-lg shadow-sm p-8 text-center">
            <p className="text-gray-500">暂无路由规则</p>
            <p className="text-sm text-gray-400 mt-2">添加第一条规则来自动化你的工作流</p>
          </div>
        ) : (
          <div className="bg-white border border-gray-200 rounded-lg shadow-sm overflow-hidden">
            <div className="divide-y divide-gray-100">
              {filteredRules.map(rule => {
                const targetBrowser = browsers.find(b => b.id === rule.targetBrowserId);
                return (
                  <div key={rule.id} className="p-4 hover:bg-gray-50 transition-colors">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-4">
                        <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${rule.type === RuleType.SOURCE_APP ? 'bg-indigo-50 text-indigo-600' : 
                                                                           rule.type === RuleType.URL_PATTERN ? 'bg-orange-50 text-orange-600' : 
                                                                           'bg-gray-50 text-gray-600'}`}>
                          {rule.type === RuleType.SOURCE_APP ? <AppWindow size={20} /> : 
                           rule.type === RuleType.URL_PATTERN ? <Globe size={20} /> : 
                           <Globe size={20} />}
                        </div>
                        <div>
                          <div className="flex items-center gap-2 mb-1">
                            <span className="text-sm font-semibold text-gray-900">{rule.value}</span>
                            <span className="text-xs text-gray-500">
                              {rule.type === RuleType.SOURCE_APP ? '来源应用' : 
                               rule.type === RuleType.URL_PATTERN ? 'URL 匹配' : '自定义规则'}
                            </span>
                          </div>
                        </div>
                      </div>

                      <div className="flex items-center gap-3">
                        <div className="flex items-center gap-2 px-3 py-1.5 bg-gray-100 rounded-lg">
                          {targetBrowser && getBrowserIcon(targetBrowser.type, 4)}
                          <span className="text-sm font-medium text-gray-700">{targetBrowser?.name}</span>
                        </div>
                        <button 
                          onClick={() => onDeleteRule(rule.id)}
                          className="p-2 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-all"
                          aria-label="删除规则"
                        >
                          <Trash2 size={18} />
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default RulesView;