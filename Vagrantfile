BRIDGE_IFACE = ENV.fetch("VAGRANT_BRIDGE", "en0")
LAN_PREFIX   = ENV.fetch("LAN_PREFIX", "192.168.0")

REPO_URL    = "https://github.com/Roma-rgb-tech/softserve-task.git"
REPO_BRANCH = "dev/redis"

RABBITMQ_USER = "app"
RABBITMQ_PASS = "example"

def lan(octet)
  "#{LAN_PREFIX}.#{octet}"
end

NODES = {
  "postgres" => {
    octet:    50,
    ssh_port: 2222,
    memory:   "1536",
    clone:    false,
    run: ->(ip) { <<~SHELL }
      docker rm -f postgres 2>/dev/null || true
      docker run -d --name postgres --restart unless-stopped --network host \\
        -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=example \\
        -e POSTGRES_DB=history_db -v pgdata:/var/lib/postgresql/data \\
        postgres:15

      docker rm -f redis 2>/dev/null || true
      docker run -d --name redis --restart unless-stopped --network host \\
        redis:7-alpine

      docker rm -f rabbitmq 2>/dev/null || true
      docker run -d --name rabbitmq --restart unless-stopped --network host \\
        -e RABBITMQ_DEFAULT_USER=#{RABBITMQ_USER} \\
        -e RABBITMQ_DEFAULT_PASS=#{RABBITMQ_PASS} \\
        rabbitmq:3-management
    SHELL
  },

  "history" => {
    octet:    51,
    ssh_port: 2223,
    memory:   "1536",
    clone:    true,
    service:  "history-service",
    run: ->(ip) { <<~SHELL }
      docker build -t history-service /opt/app/history-service
      docker rm -f history 2>/dev/null || true
      docker run -d --name history --restart unless-stopped --network host \\
        -e DATABASE_URL=postgresql://postgres:example@#{lan(50)}:5432/history_db \\
        -e RABBITMQ_URL=amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{lan(50)}/ \\
        history-service
    SHELL
  },

  "backend" => {
    octet:    52,
    ssh_port: 2224,
    memory:   "1536",
    clone:    true,
    service:  "backend-service",
    run: ->(ip) { <<~SHELL }
      docker build -t backend-service /opt/app/backend-service
      docker rm -f backend 2>/dev/null || true
      docker run -d --name backend --restart unless-stopped --network host \\
        -e HISTORY_BASE=http://#{lan(51)}:8001 \\
        -e RABBITMQ_URL=amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{lan(50)}/ \\
        -e REDIS_URL=redis://#{lan(50)}:6379/0 \\
        -e POLL_INTERVAL_SECONDS=1800 \\
        -e MIN_RECORD_INTERVAL_SECONDS=600 \\
        -e WATCHED_CITIES=Kyiv,Lviv \\
        -e MAX_WATCHED_CITIES=8 \\
        backend-service
    SHELL
  },

  "ui" => {
    octet:    53,
    ssh_port: 2225,
    memory:   "1024",
    clone:    true,
    service:  "ui-service",
    run: ->(ip) { <<~SHELL }
      docker build -t ui-service /opt/app/ui-service
      docker rm -f ui 2>/dev/null || true
      docker run -d --name ui --restart unless-stopped --network host \\
        -e BACKEND_HOST=#{lan(52)} \\
        ui-service
    SHELL
  },
}

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

      node.vm.network "public_network",
        bridge: BRIDGE_IFACE,
        ip: ip,
        netmask: "255.255.255.0"

      node.vm.provider "qemu" do |qe|
        qe.arch     = "aarch64"
        qe.machine  = "virt,accel=hvf,highmem=off"
        qe.cpu      = "host"
        qe.memory   = cfg[:memory]
        qe.ssh_port = cfg[:ssh_port]
        qe.advanced_network = true
        qe.net_mode = :vmnet_bridged
      end

      node.vm.provision "shell", inline: HOSTS_FILE
      node.vm.provision "shell", inline: INSTALL_DOCKER
      node.vm.provision "shell", inline: CLONE_REPO if cfg[:clone]
      node.vm.provision "shell", inline: "set -e\n" + cfg[:run].call(ip)
    end
  end
end