import "./globals.css";
import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Providers } from "./providers";
import { Nav } from "@/components/Nav";

export const metadata: Metadata = {
  title: "OpenSub Demo",
  description: "Minimal demo UI for OpenSub (subscriptions) on Anvil + Base Sepolia",
};

export default function RootLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <div className="container">
            <Nav />
            {children}
          </div>
        </Providers>
      </body>
    </html>
  );
}
