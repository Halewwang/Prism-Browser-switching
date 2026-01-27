import { Header } from './components/Header';
import { Hero } from './components/Hero';
import { Features } from './components/Features';
import { HowItWorks } from './components/HowItWorks';
import { NewFeatures } from './components/NewFeatures';
import { Footer } from './components/Footer';

function App() {
  return (
    <div className="min-h-screen bg-white font-sans text-neutral-900 selection:bg-gray-200 selection:text-black">
      <Header />
      <main>
        <Hero />
        <Features />
        <HowItWorks />
        <NewFeatures />
      </main>
      <Footer />
    </div>
  );
}

export default App;
