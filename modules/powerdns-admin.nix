{ config, pkgs, lib, ... }:

with lib;

{
  # Enable Docker runtime for PowerDNS Admin container
  virtualisation.docker.enable = true;

  # Deploy docker-compose configuration into /etc/powerdns-admin
  environment.etc."powerdns-admin/docker-compose.yml".text = ''
    services:
      powerdns:
        image: powerdns/pdns-auth-4.9.5
        container_name: powerdns
        restart: unless-stopped
        network_mode: host
        volumes:
          - /etc/powerdns:/etc/powerdns:ro
          - /var/lib/powerdns:/var/lib/powerdns
        command:
          - "--config-dir=/etc/powerdns"
          - "--daemon=no"
          - "--disable-syslog"
          - "--write-pid=no"

      powerdns-admin:
        image: ngoduykhanh/powerdns-admin:latest
        container_name: powerdns-admin
        restart: unless-stopped
        network_mode: host
        depends_on:
          - powerdns
        environment:
          - SECRET_KEY=changeme-on-first-run
          - BIND_ADDRESS=0.0.0.0
          - PORT=9191
          - SQLA_DB_USER=powerdns
          - SQLA_DB_NAME=powerdnsadmin
        volumes:
          - /var/lib/powerdns-admin:/data
        healthcheck:
          test: ["CMD", "curl", "-f", "http://localhost:9191/"]
          interval: 30s
          timeout: 10s
          retries: 3
          start_period: 40s
  '';

  # Manage the docker-compose stack via systemd
  systemd.services.powerdns-admin-compose = {
    description = "PowerDNS Admin (Docker Compose)";
    after = [ "network-online.target" "docker.service" "pdns.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.docker pkgs.docker-compose ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/etc/powerdns-admin";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
    };

    script = ''
      # Ensure persistent data directory exists
      mkdir -p /var/lib/powerdns-admin
      mkdir -p /var/lib/powerdns

      # Fetch latest images and launch/update the stack
      ${pkgs.docker-compose}/bin/docker-compose pull
      ${pkgs.docker-compose}/bin/docker-compose up -d

      # Wait for the web interface to respond
      echo "Waiting for PowerDNS Admin to start..."
      for i in {1..30}; do
        if ${pkgs.curl}/bin/curl -sf http://localhost:9191/ > /dev/null 2>&1; then
          echo "PowerDNS Admin is ready at http://<router-ip>:9191"
          echo "Default credentials: admin / admin (change immediately)"
          break
        fi
        sleep 2
      done
    '';

    reload = "${pkgs.docker-compose}/bin/docker-compose restart";
  };

  # Open firewall port for the admin UI
  networking.firewall.allowedTCPPorts = mkAfter [ 9191 ];
}


