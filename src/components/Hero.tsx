import { motion } from 'framer-motion';
import { Button } from './ui/Button';
import bannerImg from '../assets/banner.jpeg';

export function Hero() {
  return (
    <section className="min-h-screen pt-32 px-6 grid grid-cols-12 gap-4 items-center overflow-hidden">
      <div className="col-span-12 lg:col-span-7 z-10 flex flex-col justify-center">
        <motion.h1 
          initial={{ opacity: 0, y: 50 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 1, ease: "easeOut" }}
          className="text-[10vw] lg:text-[8vw] leading-[0.85] font-serif tracking-tighter text-charcoal mb-12"
        >
          Treasury <br />
          <span className="italic font-light ml-[10vw] block text-bronze-dark">of Tao</span>
        </motion.h1>
        
        <motion.div 
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.5, duration: 1 }}
          className="lg:ml-[10vw] flex flex-col items-start"
        >
            <p className="max-w-md text-stone text-xl leading-relaxed font-sans font-light italic mb-12 border-l border-stone/50 pl-6">
            Unlock your Treasury of Prosperity. Authentic Taoist rituals handcrafted to activate and replenish your spiritual wealth.
            </p>

            <div className="flex gap-6">
                <Button variant="primary">Begin Ritual</Button>
                <Button variant="ghost">The Philosophy</Button>
            </div>
        </motion.div>
      </div>

      <div className="col-span-12 lg:col-span-5 h-[50vh] lg:h-[80vh] relative mt-12 lg:mt-0">
         <motion.div
           initial={{ opacity: 0, scale: 0.95 }}
           animate={{ opacity: 1, scale: 1 }}
           transition={{ duration: 1.5, ease: "easeOut" }}
           className="w-full h-full bg-stone-200 overflow-hidden relative"
         >
            <img 
              src={bannerImg} 
              alt="Taoist Ritual Fire" 
              className="w-full h-full object-cover grayscale-[0.2] hover:scale-105 transition-transform duration-[2s]"
            />
         </motion.div>
      </div>
    </section>
  );
}
