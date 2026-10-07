resource "oci_core_vcn" "sayit" {
  compartment_id = var.tenancy_ocid
  display_name   = "sayit-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "vcn10071307"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_internet_gateway" "sayit" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.sayit.id
  display_name   = "Internet Gateway sayit-vcn"
  enabled        = true

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_route_table" "sayit" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.sayit.id
  display_name   = "Default Route Table for sayit-vcn"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.sayit.id
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_security_list" "sayit" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.sayit.id
  display_name   = "Default Security List for sayit-vcn"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  #SSH
  ingress_security_rules {
    protocol = "6" 
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }
  # HTTP: Let's-Encrypt-Validierung und Weiterleitung auf HTTPS
  ingress_security_rules {
    protocol = "6" #tcp 
    source   = "0.0.0.0/0"
    description = "HTTP"
    tcp_options {
      min = 80
      max = 80
    }
  }

  #HTTPS
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    description = "HTTPS"
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "10.0.0.0/16"
    icmp_options {
      type = 3
    }
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_subnet" "sayit" {
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.sayit.id
  display_name      = "sayit-net"
  cidr_block        = "10.0.0.0/24"
  dns_label         = "subnet10071307"
  route_table_id    = oci_core_route_table.sayit.id
  security_list_ids = [oci_core_security_list.sayit.id]

  prohibit_public_ip_on_vnic = false

  lifecycle {
    ignore_changes = [defined_tags]
  }
}