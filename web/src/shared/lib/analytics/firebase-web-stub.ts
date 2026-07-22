// Build-time stub for the firebase JS SDK.
//
// @capacitor-firebase/{analytics,performance} web implementations statically
// import from "firebase/analytics" / "firebase/performance". By design, firebase
// is a NO-OP on web/PWA (GA4 handles web — see ./firebase.ts) and on the native
// WebView the Capacitor bridge routes to the native SDK, so these web.js modules
// are bundled but never executed. Aliasing the firebase subpaths to this stub
// (next.config.ts -> turbopack.resolveAlias) lets the web build resolve them
// without shipping the real firebase SDK into the bundle.

const noop = (): undefined => undefined;

// firebase/analytics
export const getAnalytics = noop;
export const logEvent = noop;
export const setAnalyticsCollectionEnabled = noop;
export const setConsent = noop;
export const setUserId = noop;
export const setUserProperties = noop;

// firebase/performance
export const getPerformance = noop;
export const trace = noop;

export default {};
