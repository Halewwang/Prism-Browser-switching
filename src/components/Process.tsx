export function Process() {
  const steps = [
    { num: "01", title: "Selection", desc: "Choose the ritual package that aligns with your current life stage and spiritual needs." },
    { num: "02", title: "Details", desc: "Provide your birth information and intentions to allow for precise personalization." },
    { num: "03", title: "Crafting", desc: "Our expert calligraphers create your unique treasury document with traditional techniques." },
    { num: "04", title: "Activation", desc: "Receive your document with specific instructions to activate the flow of prosperity." }
  ];

  return (
    <section id="process" className="py-32 px-6 bg-white border-t border-stone/10">
      <div className="max-w-screen-xl mx-auto">
        <div className="mb-24">
             <h2 className="text-5xl font-serif text-charcoal">The Journey</h2>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-4 gap-8">
            {steps.map((step, i) => (
                <div key={i} className="group relative">
                    <div className="text-6xl md:text-8xl font-serif text-stone/10 group-hover:text-bronze/20 transition-colors duration-500 mb-8 select-none">
                        {step.num}
                    </div>
                    <div className="relative z-10 border-l border-stone/20 pl-6 h-full group-hover:border-bronze transition-colors duration-500">
                        <h3 className="text-2xl font-serif mb-4 text-charcoal">{step.title}</h3>
                        <p className="text-stone text-xs leading-relaxed font-sans uppercase tracking-wider">{step.desc}</p>
                    </div>
                </div>
            ))}
        </div>
      </div>
    </section>
  );
}
