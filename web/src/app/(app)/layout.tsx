import { BottomNav } from "@/shared/components/bottom-nav";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="pb-20">
      {children}
      <BottomNav />
    </div>
  );
}
