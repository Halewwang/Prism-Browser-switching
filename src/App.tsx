import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { Concept } from './components/Concept';
import { Services } from './components/Services';
import { Process } from './components/Process';
import { Footer } from './components/Footer';

function App() {
  return (
    <div className="min-h-screen bg-[var(--color-travertine)] selection:bg-[var(--color-bronze)] selection:text-white overflow-x-hidden">
      <Navbar />
      <main>
        <Hero />
        <Concept />
        <Services />
        <Process />
      </main>
      <Footer />
    </div>
  );
}

export default App;
