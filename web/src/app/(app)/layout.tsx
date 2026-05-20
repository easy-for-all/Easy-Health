import { BottomNav } from "@/shared/components/bottom-nav";
import { WorkoutSessionProvider } from "@/features/workout/workout-session-context";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <WorkoutSessionProvider>
      <div className="pb-20">
        {children}
        <BottomNav />
      </div>
    </WorkoutSessionProvider>
  );
}
