import { useState, useEffect } from 'react';
import { Download } from 'lucide-react';

export const Header = () => {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 20);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <header 
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled ? 'bg-white/70 backdrop-blur-md shadow-sm py-3' : 'bg-transparent py-5'
      }`}
    >
      <div className="container mx-auto px-6 flex items-center justify-between">
        <div className="flex items-center gap-2">
          {/* Logo Placeholder */}
          <div className="w-8 h-8 bg-gradient-to-br from-gray-800 to-black rounded-lg shadow-md flex items-center justify-center text-white font-bold text-sm overflow-hidden">
             <img src="/app-icon.png" alt="Prism Logo" className="w-full h-full object-cover" />
          </div>
          <span className="text-xl font-semibold tracking-tight text-neutral-900">Prism</span>
        </div>

        <nav className="hidden md:flex items-center gap-8 text-sm font-medium text-neutral-600">
          <a href="#features" className="hover:text-primary transition-colors">Features</a>
          <a href="#how-it-works" className="hover:text-primary transition-colors">How it Works</a>
          <a href="#new-features" className="hover:text-primary transition-colors">What's New</a>
        </nav>

        <a 
          href="https://github.com/Prism/LinkMaster/releases/latest/download/Prism-1.10.19-arm64.dmg"
          className="flex items-center gap-2 bg-neutral-900 text-white px-4 py-2 rounded-full text-sm font-medium hover:bg-neutral-800 transition-all shadow-lg hover:shadow-xl transform hover:-translate-y-0.5"
        >
          <Download size={16} />
          Download
        </a>
      </div>
    </header>
  );
};
