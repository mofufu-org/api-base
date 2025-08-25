{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        erlang = pkgs.erlang_26;
        elixir = pkgs.beam.packages.erlang_26.elixir_1_16;
        psql   = pkgs.postgresql_16;

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
        ];
        rtPkgs    = commonPkgs;
        webuiPkgs = commonPkgs ++ [
          pkgs.git
          pkgs.curl
          pkgs.cacert
          pkgs.bash
          pkgs.code-server
        ];

        mkImage = { name, tag, contents, workdir, env? [], cmd? null, ecmd? "" }:
          pkgs.dockerTools.buildLayeredImage {
            inherit name tag contents;
            config = {
              WorkingDir = workdir;
              Env = env ++ [
                "LANG=C.UTF-8"
                "LC_ALL=C.UTF-8"
                "HOME=/root"
                "PATH=/bin:/usr/bin:/sbin:/usr/sbin"
              ];
              Cmd = if cmd == null then null else cmd;
              User = "root";
            };
            extraCommands = ecmd + ''
              mkdir -p etc bin

              echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
              echo "root:x:0:" > etc/group
            '';
          };
      in {
        devShells.default = pkgs.mkShell { packages = devPkgs; };

        packages.dev = pkgs.dockerTools.buildImage {
          name = "api-base";
          tag  = "dev";
          fromImage = pkgs.dockerTools.pullImage {
            imageName      = "debian";
            imageDigest    = "sha256:b1a741487078b369e78119849663d7f1a5341ef2768798f7b7406c4240f86aef";
            finalImageName = "debian";
            finalImageTag  = "bookworm-slim";
            sha256         = "sha256-GsiMvKEcc1SbPNJubtU0xFNBbno5PMiQY9pxKRcbeK0=";
          };
          contents = devPkgs;
          config = {
            WorkingDir = "/workspace";
            Cmd = [ "sleep" "infinity" ];
            Env = [
              "LANG=C.UTF-8"
              "LC_ALL=C.UTF-8"
              "HOME=/root"
              "PATH=${pkgs.lib.makeBinPath devPkgs}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
            ];
            User = "root";
          };
          extraCommands = ''
            mkdir -p bin etc

            echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
            echo "root:x:0:" > etc/group

            ln -sf ${pkgs.busybox}/bin/busybox bin/busybox
            bin/busybox --install -s ./bin
            bin/busybox --install -s ./usr/bin
          '';
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
          env      = [
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
            "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt"
            "GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt"
          ];
          cmd      = [
            "code-server"
            "/workspace"
            "--auth"           "none"
            "--bind-addr"      "0.0.0.0:8080"
            "--extensions-dir" "/root/.vscode-oss/extensions"
          ];
          ecmd     = ''
            mkdir -p etc/ssl/certs root/.vscode-oss/extensions tmp

            chmod 1777 tmp

            ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-bundle.crt
          '';
        };

        packages.default  = self.packages.${system}.dev;
      }
    );
}