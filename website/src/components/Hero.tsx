import { motion } from 'framer-motion';
import { ArrowRight, Command } from 'lucide-react';

export const Hero = () => {
  return (
    <section className="relative pt-32 pb-20 md:pt-48 md:pb-32 overflow-hidden">
      {/* Background Blobs */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full -z-10 opacity-30 pointer-events-none">
        <div className="absolute top-[-10%] left-[20%] w-[500px] h-[500px] bg-blue-400 rounded-full mix-blend-multiply filter blur-[100px] animate-blob"></div>
        <div className="absolute top-[-10%] right-[20%] w-[500px] h-[500px] bg-indigo-400 rounded-full mix-blend-multiply filter blur-[100px] animate-blob animation-delay-2000"></div>
        <div className="absolute bottom-[-20%] left-[30%] w-[500px] h-[500px] bg-purple-400 rounded-full mix-blend-multiply filter blur-[100px] animate-blob animation-delay-4000"></div>
      </div>

      <div className="container mx-auto px-6 text-center">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
        >
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-blue-50 text-blue-600 text-xs font-semibold mb-6 border border-blue-100">
            <span className="flex h-2 w-2 rounded-full bg-blue-600"></span>
            v1.10.19 Now Available
          </div>
          
          <h1 className="text-5xl md:text-7xl font-bold tracking-tight text-slate-900 mb-6">
            Master Your Links <br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-600 to-indigo-600">
              on macOS
            </span>
          </h1>
          
          <p className="text-xl text-slate-600 max-w-2xl mx-auto mb-10 leading-relaxed">
            The intelligent browser router for power users. Automatically open links in the right browser based on rules, source apps, and your habits.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-16">
            <a 
              href="#download"
              className="w-full sm:w-auto px-8 py-4 bg-primary text-white rounded-2xl font-semibold text-lg hover:bg-blue-600 transition-all shadow-lg hover:shadow-primary/30 flex items-center justify-center gap-2"
            >
              Download for macOS
              <ArrowRight size={20} />
            </a>
            <div className="flex items-center gap-4 text-slate-500 text-sm font-medium">
               <span className="flex items-center gap-1"><Command size={14}/> Open Source</span>
               <span>•</span>
               <span>macOS 11.0+</span>
            </div>
          </div>
        </motion.div>

        {/* App Screenshot Mockup */}
        <motion.div
          initial={{ opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.2 }}
          className="relative max-w-4xl mx-auto"
        >
          <div className="relative rounded-2xl bg-slate-900/5 p-2 ring-1 ring-inset ring-slate-900/10 lg:rounded-3xl lg:p-4 backdrop-blur-sm">
             <div className="rounded-xl overflow-hidden shadow-2xl border border-slate-200/60 bg-white aspect-[16/10] flex items-center justify-center relative group">
                {/* Mock UI: Browser Selector */}
                <div className="absolute inset-0 bg-gradient-to-br from-gray-50 to-gray-100 flex items-center justify-center">
                    <div className="w-[425px] h-[200px] bg-white rounded-2xl shadow-2xl border border-gray-100 flex flex-col overflow-hidden transform group-hover:scale-105 transition-transform duration-500">
                        {/* Mock Content */}
                        <div className="p-4 border-b border-gray-100 bg-gray-50/50 flex items-center gap-3">
                            <div className="w-10 h-10 bg-blue-500 rounded-xl shadow-sm flex items-center justify-center text-white">
                                <Command size={20} />
                            </div>
                            <div className="flex-1 min-w-0">
                                <div className="text-xs text-gray-500">Opening from Slack</div>
                                <div className="text-sm font-medium truncate">https://github.com/Prism/LinkMaster</div>
                            </div>
                        </div>
                        <div className="flex-1 p-2 grid grid-cols-3 gap-2">
                             {/* Mock Browser Items */}
                             {['Arc', 'Chrome', 'Safari'].map((b, i) => (
                                 <div key={b} className={`rounded-xl flex flex-col items-center justify-center gap-2 border ${i===0 ? 'bg-gray-100 border-gray-200' : 'border-transparent hover:bg-gray-50'}`}>
                                     <div className={`w-8 h-8 rounded-lg ${i===0?'bg-purple-500':'bg-gray-300'}`}></div>
                                     <span className="text-xs font-medium">{b}</span>
                                 </div>
                             ))}
                        </div>
                    </div>
                </div>
             </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
};
