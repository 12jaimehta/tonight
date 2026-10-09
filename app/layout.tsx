import type { Metadata } from "next";
import { Fraunces, Nunito } from "next/font/google";
import Link from "next/link";
import "./globals.css";

const sans = Nunito({
  variable: "--font-sans",
  subsets: ["latin"],
});

const display = Fraunces({
  variable: "--font-display",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Tonight",
  description: "Tonight's homework, marked from the page.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${sans.variable} ${display.variable} h-full antialiased`}>
      <body className="min-h-full">
        <header className="mx-auto flex w-full max-w-lg items-center justify-between px-5 py-5">
          <Link href="/" className="font-[family-name:var(--font-display)] text-2xl tracking-tight">
            Tonight
          </Link>
          <nav className="flex gap-4 text-sm">
            <Link href="/remember">Remember</Link>
            <Link href="/new">New page</Link>
          </nav>
        </header>
        <main className="mx-auto w-full max-w-lg px-5 pb-16">{children}</main>
      </body>
    </html>
  );
}
