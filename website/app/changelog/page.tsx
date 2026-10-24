import type { Metadata } from "next";
import { DocPage } from "@/components/DocPage";
import { Markdown } from "@/components/Markdown";
import { getReleases, megabytes, version } from "@/lib/releases";
import { links } from "@/lib/site";

export const metadata: Metadata = {
  title: "Changelog: Sela",
  description: "What changed in each version of Sela.",
};

const dateFormat = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "long", year: "numeric" });

export default async function Changelog() {
  // Releases from before the rename went out under another name.
  const releases = (await getReleases()).filter((r) => r.name.startsWith("Sela"));

  return (
    <DocPage title="Changelog" lede="What changed in each version of Sela, newest first.">
      {releases.length === 0 && (
        <p>
          The list of versions couldn&rsquo;t be loaded. See every release <a href={links.releases}>on GitHub</a>.
        </p>
      )}
      {releases.map((r) => (
        <article key={r.tag} className="doc__section release" id={r.tag}>
          <h2>
            <a href={r.url}>Version {version(r)}</a>
          </h2>
          <p className="release__meta">
            {dateFormat.format(new Date(r.date))}
            {r.size ? `, ${megabytes(r.size)}` : ""}
          </p>
          <Markdown source={r.body} />
        </article>
      ))}
      <p className="doc__note">
        Versions before 0.1.2 came out under Sela&rsquo;s earlier name, and are{" "}
        <a href={links.releases}>on GitHub</a>.
      </p>
    </DocPage>
  );
}
