import { api } from "./api";

export async function initPushNotifications(): Promise<void> {
  const { PushNotifications } = await import("@capacitor/push-notifications");

  await PushNotifications.removeAllListeners();

  let status = await PushNotifications.checkPermissions();
  if (status.receive === "prompt") {
    status = await PushNotifications.requestPermissions();
  }
  if (status.receive !== "granted") return;

  await PushNotifications.register();

  await PushNotifications.addListener("registration", async ({ value: token }) => {
    try {
      await api.post("/api/v1/device_tokens", { token, platform: "android" });
    } catch {
      // token registration is best-effort
    }
  });

  await PushNotifications.addListener("registrationError", (err) => {
    console.error("[Push] Registration error:", err.error);
  });

  await PushNotifications.addListener("pushNotificationReceived", (notification) => {
    console.log("[Push] Foreground notification:", notification.title);
  });

  await PushNotifications.addListener("pushNotificationActionPerformed", (action) => {
    const url = action.notification.data?.url;
    if (url && typeof window !== "undefined") window.location.replace(url);
  });
}
