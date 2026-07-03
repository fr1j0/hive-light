# This cask is mirrored to the tap repo fr1j0/homebrew-claude-light at Casks/claude-light.rb.
# On each release: bump `version` and `sha256` (copy the value from the release's
# claude-light.zip.sha256 file).

cask "claude-light" do
  version "0.9.0"
  sha256 "3db37bbb3309af3f2567db7ae7f4dde76b1aa6336f59416d5b69e31480748f33"

  url "https://github.com/fr1j0/claude-light/releases/download/v#{version}/claude-light.zip"
  name "Claude Light"
  desc "Menu-bar status light for Claude Code sessions"
  homepage "https://github.com/fr1j0/claude-light"

  depends_on macos: :ventura

  app "Claude Light.app"

  caveats <<~EOS
    Launch Claude Light, then use "Install Claude Code hooks" from the menu
    to wire it into ~/.claude/settings.json.

    Current releases are unsigned interim builds (Apple notarization pending),
    so Gatekeeper may report the app as "damaged and can't be opened".
    Clear the quarantine flag and launch again:
      xattr -dr com.apple.quarantine "#{appdir}/Claude Light.app"
  EOS
end
