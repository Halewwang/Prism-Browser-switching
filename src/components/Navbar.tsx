import { Menu } from 'lucide-react';
import { Button } from './ui/Button';
import { useState, useEffect } from 'react';
import { clsx } from 'clsx';

export function Navbar() {
  const [isScrolled, setIsScrolled] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 50);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <nav 
      className={clsx(
        "fixed top-0 left-0 w-full z-50 px-6 flex justify-between items-center transition-all duration-500 ease-out",
        isScrolled 
          ? "bg-[#F5F5F3]/90 backdrop-blur-md border-b border-[#1A1A1A]/5 py-4 shadow-sm" 
          : "bg-transparent py-8"
      )}
    >
      <div className="text-2xl font-serif font-bold tracking-widest text-charcoal">
        TREASURY <span className="text-xs font-sans font-normal tracking-[0.3em] ml-2 block sm:inline uppercase">OF TAO</span>
      </div>
      
      <div className="hidden md:flex gap-12 items-center">
        <a href="#concept" className="text-xs uppercase tracking-[0.2em] text-charcoal hover:text-bronze transition-colors font-sans font-medium">Concept</a>
        <a href="#rituals" className="text-xs uppercase tracking-[0.2em] text-charcoal hover:text-bronze transition-colors font-sans font-medium">Rituals</a>
        <a href="#process" className="text-xs uppercase tracking-[0.2em] text-charcoal hover:text-bronze transition-colors font-sans font-medium">Process</a>
        <Button variant="outline" className="!py-2 !px-6 border-charcoal text-xs hover:bg-charcoal hover:text-white transition-colors">Start</Button>
      </div>

      <div className="md:hidden">
        <Menu className="w-6 h-6 text-charcoal" />
      </div>
    </nav>
  );
}
