import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./scrollcraft.css";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Sela: a free Mac browser for people leaving Arc",
  description:
    "Sela is a free, open-source Mac browser that works like Arc. Your spaces, pinned tabs and folders come with you.",
  icons: { icon: "/icon.svg" },
};

export const viewport: Viewport = {
  themeColor: "#d6dfdc",
  viewportFit: "cover",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
