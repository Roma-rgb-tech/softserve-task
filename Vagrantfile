IPS = {
  "postgres" => "192.168.105.10",
  "history"  => "192.168.105.11",
  "backend"  => "192.168.105.12",
  "ui"       => "192.168.105.13"
}

SSH_PORTS = {
  "postgres" => 2222,
  "history"  => 2223,
  "backend"  => 2224,
  "ui"       => 2225
}

REPO_URL    = "https://github.com/Roma-rgb-tech/softserve-task.git"
REPO_BRANCH = "dev/redis"

RABBITMQ_USER = "app"
RABBITMQ_PASS = "example"

HOSTS_FILE = IPS.map { |name, ip| "grep -q ' #{name}$' /etc/hosts || echo '#{ip} #{name}' >> /etc/hosts" }.join("\n")

CLONE_REPO = <<-SHELL
  set -e
  apt-get update -y
  apt-get install -y git
  rm -rf /opt/app
  git clone --depth 1 --branch #{REPO_BRANCH} #{REPO_URL} /opt/app
SHELL

INSTALL_DOCKER = <<-SHELL
  set -e
  if ! command -v docker >/dev/null; then
    apt-get update -y
    apt-get install -y docker.io
    systemctl enable --now docker
  fi
SHELL

Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-2204-arm64"

  # ---------------- postgres + redis + rabbitmq (shared infra VM) ----------------
  config.vm.define "postgres" do |node|
    node.vm.hostname = "postgres"
    node.vm.network "private_network", ip: IPS["postgres"]
    node.vm.provider "qemu" do |qe|
      qe.arch = "aarch64"
      qe.machine = "virt,accel=hvf,highmem=off"
      qe.cpu = "host"
      qe.memory = "1536"
      qe.advanced_network = true
      qe.net_mode = :vmnet_shared
      qe.ssh_port = SSH_PORTS["postgres"]
    end
    node.vm.provision "shell", inline: HOSTS_FILE
    node.vm.provision "shell", inline: INSTALL_DOCKER
    node.vm.provision "shell", inline: <<-SHELL
      set -e

      docker rm -f postgres 2>/dev/null || true
      docker run -d --name postgres --restart unless-stopped --network host \
        -e POSTGRES_USER=postgres \
        -e POSTGRES_PASSWORD=example \
        -e POSTGRES_DB=history_db \
        -v pgdata:/var/lib/postgresql/data \
        postgres:15

      docker rm -f redis 2>/dev/null || true
      docker run -d --name redis --restart unless-stopped --network host \
        redis:7-alpine

      docker rm -f rabbitmq 2>/dev/null || true
      docker run -d --name rabbitmq --restart unless-stopped --network host \
        -e RABBITMQ_DEFAULT_USER=#{RABBITMQ_USER} \
        -e RABBITMQ_DEFAULT_PASS=#{RABBITMQ_PASS} \
        rabbitmq:3-management
    SHELL
  end

  # ---------------- history ----------------
  config.vm.define "history" do |node|
    node.vm.hostname = "history"
    node.vm.network "private_network", ip: IPS["history"]
    node.vm.provider "qemu" do |qe|
      qe.arch = "aarch64"
      qe.machine = "virt,accel=hvf,highmem=off"
      qe.cpu = "host"
      qe.memory = "1536"
      qe.advanced_network = true
      qe.net_mode = :vmnet_shared
      qe.ssh_port = SSH_PORTS["history"]
    end
    node.vm.provision "shell", inline: HOSTS_FILE
    node.vm.provision "shell", inline: INSTALL_DOCKER
    node.vm.provision "shell", inline: CLONE_REPO
    node.vm.provision "shell", inline: <<-SHELL
      set -e
      docker build -t history-service /opt/app/history-service

      docker rm -f history 2>/dev/null || true
      docker run -d --name history --restart unless-stopped --network host \
        -e DATABASE_URL=postgresql://postgres:example@#{IPS["postgres"]}:5432/history_db \
        -e RABBITMQ_URL=amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{IPS["postgres"]}/ \
        history-service
    SHELL
  end

  # ---------------- backend ----------------
  config.vm.define "backend" do |node|
    node.vm.hostname = "backend"
    node.vm.network "private_network", ip: IPS["backend"]
    node.vm.provider "qemu" do |qe|
      qe.arch = "aarch64"
      qe.machine = "virt,accel=hvf,highmem=off"
      qe.cpu = "host"
      qe.memory = "1536"
      qe.advanced_network = true
      qe.net_mode = :vmnet_shared
      qe.ssh_port = SSH_PORTS["backend"]
    end
    node.vm.provision "shell", inline: HOSTS_FILE
    node.vm.provision "shell", inline: INSTALL_DOCKER
    node.vm.provision "shell", inline: CLONE_REPO
    node.vm.provision "shell", inline: <<-SHELL
      set -e
      docker build -t backend-service /opt/app/backend-service

      docker rm -f backend 2>/dev/null || true
      docker run -d --name backend --restart unless-stopped --network host \
        -e HISTORY_BASE=http://#{IPS["history"]}:8001 \
        -e RABBITMQ_URL=amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASS}@#{IPS["postgres"]}/ \
        -e REDIS_URL=redis://#{IPS["postgres"]}:6379/0 \
        -e POLL_INTERVAL_SECONDS=3600 \
        -e WATCHED_CITIES=Kyiv,Lviv \
        -e MAX_WATCHED_CITIES=3600 \
        backend-service
    SHELL
  end

  # ---------------- ui ----------------
  config.vm.define "ui" do |node|
    node.vm.hostname = "ui"
    node.vm.network "private_network", ip: IPS["ui"]
    node.vm.provider "qemu" do |qe|
      qe.arch = "aarch64"
      qe.machine = "virt,accel=hvf,highmem=off"
      qe.cpu = "host"
      qe.memory = "1024"
      qe.advanced_network = true
      qe.net_mode = :vmnet_shared
      qe.ssh_port = SSH_PORTS["ui"]
    end
    node.vm.provision "shell", inline: HOSTS_FILE
    node.vm.provision "shell", inline: INSTALL_DOCKER
    node.vm.provision "shell", inline: CLONE_REPO
    node.vm.provision "shell", inline: <<-SHELL
      set -e
      docker build -t ui-service /opt/app/ui-service

      docker rm -f ui 2>/dev/null || true
      docker run -d --name ui --restart unless-stopped --network host \
        -e BACKEND_HOST=#{IPS["backend"]} \
        ui-service
    SHELL
  end
end
