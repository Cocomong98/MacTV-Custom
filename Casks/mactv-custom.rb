cask "mactv-custom" do
  version "0.2.0"
  sha256 "e6d548c08e1468a951e84190255bf3a442e84951226018de0853493503d86be9"

  url "https://github.com/Cocomong98/MacTV-Custom/releases/download/v#{version}/MacTV-Custom-#{version}.dmg"
  name "MacTV Custom"
  desc "MacBook streaming app with an iPhone remote"
  homepage "https://github.com/Cocomong98/MacTV-Custom"

  depends_on macos: :sonoma

  app "MacTV Custom.app"

  uninstall quit: "local.couch.tv.custom"
end
