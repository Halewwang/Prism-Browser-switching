
import React, { useEffect, useState } from 'react';
import { BrowserApp } from '../types';
import { getSourceAppDetails } from '../utils/sourceApp';

interface SelectorPopupProps {
  url: string;
  sourceApp?: string;
  sourceAppIcon?: string;
  browsers: BrowserApp[];
  onSelect: (browserId: string, remember: boolean) => void;
  onCancel: () => void;
  isStandalone?: boolean;
}

const SelectorPopup: React.FC<SelectorPopupProps> = ({ url, sourceApp, sourceAppIcon, browsers, onSelect, onCancel }) => {
  const [highlightedIndex, setHighlightedIndex] = useState<number>(0);
  const [imageErrors, setImageErrors] = useState<Record<string, boolean>>({});

  const sourceAppDetails = getSourceAppDetails(sourceApp || '', sourceAppIcon);
  const displayIcon = sourceAppDetails.icon;

  const handleImageError = (browserId: string) => {
    setImageErrors(prev => ({ ...prev, [browserId]: true }));
  };

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') {
        setHighlightedIndex(prev => (prev + 1) % browsers.length);
      } else if (e.key === 'ArrowLeft') {
        setHighlightedIndex(prev => (prev - 1 + browsers.length) % browsers.length);
      } else if (e.key === 'Enter') {
        onSelect(browsers[highlightedIndex].id, false);
      } else if (e.key === 'Escape') {
        onCancel();
      } else if (!isNaN(Number(e.key)) && Number(e.key) > 0 && Number(e.key) <= browsers.length) {
        onSelect(browsers[Number(e.key) - 1].id, false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [browsers, highlightedIndex, onSelect, onCancel]);

  return (
    <div className="w-[425px] h-[200px] bg-white rounded-[15px] shadow-[0px_3px_18.5px_-3px_rgba(0,0,0,0.25)] flex flex-col overflow-hidden select-none font-sans relative">
      
      {/* Top Header Bar */}
      <div className="flex gap-[7px] p-[7px] h-[54px] w-full box-border">
        {/* Source App */}
        <div className="w-[75px] h-[40px] bg-[#F8F8F8] border border-[#E1E1E1] rounded-[10px] flex items-center justify-center gap-1.5 shrink-0">
          <div className="w-[14px] h-[14px] text-black flex items-center justify-center">
             {displayIcon}
          </div>
          <span className="text-[12px] font-[590] text-black truncate max-w-[40px] leading-tight font-sans">
            {sourceAppDetails.name}
          </span>
        </div>

        {/* URL Display */}
        <div className="flex-1 h-[40px] bg-[#F8F8F8] border border-[#E1E1E1] rounded-[10px] flex items-center px-3 overflow-hidden">
          <span className="text-[12px] text-[#5C5C5C] truncate w-full font-normal leading-tight font-sans">
            {url}
          </span>
        </div>

        {/* Cancel Button */}
        <div 
          onClick={onCancel}
          className="w-[79px] h-[40px] bg-[#F8F8F8] border border-[#E1E1E1] rounded-[10px] flex items-center justify-center cursor-pointer hover:bg-[#F0F0F0] active:bg-[#E8E8E8] transition-colors shrink-0"
        >
          <span className="text-[12px] text-black font-normal font-sans">Cancel</span>
        </div>
      </div>

      {/* Browser Selection Area */}
      <div className="mx-[7px] mb-[7px] flex-1 bg-[#F8F8F8] rounded-[10px] relative overflow-hidden flex items-center justify-center">
        <div className="flex items-center justify-start max-w-full h-full px-2 gap-2 overflow-x-auto no-scrollbar">
          {browsers.map((browser, idx) => {
            const isSelected = idx === highlightedIndex;
            const initial = browser.name.charAt(0).toUpperCase();
            
            return (
              <div
                key={browser.id}
                onClick={() => onSelect(browser.id, false)}
                onMouseEnter={() => setHighlightedIndex(idx)}
                className={`
                  relative w-[130px] h-[130px] rounded-[10px] flex flex-col items-center justify-center shrink-0 cursor-pointer transition-all duration-200
                  ${isSelected ? 'bg-[#EEEEEE] border border-[#E1E1E1]' : 'bg-transparent border border-transparent hover:bg-[#F0F0F0]'}
                `}
              >
                {/* Icon */}
                <div className="w-[45px] h-[45px] mb-2 flex items-center justify-center">
                  {browser.iconDataURL && !imageErrors[browser.id] ? (
                    <img 
                      src={browser.iconDataURL} 
                      alt={browser.name} 
                      className="w-full h-full object-contain drop-shadow-sm" 
                      onError={() => handleImageError(browser.id)}
                    />
                  ) : (
                    <div className="w-full h-full bg-slate-200 rounded-xl flex items-center justify-center">
                       <span className="text-slate-500 font-bold text-xl">{initial}</span>
                    </div>
                  )}
                </div>

                {/* Name */}
                <span className="text-[12px] font-[590] text-black mb-2 font-sans">
                  {browser.name}
                </span>

                {/* Shortcut Key Hint */}
                <div className="w-[20px] h-[20px] bg-white border border-[#E1E1E1] rounded-[5px] flex items-center justify-center shadow-sm mt-1">
                  <span className="text-[10px] text-[#5C5C5C] font-normal font-mono leading-none">
                    {idx + 1}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

export default SelectorPopup;
