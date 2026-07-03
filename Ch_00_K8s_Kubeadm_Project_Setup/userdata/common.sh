set -euxo pipefail

echo "=== Common bootstrap started at $(date) ==="

hostnamectl set-hostname "${NODE_HOSTNAME}"

swapoff -a
sed -i '/swap/d' /etc/fstab

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

apt-get update
apt-get install -y \
  ca-certificates curl gnupg \
  jq \
  net-tools \
  dnsutils \
  iputils-ping \
  tcpdump \
  traceroute \
  vim \
  htop \
  tree \
  wget \
  bash-completion

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update

CONTAINERD_VERSION=""
if CANDIDATES=$(apt-cache madison containerd.io 2>/dev/null); then
  CONTAINERD_VERSION=$(echo "$CANDIDATES" | awk -F'|' '{gsub(/ /,"",$2); print $2}' | grep -m1 '^2\.2\.' || true)
fi

if [[ -n "$CONTAINERD_VERSION" ]]; then
  echo "Installing containerd.io=${CONTAINERD_VERSION}"
  apt-get install -y "containerd.io=${CONTAINERD_VERSION}" conntrack
else
  echo "WARN: containerd 2.2.x not found, installing latest available"
  apt-get install -y containerd.io conntrack
fi

containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key" | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

if apt-get install -y cri-tools; then
  apt-mark hold cri-tools
  echo "cri-tools installed from pkgs.k8s.io repo"
else
  echo "WARN: cri-tools package unavailable, falling back to GitHub release"
  CRICTL_VERSION="v${KUBERNETES_VERSION}.0"
  curl -fsSL -o /tmp/crictl.tar.gz \
    "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz"
  tar -xzf /tmp/crictl.tar.gz -C /usr/local/bin crictl
  rm -f /tmp/crictl.tar.gz
  echo "crictl ${CRICTL_VERSION} installed from GitHub release"
fi

echo "=== Installing kubecolor (optional) at $(date) ==="
KUBECOLOR_VERSION="0.5.3"
if curl -fsSL -o /tmp/kubecolor.tar.gz \
      "https://github.com/kubecolor/kubecolor/releases/download/v${KUBECOLOR_VERSION}/kubecolor_${KUBECOLOR_VERSION}_linux_amd64.tar.gz" \
   && tar -xzf /tmp/kubecolor.tar.gz -C /tmp kubecolor; then
  install -m 0755 /tmp/kubecolor /usr/local/bin/kubecolor
  echo "kubecolor v${KUBECOLOR_VERSION} installed"
else
  echo "WARN: kubecolor install failed — continuing without it"
fi
rm -f /tmp/kubecolor.tar.gz /tmp/kubecolor /tmp/LICENSE 2>/dev/null || true

# --- bat install (cat replacement: syntax highlighting + line numbers) --- # ADDED
echo "=== Installing bat at $(date) ==="
if apt-get install -y bat; then
  # Ubuntu/Debian ship the binary as 'batcat' (name clash with bacula-console-qt);
  # symlink to 'bat' so the command works under sudo and in scripts.
  ln -sf /usr/bin/batcat /usr/local/bin/bat
  echo "bat installed ($(batcat --version 2>/dev/null | head -1))"
else
  echo "WARN: bat install failed — 'cat' alias will fall back to plain cat"
fi

cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

command -v kubectl &>/dev/null && kubectl completion bash > /etc/bash_completion.d/kubectl || true
command -v crictl  &>/dev/null && crictl  completion bash > /etc/bash_completion.d/crictl  || true
command -v docker  &>/dev/null && docker  completion bash > /etc/bash_completion.d/docker  || true

command -v bat &>/dev/null && alias cat="bat --paging=never"

{
  if command -v kubecolor &>/dev/null; then
    echo 'alias kubectl="kubecolor"'
    echo 'alias k=kubecolor'
  else
    echo 'alias k=kubectl'
  fi
  echo 'complete -o default -F __start_kubectl kubectl'
  echo 'complete -o default -F __start_kubectl k'
  echo 'alias c=crictl'
  echo 'command -v crictl &>/dev/null && complete -o default -F __start_crictl c'
  echo 'alias d=docker'
  echo 'command -v docker &>/dev/null && complete -o default -F __start_docker d'
} >> /home/ubuntu/.bashrc

echo "=== Common setup completed at $(date) ==="

cat >> /root/.bashrc <<'ROOT_ALIAS_EOF'
# bat: cat replacement (alias only if bat present); --paging=never = no pager in SSM
command -v bat &>/dev/null && alias cat="bat --paging=never"
ROOT_ALIAS_EOF
