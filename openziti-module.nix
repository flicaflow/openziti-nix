{config, lib, pkgs, ...}: 
with lib;
let
  cfg = config.services.openziti;
in {
  options.services.openziti = {
    enable = mkEnableOption "openziti controller";
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

    signingCertFile = mkOption {
      type = types.str;
      default = "intermediate.cert.pem";
    };
    signingKeyFile = mkOption {
      type = types.str;
      default = "intermediate.key.pem";
    };

    initPki = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Generate PKI for controller
      '';
    };
  };

  config = mkIf cfg.enable {

    users.extraGroups.ziti = {};
    users.extraUsers.ziti = {
      isSystemUser = true;
      group = "ziti";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/openziti-controller 0750 ziti ziti -"
    ];

    networking.firewall.allowedTCPPorts = with cfg; [ controllerPort controllerEdgePort routerPort webPort ];

    environment.systemPackages = [ pkgs.openziti pkgs.jq];

    systemd.services.ziti-controller = let
      configData = {
        v = 3;
        db = "ctrl.db";

        identity = {
          cert = cfg.certFile;
          server_cert = cfg.serverCertFile;
          key = cfg.keyFile;
          ca = cfg.caFile;
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
      };
      controller-config = pkgs.writeText "controller-config.yaml" (builtins.toJSON configData);

    in{

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      description = "Start the irc client of username.";
      preStart = if cfg.initPki 
        then ''
        if [ -d /var/lib/openziti-controller/pki ]
        then
          exit 0
        fi

        export EXTERNAL_DNS="${cfg.externalDNS}"

        export EXTERNAL_IP="$(curl -s eth0.me)"
        export ZITI_CTRL_EDGE_IP_OVERRIDE="$EXTERNAL_IP"
        export ZITI_ROUTER_IP_OVERRIDE="$EXTERNAL_IP"
        export ZITI_CTRL_EDGE_ADVERTISED_ADDRESS="$EXTERNAL_DNS:-$EXTERNAL_IP"
        export ZITI_ROUTER_ADVERTISED_ADDRESS="$EXTERNAL_DNS:-$EXTERNAL_IP"
        export ZITI_CTRL_ADVERTISED_PORT=${toString cfg.controllerPort}
        export ZITI_CTRL_EDGE_ADVERTISED_PORT=${toString cfg.controllerEdgePort}
        export ZITI_ROUTER_PORT=${toString cfg.routerPort}

        . ${pkgs.openziti}/bin/ziti-cli-functions.sh

        export ZITI_PKI=/var/lib/openziti-controller/pki
        mkdir $ZITI_PKI

        export ZITI_USER=ziti
        export ZITI_PWD=ziti

        setupEnvironmet
        createPki


        

      ''
      else ":";
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.openziti}/bin/ziti controller run ${controller-config}";
        User = "ziti";
        WorkingDirectory = "/var/lib/openziti-controller";
      };

    };
#    systemd.services.ziti-router = let
#      router-config = pkgs.writeText "router-config.json" ''
#      {
#      }
#      '';
#    in {
#      wantedBy = [ "multi-user.target" ];
#      after = [ "network.target" ];
#      description = "Start the irc client of username.";
#      serviceConfig = {
#        Type = "exec";
#        ExecStart = "${openziti}/bin/ziti controller run ${router-config}";
#        User = "ziti";
#      };
#    };
  };
}

