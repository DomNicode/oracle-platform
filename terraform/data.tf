# Neuestes Ubuntu 24.04 Image für ARM (A1)
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# VNIC der VM ermitteln
data "oci_core_vnic_attachments" "sayit_agent" {
  compartment_id = var.tenancy_ocid
  instance_id    = oci_core_instance.sayit_agent.id
}

# Private IP der VNIC ermitteln (für die reservierte öffentliche IP)
data "oci_core_private_ips" "sayit_agent" {
  vnic_id = data.oci_core_vnic_attachments.sayit_agent.vnic_attachments[0].vnic_id
}