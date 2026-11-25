cask "mactv-custom" do
  version "0.3.0"
  sha256 "d3ba974fb6786d2e111c43e003896c34142c7fb96f078cb93a98b5283efda9eb"

  url "https://github.com/Cocomong98/MacTV-Custom/releases/download/v#{version}/CouchDial-#{version}.dmg"
  name "CouchDial"
  desc "MacBook streaming app with an iPhone remote"
  homepage "https://github.com/Cocomong98/MacTV-Custom"

  depends_on macos: :sonoma

  app "MacTV Custom.app"

  uninstall quit: "local.couch.tv.custom"
end
