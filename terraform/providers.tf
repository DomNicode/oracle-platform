terraform{
    required_providers {
        oci = {
            source = "oracle/oci"
            version = "~> 9.8"
        }
    }
}

provider "oci" {
    config_file_profile = "DEFAULT"
}