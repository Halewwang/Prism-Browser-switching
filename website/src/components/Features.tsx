import { motion } from 'framer-motion';
import { Zap, Shield, GitBranch, Layout, Globe, Cpu } from 'lucide-react';

const features = [
  {
    icon: <GitBranch className="w-6 h-6 text-blue-500" />,
    title: "Smart Routing Rules",
    description: "Define rules based on URL patterns or source applications. Open Zoom links in Chrome and Jira tickets in Arc automatically."
  },
  {
    icon: <Layout className="w-6 h-6 text-purple-500" />,
    title: "Native macOS UI",
    description: "Designed to feel right at home on macOS. Features glassmorphism, native rounded corners, and smooth animations."
  },
  {
    icon: <Zap className="w-6 h-6 text-amber-500" />,
    title: "Blazing Fast",
    description: "Written in Electron with performance in mind. Instant startup and minimal memory footprint thanks to code splitting."
  },
  {
    icon: <Shield className="w-6 h-6 text-green-500" />,
    title: "Privacy First",
    description: "All processing happens locally on your machine. No data is ever sent to the cloud. Your browsing habits stay yours."
  },
  {
    icon: <Globe className="w-6 h-6 text-cyan-500" />,
    title: "Browser Compatibility",
    description: "Supports all major browsers including Arc, Chrome, Safari, Firefox, Edge, Brave, Vivaldi, and more."
  },
  {
    icon: <Cpu className="w-6 h-6 text-rose-500" />,
    title: "Apple Silicon Ready",
    description: "Fully optimized for M1/M2/M3 chips. Runs natively on ARM64 architecture for maximum efficiency."
  }
];

export const Features = () => {
  return (
    <section id="features" className="py-24 bg-slate-50">
      <div className="container mx-auto px-6">
        <div className="text-center max-w-2xl mx-auto mb-16">
          <h2 className="text-3xl font-bold text-slate-900 mb-4">Everything you need to manage your workflow</h2>
          <p className="text-lg text-slate-600">
            Prism runs quietly in the background and springs into action exactly when you need it.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
          {features.map((feature, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: index * 0.1 }}
              className="bg-white p-8 rounded-2xl shadow-sm border border-slate-100 hover:shadow-md transition-shadow"
            >
              <div className="w-12 h-12 bg-slate-50 rounded-xl flex items-center justify-center mb-6">
                {feature.icon}
              </div>
              <h3 className="text-xl font-semibold text-slate-900 mb-3">{feature.title}</h3>
              <p className="text-slate-600 leading-relaxed">
                {feature.description}
              </p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};
