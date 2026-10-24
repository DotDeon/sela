// Reads Sela's releases from GitHub while the site builds, so the download
// button and the changelog always match the newest release. If GitHub can't
// be reached, the site still builds and leaves the details out.

export type Release = {
  tag: string;
  name: string;
  date: string;
  url: string;
  body: string;
  // Size of Sela.zip in bytes, when the release has one.
  size?: number;
};

type GitHubRelease = {
  tag_name: string;
  name: string | null;
  published_at: string;
  html_url: string;
  body: string | null;
  draft: boolean;
  prerelease: boolean;
  assets: { name: string; size: number }[];
};

let cached: Promise<Release[]> | undefined;

export function getReleases(): Promise<Release[]> {
  cached ??= load();
  return cached;
}

async function load(): Promise<Release[]> {
  const headers: Record<string, string> = { Accept: "application/vnd.github+json" };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  try {
    const response = await fetch("https://api.github.com/repos/DotDeon/sela/releases?per_page=50", { headers });
    if (!response.ok) return [];
    const releases = (await response.json()) as GitHubRelease[];
    return releases
      .filter((r) => !r.draft && !r.prerelease)
      .map((r) => ({
        tag: r.tag_name,
        name: r.name || r.tag_name,
        date: r.published_at,
        url: r.html_url,
        body: r.body ?? "",
        size: r.assets.find((a) => a.name === "Sela.zip")?.size,
      }));
  } catch {
    return [];
  }
}

export async function getLatest(): Promise<Release | undefined> {
  return (await getReleases())[0];
}

export const version = (r: Release) => r.tag.replace(/^v/, "");

export const megabytes = (bytes: number) => `${(bytes / 1_000_000).toFixed(1)} MB`;
