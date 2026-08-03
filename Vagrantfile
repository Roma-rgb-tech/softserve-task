# ---------------------------------------------------------------------------
# Every machine is generated from the NODES dictionary below. Adding a VM
# means adding one entry plus a provision/<name>/docker-compose.yml — no new
# config block, no copy-paste.
#
# This file deliberately contains no deployment logic: it computes addresses,
# writes each VM's .env, and hands off to the scripts under provision/.
# ---------------------------------------------------------------------------

# Your home network. Change these two to match your router, then every VM gets
# a real address on your LAN and is reachable from a phone on the same Wi-Fi.
#   BRIDGE_IFACE: run `route get default | grep interface`, e.g. "en0"
#   LAN_PREFIX:   the FIRST THREE octets of your home subnet only
BRIDGE_IFACE = ENV.fetch("VAGRANT_BRIDGE", "en0")
LAN_PREFIX   = ENV.fetch("LAN_PREFIX", "192.168.88")

REPO_URL    = "https://github.com/Roma-rgb-tech/softserve-task.git"
REPO_BRANCH = "dev/rabbitmq"

APP_DIR = "/opt/app"

POSTGRES_USER = "postgres"
POSTGRES_PASS = "example"
POSTGRES_DB   = "history_db"
RABBITMQ_USER = "app"
RABBITMQ_PASS = "example"

# Images are built once on the host and pushed to the registry; the VMs only
# pull them. Publish with infra/scripts/publish-images.sh before provisioning.
REGISTRY_NAMESPACE = ENV.fetch("REGISTRY_NAMESPACE", "tripletsrc")
IMAGE_TAG          = ENV.fetch("IMAGE_TAG", "latest")

# The cities this deployment monitors. The fetcher collects them; the backend
# tells the UI which cards to render. Nothing at runtime can change the list.
WATCHED_CITIES = "Kyiv,Warsaw,Vilnius"

# One reading per city per hour. MIN_RECORD_INTERVAL keeps a restart from
# writing a second row for a city it already recorded this cycle.
POLL_INTERVAL_SECONDS       = 3600
MIN_RECORD_INTERVAL_SECONDS = 3000

def lan(octet)
  "#{LAN_PREFIX}.#{octet}"
end

# Addresses are derived from NODES, so moving a VM to a different octet updates
# every service URL that points at it. Safe to call from inside the env lambdas:
# they are only evaluated at provision time, long after NODES is built.
def node_ip(name)
  lan(NODES[name][:octet])
end

NODES = {
  # Infrastructure: three off-the-shelf images, nothing built from our repo.
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
        "REGISTRY_NAMESPACE" => REGISTRY_NAMESPACE,
        "IMAGE_TAG"          => IMAGE_TAG,
        "DATABASE_URL" => "postgresql://#{POSTGRES_USER}:#{POSTGRES_PASS}@#{node_ip("postgres")}:5432/#{POSTGRES_DB}",
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
        "REGISTRY_NAMESPACE" => REGISTRY_NAMESPACE,
        "IMAGE_TAG"          => IMAGE_TAG,
        "HISTORY_BASE"   => "http://#{node_ip("history")}:8001",
        "RABBITMQ_URL"   => "amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{node_ip("postgres")}/",
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
        "REGISTRY_NAMESPACE"          => REGISTRY_NAMESPACE,
        "IMAGE_TAG"                   => IMAGE_TAG,
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
      {
        "REGISTRY_NAMESPACE" => REGISTRY_NAMESPACE,
        "IMAGE_TAG"          => IMAGE_TAG,
        "BACKEND_HOST"       => node_ip("backend"),
      }
    },
  },
}

# /etc/hosts entries, so the VMs can also address each other by name
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

# Writes the service's .env next to its compose file. Built as a plain string
# rather than a nested heredoc: Ruby's squiggly-heredoc dedent and a shell
# heredoc inside it interact badly, and a mangled .env is hard to spot.
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

      # The qemu plugin only builds its second NIC from private_network;
      # net_mode :vmnet_bridged is what puts that NIC on the real home LAN,
      # so this address answers from any device on the router.
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

      # The infra VM never clones the repo, so its compose file is uploaded
      # from the host instead.
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

      # Every *.pub in infra/keys becomes a login on this VM — the filename is
      # the username. Runs after docker so the accounts can join its group.
      node.vm.provision "file",
        source: "infra/keys",
        destination: "/tmp/keys"
      node.vm.provision "shell", name: "users",
        path: "infra/scripts/setup-users.sh",
        args: ["/tmp/keys"]

      node.vm.provision "shell", name: "env",
        inline: env_script(name, cfg[:env].call)

      # deploy.sh lives in the repo but is uploaded by Vagrant, so the infra VM
      # (which has no clone) can run it too.
      node.vm.provision "shell", name: "deploy",
        path: "infra/scripts/deploy.sh",
        args: ["#{APP_DIR}/infra/#{name}"]
    end
  end
end
