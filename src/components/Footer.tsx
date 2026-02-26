export function Footer() {
  return (
    <footer className="bg-[#111] text-white py-24 px-6 border-t border-white/10">
      <div className="max-w-screen-xl mx-auto grid grid-cols-1 md:grid-cols-12 gap-12">
        <div className="col-span-1 md:col-span-4">
            <div className="text-2xl font-serif font-bold tracking-widest text-white mb-8">
                TREASURY <span className="text-xs font-sans font-normal tracking-[0.3em] block text-stone-500 mt-2">OF TAO</span>
            </div>
            <p className="text-stone-500 text-xs max-w-xs leading-relaxed uppercase tracking-wider">
                Authentic handcrafted Taoist treasury rituals personalized to activate and replenish your spiritual wealth.
            </p>
        </div>

        <div className="col-span-1 md:col-span-2 md:col-start-7">
            <h4 className="text-[10px] font-sans uppercase tracking-[0.2em] text-stone-500 mb-8">Explore</h4>
            <ul className="space-y-4 text-xs text-stone-300 tracking-wide font-light">
                <li><a href="#concept" className="hover:text-bronze transition-colors">Concept</a></li>
                <li><a href="#rituals" className="hover:text-bronze transition-colors">Rituals</a></li>
                <li><a href="#process" className="hover:text-bronze transition-colors">Process</a></li>
            </ul>
        </div>

        <div className="col-span-1 md:col-span-2">
            <h4 className="text-[10px] font-sans uppercase tracking-[0.2em] text-stone-500 mb-8">Support</h4>
            <ul className="space-y-4 text-xs text-stone-300 tracking-wide font-light">
                <li><a href="#" className="hover:text-bronze transition-colors">FAQ</a></li>
                <li><a href="#" className="hover:text-bronze transition-colors">Contact</a></li>
                <li><a href="#" className="hover:text-bronze transition-colors">Shipping</a></li>
            </ul>
        </div>

        <div className="col-span-1 md:col-span-2">
            <h4 className="text-[10px] font-sans uppercase tracking-[0.2em] text-stone-500 mb-8">Legal</h4>
            <ul className="space-y-4 text-xs text-stone-300 tracking-wide font-light">
                <li><a href="#" className="hover:text-bronze transition-colors">Privacy</a></li>
                <li><a href="#" className="hover:text-bronze transition-colors">Terms</a></li>
            </ul>
        </div>
      </div>
      <div className="max-w-screen-xl mx-auto mt-24 pt-8 border-t border-white/5 flex flex-col md:flex-row justify-between text-xs text-stone-600 font-sans tracking-wider">
          <p>© 2026 Treasury of Tao. All rights reserved.</p>
          <p>Handcrafted with reverence.</p>
      </div>
    </footer>
  );
}
