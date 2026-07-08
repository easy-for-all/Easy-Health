"use client";

import { useRouter } from "next/navigation";
import { AiWorkoutChatScreen } from "@/features/ai-workout-chat/ai-workout-chat-screen";

export default function AiWorkoutChatPage() {
  const router = useRouter();

  return (
    <AiWorkoutChatScreen
      onBack={() => router.back()}
      onConfirmed={() => router.replace("/workouts")}
    />
  );
}
