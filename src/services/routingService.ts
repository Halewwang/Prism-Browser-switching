import { BrowserApp, RoutingRule, RuleType } from '../types';
import { PrismApi } from '../utils/prism';

// 路由服务：纯业务逻辑
export const RoutingService = {
  // 核心路由匹配逻辑
  matchRule: (
    url: string, 
    source: string, 
    sourceBundleId: string | undefined, 
    rules: RoutingRule[]
  ): RoutingRule | null => {
    // 规范化sourceApp名称
    const normalizedSource = source.replace(/\.app$/i, '').trim().toLowerCase();
    // 规范化URL
    const normalizedUrl = url.toLowerCase();
    
    // 1. 优先检查 URL 规则 (精确度更高)
    const matchedUrlRule = rules.find(rule => {
      if (!rule.active || rule.type !== RuleType.URL_PATTERN) return false;
      const ruleValue = rule.value.trim().toLowerCase();
      // 支持简单的通配符匹配或包含匹配
      return ruleValue && normalizedUrl.includes(ruleValue);
    });
    
    if (matchedUrlRule) return matchedUrlRule;
    
    // 2. 如果没有 URL 规则，检查来源应用规则
    const matchedSourceRule = rules.find(rule => {
      if (!rule.active || rule.type !== RuleType.SOURCE_APP) return false;
      
      // Check Bundle ID match first (Exact match)
      if (sourceBundleId && rule.value === sourceBundleId) {
          return true;
      }

      // Fallback to legacy name matching
      const ruleValue = rule.value.replace(/\.app$/i, '').trim().toLowerCase();
      // 来源匹配逻辑：检查包含关系
      if (ruleValue.includes('.')) {
           // Treat as bundle ID, so strict equality
           return sourceBundleId === rule.value;
      }
      return normalizedSource && ruleValue && normalizedSource.includes(ruleValue);
    });

    return matchedSourceRule || null;
  },

  // 执行路由跳转
  executeRouting: (
    url: string,
    targetBrowserId: string,
    browsers: BrowserApp[],
    prism: PrismApi | null
  ): boolean => {
    const targetBrowser = browsers.find(b => b.id === targetBrowserId);
    if (targetBrowser && targetBrowser.path && prism) {
      prism.send('open-in-browser', { url, browserPath: targetBrowser.path });
      return true;
    }
    return false;
  }
};
