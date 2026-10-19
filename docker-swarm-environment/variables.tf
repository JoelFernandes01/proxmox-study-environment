# =========================================================================
# Credenciais e Conexão Proxmox
# =========================================================================
variable "proxmox_api_url" {
  type        = string
  description = "A URL de API do servidor Proxmox"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "ID do API Token gerado no Proxmox"
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "A chave secreta (secret value) do API Token"
  sensitive   = true
}

variable "target_node" {
  type        = string
  default     = "des"
  description = "Nome do nó do Proxmox onde as VMs serão criadas"
}

# =========================================================================
# Template e Nós
# =========================================================================
variable "template_vm_id" {
  type        = string
  description = "O ID da VM do template (Ex: 8000)"
}

variable "swarm_managers" {
  type        = list(string)
  default     = ["docker-swarm-01", "docker-swarm-02", "docker-swarm-03"]
  description = "Lista de nomes das VMs manager do Docker Swarm"
}

variable "swarm_workers" {
  type        = list(string)
  default     = ["docker-worker-01", "docker-worker-02", "docker-worker-03"]
  description = "Lista de nomes das VMs worker do Docker Swarm"
}

# =========================================================================
# Configurações do NFS Server Dedicado (swm-nfs-01)
# =========================================================================
variable "swarm_nfs_ip" {
  type        = number
  default     = 30
  description = "Número do host IP do NFS Server do Swarm (10.0.39.30)"
}

variable "swarm_nfs_vm_id" {
  type        = number
  default     = 9030
  description = "VM ID do NFS Server do Docker Swarm"
}

# =========================================================================
# Faixas de IPs e VM IDs
# =========================================================================
variable "swarm_manager_ip_start" {
  type        = number
  default     = 31
  description = "Host IP inicial dos managers (10.0.39.31)"
}

variable "swarm_worker_ip_start" {
  type        = number
  default     = 35
  description = "Host IP inicial dos workers (10.0.39.35)"
}

variable "swarm_manager_vm_id_start" {
  type        = number
  default     = 9000
  description = "VM ID inicial para os managers"
}

variable "swarm_worker_vm_id_start" {
  type        = number
  default     = 9010
  description = "VM ID inicial para os workers"
}

# =========================================================================
# Recursos e Hardware da VM
# =========================================================================
variable "vm_cores" {
  type        = string
  default     = "2"
  description = "Quantidade de vCPUs alocadas por VM"
}

variable "vm_memory" {
  type        = string
  default     = "4096"
  description = "Memória RAM dedicada em MB por VM"
}

variable "vm_storage_id" {
  type        = string
  default     = "storage-vms"
  description = "O ID do storage onde os discos serão provisionados"
}

variable "vm_disk_size" {
  type        = string
  default     = "50"
  description = "Tamanho do disco do Sistema Operacional em GB"
}

# =========================================================================
# Rede e SSH
# =========================================================================
variable "vm_network_cidr" {
  type        = string
  default     = "10.0.39.0/24"
  description = "CIDR da rede onde as VMs serão provisionadas"
}

variable "vm_gateway" {
  type        = string
  default     = "10.0.39.1"
  description = "Gateway da rede"
}

variable "vm_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Bridge de rede do Proxmox"
}

variable "vm_user" {
  type        = string
  default     = "connect"
  description = "Usuário administrador existente no template"
}

variable "ssh_public_key" {
  type        = string
  description = "Chave SSH pública para administração"
}
