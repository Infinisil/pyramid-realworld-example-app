{ type ? "develop" }:
let
  nixpkgs = let cfg = builtins.fromJSON (builtins.readFile ./nixpkgs.json);
  in fetchTarball {
    url = "https://github.com/${cfg.owner}/${cfg.repo}/tarball/${cfg.rev}";
    sha256 = cfg.sha256;
  };
  pkgs = import nixpkgs {
    config = { allowUnfree = true; };
    overlays = [ ];
  };
  inherit (pkgs) lib;

  # TODO: Remove this when upgrading to nixos-20.03 when we can
  # use poetry from the stable channel
  unstableSrc = pkgs.srcOnly {
    name = "nixpkgs-unstable-src";
    src = fetchTarball {
      url = "https://github.com/nixos/nixpkgs/tarball/e94a84a144b83eebfcfb33ac3315c01d0d4b3a0a";
      sha256 = "12n3va055kn001mqps7yar090vf2h4riwczd0ma6l2vb0rf2gd36";
    };
    patches = [
      # https://github.com/NixOS/nixpkgs/pull/80880
      (pkgs.fetchpatch {
        url = "https://github.com/NixOS/nixpkgs/commit/8f5b5baed7eb09aa84e09bffb33a437e90186ba7.patch";
        sha256 = "057x5prxkvffd99v5pmvk2faliyk4qd4psf6bdqpwcc0839f7z0x";
      })
    ];
  };
  unstable = import unstableSrc {
    config = { };
    overlays = [ ];
  };

  dependencies = let
    mapping = {
      develop = developDeps ++ runDeps;
      build = runDeps;
      run = runDeps;
    };
  in mapping.${type} or (throw
    "${type} is not a valid shell type. Valid ones are ${
      toString (lib.attrNames mapping)
    }");

  stdenv = if type == "develop" then pkgs.stdenv else pkgs.stdenvNoCC;

  developDeps = with pkgs;
    [
      git
      b2sum
      libffi
      libxslt
      openssl
      python38Full
      which
      zlib
    ]

    # The watchdog Python lib has a few extra requirements on Darwin (MacOS)
    # Taken from https://github.com/NixOS/nixpkgs/blob/d72887e0d28a98cc6435bde1962e2b414224e717/pkgs/development/python-modules/watchdog/default.nix#L20
    ++ lib.optionals pkgs.stdenv.isDarwin [
      pkgs.darwin.apple_sdk.frameworks.CoreServices
      pkgs.darwin.cf-private
    ];

  # Only these dependencies are needed to run in production
  runDeps = with pkgs; [ (unstable.poetry.override { python = unstable.python38; }) curl postgresql_11 ];

in stdenv.mkDerivation {
  name = "dev-shell";
  buildInputs = dependencies;

  # Needed to be able to install Python packages from GitHub
  GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # Such that nixpkgs doesn't need to be downloaded again when running we make
  # it a dependency of the derivation. Also allows using `nix-shell -p` with the
  # correct nixpkgs version
  NIX_PATH = "nixpkgs=${nixpkgs}";
}
