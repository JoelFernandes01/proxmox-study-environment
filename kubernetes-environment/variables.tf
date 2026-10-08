# =========================================================================
# Kubernetes — Variables
# =========================================================================

# =========================================================================
# Credenciais Proxmox
# =========================================================================
variable "proxmox_api_url" {
  type        = string
  description = "URL da API do Proxmox"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "ID do API Token"
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Secret do API Token"
  sensitive   = true
}

# =========================================================================
# Node e Template
# =========================================================================
variable "target_node" {
  type        = string
  description = "Nome do nó do Proxmox"
  default     = "des"
}

variable "template_vm_id" {
  type        = string
  description = "ID do template (ex: 8000)"
  default     = "8000"
}

# =========================================================================
# HAProxy
# =========================================================================
variable "k8s_haproxy" {
  type        = list(string)
  description = "Lista de nomes dos HAProxy"
  default     = ["k8s-haproxy-01", "k8s-haproxy-02"]
}

variable "k8s_haproxy_ip_start" {
  type        = number
  description = "IP inicial do HAProxy (10.0.39.X)"
  default     = 41
}

variable "k8s_haproxy_vm_id_start" {
  type        = number
  description = "VM ID inicial do HAProxy"
  default     = 9400
}

# =========================================================================
# Control Planes
# =========================================================================
variable "k8s_control_planes" {
  type        = list(string)
  description = "Lista de nomes dos Control Planes"
  default     = ["k8s-control-plane-01", "k8s-control-plane-02", "k8s-control-plane-03"]
}

variable "k8s_cp_ip_start" {
  type        = number
  description = "IP inicial dos Control Planes"
  default     = 43
}

variable "k8s_cp_vm_id_start" {
  type        = number
  description = "VM ID inicial dos Control Planes"
  default     = 9402
}

# =========================================================================
# Workers
# =========================================================================
variable "k8s_workers" {
  type        = list(string)
  description = "Lista de nomes dos Workers"
  default     = ["k8s-worker-01", "k8s-worker-02", "k8s-worker-03"]
}

variable "k8s_workers_ip_start" {
  type        = number
  description = "IP inicial dos Workers"
  default     = 61
}

variable "k8s_workers_vm_id_start" {
  type        = number
  description = "VM ID inicial dos Workers"
  default     = 9405
}

# =========================================================================
# VM Config
# =========================================================================
variable "vm_cores" {
  type        = string
  description = "vCPUs por VM"
  default     = "2"
}

variable "vm_memory" {
  type        = string
  description = "RAM em MB por VM"
  default     = "4096"
}

variable "vm_storage_id" {
  type        = string
  description = "Storage das VMs"
  default     = "storage-vms"
}

variable "vm_disk_size" {
  type        = string
  description = "Tamanho do disco em GB"
  default     = "50"
}

# =========================================================================
# Rede
# =========================================================================
variable "vm_network_cidr" {
  type        = string
  description = "CIDR da rede"
  default     = "10.0.39.0/24"
}

variable "vm_gateway" {
  type        = string
  description = "Gateway da rede"
  default     = "10.0.39.1"
}

variable "vm_bridge" {
  type        = string
  description = "Bridge de rede"
  default     = "vmbr0"
}

# =========================================================================
# SSH
# =========================================================================
variable "vm_user" {
  type        = string
  description = "Usuário SSH"
  default     = "connect"
}

variable "ssh_public_key" {
  type        = string
  description = "Chave SSH pública"
}
