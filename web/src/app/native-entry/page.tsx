import type { Metadata } from "next";
import { NativeEntryGate } from "@/features/native-entry/native-entry-gate";

export const metadata: Metadata = {
  title: "EasyHealth",
  robots: {
    index: false,
    follow: false,
  },
};

export default function NativeEntryPage() {
  return <NativeEntryGate />;
}
