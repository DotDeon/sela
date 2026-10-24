export const links = {
  download: "https://github.com/DotDeon/sela/releases/latest",
  sponsor: "https://github.com/sponsors/DotDeon",
  code: "https://github.com/DotDeon/sela",
  issues: "https://github.com/DotDeon/sela/issues",
};

export const downloadLabel = "Download for Mac";

export type IconName =
  | "home"
  | "leaf"
  | "move"
  | "hand"
  | "shield"
  | "receipt"
  | "download";

export type Section = {
  id: string;
  title: string;
  icon: IconName;
  tint: string;
  // Sections that arrive in the sidebar during the move, standing in for
  // someone's Arc tabs.
  fromArc?: boolean;
};

export const sections: Section[] = [
  { id: "sela", title: "Sela", icon: "home", tint: "#0f766e" },
  { id: "leaving-arc", title: "Leaving Arc", icon: "leaf", tint: "#9a6b2f" },
  { id: "the-move", title: "The move", icon: "move", tint: "#3b5bcc" },
  { id: "every-day", title: "Every day", icon: "hand", tint: "#b4452f", fromArc: true },
  { id: "ad-blocking", title: "Ad blocking", icon: "shield", tint: "#5b3fb0", fromArc: true },
  { id: "fine-print", title: "Fine print", icon: "receipt", tint: "#4d6b2a", fromArc: true },
  { id: "get-sela", title: "Get Sela", icon: "download", tint: "#0f766e", fromArc: true },
];

export const arcSections = sections.filter((s) => s.fromArc);

// Two sample spaces travel with the tabs and land in the space bar.
export const arcSpaces = [
  { id: "space-personal", title: "Personal", tint: "#d9673c" },
  { id: "space-work", title: "Work", tint: "#3b5bcc" },
];

// Everything that flies, in the order it leaves Arc.
export const flightOrder = [
  ...arcSpaces.map((s) => s.id),
  ...arcSections.map((s) => s.id),
];
