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
REPO_BRANCH = "feature/weather-dashboard"

HOSTS_FILE = IPS.map { |name, ip| "grep -q ' #{name}$' /etc/hosts || echo '#{ip} #{name}' >> /etc/hosts" }.join("\n")

CLONE_REPO = <<-SHELL
  set -e
  apt-get update -y
  apt-get install -y git
  rm -rf /opt/app
  git clone --depth 1 --branch #{REPO_BRANCH} #{REPO_URL} /opt/app
SHELL

Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-2204-arm64"

  # ---------------- postgres ----------------
  config.vm.define "postgres" do |node|
    node.vm.hostname = "postgres"
    node.vm.network "private_network", ip: IPS["postgres"]
    node.vm.provider "qemu" do |qe|
      qe.arch = "aarch64"
      qe.machine = "virt,accel=hvf,highmem=off"
      qe.cpu = "host"
      qe.memory = "1024"
      qe.advanced_network = true
      qe.net_mode = :vmnet_shared
      qe.ssh_port = SSH_PORTS["postgres"]
    end
    node.vm.provision "shell", inline: HOSTS_FILE
    node.vm.provision "shell", inline: <<-SHELL
      set -e
      apt-get update -y
      apt-get install -y postgresql

      PGV=$(pg_lsclusters -h | awk '{print $1}' | head -n1)
      PGCONF=/etc/postgresql/$PGV/main

      sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" $PGCONF/postgresql.conf

      grep -q "192.168.105.0/24" $PGCONF/pg_hba.conf || \
        echo "host all all 192.168.105.0/24 md5" >> $PGCONF/pg_hba.conf

      systemctl restart postgresql

      sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'example';"
      sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'history_db'" | grep -q 1 || \
        sudo -u postgres createdb history_db
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
      qe.memory = "1024"
      qe.advanced_network = true
      qe.net_mode = :vmnet_shared
      qe.ssh_port = SSH_PORTS["history"]
    end
    node.vm.provision "shell", inline: HOSTS_FILE
    node.vm.provision "shell", inline: CLONE_REPO
    node.vm.provision "shell", inline: <<-SHELL
      set -e
      apt-get update -y
      apt-get install -y python3-venv python3-pip build-essential libpq-dev

      python3 -m venv /opt/history-venv
      /opt/history-venv/bin/pip install --upgrade pip
      /opt/history-venv/bin/pip install -r /opt/app/history-service/requirements.txt

      cat > /etc/systemd/system/history.service <<EOF
[Unit]
Description=History service
After=network.target

[Service]
WorkingDirectory=/opt/app/history-service
Environment=DATABASE_URL=postgresql://postgres:example@postgres:5432/history_db
ExecStart=/opt/history-venv/bin/uvicorn main:app --host 0.0.0.0 --port 8001
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

      systemctl daemon-reload
      systemctl enable --now history.service
      systemctl restart history.service
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
      qe.memory = "1024"
      qe.advanced_network = true
      qe.net_mode = :vmnet_shared
      qe.ssh_port = SSH_PORTS["backend"]
    end
    node.vm.provision "shell", inline: HOSTS_FILE
    node.vm.provision "shell", inline: CLONE_REPO
    node.vm.provision "shell", inline: <<-SHELL
      set -e
      apt-get update -y
      apt-get install -y python3-venv python3-pip build-essential libpq-dev

      python3 -m venv /opt/backend-venv
      /opt/backend-venv/bin/pip install --upgrade pip
      /opt/backend-venv/bin/pip install -r /opt/app/backend-service/requirements.txt

      cat > /etc/systemd/system/backend.service <<EOF
[Unit]
Description=Backend service
After=network.target

[Service]
WorkingDirectory=/opt/app/backend-service
Environment=HISTORY_BASE=http://192.168.105.11:8001
Environment=POLL_INTERVAL_SECONDS=3600
Environment=WATCHED_CITIES=Kyiv,Lviv
Environment=MAX_WATCHED_CITIES=3600
ExecStart=/opt/backend-venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

      systemctl daemon-reload
      systemctl enable --now backend.service
      systemctl restart backend.service
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
    node.vm.provision "shell", inline: CLONE_REPO
    node.vm.provision "shell", inline: <<-SHELL
      set -e
      apt-get update -y
      apt-get install -y nginx

      rm -rf /usr/share/nginx/html/*
      cp -r /opt/app/ui-service/* /usr/share/nginx/html/
      if [ -f /opt/app/ui-service/nginx.conf ]; then
        cp /opt/app/ui-service/nginx.conf /etc/nginx/nginx.conf
      fi

      nginx -t
      systemctl restart nginx
      systemctl enable nginx
    SHELL
  end
end