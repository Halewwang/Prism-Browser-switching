import { Button } from './ui/Button';

export function Services() {
  return (
    <section id="rituals" className="py-32 px-6 bg-[#F5F5F3]">
      <div className="max-w-screen-xl mx-auto">
        <div className="text-center mb-24">
            <span className="text-[10px] font-sans uppercase tracking-[0.3em] text-stone block mb-4">Choose Your Path</span>
            <h2 className="text-5xl font-serif text-charcoal">Sacred Rituals</h2>
        </div>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8 md:gap-16 items-start">
          {/* Opening */}
          <div className="bg-white p-12 md:p-16 flex flex-col justify-between min-h-[500px] shadow-sm hover:shadow-xl transition-shadow duration-500 group relative overflow-hidden">
            <div className="absolute top-0 left-0 w-1 h-0 bg-bronze group-hover:h-full transition-all duration-700"></div>
            <div>
               <span className="text-[10px] uppercase tracking-[0.3em] text-stone mb-8 block">For Initiation</span>
               <h3 className="text-4xl font-serif mb-6 group-hover:text-bronze transition-colors">Opening Treasury</h3>
               <p className="text-stone text-base leading-relaxed mb-8 font-light">
                 Establish new sources of prosperity. Ideal for those beginning their journey or seeking to activate their spiritual wealth potential.
               </p>
               <ul className="space-y-4 text-stone/80 mb-12 font-sans text-xs tracking-[0.15em] uppercase">
                 <li className="flex items-center gap-3"><span className="w-1 h-1 bg-bronze rounded-full"></span>Activate wealth potential</li>
                 <li className="flex items-center gap-3"><span className="w-1 h-1 bg-bronze rounded-full"></span>Establish connection</li>
                 <li className="flex items-center gap-3"><span className="w-1 h-1 bg-bronze rounded-full"></span>Personalized calculation</li>
               </ul>
            </div>
            <Button variant="outline" className="w-full md:w-auto self-start">Select Ritual</Button>
          </div>

          {/* Replenishing */}
          <div className="bg-[#1C1C1C] text-white p-12 md:p-16 flex flex-col justify-between min-h-[500px] md:mt-24 shadow-2xl group relative overflow-hidden">
             <div className="absolute top-0 left-0 w-1 h-0 bg-bronze group-hover:h-full transition-all duration-700"></div>
             <div>
               <span className="text-[10px] uppercase tracking-[0.3em] text-stone-500 mb-8 block">For Restoration</span>
               <h3 className="text-4xl font-serif mb-6 text-white group-hover:text-bronze transition-colors">Replenishing Treasury</h3>
               <p className="text-stone-400 text-base leading-relaxed mb-8 font-light">
                 Restore depleted spiritual treasuries and remove blockages. Perfect for those experiencing stagnation or financial difficulties.
               </p>
               <ul className="space-y-4 text-stone-400 mb-12 font-sans text-xs tracking-[0.15em] uppercase">
                 <li className="flex items-center gap-3"><span className="w-1 h-1 bg-bronze rounded-full"></span>Restore depleted energy</li>
                 <li className="flex items-center gap-3"><span className="w-1 h-1 bg-bronze rounded-full"></span>Remove prosperity blockages</li>
                 <li className="flex items-center gap-3"><span className="w-1 h-1 bg-bronze rounded-full"></span>Tailored restoration</li>
               </ul>
            </div>
            <Button variant="outline" className="w-full md:w-auto self-start border-stone-700 text-white hover:bg-white hover:text-charcoal hover:border-white">Select Ritual</Button>
          </div>
        </div>
      </div>
    </section>
  );
}
