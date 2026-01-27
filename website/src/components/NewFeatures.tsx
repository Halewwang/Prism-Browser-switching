import { motion } from 'framer-motion';
import { MousePointer2, MoveHorizontal } from 'lucide-react';

export const NewFeatures = () => {
  return (
    <section id="new-features" className="py-24 overflow-hidden">
      <div className="container mx-auto px-6">
        <div className="mb-16">
          <span className="text-blue-600 font-semibold tracking-wider uppercase text-sm">What's New in v1.10.19</span>
          <h2 className="text-3xl font-bold text-slate-900 mt-2">Designed for Efficiency</h2>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
          {/* Feature 1: Mouse Follow */}
          <div className="order-2 lg:order-1 relative">
             <div className="bg-slate-100 rounded-3xl p-8 aspect-square flex items-center justify-center relative overflow-hidden group">
                {/* Mock Cursor Animation */}
                <motion.div 
                    animate={{ 
                        x: [0, 100, -50, 0],
                        y: [0, -50, 80, 0]
                    }}
                    transition={{ 
                        duration: 8,
                        repeat: Infinity,
                        ease: "easeInOut"
                    }}
                    className="absolute z-20 pointer-events-none"
                >
                    <MousePointer2 className="w-6 h-6 text-slate-900 fill-white drop-shadow-md" />
                    {/* Popup follows cursor */}
                    <div className="absolute top-8 left-[-100px] w-[200px] h-[100px] bg-white rounded-xl shadow-xl border border-slate-200 p-2 opacity-90 scale-90">
                        <div className="w-full h-full bg-slate-50 rounded-lg animate-pulse"></div>
                    </div>
                </motion.div>
                
                <div className="absolute inset-0 grid grid-cols-6 grid-rows-6 gap-4 opacity-10">
                    {[...Array(36)].map((_, i) => (
                        <div key={i} className="bg-slate-400 rounded-full w-1 h-1"></div>
                    ))}
                </div>
             </div>
          </div>
          
          <div className="order-1 lg:order-2">
            <div className="w-12 h-12 bg-blue-100 rounded-xl flex items-center justify-center text-blue-600 mb-6">
                <MousePointer2 size={24} />
            </div>
            <h3 className="text-2xl font-bold text-slate-900 mb-4">Smart Mouse Follow</h3>
            <p className="text-lg text-slate-600 leading-relaxed mb-6">
                No more traveling across the screen. The browser selector popup now intelligently appears right where your cursor is, reducing mouse movement and speeding up your workflow.
            </p>
            <ul className="space-y-3">
                <li className="flex items-center gap-3 text-slate-700">
                    <div className="w-1.5 h-1.5 rounded-full bg-blue-500"></div>
                    Context-aware positioning
                </li>
                <li className="flex items-center gap-3 text-slate-700">
                    <div className="w-1.5 h-1.5 rounded-full bg-blue-500"></div>
                    Screen edge detection
                </li>
            </ul>
          </div>

          {/* Feature 2: Horizontal Scroll */}
          <div className="order-3">
            <div className="w-12 h-12 bg-indigo-100 rounded-xl flex items-center justify-center text-indigo-600 mb-6">
                <MoveHorizontal size={24} />
            </div>
            <h3 className="text-2xl font-bold text-slate-900 mb-4">Horizontal Scroll</h3>
            <p className="text-lg text-slate-600 leading-relaxed mb-6">
                Got a lot of browsers? No problem. The new horizontal scroll interface handles large lists of browsers elegantly, keeping the UI compact while ensuring everything is accessible.
            </p>
             <ul className="space-y-3">
                <li className="flex items-center gap-3 text-slate-700">
                    <div className="w-1.5 h-1.5 rounded-full bg-indigo-500"></div>
                    Smooth gesture support
                </li>
                <li className="flex items-center gap-3 text-slate-700">
                    <div className="w-1.5 h-1.5 rounded-full bg-indigo-500"></div>
                    Visual scroll indicators
                </li>
            </ul>
          </div>

          <div className="order-4 relative">
             <div className="bg-slate-900 rounded-3xl p-8 aspect-[4/3] flex items-center justify-center overflow-hidden">
                <div className="w-full max-w-sm bg-white/10 backdrop-blur-md rounded-2xl border border-white/10 p-4">
                    <div className="flex gap-4 overflow-x-auto pb-4 scrollbar-hide mask-linear">
                        {[1, 2, 3, 4, 5, 6].map((i) => (
                            <div key={i} className="flex-shrink-0 w-24 h-24 bg-white/10 rounded-xl animate-pulse"></div>
                        ))}
                    </div>
                    {/* Custom Scrollbar visual */}
                    <div className="h-1 bg-white/10 rounded-full mt-2 overflow-hidden">
                        <motion.div 
                            className="h-full w-1/3 bg-blue-500 rounded-full"
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
