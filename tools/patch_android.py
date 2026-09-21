#!/usr/bin/env python3
"""
Patches the android/ folder that `flutter create` generates so that it:
  * applies the Google Services (Firebase) Gradle plugin
  * sets minSdk 23
  * enables core-library desugaring (needed by flutter_local_notifications)
  * declares the permissions we need and a friendly app name
  * contains google-services.json
Works with both Kotlin-DSL (.kts) and Groovy Gradle files.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"
APP = ANDROID / "app"
PACKAGE = "com.teabreak.circles"


def find(folder, *names):
    for n in names:
        p = folder / n
        if p.exists():
            return p
    sys.exit(f"ERROR: none of {names} found in {folder}")


def insert_after(text, pattern, addition, what):
    m = re.search(pattern, text, re.M)
    if not m:
        sys.exit(f"ERROR: could not find {what}")
    return text[: m.end()] + addition + text[m.end():]


# ---------------------------------------------------------------- settings
settings = find(ANDROID, "settings.gradle.kts", "settings.gradle")
s = settings.read_text()
if "com.google.gms.google-services" not in s:
    kts = settings.suffix == ".kts"
    line = ('    id("com.google.gms.google-services") version "4.4.2" apply false\n'
            if kts else
            '    id "com.google.gms.google-services" version "4.4.2" apply false\n')
    s = insert_after(s, r'^[ \t]*id\(?\s*"com\.android\.application"[^\n]*\n', line,
                     "com.android.application plugin in settings.gradle")
    settings.write_text(s)

# ---------------------------------------------------------------- app gradle
build = find(APP, "build.gradle.kts", "build.gradle")
kts = build.suffix == ".kts"
b = build.read_text()

if "com.google.gms.google-services" not in b:
    line = ('    id("com.google.gms.google-services")\n' if kts
            else '    id "com.google.gms.google-services"\n')
    b = insert_after(b, r'^[ \t]*id\(?\s*"com\.android\.application"[^\n]*\n', line,
                     "com.android.application plugin in app/build.gradle")

# minSdk 23
b, n = re.subn(r'(minSdk(?:Version)?)(\s*=\s*|\s+)flutter\.minSdkVersion', r'\g<1>\g<2>23', b)
if n == 0:
    print("WARNING: minSdk line not found, leaving as is")

# desugaring
if "oreLibraryDesugaring" not in b:
    flag = ("        isCoreLibraryDesugaringEnabled = true\n" if kts
            else "        coreLibraryDesugaringEnabled true\n")
    b = insert_after(b, r'compileOptions\s*\{[ \t]*\n', flag, "compileOptions block")
    dep = ('    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n' if kts
           else "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n")
    if re.search(r'^dependencies\s*\{', b, re.M):
        b = insert_after(b, r'^dependencies\s*\{[ \t]*\n', dep, "dependencies block")
    else:
        b += "\ndependencies {\n" + dep + "}\n"
build.write_text(b)

# ---------------------------------------------------------------- manifest
manifest = APP / "src/main/AndroidManifest.xml"
m = manifest.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.VIBRATE",
    "android.permission.WAKE_LOCK",
]
add = "".join(
    f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m
)
if add:
    m = m.replace("<application", add + "    <application", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Tea Circles"', m, count=1)
manifest.write_text(m)

# ---------------------------------------------------------------- google-services.json
src = ROOT / "google-services.json"
data = json.loads(src.read_text())
packages = [
    c["client_info"]["android_client_info"]["package_name"]
    for c in data.get("client", [])
]
if PACKAGE not in packages:
    sys.exit(
        f"ERROR: google-services.json is for {packages}, but the app id is {PACKAGE}. "
        f"Register an Android app with package name {PACKAGE} in Firebase and download the file again."
    )
(APP / "google-services.json").write_text(src.read_text())

print("Android project patched OK (" + ("kts" if kts else "groovy") + ")")
