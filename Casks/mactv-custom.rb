cask "mactv-custom" do
  version "0.3.1"
  sha256 "95955be5ae40d47edbc137777763542a9fa9c0fa599003607f860f5655aa5a8b"

  url "https://github.com/Cocomong98/MacTV-Custom/releases/download/v#{version}/CouchDial-#{version}.dmg"
  name "CouchDial"
  desc "MacBook streaming app with an iPhone remote"
  homepage "https://github.com/Cocomong98/MacTV-Custom"

  depends_on macos: :sonoma

  app "MacTV Custom.app"

  uninstall quit: "local.couch.tv.custom"
end
