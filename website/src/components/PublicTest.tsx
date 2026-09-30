import { release } from '../release';

export const PublicTest = () => (
  <section id="public-test" className="px-4 md:px-6 pb-16 md:pb-24 scroll-mt-24">
    <div className="container mx-auto max-w-4xl rounded-2xl border border-neutral-200 bg-neutral-50 p-6 md:p-8">
      <h2 className="text-xl md:text-2xl font-bold mb-4">Before You Install the Public Test</h2>
      <p className="text-sm md:text-base text-neutral-600 leading-relaxed mb-5">
        v{release.version}, build {release.build} requires {release.minimumSystem}. The Universal download includes Apple Silicon and Intel binaries.
        It uses ad hoc signing, without Developer ID signing or Apple notarization.
      </p>
      <ol className="list-decimal pl-5 space-y-3 text-sm md:text-base text-neutral-700 leading-relaxed">
        <li>Download the DMG and <a href={release.checksumsUrl} className="underline underline-offset-4">SHA256SUMS.txt</a>. In the download folder, run <code className="break-all">shasum -a 256 -c SHA256SUMS.txt</code> to check file integrity.</li>
        <li>Quit Prism, open the DMG, and drag Prism into Applications. Then try opening Prism.</li>
        <li>If macOS blocks this trusted download because it cannot verify the developer, go to System Settings → Privacy &amp; Security → Open Anyway, then confirm Open. Follow <a href="https://support.apple.com/en-us/102445" className="underline underline-offset-4">Apple’s first-open guidance</a>. Do not use this step for a malware or damaged-app warning.</li>
      </ol>
      <h3 className="font-semibold mt-7 mb-3">Updating This Public Test</h3>
      <p className="text-sm md:text-base text-neutral-600 leading-relaxed">
        If you use v1.14.0, install this version manually once to get in-app update downloads and verification.
        Installation and restart are experimental: macOS may block an unnotarized update, causing Prism to restore the previous version.
        You may need to install the update manually. Prism keeps macOS security checks enabled.
      </p>
      <h3 className="font-semibold mt-7 mb-3">What Still Needs Real-World Testing</h3>
      <ul className="list-disc pl-5 space-y-2 text-sm md:text-base text-neutral-600 leading-relaxed">
        <li>Source-app routing only runs for a confirmed sender. Real-app coverage is still incomplete; not every app or link can be identified.</li>
        <li>Stable Chrome and Edge profile targets are experimental. Cold and already-running launches, account context, and profile removal still need real-browser validation.</li>
        <li>The Intel binary is included, but this release has not been verified on a physical Intel Mac. Supported macOS versions have not all been tested.</li>
      </ul>
      <p className="text-sm text-neutral-600 mt-5">
        <a href={release.notesUrl} className="underline underline-offset-4">Release notes</a>{' · '}
        <a href={release.issuesUrl} className="underline underline-offset-4">Report an issue</a>
      </p>
    </div>
  </section>
);
