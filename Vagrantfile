BRIDGE_IFACE = ENV.fetch("VAGRANT_BRIDGE", "en0")
LAN_PREFIX   = ENV.fetch("LAN_PREFIX", "192.168.88")

REPO_URL    = "https://github.com/Roma-rgb-tech/softserve-task.git"
REPO_BRANCH = "roman-chernyshev/dev-weather"

APP_DIR = "/opt/app"

POSTGRES_USER = "postgres"
POSTGRES_PASS = "example"
POSTGRES_DB   = "history_db"
RABBITMQ_USER = "app"
RABBITMQ_PASS = "example"

WATCHED_CITIES = "Kyiv,Warsaw,Vilnius"


POLL_INTERVAL_SECONDS       = 3600
MIN_RECORD_INTERVAL_SECONDS = 3000

def lan(octet)
  "#{LAN_PREFIX}.#{octet}"
end


def node_ip(name)
  lan(NODES[name][:octet])
end

NODES = {
  "postgres" => {
    octet:    200,
    ssh_port: 2222,
    memory:   "1536",
    clone:    false,
    env: -> {
      {
        "POSTGRES_USER"     => POSTGRES_USER,
        "POSTGRES_PASSWORD" => POSTGRES_PASS,
        "POSTGRES_DB"       => POSTGRES_DB,
        "RABBITMQ_USER"     => RABBITMQ_USER,
        "RABBITMQ_PASS"     => RABBITMQ_PASS,
      }
    },
  },

  "history" => {
    octet:    201,
    ssh_port: 2223,
    memory:   "1536",
    clone:    true,
    env: -> {
      {
        "DATABASE_URL" => "postgresql://#{POSTGRES_USER}:#{POSTGRES_PASS}@#{node_ip("postgres")}:5432/#{POSTGRES_DB}",
        "RABBITMQ_URL" => "amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{node_ip("postgres")}/",
      }
    },
  },

  "backend" => {
    octet:    202,
    ssh_port: 2224,
    memory:   "1536",
    clone:    true,
    env: -> {
      {
        "HISTORY_BASE"   => "http://#{node_ip("history")}:8001",
        "REDIS_URL"      => "redis://#{node_ip("postgres")}:6379/0",
        "WATCHED_CITIES" => WATCHED_CITIES,
      }
    },
  },

  "fetcher" => {
    octet:    203,
    ssh_port: 2226,
    memory:   "1024",
    clone:    true,
    env: -> {
      {
        "RABBITMQ_URL"                => "amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{node_ip("postgres")}/",
        "WATCHED_CITIES"              => WATCHED_CITIES,
        "POLL_INTERVAL_SECONDS"       => POLL_INTERVAL_SECONDS.to_s,
        "MIN_RECORD_INTERVAL_SECONDS" => MIN_RECORD_INTERVAL_SECONDS.to_s,
      }
    },
  },

  "ui" => {
    octet:    204,
    ssh_port: 2225,
    memory:   "1024",
    clone:    true,
    env: -> {
      { "BACKEND_HOST" => node_ip("backend") }
    },
  },
}


HOSTS_FILE = NODES.map { |name, c|
  "grep -q ' #{name}$' /etc/hosts || echo '#{lan(c[:octet])} #{name}' >> /etc/hosts"
}.join("\n")

CLONE_REPO = <<~SHELL
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y git
  rm -rf #{APP_DIR}
  git clone --depth 1 --branch #{REPO_BRANCH} #{REPO_URL} #{APP_DIR}
SHELL



def env_script(name, env_vars)
  lines = [
    "set -euo pipefail",
    "ENV_FILE=#{APP_DIR}/infra/#{name}/.env",
    'mkdir -p "$(dirname "$ENV_FILE")"',
    ': > "$ENV_FILE"',
  ]
  env_vars.each do |k, val|
    lines << %Q{printf '%s\\n' '#{k}=#{val}' >> "$ENV_FILE"}
  end
  lines << 'echo "wrote $ENV_FILE:"'
  lines << 'cat "$ENV_FILE"'
  lines.join("\n")
end

Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-2204-arm64"

  NODES.each do |name, cfg|
    ip = lan(cfg[:octet])

    config.vm.define name do |node|
      node.vm.hostname = name

      node.vm.network "private_network", ip: ip

      node.vm.provider "qemu" do |qe|
        qe.arch     = "aarch64"
        qe.machine  = "virt,accel=hvf,highmem=off"
        qe.cpu      = "host"
        qe.memory   = cfg[:memory]
        qe.ssh_port = cfg[:ssh_port]
        qe.advanced_network = true
        qe.net_mode         = :vmnet_bridged
        qe.vmnet_interface  = BRIDGE_IFACE
      end

      node.vm.provision "shell", name: "hosts", inline: HOSTS_FILE
      node.vm.provision "shell", name: "clone", inline: CLONE_REPO if cfg[:clone]


      unless cfg[:clone]
        node.vm.provision "shell", name: "mkdir",
          inline: "mkdir -p #{APP_DIR}/infra/#{name}"
        node.vm.provision "file",
          source: "infra/#{name}/docker-compose.yml",
          destination: "/tmp/docker-compose.yml"
        node.vm.provision "shell", name: "place",
          inline: "mv /tmp/docker-compose.yml #{APP_DIR}/infra/#{name}/docker-compose.yml"
      end

      node.vm.provision "shell", name: "docker",
        path: "infra/scripts/install-docker.sh"

      node.vm.provision "shell", name: "env",
        inline: env_script(name, cfg[:env].call)

        
      node.vm.provision "shell", name: "deploy",
        path: "infra/scripts/deploy.sh",
        args: ["#{APP_DIR}/infra/#{name}"]
    end
  end
end
