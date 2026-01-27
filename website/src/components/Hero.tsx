import { motion } from 'framer-motion';
import { Command } from 'lucide-react';

export const Hero = () => {
  return (
    <section className="relative pt-32 pb-20 md:pt-48 md:pb-32 overflow-hidden px-4 md:px-6">
      {/* Background Blobs - Optimized for Mobile */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full -z-10 opacity-40 pointer-events-none overflow-hidden">
        <div className="absolute top-[-10%] left-[10%] w-[300px] md:w-[500px] h-[300px] md:h-[500px] bg-neutral-200/50 rounded-full mix-blend-multiply filter blur-[80px] md:blur-[100px] animate-blob"></div>
        <div className="absolute top-[-10%] right-[10%] w-[300px] md:w-[500px] h-[300px] md:h-[500px] bg-gray-200/50 rounded-full mix-blend-multiply filter blur-[80px] md:blur-[100px] animate-blob animation-delay-2000"></div>
        <div className="absolute bottom-[-20%] left-[20%] w-[300px] md:w-[500px] h-[300px] md:h-[500px] bg-neutral-200/50 rounded-full mix-blend-multiply filter blur-[80px] md:blur-[100px] animate-blob animation-delay-4000"></div>
      </div>

      <div className="container mx-auto max-w-6xl text-center">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
        >
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-neutral-100 text-neutral-800 text-xs font-semibold mb-6 border border-neutral-200">
            <span className="flex h-2 w-2 rounded-full bg-black"></span>
            v1.10.19 Now Available
          </div>
          
          <h1 className="text-4xl sm:text-5xl md:text-7xl font-bold tracking-tight text-neutral-900 mb-6 leading-tight">
            Master Your Links <br className="hidden sm:block" />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-neutral-900 to-neutral-600">
              on macOS
            </span>
          </h1>
          
          <p className="text-lg md:text-xl text-neutral-600 max-w-2xl mx-auto mb-10 leading-relaxed px-4">
            The intelligent browser router for power users. Automatically open links in the right browser based on rules, source apps, and your habits.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-12 md:mb-16">
            <div className="flex items-center gap-4 text-neutral-500 text-sm font-medium bg-white/50 backdrop-blur-sm px-4 py-2 rounded-full border border-neutral-100">
               <span className="flex items-center gap-1"><Command size={14}/> Open Source</span>
               <span className="text-neutral-300">•</span>
               <span>macOS 11.0+</span>
            </div>
          </div>
        </motion.div>

        {/* App Screenshot Mockup - Improved Mobile Aspect Ratio */}
        <motion.div
          initial={{ opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.2 }}
          className="relative max-w-5xl mx-auto"
        >
          <div className="relative">
             <div className="rounded-lg md:rounded-2xl overflow-hidden shadow-2xl border border-neutral-200/60 bg-white flex items-center justify-center relative group">
                {/* Image 1: Main App Window */}
                <img 
                  src="/app-screenshot-main.png" 
                  alt="Prism App Main Window" 
                  className="w-full h-auto object-cover transform group-hover:scale-[1.01] transition-transform duration-700" 
                />
             </div>
             
             {/* Image 2: Floating Selector Popup (Overlay) */}
             <motion.div 
                initial={{ opacity: 0, y: 20, scale: 0.95 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                transition={{ duration: 0.6, delay: 0.8 }}
                className="absolute bottom-[5%] right-[-5%] w-[45%] md:w-[40%] rounded-xl md:rounded-2xl overflow-hidden shadow-2xl border border-neutral-200/60 bg-white"
             >
                <img 
                  src="/app-screenshot-popup.png" 
                  alt="Prism Browser Selector" 
                  className="w-full h-auto object-cover" 
                />
             </motion.div>
          </div>
        </motion.div>
      </div>
    </section>
  );
};
