import { motion } from 'framer-motion';
import { Zap, Shield, GitBranch, Layout, Globe, Cpu } from 'lucide-react';

const features = [
  {
    icon: <GitBranch className="w-6 h-6 text-neutral-700" />,
    title: "Smart Routing Rules",
    description: "Define rules based on URL patterns or source applications. Open Zoom links in Chrome and Jira tickets in Arc automatically."
  },
  {
    icon: <Layout className="w-6 h-6 text-neutral-700" />,
    title: "Native macOS UI",
    description: "Designed to feel right at home on macOS. Features glassmorphism, native rounded corners, and smooth animations."
  },
  {
    icon: <Zap className="w-6 h-6 text-neutral-700" />,
    title: "Blazing Fast",
    description: "Written in Electron with performance in mind. Instant startup and minimal memory footprint thanks to code splitting."
  },
  {
    icon: <Shield className="w-6 h-6 text-neutral-700" />,
    title: "Privacy First",
    description: "All processing happens locally on your machine. No data is ever sent to the cloud. Your browsing habits stay yours."
  },
  {
    icon: <Globe className="w-6 h-6 text-neutral-700" />,
    title: "Browser Compatibility",
    description: "Supports all major browsers including Arc, Chrome, Safari, Firefox, Edge, Brave, Vivaldi, and more."
  },
  {
    icon: <Cpu className="w-6 h-6 text-neutral-700" />,
    title: "Apple Silicon Ready",
    description: "Fully optimized for M1/M2/M3 chips. Runs natively on ARM64 architecture for maximum efficiency."
  }
];

export const Features = () => {
  return (
    <section id="features" className="py-16 md:py-24 bg-neutral-50 px-4 md:px-6">
      <div className="container mx-auto max-w-6xl">
        <div className="text-center max-w-2xl mx-auto mb-12 md:mb-16">
          <h2 className="text-2xl md:text-3xl font-bold text-neutral-900 mb-4 leading-tight">Everything you need to manage your workflow</h2>
          <p className="text-base md:text-lg text-neutral-600 px-4">
            Prism runs quietly in the background and springs into action exactly when you need it.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 md:gap-8">
          {features.map((feature, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.5, delay: index * 0.1 }}
              className="bg-white p-6 md:p-8 rounded-2xl shadow-sm border border-neutral-100 hover:shadow-md transition-shadow flex flex-col items-start"
            >
              <div className="w-10 h-10 md:w-12 md:h-12 bg-neutral-50 rounded-xl flex items-center justify-center mb-4 md:mb-6">
                {feature.icon}
              </div>
              <h3 className="text-lg md:text-xl font-semibold text-neutral-900 mb-2 md:mb-3">{feature.title}</h3>
              <p className="text-sm md:text-base text-neutral-600 leading-relaxed">{feature.description}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};
