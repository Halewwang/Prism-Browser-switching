import { Github } from 'lucide-react';
import { release } from '../release';

export const Footer = () => {
  return (
    <footer id="download" className="bg-neutral-900 text-neutral-400 py-12 md:py-20 px-4 md:px-6">
      <div className="container mx-auto max-w-6xl">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-12 mb-12 md:mb-16">
          <div className="col-span-1 lg:col-span-2">
            <div className="flex items-center gap-2 mb-6">
              <div className="w-8 h-8 bg-gradient-to-br from-neutral-800 to-black rounded-lg flex items-center justify-center overflow-hidden">
                <img src="/app-icon.png" alt="Prism Logo" className="w-full h-full object-cover" />
              </div>
              <span className="text-xl font-semibold text-white">Prism</span>
            </div>
            <p className="text-neutral-400 max-w-sm mb-6 text-sm md:text-base">
              A native browser router for macOS. Your rules and history stay on your Mac.
            </p>
            <a href={release.repositoryUrl} aria-label="Prism on GitHub" className="w-10 h-10 rounded-full bg-neutral-800 flex items-center justify-center hover:bg-neutral-700 transition-colors text-white">
              <Github size={20} />
            </a>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-6">Product</h4>
            <ul className="space-y-4 text-sm">
              <li><a href="#features" className="hover:text-white transition-colors">Features</a></li>
              <li><a href="#how-it-works" className="hover:text-white transition-colors">How it Works</a></li>
              <li><a href={release.downloadUrl} className="hover:text-white transition-colors">Download Public Test</a></li>
              <li><a href={release.notesUrl} className="hover:text-white transition-colors">Release &amp; Installation Notes</a></li>
            </ul>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-6">Repository</h4>
            <ul className="space-y-4 text-sm">
              <li><a href={`${release.repositoryUrl}#readme`} className="hover:text-white transition-colors">Documentation</a></li>
              <li><a href={release.issuesUrl} className="hover:text-white transition-colors">Report an Issue</a></li>
              <li><a href={release.checksumsUrl} className="hover:text-white transition-colors">Download Checksum</a></li>
            </ul>
          </div>
        </div>

        <div className="pt-8 border-t border-neutral-800 flex flex-col md:flex-row items-center justify-between gap-4 text-sm text-center">
          <p>&copy; 2026 Prism.</p>
          <p>v{release.version} · {release.minimumSystem} · Universal Public Test</p>
        </div>
      </div>
    </footer>
  );
};
