class Flow < Formula
  desc "Statically typed language with algebraic effects, autodiff, and a C backend"
  homepage "https://flooooooooooow.github.io/flow/"
  url "https://github.com/flooooooooooow/flow/releases/download/v2.0.0/flow-v2.0.0.tar.gz"
  sha256 "6fc8ce236e4d950f4b841ba20c64be3cad14efe004bd805624364f8d47f96a3e"
  license :cannot_represent
  head "https://github.com/flooooooooooow/flow.git", branch: "main"

  # flowc builds from checked-in bootstrap C; the CLI also shells out to cc
  # when compiling user programs.
  on_linux do
    depends_on "gcc"
  end

  def install
    # Mirror packaging/nix/default.nix: build flowc from the checked-in
    # bootstrap C, then emit and compile tools/flow_cli into build/cli/flow.
    mkdir_p "compiler/build"
    mkdir_p "build/cli"
    system ENV.cc, "-O2", "-w", "-o", "compiler/build/flowc_bootstrap",
           "compiler/bootstrap/flowc_stage_a.c", "-lm"
    system "env",
           "FLOWC_BUNDLE=1",
           "FLOWC_DIR=.",
           "FLOWC_TYPECHECK=1",
           "FLOWC_IN=tools/flow_cli/main.flow",
           "FLOWC_OUT=#{buildpath}/build/cli/flow.c",
           "./compiler/build/flowc_bootstrap"
    system ENV.cc, "-O1", "-w", "-o", "build/cli/flow", "build/cli/flow.c", "-lm"
    rm "build/cli/flow.c"

    libexec.install "compiler", "lib", "runtime", "tools", "scripts", "registry",
                    "build", "flow", "flow-lsp", "flow.toml", "VERSION"
    libexec.install "examples" if (buildpath/"examples").exist?

    chmod 0755, libexec/"flow"
    chmod 0755, libexec/"flow-lsp" if (libexec/"flow-lsp").exist?

    # The Cellar is read-only after install. Drop the stub's user-cache
    # fallback so it keeps using the prebuilt CLI and bootstrap compiler.
    inreplace libexec/"flow",
              '[ -w "$root" ] || cache=${XDG_CACHE_HOME:-$HOME/.cache}/flow', ""
    inreplace libexec/"flow",
              '[ -w "$root" ] || boot=$cache/flowc_bootstrap', ""

    # Mirror the Nix store contract: keep libexec/build immutable so the
    # CLI's cache_dir (tools/flow_cli/toolchain.flow) falls back to the
    # user cache. An existing owner-writable build/ fools brew test's
    # landlock sandbox (unix write bits still look ok) into a path it
    # cannot create run directories in.
    chmod 0555, libexec/"build"

    cc = OS.mac? ? "cc" : ENV.cc
    path_prefix = OS.linux? ? "#{Formula["gcc"].opt_bin}:" : ""

    # Compiled programs go under the user cache; FLOW_BUILD_ROOT stays
    # overridable. On Linux, put Homebrew gcc on PATH and pin CC.
    %w[flow flow-lsp].each do |cmd|
      next unless (libexec/cmd).exist?

      (bin/cmd).write <<~SH
        #!/bin/bash
        set -e
        export FLOW_BUILD_ROOT="${FLOW_BUILD_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/flow/build}"
        export PATH="#{path_prefix}$PATH"
        export CC="${CC:-#{cc}}"
        exec "#{libexec}/#{cmd}" "$@"
      SH
      chmod 0755, bin/cmd
    end
  end

  def caveats
    <<~EOS
      Flow #{version} uses the self-hosted flowc compiler (no Python).
      It compiles programs to C and shells out to a C toolchain at run time.
      On macOS, install the Xcode Command Line Tools if needed:
        xcode-select --install

      For MLIR / JIT support, also install LLVM and put it on PATH:
        brew install llvm
        export PATH="$(brew --prefix llvm)/bin:$PATH"

      Use `brew install --HEAD flow` to track main.
    EOS
  end

  test do
    output = shell_output("#{bin}/flow version")
    if version.head?
      assert_match(/^Flow \d+\.\d+\.\d+/, output)
    else
      assert_match "Flow #{version}", output
    end
    assert_match(/host:\s*flowc/, output)

    (testpath/"hello.flow").write <<~FLOW
      function main() -> i32 {
          println("brew ok")
          return 0
      }
    FLOW
    assert_match "brew ok", shell_output("#{bin}/flow run #{testpath}/hello.flow")
  end
end
