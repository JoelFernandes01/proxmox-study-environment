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
variable "template_vm_id" {
  type        = string
  description = "O ID da VM do template (Ex: 8000)"
}

# =========================================================================
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
variable "swarm_manager_ip_start" {
  type        = number
  default     = 100
  description = "Número de host inicial para os managers (10.0.39.X)"
}

variable "swarm_worker_ip_start" {
  type        = number
  default     = 120
  description = "Número de host inicial para os workers (10.0.39.X)"
}

# =========================================================================
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
  description = "Tamanho do disco do Sistema Operacional (SCSI 0) em GB"
}

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

# =========================================================================
variable "vm_user" {
  type        = string
  default     = "connect"
  description = "Usuário administrador já existente no template"
}

variable "ssh_public_key" {
  type        = string
  description = "Chave SSH pública para acesso de administração"
}