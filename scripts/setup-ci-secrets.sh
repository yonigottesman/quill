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
# Export the identity (cert + private key) to a temp .p12 protected by a random
# password. macOS will pop a keychain-access prompt — approve it. `security
# export` has no per-identity filter, so this exports every code-signing identity
# in the keychain into the .p12; that's fine — xcodebuild selects the right one
# by name ("Developer ID Application") at sign time.
security find-identity -v -p codesigning | grep -qF "$IDENTITY" \
  || { echo "error: '$IDENTITY' not found in your keychain" >&2; exit 1; }
p12="$(mktemp -t quill-cert).p12"
p12_pwd="$(uuidgen)"
echo "Exporting code-signing identities from the login keychain (approve the keychain prompt)…"
security export -t identities -f pkcs12 -P "$p12_pwd" -o "$p12"

gh secret set CSC_LINK         --repo "$REPO" < <(base64 < "$p12")
gh secret set CSC_KEY_PASSWORD --repo "$REPO" --body "$p12_pwd"
rm -f "$p12"
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
