#!/usr/bin/env bash
# One-time setup: populate the five GitHub Actions secrets that .github/workflows/
# release.yml needs to sign & notarize the DMG.
#
# GitHub secret VALUES can never be read back out of a repo (the API is
# write-only), so the ones already in the ezdash repo can't be copied
# programmatically — they have to be re-supplied here. This script:
#   * exports the Developer ID Application identity from your login keychain
#     into a fresh .p12  ->  CSC_LINK + CSC_KEY_PASSWORD
#   * takes your App Store Connect API key (.p8) + its IDs
#                         ->  APPLE_API_KEY_P8 + APPLE_API_KEY_ID + APPLE_API_ISSUER
#
# Re-run any time to rotate. Requires the `gh` CLI authenticated to GitHub.
set -euo pipefail

REPO="${REPO:-yonigottesman/quill}"
IDENTITY="Developer ID Application: Yonatan Gottesman (29HD5Q85D4)"

echo "Setting CI secrets on $REPO"
echo

# --- Developer ID cert -> CSC_LINK / CSC_KEY_PASSWORD -----------------------
# `security export -t identities` grabs EVERY code-signing identity at once, so a
# single non-exportable key in the keychain (e.g. a Secure-Enclave / Xcode-managed
# one) fails the whole batch with "contents cannot be retrieved". There's no
# per-identity filter on the CLI, so export just the Developer ID identity via
# Keychain Access (GUI), then point this script at the resulting .p12.
security find-identity -v -p codesigning | grep -qF "$IDENTITY" \
  || { echo "error: '$IDENTITY' not found in your keychain" >&2; exit 1; }
cat <<EOF
Export the signing identity to a .p12 with Keychain Access:
  1. Keychain Access opens now → left sidebar 'login', Category 'My Certificates'.
  2. Find:  $IDENTITY
  3. Right-click it → Export "$IDENTITY"… → File Format: Personal Information Exchange (.p12)
  4. Save it, and set a password (you'll paste that same password below).
EOF
open -a "Keychain Access" 2>/dev/null || true
echo
read -r -p  "Path to the exported .p12: " p12_path
p12_path="${p12_path/#\~/$HOME}"
[ -f "$p12_path" ] || { echo "error: no file at $p12_path" >&2; exit 1; }
read -r -s -p "The .p12 password you just set: " p12_pwd; echo

gh secret set CSC_LINK         --repo "$REPO" < <(base64 < "$p12_path")
gh secret set CSC_KEY_PASSWORD --repo "$REPO" --body "$p12_pwd"
echo "  ✓ CSC_LINK, CSC_KEY_PASSWORD"
echo

# --- App Store Connect API key -> APPLE_API_* -------------------------------
# These come from App Store Connect → Users and Access → Integrations → Keys.
# The .p8 is downloadable only once; reuse the same file you put in ezdash.
read -r -p "Path to App Store Connect API key (.p8): " p8_path
p8_path="${p8_path/#\~/$HOME}"
[ -f "$p8_path" ] || { echo "error: no file at $p8_path" >&2; exit 1; }
read -r -p "APPLE_API_KEY_ID (the key's Key ID): " key_id
read -r -p "APPLE_API_ISSUER (the Issuer ID):    " issuer

gh secret set APPLE_API_KEY_P8 --repo "$REPO" < <(base64 < "$p8_path")
gh secret set APPLE_API_KEY_ID --repo "$REPO" --body "$key_id"
gh secret set APPLE_API_ISSUER --repo "$REPO" --body "$issuer"
echo "  ✓ APPLE_API_KEY_P8, APPLE_API_KEY_ID, APPLE_API_ISSUER"
echo
echo "Done. Verify with:  gh secret list --repo $REPO"
