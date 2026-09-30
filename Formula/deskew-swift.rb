class DeskewSwift < Formula
  desc "Deskew scanned documents (Swift reimplementation of Deskew)"
  homepage "https://github.com/Opware2000/deskew-swift"
  url "https://github.com/Opware2000/deskew-swift/releases/download/v0.4.0/deskew-macos-universal"
  sha256 "22d92bb287a802e1e7987664506670bcb1133b5536aa4575cb4c32a8bd4e5ee6"
  version "0.4.0"
  license "MPL-2.0"

  depends_on macos: :ventura

  def install
    bin.install "deskew-macos-universal" => "deskew"
  end

  test do
    assert_match "Deskew", shell_output("#{bin}/deskew 2>&1", 1)
  end
end
