import { motion } from 'framer-motion';
import { MousePointer2, MoveHorizontal } from 'lucide-react';

export const NewFeatures = () => {
  return (
    <section id="new-features" className="py-16 md:py-24 overflow-hidden px-4 md:px-6">
      <div className="container mx-auto max-w-6xl">
        <div className="mb-12 md:mb-16">
          <span className="text-neutral-600 font-semibold tracking-wider uppercase text-xs md:text-sm">What's New in v1.10.19</span>
          <h2 className="text-2xl md:text-3xl font-bold text-neutral-900 mt-2">Designed for Efficiency</h2>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-16 items-center">
          {/* Feature 1: Mouse Follow */}
          <div className="order-2 lg:order-1 relative">
             <div className="bg-neutral-100 rounded-3xl p-6 md:p-8 aspect-square flex items-center justify-center relative overflow-hidden group">
                {/* Mock Cursor Animation */}
                <motion.div 
                    animate={{ 
                        x: [0, 80, -40, 0],
                        y: [0, -40, 60, 0]
                    }}
                    transition={{ 
                        duration: 8,
                        repeat: Infinity,
                        ease: "easeInOut"
                    }}
                    className="absolute z-20 pointer-events-none"
                >
                    <MousePointer2 className="w-6 h-6 text-neutral-900 fill-white drop-shadow-md" />
                    {/* Popup follows cursor */}
                    <div className="absolute top-8 left-[-100px] w-[180px] md:w-[200px] h-[90px] md:h-[100px] bg-white rounded-xl shadow-xl border border-neutral-200 p-2 opacity-90 scale-90">
                        <div className="w-full h-full bg-neutral-50 rounded-lg animate-pulse"></div>
                    </div>
                </motion.div>
                
                <div className="absolute inset-0 grid grid-cols-6 grid-rows-6 gap-4 opacity-10">
                    {[...Array(36)].map((_, i) => (
                        <div key={i} className="bg-neutral-400 rounded-full w-1 h-1"></div>
                    ))}
                </div>
             </div>
          </div>
          
          <div className="order-1 lg:order-2">
            <div className="w-10 h-10 md:w-12 md:h-12 bg-neutral-100 rounded-xl flex items-center justify-center text-neutral-800 mb-4 md:mb-6">
                <MousePointer2 className="w-5 h-5 md:w-6 md:h-6" />
            </div>
            <h3 className="text-xl md:text-2xl font-bold text-neutral-900 mb-3 md:mb-4">Smart Mouse Follow</h3>
            <p className="text-base md:text-lg text-neutral-600 leading-relaxed mb-6">
                No more traveling across the screen. The browser selector popup now intelligently appears right where your cursor is, reducing mouse movement and speeding up your workflow.
            </p>
            <ul className="space-y-3">
                <li className="flex items-center gap-3 text-neutral-700 text-sm md:text-base">
                    <div className="w-1.5 h-1.5 rounded-full bg-neutral-800"></div>
                    Context-aware positioning
                </li>
                <li className="flex items-center gap-3 text-neutral-700 text-sm md:text-base">
                    <div className="w-1.5 h-1.5 rounded-full bg-neutral-800"></div>
                    Screen edge detection
                </li>
            </ul>
          </div>

          {/* Feature 2: Horizontal Scroll */}
          <div className="order-3">
            <div className="w-10 h-10 md:w-12 md:h-12 bg-neutral-100 rounded-xl flex items-center justify-center text-neutral-800 mb-4 md:mb-6">
                <MoveHorizontal className="w-5 h-5 md:w-6 md:h-6" />
            </div>
            <h3 className="text-xl md:text-2xl font-bold text-neutral-900 mb-3 md:mb-4">Horizontal Scroll</h3>
            <p className="text-base md:text-lg text-neutral-600 leading-relaxed mb-6">
                Got a lot of browsers? No problem. The new horizontal scroll interface handles large lists of browsers elegantly, keeping the UI compact while ensuring everything is accessible.
            </p>
             <ul className="space-y-3">
                <li className="flex items-center gap-3 text-neutral-700 text-sm md:text-base">
                    <div className="w-1.5 h-1.5 rounded-full bg-neutral-800"></div>
                    Smooth gesture support
                </li>
                <li className="flex items-center gap-3 text-neutral-700 text-sm md:text-base">
                    <div className="w-1.5 h-1.5 rounded-full bg-neutral-800"></div>
                    Visual scroll indicators
                </li>
            </ul>
          </div>

          <div className="order-4 relative">
             <div className="bg-neutral-900 rounded-3xl p-6 md:p-8 aspect-[4/3] flex items-center justify-center overflow-hidden">
                <div className="w-full max-w-sm bg-white/10 backdrop-blur-md rounded-2xl border border-white/10 p-4">
                    <div className="flex gap-4 overflow-x-auto pb-4 scrollbar-hide mask-linear">
                        {[1, 2, 3, 4, 5, 6].map((i) => (
                            <div key={i} className="flex-shrink-0 w-20 h-20 md:w-24 md:h-24 bg-white/10 rounded-xl animate-pulse"></div>
                        ))}
                    </div>
                    {/* Custom Scrollbar visual */}
                    <div className="h-1 bg-white/10 rounded-full mt-2 overflow-hidden">
                        <motion.div 
                            className="h-full w-1/3 bg-white/50 rounded-full"
                            animate={{ x: ['0%', '200%', '0%'] }}
                            transition={{ duration: 3, repeat: Infinity, ease: "easeInOut" }}
                        />
                    </div>
                </div>
             </div>
          </div>
        </div>
      </div>
    </section>
  );
};
