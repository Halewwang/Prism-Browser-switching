import { motion } from 'framer-motion';
import { MousePointer2, GitBranch } from 'lucide-react';
import { release } from '../release';

export const NewFeatures = () => {
  return (
    <section id="new-features" className="py-16 md:py-24 overflow-hidden px-4 md:px-6">
      <div className="container mx-auto max-w-6xl">
        <div className="mb-12 md:mb-16">
          <span className="text-neutral-600 font-semibold tracking-wider uppercase text-xs md:text-sm">v{release.version} · {release.channel}</span>
          <h2 className="text-2xl md:text-3xl font-bold text-neutral-900 mt-2">A Native Home for Your Links</h2>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-16 items-center">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} className="order-2 lg:order-1 bg-neutral-100 rounded-3xl p-4 md:p-6">
            <img src="/app-screenshot-popup.png" alt="Prism's native browser selector in v1.13.1" className="w-full h-auto rounded-xl shadow-lg" />
            <p className="mt-3 text-xs text-neutral-500">v1.13.1 interface illustration</p>
          </motion.div>

          <div className="order-1 lg:order-2">
            <div className="w-10 h-10 md:w-12 md:h-12 bg-neutral-100 rounded-xl flex items-center justify-center text-neutral-800 mb-4 md:mb-6">
              <MousePointer2 className="w-5 h-5 md:w-6 md:h-6" />
            </div>
            <h3 className="text-xl md:text-2xl font-bold text-neutral-900 mb-3 md:mb-4">Choose Near Your Cursor</h3>
            <p className="text-base md:text-lg text-neutral-600 leading-relaxed mb-6">
              The native selector appears near your pointer and stays within the screen. Choose a browser with a click or its displayed number key, and scroll horizontally when more browsers are available.
            </p>
            <ul className="space-y-3 text-neutral-700 text-sm md:text-base">
              <li>Number keys, arrow keys, and Return</li>
              <li>Hide and reorder browser choices in settings</li>
              <li>Experimental Chrome and Edge profile targets</li>
            </ul>
          </div>

          <div className="order-3">
            <div className="w-10 h-10 md:w-12 md:h-12 bg-neutral-100 rounded-xl flex items-center justify-center text-neutral-800 mb-4 md:mb-6">
              <GitBranch className="w-5 h-5 md:w-6 md:h-6" />
            </div>
            <h3 className="text-xl md:text-2xl font-bold text-neutral-900 mb-3 md:mb-4">Rules You Can See and Order</h3>
            <p className="text-base md:text-lg text-neutral-600 leading-relaxed mb-6">
              Keep URL rules and source-app rules in separate groups. Preview a URL before routing, undo a newly saved rule, and use link history to correct the current rule.
            </p>
            <p className="text-sm md:text-base text-neutral-500 leading-relaxed">
              Source rules require a confirmed sender. Profile routing is experimental for stable Chrome and Edge; real browser and account-context validation is still incomplete. Regular expression rules are not supported.
            </p>
          </div>

          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} className="order-4 bg-neutral-100 rounded-3xl p-4 md:p-6">
            <img src="/app-screenshot-main.png" alt="Prism's native rule groups and priority order in v1.13.1" className="w-full h-auto rounded-xl shadow-lg" />
            <p className="mt-3 text-xs text-neutral-500">v1.13.1 interface illustration</p>
          </motion.div>
        </div>
      </div>
    </section>
  );
};
