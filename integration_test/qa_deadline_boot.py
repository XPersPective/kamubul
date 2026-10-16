"""Real reboot/receiver check for the pinned disposable SA-015 QA APK only."""
import json
import os
import re
import subprocess
import time
from pathlib import Path

ADB = Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/platform-tools/adb.exe"
SERIAL = "emulator-5556"
PACKAGE = "com.crazypenguin.kamubul"
APK_HASH = "b0bc202c0186fa22f3df0bdcc2b95e092758debefa5a5b68ad228b226175fd74"
STATE = "no_backup/deadline-reminders.v1"
URL = "https://www.ilan.gov.tr/ilan/sa015-device-test"


def adb(*args, data=None, check=True):
    return subprocess.run(
        [str(ADB), "-s", SERIAL, *args], input=data, capture_output=True,
        text=True, encoding="utf-8", errors="replace", timeout=15, check=check,
    ).stdout.strip()


def read():
    return json.loads(adb("shell", "run-as", PACKAGE, "cat", STATE))


def write(state):
    # Test fixture only. No production inspection API or clock/permission changes.
    adb("shell", "run-as", PACKAGE, "sh", "-c", f"'cat > {STATE}'",
        data=json.dumps(state, ensure_ascii=False))
    assert read() == state


def own_notifications():
    return [line for line in adb("shell", "dumpsys", "notification").splitlines()
            if "NotificationRecord(" in line and f"pkg={PACKAGE} " in line]


def main():
    assert adb("emu", "avd", "name").splitlines()[0] == "kamubul_sa015_qa"
    apk = adb("shell", "pm", "path", PACKAGE)
    assert re.fullmatch(r"package:/data/app/[-_.~A-Za-z0-9/=]+/base\.apk", apk), apk
    assert adb("shell", "sha256sum", apk[8:]).split()[0] == APK_HASH
    original = read()
    assert original["enabled"] is False and not original["plans"]
    assert all(p["url"] == URL for p in original["sent"]), "Non-fixture data: abort"
    assert not own_notifications(), "Unexpected existing notification: abort"
    # The Flutter test harness force-stops on exit. A real launcher start clears it.
    adb("shell", "am", "start", "-n", f"{PACKAGE}/.MainActivity")
    package = adb("shell", "dumpsys", "package", PACKAGE)
    assert "stopped=false" in package
    # ponytail: the paused integration launcher may never become a used app.
    # Use a normally rendered QA app and refresh the pinned hash before boot QA.
    bucket = adb("shell", "am", "get-standby-bucket", PACKAGE)
    assert bucket != "50", "Never-used integration fixture: normal interactive QA APK required"
    now = int(adb("shell", "date", "+%s")) * 1000
    assert 8 <= ((now // 3600000 + 3) % 24) < 22, "Quiet hours: defer this delivery check"
    identifier = max(42, original["nextId"])
    fixture = {
        "version": 1, "enabled": True, "nextId": identifier + 1, "sent": [],
        "plans": [{"id": identifier, "url": URL,
                   "title": "SA015 yeniden başlatma testi — üretim ilanı değildir",
                   "at": now + 180000, "expires": now + 86400000}],
    }
    try:
        write(fixture)
        print("FIXTURE_BEFORE_REBOOT", json.dumps(fixture), flush=True)
        adb("reboot")
        boot_deadline = time.monotonic() + 150
        while time.monotonic() < boot_deadline:
            try:
                if adb("shell", "getprop", "sys.boot_completed", check=False) == "1":
                    break
            except subprocess.TimeoutExpired:
                pass
            time.sleep(2)
        else:
            raise AssertionError("QA reboot did not complete within150s")
        print("BOOT_PROPERTY_SET: waiting for actual receiver/AlarmManager", flush=True)
        restore_deadline = time.monotonic() + 60
        while time.monotonic() < restore_deadline:
            alarms = adb("shell", "dumpsys", "alarm")
            own_alarms = [line.strip() for line in alarms.splitlines()
                          if f"{PACKAGE}/.DeadlineReminderReceiver" in line]
            if own_alarms:
                break
            time.sleep(2)
        else:
            raise AssertionError("Persisted-only fixture was not restored within60s of boot property")
        assert read() == fixture, "Boot must retain the persisted plan"
        print("BOOT_RESTORED_ALARM", json.dumps(own_alarms), flush=True)
        delivery_deadline = time.monotonic() + 240
        while time.monotonic() < delivery_deadline:
            state, notifications = read(), own_notifications()
            if notifications and not state["plans"] and len(state["sent"]) == 1:
                assert state["sent"][0]["url"] == URL
                assert f"id={identifier} " in notifications[0]
                assert "tag=kamubul.deadline" in notifications[0]
                print("BOOT_DELIVERED", json.dumps(state), notifications[0], flush=True)
                break
            time.sleep(2)
        else:
            raise AssertionError("Inexact notification not observed within240s; not a delivery guarantee")
    finally:
        # Restore only our known disposable fixture and stop its package/alarms.
        original["nextId"] = identifier + 1
        write(original)
        adb("shell", "am", "force-stop", PACKAGE)
        assert not own_notifications(), "QA notification cleanup failed"
        print("QA_CLEANUP", json.dumps(read()), flush=True)
    print("PASS: real reboot restored and delivered the persisted-only QA fixture", flush=True)


if __name__ == "__main__":
    main()
