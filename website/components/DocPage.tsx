import Link from "next/link";
import { asset } from "@/lib/site";

// The plain pages beside the film: a small header back to the home page and
// one readable column.
export function DocPage({ title, lede, children }: { title: string; lede: string; children: React.ReactNode }) {
  return (
    <div className="doc">
      <header className="doc__header">
        <Link href="/" className="doc__home">
          <img src={asset("/icon.svg")} alt="" width={28} height={28} />
          <span>Sela</span>
        </Link>
      </header>
      <main className="doc__main">
        <h1 className="doc__title">{title}</h1>
        <p className="doc__lede">{lede}</p>
        {children}
      </main>
      <footer className="doc__foot">
        <p>Sela is free software under the GNU GPL, version 3.</p>
        <p className="foot__links">
          <Link href="/">Home</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/changelog">Changelog</Link>
        </p>
      </footer>
    </div>
  );
}
