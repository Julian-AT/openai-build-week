import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";

import "./globals.css";

export const metadata: Metadata = {
  title: "ReRoom · Mode B0 Recorded Replay",
  description: "Provider-independent local inspection of a verified ReRoom golden capture.",
};

export const viewport: Viewport = {
  colorScheme: "dark",
  themeColor: "#08100f",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
