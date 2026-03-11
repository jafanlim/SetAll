# SetAll | Multi-Environment Sync Guide

GitHub `main` is the primary source of truth for releases, while `develop` is used for integration and testing. Features must be verified on both macOS and Windows before being merged to `main`.

### 1. The Development Workflow

1. **Start on Mac (Feature Development):**
   - Create a feature branch: `git checkout -b feature/your-feature-name`.
   - Implement logic and UI.
   - Push to GitHub: `git push origin feature/your-feature-name`.

2. **Switch to Windows VM (Parity Verification):**
   - Open PowerShell in `C:\Users\jafa\developer\SetAll`.
   - Fetch and checkout: `git fetch` then `git checkout feature/your-feature-name`.
   - Run the app: `flutter run -d windows`.

3. **The Parity Checklist:**
   - **Context Menus:** Does right-click (secondary tap) work as expected on the desktop?
   - **UI Scaling:** Does the Control Center and update banner look correct on Windows 11?
   - **Sync Integrity:** Does data added on Mac appear on Windows (and vice versa) after a sync tick?
   - **Platform Tweaks:** If Windows requires specific adjustments, commit them directly from the VM.

4. **Merging to Develop:**
   - Once both platforms are green, merge the feature branch into `develop`.
   - Test the "Testing Release" builds triggered from the `develop` branch.

5. **Final Release to Main:**
   - Merge `develop` into `main` only after full manual validation of the generated `.dmg` and `.exe` artifacts.

### 2. Full Paths for Reference
- **Mac Repository:** `/Users/jafa/developer/SetAll`
- **Windows Repository:** `C:\Users\jafa\developer\SetAll` (Native C: drive to avoid file locks)
- **Flutter SDK (Windows):** `C:\flutter`

### 3. The "Anti-Drift" Rule
Never implement a UI feature using platform-specific libraries without providing a fallback or equivalent for the other platform. If you add "Swipe to Delete" for mobile/macOS, you must ensure a "Right-click/Context Menu Delete" exists for Windows.

### 4. Release Protocol
1. Increment version in `pubspec.yaml`.
2. Commit and Tag (e.g., `v1.2.4`).
3. Push Tag: `git push origin v1.2.4`.
4. GitHub Actions will build the macOS `.dmg` (with ad-hoc signing) and Windows `.exe` automatically.