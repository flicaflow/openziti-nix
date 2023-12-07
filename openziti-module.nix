{config, lib, pkgs, ...}: 
with lib;
let
  cfg = config.services.openziti;
in {
  options = {
    services.openziti = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      externalDNS = mkOption {
        type = types.str;
      };
      controllerPort = mkOption {
        type = types.int;
        default = 8440;
      };
      controllerEdgePort = mkOption {
        type = types.int;
        default = 8441;
      };
      routerPort = mkOption {
        type = types.int;
        default = 8442;
      };
      webPort = mkOption {
        type = types.int;
        default = 8443;
      };

      certFile = mkOption {
        type = types.str;
        default = "ctrl-client.cert.pem";
      };
      serverCertFile = mkOption {
        type = types.str;
        default = "ctrl-server.cert.pem";
      };
      keyFile = mkOption {
        type = types.str;
        default = "ctrl.key.pem";
      };
      caFile = mkOption {
        type = types.str;
        default = "ca-chain.cert.pem";
      };

    };
  };

  config = mkIf cfg.enable {

    users.extraUsers.ziti = {
      isSystemUser = true;
    };

    networking.firewall.allowedTCPPorts = with cfg; [ controllerPort controllerEdgePort routerPort webPort ];

    systemd.services.ziti-controller = let
      controller-config = lib.writeTest "controller-config.yaml" (builtins.toYAML {
        v = 3;
        db = "ctrl.db";

        identity = {
          cert = cfg.certFile;
          server_cert = cfg.serverCertFile;
          key = cfg.keyFile;
          ca = caFile;
        };

        ctrl.listener = "tls:127.0.0.1:6262";

        edge.enrollment = {
          signingCert = {
            cert = "intermediate.cert.pem";
            key = "intermediate.key.pem";
          };
        };


        web = [
          {
            name = "all-apis-localhost";
            bindPoints = [{
              interface = "127.0.0.1:1280";
            }];
            address = "127.0.0.1:1280";
            apis = [
              { binding = "fabric"; }
              { binding = "edge-management"; }
              { binding = "edge-client"; }
            ];
          }
        ];
      });

    in{

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      description = "Start the irc client of username.";
      preStart = "initPKI";
      serviceConfig = {
        Type = "exec";
        ExecStart = "${openziti}/bin/ziti controller run ${controller-config}";
        User = "ziti";
        WorkingDirectory = "/var/lib/openziti-controller";
      };

    };
    systemd.services.ziti-router = let
      router-config = pkgs.writeText "router-config.json" ''
      {
      }
      '';
    in {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      description = "Start the irc client of username.";
      serviceConfig = {
        Type = "exec";
        ExecStart = "${openziti}/bin/ziti controller run ${router-config}";
        User = "ziti";
      };
    };
  };
}

