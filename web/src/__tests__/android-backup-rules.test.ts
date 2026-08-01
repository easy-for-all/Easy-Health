import { readFileSync } from "fs";
import path from "path";
import { describe, it, expect } from "vitest";

// The client can only treat "the Capacitor store has an id" as proof of "this
// installation created it" while that store stays out of Android Auto Backup.
// These files are the other half of installation.ts — if the manifest stops
// pointing at them, or an exclusion is dropped, a reinstall silently starts
// reusing the previous installation's id again (link_result=conflict).

const CONFIG_DIR = path.resolve(__dirname, "../../android-config");

function read(relative: string): string {
  return readFileSync(path.join(CONFIG_DIR, relative), "utf8");
}

// The SharedPreferences file @capacitor/preferences writes to
// (PreferencesConfiguration.DEFAULTS.group = "CapacitorStorage").
const CAPACITOR_STORE = "CapacitorStorage";

describe("android backup rules", () => {
  const manifest = read("AndroidManifest.xml");

  it("keeps backup enabled but governed by explicit rules", () => {
    expect(manifest).toContain('android:allowBackup="true"');
    // API 23-30.
    expect(manifest).toContain('android:fullBackupContent="@xml/backup_rules"');
    // API 31+ — the one that governs the shipped app (targetSdk 36).
    expect(manifest).toContain('android:dataExtractionRules="@xml/data_extraction_rules"');
  });

  it("excludes the Capacitor store from full backup (API 23-30)", () => {
    const rules = read("res/xml/backup_rules.xml");
    expect(rules).toContain(`<exclude domain="sharedpref" path="${CAPACITOR_STORE}.xml" />`);
  });

  it("excludes the Capacitor store from BOTH transports (API 31+)", () => {
    const rules = read("res/xml/data_extraction_rules.xml");
    const cloud = rules.split("<cloud-backup>")[1]?.split("</cloud-backup>")[0] ?? "";
    const transfer = rules.split("<device-transfer>")[1]?.split("</device-transfer>")[0] ?? "";

    // cloud-backup alone would still let a device-to-device transfer clone the
    // installation id onto a second phone.
    expect(cloud).toContain(`path="${CAPACITOR_STORE}.xml"`);
    expect(transfer).toContain(`path="${CAPACITOR_STORE}.xml"`);
  });

  it("is applied by every path that builds the Android project", () => {
    // android-config/ is only versioned config: it reaches the build through
    // explicit copies. A rule nobody copies is a rule that does not exist.
    const setup = readFileSync(path.resolve(__dirname, "../../scripts/setup-android.sh"), "utf8");
    const workflow = readFileSync(
      path.resolve(__dirname, "../../../.github/workflows/android-internal-testing.yml"),
      "utf8"
    );
    const pkg = readFileSync(path.resolve(__dirname, "../../package.json"), "utf8");

    expect(setup).toContain("android-config/res/xml/data_extraction_rules.xml");
    expect(workflow).toContain("android-config/res/xml/data_extraction_rules.xml");
    // android:sync copies res/ wholesale, which already carries res/xml.
    expect(pkg).toContain("cp -R android-config/res/.");
  });
});
