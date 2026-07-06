# TEMPLATE — do not hand-bump; version/sha256 below are placeholders.
# On every release, release.yml renders this file with the real values
# (scripts/render-cask.sh) and pushes it to the tap repo
# fr1j0/homebrew-hive-light — which is what `brew install` reads.

cask "hive-light" do
  version "0.0.0-dev"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/fr1j0/hive-light/releases/download/v#{version}/hive-light.zip"
  name "Hive Light"
  desc "Menu-bar status light for Claude Code sessions"
  homepage "https://github.com/fr1j0/hive-light"

  depends_on macos: :ventura

  app "Hive Light.app"

  caveats <<~EOS
    Launch Hive Light, then use "Install Claude Code hooks" from the menu
    to wire it into ~/.claude/settings.json.

    Current releases are unsigned interim builds (Apple notarization pending),
    so Gatekeeper may report the app as "damaged and can't be opened".
    Clear the quarantine flag and launch again:
      xattr -dr com.apple.quarantine "#{appdir}/Hive Light.app"
  EOS
end
