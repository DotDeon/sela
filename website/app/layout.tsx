import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { asset, siteUrl } from "@/lib/site";
import "./scrollcraft.css";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

const title = "Sela: a browser that holds still";
const description =
  "Sela is a free, open-source Mac browser. Your tabs rest in a calm sidebar while the web rushes past.";
const preview = { url: `${siteUrl}/og.jpg`, width: 1200, height: 630, alt: "Sela: a browser that holds still" };

export const metadata: Metadata = {
  metadataBase: new URL(`${siteUrl}/`),
  title,
  description,
  icons: { icon: asset("/icon.svg"), apple: asset("/apple-icon.png") },
  openGraph: { type: "website", url: `${siteUrl}/`, siteName: "Sela", title, description, images: [preview] },
  twitter: { card: "summary_large_image", title, description, images: [preview] },
};

export const viewport: Viewport = {
  themeColor: "#070a0a",
  viewportFit: "cover",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
