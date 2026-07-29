# ---------------------------------------------------------------------------
# Everything about the machines lives in one dictionary. Adding a fifth VM
# means adding one entry here — no new config block, no copy-paste.
# ---------------------------------------------------------------------------

# Your home network. Change these two to match your router, then every VM
# gets a real address on your LAN and is reachable from your phone/laptop.
#   BRIDGE_IFACE: run `ifconfig` (macOS) or `ip a` and use the active adapter
#                 that carries your Wi-Fi/Ethernet traffic, e.g. "en0".
#   LAN_PREFIX:   the first three octets of your home subnet.
BRIDGE_IFACE = ENV.fetch("VAGRANT_BRIDGE", "en0")
LAN_PREFIX   = ENV.fetch("LAN_PREFIX", "192.168.88")

REPO_URL    = "https://github.com/Roma-rgb-tech/softserve-task.git"
REPO_BRANCH = "dev/redis"

RABBITMQ_USER = "app"
RABBITMQ_PASS = "example"

# host octet -> IP, so service URLs below stay readable
def lan(octet)
  "#{LAN_PREFIX}.#{octet}"
end

NODES = {
  "postgres" => {
    octet:    200,
    ssh_port: 2222,
    memory:   "1536",
    # Infra VM: three off-the-shelf images, nothing built from our repo.
    clone:    false,
    run: ->(ip) { <<~SHELL }
      docker rm -f postgres 2>/dev/null || true
      docker run -d --name postgres --restart unless-stopped --network host -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=example -e POSTGRES_DB=history_db -v pgdata:/var/lib/postgresql/data postgres:15

      docker rm -f redis 2>/dev/null || true
      docker run -d --name redis --restart unless-stopped --network host redis:7-alpine

      docker rm -f rabbitmq 2>/dev/null || true
      docker run -d --name rabbitmq --restart unless-stopped --network host -e RABBITMQ_DEFAULT_USER=#{RABBITMQ_USER} -e RABBITMQ_DEFAULT_PASS=#{RABBITMQ_PASS} rabbitmq:3-management
    SHELL
  },

  "history" => {
    octet:    201,
    ssh_port: 2223,
    memory:   "1536",
    clone:    true,
    service:  "history-service",
    run: ->(ip) { <<~SHELL }
      docker build -t history-service /opt/app/history-service
      docker rm -f history 2>/dev/null || true
      docker run -d --name history --restart unless-stopped --network host -e DATABASE_URL=postgresql://postgres:example@#{node_ip("postgres")}:5432/history_db -e RABBITMQ_URL=amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{node_ip("postgres")}/ history-service
    SHELL
  },

  "backend" => {
    octet:    202,
    ssh_port: 2224,
    memory:   "1536",
    clone:    true,
    service:  "backend-service",
    run: ->(ip) { <<~SHELL }
      docker build -t backend-service /opt/app/backend-service
      docker rm -f backend 2>/dev/null || true
      docker run -d --name backend --restart unless-stopped --network host -e HISTORY_BASE=http://#{node_ip("history")}:8001 -e REDIS_URL=redis://#{node_ip("postgres")}:6379/0 -e WATCHED_CITIES=Kyiv,Lviv backend-service
    SHELL
  },

  "fetcher" => {
    octet:    203,
    ssh_port: 2226,
    memory:   "1024",
    clone:    true,
    service:  "fetcher-service",
    run: ->(ip) { <<~SHELL }
      docker build -t fetcher-service /opt/app/fetcher-service
      docker rm -f fetcher 2>/dev/null || true
      docker run -d --name fetcher --restart unless-stopped --network host -e HISTORY_BASE=http://#{node_ip("history")}:8001 -e RABBITMQ_URL=amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{node_ip("postgres")}/ -e POLL_INTERVAL_SECONDS=1800 -e MIN_RECORD_INTERVAL_SECONDS=600 fetcher-service
    SHELL
  },

  "ui" => {
    octet:    204,
    ssh_port: 2225,
    memory:   "1024",
    clone:    true,
    service:  "ui-service",
    run: ->(ip) { <<~SHELL }
      docker build -t ui-service /opt/app/ui-service
      docker rm -f ui 2>/dev/null || true
      docker run -d --name ui --restart unless-stopped --network host -e BACKEND_HOST=#{node_ip("backend")} ui-service
    SHELL
  },
}

def node_ip(name)
  lan(NODES[name][:octet])
end

# /etc/hosts entries so the VMs can also address each other by name
HOSTS_FILE = NODES.map { |name, c|
  "grep -q ' #{name}$' /etc/hosts || echo '#{lan(c[:octet])} #{name}' >> /etc/hosts"
}.join("\n")

INSTALL_DOCKER = <<~SHELL
  set -e
  if ! command -v docker >/dev/null; then
    apt-get update -y
    apt-get install -y docker.io
    systemctl enable --now docker
  fi
  usermod -aG docker vagrant
SHELL

CLONE_REPO = <<~SHELL
  set -e
  apt-get update -y
  apt-get install -y git
  rm -rf /opt/app
  git clone --depth 1 --branch #{REPO_BRANCH} #{REPO_URL} /opt/app
SHELL

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

      node.vm.provision "shell", inline: HOSTS_FILE
      node.vm.provision "shell", inline: INSTALL_DOCKER
      node.vm.provision "shell", inline: CLONE_REPO if cfg[:clone]
      node.vm.provision "shell", inline: "set -e\n" + cfg[:run].call(ip)
    end
  end
end
