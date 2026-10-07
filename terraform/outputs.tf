output "public_ip" {
  description = "Öffentliche IP der VM"
  value       = oci_core_public_ip.sayit.ip_address
}