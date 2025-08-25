{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        erlang  = pkgs.erlang_26;
        elixir  = pkgs.beam.packages.erlang_26.elixir_1_16;
        psql    = pkgs.postgresql_16;

        commonPkgs = [
          pkgs.openssl
          erlang
          elixir
          psql
        ];

        devPkgs   = commonPkgs ++ [
          pkgs.git
          pkgs.curl
          pkgs.busybox
          pkgs.glibc.bin
        ];
        rtPkgs    = commonPkgs;
        webuiPkgs = commonPkgs ++ [
          pkgs.git
          pkgs.curl
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.openvscode-server
        ];

        mkImage = { name, tag, contents, workdir, cmd ? null }:
          pkgs.dockerTools.buildLayeredImage {
            inherit name tag contents;
            config = {
              WorkingDir = workdir;
              Env = [ "LANG=C.UTF-8" "LC_ALL=C.UTF-8" "HOME=/root" "PATH=/bin:/usr/bin:/sbin:/usr/sbin" ];
              Cmd = if cmd == null then null else cmd;
              User = "root";
            };
            extraCommands = ''
              mkdir -p etc bin usr/bin sbin tmp
              chmod 1777 tmp

              ln -sf ${pkgs.busybox}/bin/busybox bin/busybox

              bin/busybox --install -s /bin
              bin/busybox --install -s /usr/bin

              echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
              echo "root:x:0:" > etc/group
              ln -sf /bin/busybox usr/bin/env
              ln -sf /bin/sh      usr/bin/bash

              ln -sf ${pkgs.coreutils}/bin/env usr/bin/env
              ln -sf ${pkgs.bashInteractive}/bin/bash bin/sh
              ln -sf ${pkgs.glibc.bin}/bin/ldd usr/bin/ldd
              touch etc/ld.so.cache
              printf '%s\n' '#!/bin/sh' 'exec /nix/store/*-glibc-*/bin/ldconfig -C /etc/ld.so.cache "$@"' \
                | install -Dm755 /dev/stdin sbin/ldconfig
            '';
          };
      in {
        devShells.default = pkgs.mkShell { packages = devPkgs; };

        packages.dev      = mkImage { name="api-base"; tag="dev";      contents=devPkgs;   workdir="/workspace"; cmd=[ "sleep" "infinity" ]; };
        packages.runtime  = mkImage { name="api-base"; tag="runtime";  contents=rtPkgs;    workdir="/app";       };
        packages.webui    = mkImage { name="api-base"; tag="webui";    contents=webuiPkgs; workdir="/workspace"; cmd=[ "openvscode-server" "--host" "0.0.0.0" "--port" "8080" "--without-connection-token" "--disable-telemetry" "--extensions-dir" "/root/.vscode-oss/extensions" ]; };

        packages.default  = self.packages.${system}.dev;
      }
    );
}