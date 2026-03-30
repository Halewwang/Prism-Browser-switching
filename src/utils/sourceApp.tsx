import React from 'react';
import { AppWindow } from 'lucide-react';
import { resolveIcon } from './iconResolver';

interface AppDetails {
  name: string;
  icon: React.ReactNode;
}

export const getSourceAppDetails = (sourceApp: string, iconDataURL?: string, bundleId?: string): AppDetails => {
  // Normalize the source app name
  // Remove .app extension and trim
  const normalized = (sourceApp || '').replace(/\.app$/i, '').trim();
  
  const iconClass = "w-full h-full object-contain rounded-md";
  const resolvedIcon = resolveIcon({ appName: normalized, bundleId, iconDataURL });

  // Use dynamic icon if available
  if (resolvedIcon.src) {
      return {
          name: normalized || 'Unknown App',
          icon: <img src={resolvedIcon.src} alt={normalized} className={iconClass} />
      };
  }

  // Default fallback if no icon provided
  return {
    name: normalized || 'External Link',
    icon: <div className="w-full h-full bg-gray-100 rounded-md flex items-center justify-center">
            <AppWindow size={14} className="text-gray-500" />
          </div>
  };
};
