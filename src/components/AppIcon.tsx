import React from 'react';

interface AppIconProps {
  appName: string;
  className?: string;
  size?: number;
}

const AppIcon: React.FC<AppIconProps> = ({ appName, className = '', size = 16 }) => {
  const letter = appName ? appName.charAt(0).toUpperCase() : '?';
  
  return (
    <div 
      className={`flex items-center justify-center bg-[#F2F3F5] text-gray-700 font-medium rounded-[6px] select-none ${className}`}
      style={{ width: size, height: size, fontSize: size * 0.6 }}
    >
      {letter}
    </div>
  );
};

export default AppIcon;
