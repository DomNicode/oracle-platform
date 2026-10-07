variable "tenancy_ocid" {
  type        = string
  description = "OCID der Tenancy (Root-Compartment)"
}
variable "ssh_public_key" {
  type        = string
  description = "Öffentlicher SSH-Key für den Zugang zur VM"
}