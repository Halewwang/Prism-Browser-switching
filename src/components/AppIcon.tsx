import React, { useEffect, useState } from 'react';
import { resolveIcon } from '../utils/iconResolver';

interface AppIconProps {
  appName: string;
  bundleId?: string;
  type?: string;
  iconDataURL?: string;
  className?: string;
  size?: number;
}

const AppIcon: React.FC<AppIconProps> = ({
  appName,
  bundleId,
  type,
  iconDataURL,
  className = '',
  size = 16
}) => {
  const [attemptedFallback, setAttemptedFallback] = useState(false);
  const resolved = attemptedFallback
    ? resolveIcon({ appName, bundleId, type })
    : resolveIcon({ appName, bundleId, type, iconDataURL });

  useEffect(() => {
    setAttemptedFallback(false);
  }, [appName, bundleId, type, iconDataURL]);

  if (resolved.src) {
    return (
      <img
        src={resolved.src}
        alt={appName}
        className={`object-contain select-none ${className}`}
        style={{ width: size, height: size }}
        draggable={false}
        onError={() => {
          if (!attemptedFallback) {
            setAttemptedFallback(true);
          }
        }}
      />
    );
  }

  return (
    <div
      className={`flex items-center justify-center bg-[#F2F3F5] text-gray-700 font-medium rounded-[6px] select-none ${className}`}
      style={{ width: size, height: size, fontSize: size * 0.6 }}
    >
      {resolved.letter}
    </div>
  );
};

export default AppIcon;
