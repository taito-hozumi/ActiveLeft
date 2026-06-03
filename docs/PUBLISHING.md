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

3. Optionally check the login-item installer with a temporary install path:

   ```bash
   tmp_install_dir="$(mktemp -d)"
   ACTIVELEFT_INSTALL_DIR="$tmp_install_dir" ./scripts/install_launch_agent.sh
   ACTIVELEFT_INSTALL_DIR="$tmp_install_dir" ./scripts/uninstall_launch_agent.sh
   rmdir "$tmp_install_dir"
   ```

4. Confirm generated artifacts are ignored:

   ```bash
   git status --short --ignored
   ```

5. Create a GitHub repository named `ActiveLeft`, then push:

   ```bash
   git remote add origin git@github.com:hozumitaito/ActiveLeft.git
   git branch -M main
   git push -u origin main
   ```

6. Suggested repository metadata:

   - Description: `Tiny macOS menu bar toggle for display-only caffeinate mode`
   - Topics: `macos`, `menubar`, `caffeinate`, `sleep`, `appkit`, `swift`

7. Optional later polish:

   - Add a screenshot or short GIF of the menu bar state.
   - Add signed/notarized release artifacts if distributing binaries.
