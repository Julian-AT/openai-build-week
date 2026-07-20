import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";

import "./globals.css";

export const metadata: Metadata = {
  title: "Reframe · Spatial Design Intelligence",
  description: "A realtime spatial design system for understanding and reshaping real rooms.",
};

export const viewport: Viewport = {
  colorScheme: "dark",
  themeColor: "#10120f",
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
