import { BottomNav } from "@/shared/components/bottom-nav";
import { SupportChat } from "@/shared/components/support-chat";
import { PageTransition } from "@/shared/components/page-transition";
import { WorkoutSessionProvider } from "@/features/workout/workout-session-context";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <WorkoutSessionProvider>
      <div className="pb-20">
        <PageTransition>{children}</PageTransition>
        <BottomNav />
        <SupportChat />
      </div>
    </WorkoutSessionProvider>
  );
}
