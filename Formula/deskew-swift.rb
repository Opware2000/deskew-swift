class DeskewSwift < Formula
  desc "Deskew scanned documents (Swift reimplementation of Deskew)"
  homepage "https://github.com/Opware2000/deskew-swift"
  url "https://github.com/Opware2000/deskew-swift/releases/download/v0.2.0/deskew-macos-universal"
  sha256 "59e0f39a7bc16cb7ceb416f1c304a18f2a145c320eff7124153a6987ac5de30f"
  version "0.2.0"
  license "MPL-2.0"

  depends_on macos: :ventura

  def install
    bin.install "deskew-macos-universal" => "deskew"
  end

  test do
    assert_match "Deskew", shell_output("#{bin}/deskew 2>&1", 1)
  end
end
