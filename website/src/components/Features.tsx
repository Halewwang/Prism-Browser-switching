import { motion } from 'framer-motion';
import { Zap, Shield, GitBranch, Layout, Globe, Cpu } from 'lucide-react';

const features = [
  {
    icon: <GitBranch className="w-6 h-6 text-neutral-700" />,
    title: "Smart Routing Rules",
    description: "Match an exact domain, a domain and its subdomains, or text in a URL. URL rules run before confirmed source-app rules."
  },
  {
    icon: <Layout className="w-6 h-6 text-neutral-700" />,
    title: "Native macOS UI",
    description: "Built with SwiftUI and AppKit. Manage rules, browser choices, and link history in a native macOS interface."
  },
  {
    icon: <Zap className="w-6 h-6 text-neutral-700" />,
    title: "Choose Your Fallback",
    description: "When no rule matches, show the browser selector, use your preferred browser, or reuse the last browser you chose."
  },
  {
    icon: <Shield className="w-6 h-6 text-neutral-700" />,
    title: "Privacy First",
    description: "Routing rules and link history stay on your Mac. Update checks contact GitHub; your browsing history is not uploaded."
  },
  {
    icon: <Globe className="w-6 h-6 text-neutral-700" />,
    title: "Browser Compatibility",
    description: "Choose from installed browsers such as Safari, Chrome, Arc, Firefox, Edge, and more. You can also add a browser application manually."
  },
  {
    icon: <Cpu className="w-6 h-6 text-neutral-700" />,
    title: "One Universal Download",
    description: "The native public test includes arm64 and x86_64 in one installer for Apple Silicon and Intel Macs running macOS 15 or later."
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
