{
  description = "openZiti flake";
  inputs.nixpkgs.url = github:NixOS/nixpkgs/nixos-23.11;
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils, ... }: 
    flake-utils.lib.eachDefaultSystem (system: 
      let pkgs = nixpkgs.legacyPackages.${system}; in
      {
        packages = rec {
          openziti = pkgs.buildGoModule rec {
            version = "0.31.0";
            pname = "openziti";
            src = pkgs.fetchFromGitHub {
              owner = "openziti";
              repo = "ziti";
              rev = "v${version}";
              hash = "sha256-KCYtbNN9OFoy8bsQqrkMLjCWSOsZcvZodWL7VT45Rsw=";
            };
            vendorHash = "sha256-yriMXGr7HeuA7wMQnG5NFLWtiedeu7UgPt9SoTmkfuM=";
            doCheck = false;
            preBuild = "rm -r zititest/"; # zititest contains its own go.mod which breaks buildGoModule
            postInstall = ''
              cp $src/quickstart/docker/image/ziti-cli-functions.sh $out/bin/ziti-cli-functions.sh
            '';
          };

          openziti-createPki = pkgs.writeScript "init_pki" ''
            function help() {
              echo "Usage:"
            }

            function assertEnv() {
              if [ -z "$1" ]
              then
                echo "Env var $1 is unset"
                help
                exit -1
              fi
            }

            assertEnv "PKI_ROOT"
            assertEnv "ROOT_CA_NAME"

            result/bin/ziti pki create ca \
              --pki-root "$PKI_ROOT" \
              --ca-file "$ROOT_CA_NAME" \
              --ca-name "$ROOT_CA_NAME CA"


            function createIntermediate() {
              local INTER=$1
              result/bin/ziti pki create intermediate \
                --pki-root "$PKI_ROOT" \
                --ca-name "$ROOT_CA_NAME" \
                --intermediate-file "$INTER" \
                --intermediate-name "$INTER CA"
            }

            createIntermediate "ctrl-client"
            createIntermediate "ctrl-client"
            createIntermediate "ctrl-client"
            createIntermediate "ctrl-client"
          '';
          


          default = openziti;

        };


      }) // {
        modules.openziti = import ./openziti-module.nix; 

        nixosConfigurations.test = let system = "x86_64-linux"; in nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ({ config, pkgs, ... }: { nixpkgs.overlays = [ 
              (final: prev: {
                openziti = self.packages."x86_64-linux".openziti;
              })
            ]; })
            ./openziti-module.nix
            ./configuration.nix
          ];

        };

      };

}
