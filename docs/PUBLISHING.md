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

3. Optionally check the login-item installer with a temporary install path and label:

   ```bash
   if pgrep -x ActiveLeft >/dev/null 2>&1; then
     echo "Quit ActiveLeft before running the installer smoke test." >&2
     exit 1
   fi

   tmp_install_dir="$(mktemp -d)"
   tmp_label="com.example.activeleft.publish-test.$$"
   ACTIVELEFT_INSTALL_DIR="$tmp_install_dir" ACTIVELEFT_LAUNCH_AGENT_LABEL="$tmp_label" ./scripts/install_launch_agent.sh
   ACTIVELEFT_INSTALL_DIR="$tmp_install_dir" ACTIVELEFT_LAUNCH_AGENT_LABEL="$tmp_label" ./scripts/uninstall_launch_agent.sh
   rmdir "$tmp_install_dir"
   ```

4. Confirm generated artifacts are ignored:

   ```bash
   git status --short --ignored
   ```

5. Create a GitHub repository named `ActiveLeft`, then push:

   ```bash
   git remote add origin git@github.com:taito-hozumi/ActiveLeft.git
   git branch -M main
   git push -u origin main
   ```

6. Suggested repository metadata:

   - Description: `Tiny macOS menu bar toggle for display-only caffeinate mode`
   - Topics: `macos`, `menubar`, `caffeinate`, `sleep`, `appkit`, `swift`

7. Optional later polish:

   - Add a screenshot or short GIF of the menu bar state.
   - Add signed/notarized release artifacts if distributing binaries.
