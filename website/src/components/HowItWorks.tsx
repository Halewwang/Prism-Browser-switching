import { MousePointerClick, Settings, ExternalLink } from 'lucide-react';

const steps = [
  {
    icon: <MousePointerClick className="w-8 h-8 text-white" />,
    title: "Click a Link",
    description: "Click any link in any application like Slack, Discord, or Mail.",
    color: "bg-blue-500"
  },
  {
    icon: <Settings className="w-8 h-8 text-white" />,
    title: "Prism Activates",
    description: "Prism intercepts the request and checks your predefined rules.",
    color: "bg-indigo-500"
  },
  {
    icon: <ExternalLink className="w-8 h-8 text-white" />,
    title: "Browser Opens",
    description: "The correct browser opens automatically. If no rule matches, you choose.",
    color: "bg-purple-500"
  }
];

export const HowItWorks = () => {
  return (
    <section id="how-it-works" className="py-24 bg-white">
      <div className="container mx-auto px-6">
        <div className="text-center max-w-2xl mx-auto mb-16">
          <h2 className="text-3xl font-bold text-slate-900 mb-4">How Prism Works</h2>
          <p className="text-lg text-slate-600">
            Seamlessly integrated into your macOS workflow.
          </p>
        </div>

        <div className="relative">
          {/* Connecting Line (Desktop) */}
          <div className="hidden md:block absolute top-1/2 left-0 w-full h-0.5 bg-slate-100 -translate-y-1/2 z-0"></div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-12 relative z-10">
            {steps.map((step, index) => (
              <div key={index} className="flex flex-col items-center text-center">
                <div className={`w-20 h-20 ${step.color} rounded-2xl shadow-lg shadow-blue-500/20 flex items-center justify-center mb-8 transform transition-transform hover:scale-110`}>
                  {step.icon}
                </div>
                <h3 className="text-xl font-bold text-slate-900 mb-3">{step.title}</h3>
                <p className="text-slate-600 leading-relaxed max-w-xs">
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
