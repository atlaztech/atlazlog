{ ... }:
let
  masterPassword = "be4e224c-b18e-49b1-aac9-ca27190ea819";
in
{
  virtualisation = {
    docker = {
      enable = true;
      daemon.settings.log-driver = "local";
    };

    oci-containers = {
      backend = "docker";

      containers.clickhouse = {
        image = "clickhouse/clickhouse-server:latest";
        environment = {
          CLICKHOUSE_DB = "laravel";
          CLICKHOUSE_USER = "laravel";
          CLICKHOUSE_PASSWORD = masterPassword;
          LISTEN_HOST = "0.0.0.0";
        };
        volumes = [
          "clickhouse_data:/var/lib/clickhouse"
          "clickhouse_logs:/var/log/clickhouse-server"
          "${../clickhouse_config.xml}:/etc/clickhouse-server/config.d/custom.xml:ro"
        ];
        extraOptions = [ "--network=host" ];
      };

      containers.atlazlog = {
        image = "atlaztech/atlazlog:latest";
        environment = {
          APP_ENV = "production";
          APP_DEBUG = "false";
          DB_PASSWORD = masterPassword;
          REDIS_PASSWORD = masterPassword;
          CLICKHOUSE_PASSWORD = masterPassword;
        };
        volumes = [
          "pg_data:/var/lib/postgresql/data"
          "/var/lib/atlaz:/var/lib/atlaz"
        ];
        dependsOn = [ "clickhouse" ];
        extraOptions = [ "--network=host" "--pull=always" "--privileged" ];
      };
    };
  };
}
