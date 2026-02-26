import { motion } from 'framer-motion';

const treasuries = [
  {
    name: "Heaven Treasury",
    desc: "Represents your pre-destined wealth potential and spiritual merit accumulated from past lives. It is the foundation of your fortune.",
    chinese: "天库"
  },
  {
    name: "Earth Treasury",
    desc: "Governs your current life's accumulation, material assets, and the ability to retain wealth. It turns potential into reality.",
    chinese: "地库"
  },
  {
    name: "Water Treasury",
    desc: "Controls the flow of fortune, opportunities, and the liquidity of your resources in times of need. It ensures movement and growth.",
    chinese: "水库"
  }
];

export function Concept() {
  return (
    <section id="concept" className="py-32 px-6 bg-white relative z-10">
      <div className="max-w-screen-xl mx-auto grid grid-cols-1 md:grid-cols-12 gap-12">
        <div className="col-span-1 md:col-span-4 relative">
          <div className="sticky top-32">
            <h2 className="text-5xl lg:text-7xl font-serif mb-12 text-charcoal">The Three <br/> Treasuries</h2>
            <p className="text-stone font-sans text-base leading-relaxed max-w-xs border-t border-stone/50 pt-6">
              In Taoist philosophy, every person possesses three spiritual treasuries. Balancing them is key to holistic prosperity.
            </p>
          </div>
        </div>
        
        <div className="col-span-1 md:col-span-8 flex flex-col gap-32 pt-12 md:pt-32">
          {treasuries.map((t, i) => (
            <motion.div 
              key={i}
              initial={{ opacity: 0, y: 50 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-100px" }}
              transition={{ duration: 0.8 }}
              className="group border-t border-stone/20 pt-12 relative"
            >
              <div className="absolute top-0 right-0 -mt-16 md:-mt-24 text-[10rem] md:text-[12rem] font-serif text-stone/5 select-none z-0 group-hover:text-bronze/10 transition-colors duration-700">
                {t.chinese}
              </div>
              
              <div className="relative z-10">
                <div className="flex items-center gap-4 mb-6">
                   <span className="text-[10px] font-sans uppercase tracking-[0.2em] text-bronze border border-bronze px-3 py-1 rounded-full">0{i+1}</span>
                </div>
                <h3 className="text-4xl md:text-5xl font-serif mb-6 text-charcoal group-hover:pl-4 transition-all duration-500">{t.name}</h3>
                <p className="text-lg md:text-xl text-stone font-sans leading-relaxed max-w-2xl font-light">{t.desc}</p>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
