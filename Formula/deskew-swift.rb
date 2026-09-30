class DeskewSwift < Formula
  desc "Deskew scanned documents (Swift reimplementation of Deskew)"
  homepage "https://github.com/Opware2000/deskew-swift"
  url "https://github.com/Opware2000/deskew-swift/releases/download/v0.3.0/deskew-macos-universal"
  sha256 "ba8c7994ec64be107afdcff662d1e910801319b3e9d026df6023b6c340e165da"
  version "0.3.0"
  license "MPL-2.0"

  depends_on macos: :ventura

  def install
    bin.install "deskew-macos-universal" => "deskew"
  end

  test do
    assert_match "Deskew", shell_output("#{bin}/deskew 2>&1", 1)
  end
end
