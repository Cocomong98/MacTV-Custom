cask "mactv-custom" do
  version "0.4.0"
  sha256 "aec6ad70a773e03d101330999163bbe3187581478372868feb57f7763f99061e"

  url "https://github.com/Cocomong98/MacTV-Custom/releases/download/v#{version}/CouchDial-#{version}.dmg"
  name "CouchDial"
  desc "MacBook streaming app with an iPhone remote"
  homepage "https://github.com/Cocomong98/MacTV-Custom"

  depends_on macos: :sonoma

  app "MacTV Custom.app"

  uninstall quit: "local.couch.tv.custom"
end
