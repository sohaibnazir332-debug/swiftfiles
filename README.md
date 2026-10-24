# SwiftFiles ⚡ — Android + Windows File Manager (Flutter)

Light-blue, clean, rounded-card UI. 1-tap rename, swipe actions, bulk operations,
instant search + category filters, cable ke bina wireless transfer, **ZIP extractor
(auto-delete ke sath)**, **Storage Optimizer (duplicate + badi files)**, **hidden files toggle**
aur **storage indicator**.

---

## 0. Sab se aasan raasta: GitHub se build (Flutter install ki zaroorat nahi)

1. GitHub par naya repository banayein (Public ya Private, dono theek)
2. Is zip ko PC par extract karein. `swift_files` folder ke **andar** ki sab cheezein (`lib`, `pubspec.yaml`, `android_patch`, `README.md`) repo mein upload karein (*Add file → Upload files*)
3. Workflow file alag se banayein (hidden folder upload mein kabhi chhoot jata hai): *Add file → Create new file* → naam mein likhein `.github/workflows/build.yml` → zip wali `build.yml` ka text paste karein → *Commit*
4. **Actions** tab → *Build SwiftFiles* → **Run workflow**
5. 5–10 minute baad run kholein → neeche **Artifacts**: `SwiftFiles-Android-APK` (phone par install) aur `SwiftFiles-Windows` (PC par `swift_files.exe` chalayein)
6. Agar run lal ❌ ho: run kholein → ❌ wale step par click → **"Code check"** step ka text copy karke bhej dein

Neeche wale steps sirf tab chahiye jab aap apne computer par khud build karna chahein.

---

## 1. Setup (ek baar)

1. **Flutter SDK** install karein: https://flutter.dev → Install → Windows
2. **Android Studio** install karein (Android SDK ke liye) + phone par *USB debugging* ON karein
3. **Windows app ke liye:** Visual Studio 2022 install karein, aur usme
   **"Desktop development with C++"** workload select karein
4. Windows Settings → *For developers* → **Developer Mode ON** (plugins ke liye zaroori)
5. Terminal mein check karein:
   ```
   flutter doctor
   ```
   Jo bhi ❌ dikhe use theek karein (ya mujhe screenshot bhejein).

## 2. Project banayein

Is zip ko extract karke, **Flutter ka naya project banayein** (taake android/windows
folders ban jayein), phir hamari files uske upar copy karein:

```
flutter create --org com.swiftfiles --project-name swift_files --platforms=android,windows swift_files_app
```

Phir:
- zip ke andar ka **`lib/` folder** → `swift_files_app/lib/` (purani `lib` replace kar dein)
- zip ke andar ki **`pubspec.yaml`** → `swift_files_app/pubspec.yaml` (replace)

## 3. Android permissions (zaroori)

File: `android/app/src/main/AndroidManifest.xml`

`<manifest ...>` ke andar, `<application>` se **pehle** ye lines add karein:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
```

Aur `<application` tag ke andar ye attribute add karein:

```xml
android:requestLegacyExternalStorage="true"
```

### Storage indicator ke liye (Android, optional magar recommended)

Zip ke andar `android_patch/MainActivity.kt` hai. Ise yahan copy karein (purani file replace):

```
swift_files_app/android/app/src/main/kotlin/com/swiftfiles/swift_files/MainActivity.kt
```

Ye na karein to app bilkul theek chalegi, bas phone ka storage-bar nahi dikhega.
(Windows par iski zaroorat nahi, wahan PowerShell se khud pata chal jata hai.)

> Note: `MANAGE_EXTERNAL_STORAGE` personal use ke liye bilkul theek hai.
> Play Store par publish karna ho to Google ki alag approval lagti hai.

## 4. Run karein

```
cd swift_files_app
flutter pub get
flutter run -d windows        # PC par
flutter run                   # phone connected ho to Android par
```

## 5. Release build (installable)

```
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release   # build/windows/x64/runner/Release/
```

---

## Features aur kaise use karein

| Feature | Kaise |
|---|---|
| **1-tap Rename** | Tile ko **right swipe** karein (PC par ✏️ button ya `F2`). Mobile par ✏️ button nahi dikhta taake list saaf rahe |
| **Quick Delete** | Tile ko **left swipe** karein (PC par `Del`). File pehle **Trash** mein jati hai, 5 second tak **UNDO** milta hai |
| **Bulk select** | Icon par tap ya long press → baaki files tap karein (PC: `Ctrl+A`) |
| **Batch Rename** | 2+ files select → ✏️ → prefix / suffix / numbering, live preview ke sath |
| **Move** | Select → 📁 Move → destination folder kholein → **Yahan paste** |
| **Search + Filter** | Upar search box, neeche Images / Videos / Audio / Docs / Archives chips. Poori storage mein dhoondta hai, aur category par **badi files pehle** dikhata hai |
| **ZIP Extract** | ZIP / TAR / TAR.GZ / TGZ par **tap** karein → foran usi jagah naye folder (archive ke naam se) mein extract. Phir ya to sheet aati hai (*Folder kholein* / *ZIP delete karein*), ya agar ⋮ menu mein **"Extract ke baad ZIP delete"** ON hai to ZIP khud delete ho jati hai (5 sec **UNDO**, uske baad hamesha ke liye — storage sach mein bachti hai) |
| **Hidden files** | ⋮ menu → *Hidden files dikhayein* (tick ON/OFF, setting yaad rehti hai) |
| **⭐ Important / Favorites** | Item select karke header ka ⭐ dabayein (PC par tile ka ⭐ button). Marked items par chhota star dikhta hai (star par tap = hata do). Upar **Favorites** chip (PC par sidebar mein) = saari important files ek click mein, kisi bhi folder se |
| **Folder items** | Har folder ke niche **N items** likha aata hai (khali par **0 items**, icon halka "khula"), andar jaye bina pata chal jata hai |
| **Time** | Size ke saath chhota time: `2.4 MB • 4:35 PM` (aaj), `23 Oct` (is saal). ⋮ menu → *Time dikhayein* se band karein |
| **Image thumbnails** | Images ke icon ki jagah unka chhota preview |
| **Storage indicator** | Mobile par Home folder ke sab se upar card, PC par sidebar mein: kitni jagah use hui / khali hai. Card par tap → Storage Optimizer |
| **Storage Optimizer** | ⋮ menu → *Storage Optimizer* (ya storage card par tap) → **Scan** → *Badi files* (50 MB+) aur *Duplicates* (hash se, ek jaisi files). **Smart select** har group mein sabse purani copy rakh kar baaki chun deta hai. Delete → Trash + UNDO, aur wahin se *Trash saaf karein* |
| **Wireless Transfer** | Wireless button → Start → dusre device ke browser mein address / QR + PIN |
| **Trash saaf** | ⋮ menu → *Trash saaf karein* (jagah khali hoti hai) |

## Wireless Transfer kaise kaam karta hai

App ke andar chhota local web server chalta hai. Dusra device sirf **browser** kholta hai
(koi app install nahi chahiye).

- **PC → Mobile:** Mobile par Transfer start karein → PC ke browser mein address kholein → files upload karein
- **Mobile → PC:** PC par Transfer start karein → mobile ke browser mein address kholein → files upload karein
- Files `Download/SwiftFiles` folder mein aati hain
- **Safety:** 4-digit PIN lagta hai, sirf same Wi-Fi par chalta hai, 10 galat PIN ke baad lock ho jata hai
- Windows par pehli baar **Firewall** poochay to **Private networks** par *Allow* karein

## Folder structure

```
lib/
├── main.dart                     App ka entry point
├── core/
│   ├── theme.dart                🎨 Rang (light blue) aur theme — rang yahin badlein
│   └── format.dart               Size / date formatting
├── models/
│   └── file_item.dart            File ka model + category (Images, Videos...)
├── services/
│   ├── file_service.dart         List, search, rename, batch rename, move, trash
│   ├── archive_service.dart      ZIP/TAR/TGZ extract (alag isolate, zip-slip safe)
│   ├── optimizer_service.dart    Badi files + duplicate scan (alag isolate)
│   ├── storage_info.dart         Total / khali storage (Android channel, Windows PowerShell)
│   ├── transfer_service.dart     Wireless transfer server
│   └── web_page.dart             Dusre device ke browser ka page
├── providers/
│   ├── browser_provider.dart     State (Riverpod): folder, selection, filters, hidden toggle
│   └── settings_provider.dart    Yaad rakhi jane wali settings (auto-delete ZIP, hidden files)
└── ui/
    ├── home_screen.dart          Main screen (header, chips, list, sidebar)
    ├── transfer_screen.dart      Wireless transfer screen (QR + PIN)
    ├── optimizer_screen.dart     Storage Optimizer screen
    ├── dialogs.dart              Rename aur Batch Rename dialogs
    └── widgets/
        ├── file_tile.dart        Swipe wali file row
        ├── file_icon.dart        Icons aur rang
        └── storage_card.dart     Storage indicator card
```

## Aam masle

- **"Permission dein" screen aati rahe** → Settings → Apps → SwiftFiles → Permissions → *All files access* ON
- **Windows par plugin/symlink error** → Developer Mode ON karein (Step 1.4)
- **Dusra device connect na ho** → dono same Wi-Fi par hain? Windows Firewall mein *Private* allow hai?
- **Koi bhi error aaye** → poora error text copy karke mujhe bhej dein, main theek karwa dunga

## Optimizer ki safety

- Scan sirf **dikhata** hai, delete aap khud chunte hain; delete hamesha Trash + UNDO ke raste se
- Har duplicate group mein **kam az kam ek copy** hamesha bachi rehti hai (app khud rok deti hai)
- Windows par `AppData`, Android par `Android/` folder scan nahi hota (system/apps kharab na hon)
- RAR / 7z abhi extract nahi hote (sirf ZIP, TAR, TAR.GZ, TGZ)

## Agla step (roadmap)

- 🌙 Dark mode, grid view, image thumbnails
- ⭐ Favorites aur recent files
- RAR / 7z support
