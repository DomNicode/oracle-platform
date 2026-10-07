resource "oci_core_instance" "sayit_agent" {
  compartment_id      = var.tenancy_ocid
  availability_domain = "TxBl:EU-FRANKFURT-1-AD-1"
  fault_domain        = "FAULT-DOMAIN-2"
  display_name        = "sayit-agent"

  # Always Free: 2 OCPU / 12 GB
  shape = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = 100
    boot_volume_vpus_per_gb = 10 # Balanced
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.sayit.id
    display_name     = "sayit-agent"
    hostname_label   = "sayit-agent"
    assign_public_ip = false # öffentliche IP kommt über die reservierte IP
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      defined_tags,
      create_vnic_details[0].defined_tags,
      create_vnic_details[0].assign_public_ip,
      source_details[0].source_id,
      metadata,
    ]
  }
}

resource "oci_core_public_ip" "sayit" {
  compartment_id = var.tenancy_ocid
  display_name   = "sayit-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.sayit_agent.private_ips[0].id

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [defined_tags]
  }
}