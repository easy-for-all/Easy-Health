import type { Metadata } from "next";
import { Geist } from "next/font/google";
import { AuthProvider } from "@/features/auth/auth-context";
import "./globals.css";

const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });

export const metadata: Metadata = {
  title: "Easy Health",
  description: "Seu treino diário simplificado",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={`${geist.variable} h-full antialiased`}>
      <body className="min-h-full bg-gray-50 font-sans">
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
