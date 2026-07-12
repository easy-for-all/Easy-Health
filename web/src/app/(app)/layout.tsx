import { BottomNav } from "@/shared/components/bottom-nav";
import { PageTransition } from "@/shared/components/page-transition";
import { WorkoutSessionProvider } from "@/features/workout/workout-session-context";
import { CoachProvider } from "@/features/coach/coach-context";
import { CoachFab, CoachSheet } from "@/shared/components/coach-sheet";
import { TrialBanner } from "@/shared/components/trial-banner";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <WorkoutSessionProvider>
      <CoachProvider>
        <div
          style={{
            minHeight: "100svh",
            background: "var(--bg)",
            color: "var(--text)",
            paddingTop: "var(--safe-area-top)",
            paddingRight: "var(--safe-area-right)",
            paddingBottom: "var(--nav-pb)",
            paddingLeft: "var(--safe-area-left)",
          }}
        >
          <TrialBanner />
          <PageTransition>{children}</PageTransition>
          <BottomNav />
          <CoachFab />
          <CoachSheet />
        </div>
      </CoachProvider>
    </WorkoutSessionProvider>
  );
}
