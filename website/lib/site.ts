export const links = {
  download: "https://github.com/DotDeon/sela/releases/latest",
  sponsor: "https://github.com/sponsors/DotDeon",
  code: "https://github.com/DotDeon/sela",
  issues: "https://github.com/DotDeon/sela/issues",
};

export const downloadLabel = "Download for Mac";

export type IconName = "home" | "mountain" | "waves" | "hand" | "droplet" | "receipt" | "download";

export type Section = {
  id: string;
  title: string;
  icon: IconName;
  tint: string;
  // Pinned tabs that climb out of the river into the sidebar.
  drifts?: boolean;
};

export const sections: Section[] = [
  { id: "sela", title: "Sela", icon: "home", tint: "#0f766e" },
  { id: "rock", title: "The name", icon: "mountain", tint: "#57534e" },
  { id: "river", title: "Your tabs", icon: "waves", tint: "#1d4ed8" },
  { id: "every-day", title: "Every day", icon: "hand", tint: "#b4452f", drifts: true },
  { id: "clear-water", title: "Ad blocking", icon: "droplet", tint: "#0e7490", drifts: true },
  { id: "fine-print", title: "Fine print", icon: "receipt", tint: "#4d6b2a", drifts: true },
  { id: "get-sela", title: "Get Sela", icon: "download", tint: "#0f766e", drifts: true },
];

export const pinnedTabs = sections.filter((s) => s.drifts);

// Unpinned tabs float past and are carried off downstream: archived.
export const looseTabs = ["Search results", "Weather", "Checkout", "Old article"];
