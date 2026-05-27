{
  description = "Nixstasis packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
      let
        pkgs = import nixpkgs { inherit system; };
        frpVersion = "0.68.1";
        frpPlatform = {
          aarch64-linux = {
            arch = "arm64";
            hash = "sha256-560VsM/kzwEl30IXd4tmy0QmF5JwlntZkA7LI2LYzQE=";
          };
          x86_64-linux = {
            arch = "amd64";
            hash = "sha256-Sk6ImH05Vh4bOzsj0O3kikV+6/dqhyMZmZV+hw9fArY=";
          };
        }.${system};
        frpc = pkgs.stdenvNoCC.mkDerivation {
          pname = "frpc";
          version = frpVersion;

          src = pkgs.fetchurl {
            url = "https://github.com/fatedier/frp/releases/download/v${frpVersion}/frp_${frpVersion}_linux_${frpPlatform.arch}.tar.gz";
            hash = frpPlatform.hash;
          };

          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin"
            tar -xzf "$src" --wildcards '*/frpc' --strip-components=1
            install -m0755 frpc "$out/bin/frpc"
            runHook postInstall
          '';
        };
        nixstasis-client = pkgs.buildGoModule {
          pname = "nixstasis-client";
          version = "0.0.0";

          src = ./packages/client;
          modRoot = ".";
          vendorHash = "sha256-YcSImzcTNhVLNq9vFnDA0PIgQJYZm+HqMxHGHqW3CH4=";

          env.CGO_ENABLED = "0";
          env.GOEXPERIMENT = "jsonv2";

          subPackages = [ "cmd/nixstasis" ];
          ldflags = [
            "-s"
            "-w"
          ];

          postInstall = ''
            mkdir -p "$out/libexec/nixstasis" "$out/share/nixstasis"
            ln -s ${frpc}/bin/frpc "$out/libexec/nixstasis/frpc"
            install -m0644 build/root-dir/usr/share/nixstasis/frpc.toml "$out/share/nixstasis/frpc.toml"
            install -m0644 build/root-dir/usr/share/nixstasis/config.example.yaml "$out/share/nixstasis/config.example.yaml"
            wrapProgram "$out/bin/nixstasis" \
              --set-default NIXSTASIS_FRPC_BINARY_PATH "$out/libexec/nixstasis/frpc" \
              --set-default NIXSTASIS_FRPC_CONFIG_PATH "$out/share/nixstasis/frpc.toml"
          '';

          nativeBuildInputs = [ pkgs.makeWrapper ];
        };
      in
      {
        default = nixstasis-client;
        client = nixstasis-client;
        frpc = frpc;
      }
      );

      checks = forAllSystems (system: {
        client = self.packages.${system}.client;
        frpc = self.packages.${system}.frpc;
      });
    };
}
