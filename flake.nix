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
          pkgs.glibc
        ];
        rtPkgs    = commonPkgs;
        webuiPkgs = commonPkgs ++ [
          pkgs.git
          pkgs.curl
          pkgs.bash
          pkgs.cacert
          pkgs.code-server
        ];

        mkImage = { name, tag, contents, workdir, cmd ? null }:
          pkgs.dockerTools.buildLayeredImage {
            inherit name tag contents;
            config = {
              WorkingDir = workdir;
              Env = [
                "LANG=C.UTF-8"
                "LC_ALL=C.UTF-8"
                "HOME=/root"
                "PATH=/bin:/usr/bin:/sbin:/usr/sbin"
              ];
              Cmd = if cmd == null then null else cmd;
              User = "root";
            };
            extraCommands = ''
              mkdir -p etc bin etc/ssl/certs tmp root/.vscode-oss/extensions

              chmod 1777 tmp

              ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-bundle.crt

              echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
              echo "root:x:0:" > etc/group
            '';
          };
      in {
        devShells.default = pkgs.mkShell { packages = devPkgs; };

        packages.dev      = mkImage {
          name     = "api-base";
          tag      = "dev";
          contents = devPkgs;
          workdir  = "/workspace";
          cmd      = [
            "sleep"
            "infinity"
          ];
        };
        packages.runtime  = mkImage {
          name     = "api-base";
          tag      = "runtime";
          contents = rtPkgs;
          workdir  = "/app";
        };
        packages.webui    = mkImage {
          name     ="api-base";
          tag      = "webui";
          contents = webuiPkgs;
          workdir  = "/workspace";
          cmd      = [
            "code-server"
            "--auth none"
            "--cert /etc/ssl/certs/ca-bundle.crt"
            "--bind-addr 127.0.0.1:8080"
            "--extensions-dir /root/.vscode-oss/extensions"
          ];
        };

        packages.default  = self.packages.${system}.dev;
      }
    );
}