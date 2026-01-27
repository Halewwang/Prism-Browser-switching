import { MousePointerClick, Settings, ExternalLink } from 'lucide-react';

const steps = [
  {
    icon: <MousePointerClick className="w-8 h-8 text-white" />,
    title: "Click a Link",
    description: "Click any link in any application like Slack, Discord, or Mail.",
    color: "bg-neutral-800"
  },
  {
    icon: <Settings className="w-8 h-8 text-white" />,
    title: "Prism Activates",
    description: "Prism intercepts the request and checks your predefined rules.",
    color: "bg-neutral-700"
  },
  {
    icon: <ExternalLink className="w-8 h-8 text-white" />,
    title: "Browser Opens",
    description: "The correct browser opens automatically. If no rule matches, you choose.",
    color: "bg-neutral-600"
  }
];

export const HowItWorks = () => {
  return (
    <section id="how-it-works" className="py-16 md:py-24 relative overflow-hidden bg-white px-4 md:px-6">
      <div className="container mx-auto max-w-6xl">
        <div className="text-center mb-12 md:mb-16">
          <h2 className="text-2xl md:text-3xl font-bold text-neutral-900 mb-4">How Prism Works</h2>
          <p className="text-base md:text-lg text-neutral-600 max-w-2xl mx-auto px-4">
            A seamless experience from the moment you click a link.
          </p>
        </div>

        <div className="relative">
          {/* Connecting Line (Desktop) */}
          <div className="hidden md:block absolute top-[40px] left-0 w-full h-0.5 bg-neutral-100 z-0"></div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-12 relative z-10">
            {steps.map((step, index) => (
              <div key={index} className="flex flex-col items-center text-center">
                <div className={`w-16 h-16 md:w-20 md:h-20 ${step.color} rounded-2xl shadow-lg shadow-gray-500/20 flex items-center justify-center mb-6 md:mb-8 transform transition-transform hover:scale-110 relative bg-white border-4 border-white`}>
                  {step.icon}
                </div>
                <h3 className="text-lg md:text-xl font-bold text-neutral-900 mb-2 md:mb-3">{step.title}</h3>
                <p className="text-sm md:text-base text-neutral-600 leading-relaxed max-w-xs px-4 md:px-0">
                  {step.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
