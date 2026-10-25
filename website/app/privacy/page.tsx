import type { Metadata } from "next";
import { DocPage } from "@/components/DocPage";
import { links } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy: Sela",
  description: "What Sela sends over the network, and what stays on your Mac.",
};

export default function Privacy() {
  return (
    <DocPage
      title="Privacy"
      lede="Sela has no account, no analytics and no crash reporting. It doesn't know who you are, and nothing you do in it is sent to us."
    >
      <section className="doc__section">
        <h2>What Sela sends</h2>
        <p>Apart from the pages you visit, Sela makes four kinds of request.</p>
        <ul>
          <li>
            <strong>Filter lists.</strong> Every 6 hours Sela downloads the AdGuard Base list from
            filters.adtidy.org and the EasyPrivacy list from easylist.to. Those servers see your IP
            address and nothing else.
          </li>
          <li>
            <strong>Searches.</strong> Anything you type in the address bar that isn&rsquo;t a web
            address goes as a search to the search engine you choose in Settings. That&rsquo;s Google
            unless you change it. The others are DuckDuckGo, Bing, Ecosia, Kagi, Brave Search and
            Startpage.
          </li>
          <li>
            <strong>Remote settings.</strong> Once a day Sela downloads a small file from this
            website, dotdeon.github.io, that can change search engine addresses, default settings
            and switches, or show a notice. It holds no code, and Sela only uses it when its signature
            checks out. GitHub, which hosts the site, sees your IP address and nothing else.
          </li>
          <li>
            <strong>Site icons.</strong> Sela loads each site&rsquo;s icon from the address the site
            gives it, which is almost always the site&rsquo;s own server.
          </li>
        </ul>
      </section>

      <section className="doc__section">
        <h2>What stays on your Mac</h2>
        <p>
          Your tabs, spaces, history, archived tabs, downloads and site settings are stored in
          ~/Library/Application Support/Sela. Nothing syncs, and nothing leaves your Mac. Cookies and
          website data are kept by WebKit in Sela&rsquo;s own storage on your Mac, separate from
          Safari&rsquo;s.
        </p>
      </section>

      <section className="doc__section">
        <h2>Checking this yourself</h2>
        <p>
          Sela is open source, so you don&rsquo;t have to take our word for it. Every network request
          it makes is in the <a href={links.code}>code on GitHub</a>. If you find one that this page
          doesn&rsquo;t mention, please <a href={links.issues}>open an issue</a>.
        </p>
      </section>
    </DocPage>
  );
}
