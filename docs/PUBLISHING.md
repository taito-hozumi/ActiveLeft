# Publishing Checklist

Use this checklist before making the repository public.

1. Build the app bundle:

   ```bash
   ./scripts/build_app.sh release
   ```

2. Run the smoke test:

   ```bash
   ./scripts/self_test.sh
   ```

3. Confirm generated artifacts are ignored:

   ```bash
   git status --short --ignored
   ```

4. Create a GitHub repository named `ActiveLeft`, then push:

   ```bash
   git remote add origin git@github.com:hozumitaito/ActiveLeft.git
   git branch -M main
   git push -u origin main
   ```

5. Suggested repository metadata:

   - Description: `Tiny macOS menu bar toggle for display-only caffeinate mode`
   - Topics: `macos`, `menubar`, `caffeinate`, `sleep`, `appkit`, `swift`

6. Optional later polish:

   - Add a screenshot or short GIF of the menu bar state.
   - Add signed/notarized release artifacts if distributing binaries.
