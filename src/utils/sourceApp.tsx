import React from 'react';
import { AppWindow } from 'lucide-react';

interface AppDetails {
  name: string;
  icon: React.ReactNode;
}

export const getSourceAppDetails = (sourceApp: string, iconDataURL?: string): AppDetails => {
  // Normalize the source app name
  // Remove .app extension and trim
  const normalized = (sourceApp || '').replace(/\.app$/i, '').trim();
  
  const iconClass = "w-full h-full object-contain rounded-md";

  // Use dynamic icon if available
  if (iconDataURL) {
      return {
          name: normalized || 'Unknown App',
          icon: <img src={iconDataURL} alt={normalized} className={iconClass} />
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
