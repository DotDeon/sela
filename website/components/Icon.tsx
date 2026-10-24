import {
  Download,
  Hand,
  House,
  Leaf,
  Receipt,
  ShieldCheck,
  Truck,
  type LucideProps,
} from "lucide-react";
import type { IconName } from "@/lib/site";

const icons = {
  home: House,
  leaf: Leaf,
  move: Truck,
  hand: Hand,
  shield: ShieldCheck,
  receipt: Receipt,
  download: Download,
};

export function Icon({ name, ...props }: { name: IconName } & LucideProps) {
  const Glyph = icons[name];
  return <Glyph aria-hidden size={14} strokeWidth={2} {...props} />;
}

// A favicon-sized tile, the way a sidebar row shows a site.
export function Favicon({ name, tint }: { name: IconName; tint: string }) {
  return (
    <span className="favicon" style={{ background: tint }}>
      <Icon name={name} size={11} strokeWidth={2.4} color="#fff" />
    </span>
  );
}
