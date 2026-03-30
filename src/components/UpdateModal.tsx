import React from 'react';
import { X, Download, Clock } from 'lucide-react';
import { UpdateInfo } from '../utils/updater';

interface UpdateModalProps {
  updateInfo: UpdateInfo;
  onClose: () => void;
  onUpdate: () => void;
  isDownloading?: boolean;
}

const UpdateModal: React.FC<UpdateModalProps> = ({ updateInfo, onClose, onUpdate, isDownloading = false }) => {
  // Convert markdown-like release notes to simple text/paragraphs
  // For a robust implementation, use a markdown parser library. 
  // Here we do a simple split by newline for safety and speed.
  const notes = updateInfo.releaseNotes.split('\n').filter(line => line.trim() !== '');

  const formatSize = (bytes: number) => {
    if (bytes === 0) return 'Unknown size';
    const mb = bytes / (1024 * 1024);
    return `${mb.toFixed(1)} MB`;
  };

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/20 backdrop-blur-sm p-4">
      <div className="w-[400px] bg-white rounded-xl shadow-2xl border border-gray-100 overflow-hidden flex flex-col max-h-[80vh]">
        {/* Header */}
        <div className="bg-[#F8F8F8] px-5 py-4 border-b border-gray-100 flex justify-between items-center">
          <div>
            <h3 className="text-lg font-semibold text-black">New Version Available</h3>
            <p className="text-xs text-gray-500 mt-0.5">
              v{updateInfo.latestVersion} • {formatSize(updateInfo.downloadSize)}
            </p>
          </div>
          <button 
            onClick={onClose}
            className="p-1.5 hover:bg-gray-200 rounded-md transition-colors text-gray-500"
          >
            <X size={18} />
          </button>
        </div>

        {/* Content */}
        <div className="p-5 overflow-y-auto flex-1">
          <h4 className="text-sm font-medium text-gray-900 mb-2">Release Notes</h4>
          <div className="text-sm text-gray-600 space-y-1.5 leading-relaxed">
            {notes.map((line, i) => (
              <p key={i} className="break-words">
                {line.startsWith('-') || line.startsWith('*') ? (
                  <span className="flex gap-2">
                    <span className="text-gray-400">•</span>
                    <span>{line.replace(/^[-*]\s*/, '')}</span>
                  </span>
                ) : (
                  line
                )}
              </p>
            ))}
          </div>
        </div>

        {/* Footer */}
        <div className="p-4 bg-gray-50 border-t border-gray-100 flex gap-3">
          <button
            onClick={onClose}
            className="flex-1 px-4 py-2.5 bg-white border border-gray-200 text-gray-700 rounded-lg text-sm font-medium hover:bg-gray-50 transition-colors flex items-center justify-center gap-2"
          >
            <Clock size={16} />
            Remind Me Later
          </button>
          <button
            onClick={onUpdate}
            disabled={isDownloading}
            className="flex-1 px-4 py-2.5 bg-black text-white rounded-lg text-sm font-medium hover:bg-gray-800 transition-colors shadow-sm flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-wait"
          >
            <Download size={16} />
            {isDownloading ? 'Downloading...' : 'Update Now'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default UpdateModal;
