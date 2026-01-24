
import React, { useEffect, useState } from 'react';
import { BrowserApp } from '../types';
import { X } from 'lucide-react';

interface SelectorPopupProps {
  url: string;
  sourceApp?: string;
  browsers: BrowserApp[];
  onSelect: (browserId: string, remember: boolean) => void;
  onCancel: () => void;
  isStandalone?: boolean;
}

const SelectorPopup: React.FC<SelectorPopupProps> = ({ url, sourceApp, browsers, onSelect, onCancel, isStandalone = false }) => {
  const [highlightedIndex, setHighlightedIndex] = useState<number>(0);
  const [rememberChoice, setRememberChoice] = useState(false);
  const [imageErrors, setImageErrors] = useState<Record<string, boolean>>({});

  const handleImageError = (browserId: string) => {
    setImageErrors(prev => ({ ...prev, [browserId]: true }));
  };

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
        setHighlightedIndex(prev => (prev + 1) % browsers.length);
      } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
        setHighlightedIndex(prev => (prev - 1 + browsers.length) % browsers.length);
      } else if (e.key === 'Enter') {
        onSelect(browsers[highlightedIndex].id, rememberChoice);
      } else if (e.key === 'Escape') {
        onCancel();
      } else if (!isNaN(Number(e.key)) && Number(e.key) > 0 && Number(e.key) <= browsers.length) {
        onSelect(browsers[Number(e.key) - 1].id, rememberChoice);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [browsers, highlightedIndex, onSelect, onCancel, rememberChoice]);

  return (
    <div className="flex flex-col items-center justify-center p-8 bg-white/70 backdrop-blur-2xl select-none animate-in zoom-in duration-200 overflow-hidden rounded-3xl border border-white/20">
      {/* Source App Name */}
      <div className="mb-8 text-center">
        <div className="text-sm font-medium text-slate-500 tracking-wide uppercase">
          {sourceApp || 'Open Link With'}
        </div>
      </div>

      {/* Browser Items */}
      <div className="flex items-center justify-center gap-8 w-full overflow-x-auto px-4 pb-4 no-scrollbar">
        {browsers.map((browser, idx) => {
          const isSelected = idx === highlightedIndex;
          const initial = browser.name.charAt(0).toUpperCase();
          let bgColor = 'bg-slate-500';
          
          switch (browser.type) {
            case 'arc': bgColor = 'bg-gradient-to-br from-[#FF9696] to-[#FF4D4D]'; break; // Pinkish Red
            case 'safari': bgColor = 'bg-gradient-to-br from-[#4D94FF] to-[#0066CC]'; break; // Blue
            case 'chrome': bgColor = 'bg-gradient-to-br from-[#FFD166] to-[#FF9900]'; break; // Yellow/Orange
            case 'firefox': bgColor = 'bg-gradient-to-br from-[#FF6B6B] to-[#C92A2A]'; break; // Red
            case 'edge': bgColor = 'bg-gradient-to-br from-[#38D9A9] to-[#087F5B]'; break; // Green/Teal
            case 'brave': bgColor = 'bg-gradient-to-br from-[#FF922B] to-[#E8590C]'; break; // Orange
            case 'comet': bgColor = 'bg-gradient-to-br from-[#868E96] to-[#495057]'; break; // Grey
            default: bgColor = 'bg-gradient-to-br from-[#ADB5BD] to-[#868E96]'; // Light Grey
          }
          
          return (
            <button
              key={browser.id}
              onClick={() => onSelect(browser.id, rememberChoice)}
              onMouseEnter={() => setHighlightedIndex(idx)}
              className="flex flex-col items-center gap-4 group focus:outline-none"
            >
              <div className={`
                w-24 h-24 rounded-2xl flex items-center justify-center transition-all duration-300
                ${!browser.iconDataURL || imageErrors[browser.id] ? bgColor : 'bg-transparent'} 
                ${isSelected ? 'scale-110 shadow-xl ring-4 ring-white/50' : 'scale-100 shadow-sm opacity-90 hover:opacity-100'}
              `}>
                {browser.iconDataURL && !imageErrors[browser.id] ? (
                  <img 
                    src={browser.iconDataURL} 
                    alt={browser.name} 
                    className="w-full h-full object-contain drop-shadow-md rounded-2xl" 
                    onError={() => handleImageError(browser.id)}
                  />
                ) : (
                  <span className="text-white font-bold text-5xl drop-shadow-md">{initial}</span>
                )}
              </div>
              <span className={`text-sm font-medium transition-colors duration-200 ${isSelected ? 'text-slate-800' : 'text-slate-500'}`}>
                {browser.name}
              </span>
            </button>
          );
        })}
      </div>

      {/* Close Button */}
      <button 
        onClick={onCancel} 
        className="mt-6 p-2 rounded-full hover:bg-black/5 text-slate-400 hover:text-slate-600 transition-all active:scale-95"
      >
        <X size={20} />
      </button>
    </div>
  );
};

export default SelectorPopup;
