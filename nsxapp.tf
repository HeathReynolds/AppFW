#Test Push
terraform {
  required_providers {
    nsxt = {
      source = "vmware/nsxt"
    }
  }
}

provider "vsphere" {
  user                 = "administrator@CORP.LOCAL"
  password             = "VMware1!"
  vsphere_server       = "vcsa-01a"
  allow_unverified_ssl = true
}

provider "nsxt" {
  version               = "~> 3.2"
  host                  = "nsxmgr-01a"
  username              = "admin"
  password              = "VMware1!VMware1!"
  allow_unverified_ssl  = true
  max_retries           = 10
  retry_min_delay       = 500
  retry_max_delay       = 5000
  retry_on_status_codes = [429]
}

data "nsxt_policy_service" "http" {
  display_name = "HTTP"
}

data "nsxt_policy_service" "https" {
  display_name = "HTTPS"
}

data "vsphere_datacenter" "datacenter" {
  name = "RegionA01"
}

data "vsphere_datastore" "datastore" {
  name          = "Local-esx-01a"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = "RegionA01-COMP01"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name          = "HR-VLAN"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "hr-web-01" {
  name          = "hr-web-01"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "hr-web-02" {
  name          = "hr-web-02"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "hr-app-01" {
  name          = "hr-app-01"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "hr-db-01" {
  name          = "hr-db-01"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

#Define group membership to be used in Firewall Rule

resource "nsxt_policy_group" "hr_web_group" {
  display_name = "HR Web VMs"
  description  = "Group consisting of HR Web VMs VMs"
  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "Web"
    }
  }

    conjunction {
    operator = "AND"
  }

  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "HR"
    }
  }
}

resource "nsxt_policy_group" "hr_app_group" {
  display_name = "HR App VMs"
  description  = "Group consisting of HR App VMs VMs"
  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "App"
    }
  }

    conjunction {
    operator = "AND"
  }

  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "HR"
    }
  }
}

resource "nsxt_policy_group" "hr_db_group" {
  display_name = "HR DB VMs"
  description  = "Group consisting of HR DB VMs VMs"
  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "DB"
    }
  }

    conjunction {
    operator = "AND"
  }

  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "HR"
    }
  }
}

#Create Microseg firewall rules for HR app

resource "nsxt_policy_group" "all_HR" {
  display_name = "HR_VMs"
  description  = "Group consisting of all HR VMs"
  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "HR"
    }
  }
}

resource "nsxt_policy_security_policy" "firewall_section" {
  display_name = "HR App - Zero Trust"
  description  = "Microsegment HR Application"
  category     = "Application"
  locked       = "false"
  stateful     = "true"

  rule {
    display_name          = "HR Web Access"
    description           = "Access to app front end"
    action                = "ALLOW"
    logged                = true
    ip_version            = "IPV4"
    destination_groups    = [nsxt_policy_group.hr_web_group.path]
    scope                 = [nsxt_policy_group.all_HR.path]
    services              = [data.nsxt_policy_service.http.path, data.nsxt_policy_service.https.path]
 
  }

  rule {
    display_name          = "HR Web to App"
    description           = "Allow Web to App in HR App"
    action                = "ALLOW"
    logged                = true
    ip_version            = "IPV4"
    destination_groups    = [nsxt_policy_group.hr_app_group.path]
    source_groups         = [nsxt_policy_group.hr_web_group.path]
    scope                 = [nsxt_policy_group.all_HR.path]
  }

   rule {
    display_name          = "HR App to DB"
    description           = "Allow App to DB in HR app"
    action                = "ALLOW"
    logged                = true
    ip_version            = "IPV4"
    destination_groups    = [nsxt_policy_group.hr_db_group.path]
    source_groups         = [nsxt_policy_group.hr_app_group.path]
    scope                 = [nsxt_policy_group.all_HR.path]
  }

    rule {
    display_name          = "HR Default"
    description           = "Default Deny for HR app"
    action                = "DROP"
    logged                = true
    ip_version            = "IPV4"
    scope                 = [nsxt_policy_group.all_HR.path]
  }
}

#Create HR Application VMs

resource "vsphere_virtual_machine" "vm" {
  name             = "CICD-HR-WEB01"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  num_cpus         = 1
  memory           = 1024
  guest_id         = data.vsphere_virtual_machine.hr-web-01.guest_id
  scsi_type        = data.vsphere_virtual_machine.hr-web-01.scsi_type
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.hr-web-01.network_interface_types[0]
  }
  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.hr-web-01.disks.0.size
    thin_provisioned = data.vsphere_virtual_machine.hr-web-01.disks.0.thin_provisioned
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.hr-web-01.id
  }
}

resource "vsphere_virtual_machine" "vm2" {
  name             = "CICD-HR-WEB02"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  num_cpus         = 1
  memory           = 1024
  guest_id         = data.vsphere_virtual_machine.hr-web-02.guest_id
  scsi_type        = data.vsphere_virtual_machine.hr-web-02.scsi_type
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.hr-web-02.network_interface_types[0]
  }
  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.hr-web-02.disks.0.size
    thin_provisioned = data.vsphere_virtual_machine.hr-web-02.disks.0.thin_provisioned
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.hr-web-02.id
  }
}

resource "vsphere_virtual_machine" "vm3" {
  name             = "CICD-HR-APP01"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  num_cpus         = 1
  memory           = 1024
  guest_id         = data.vsphere_virtual_machine.hr-app-01.guest_id
  scsi_type        = data.vsphere_virtual_machine.hr-app-01.scsi_type
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.hr-app-01.network_interface_types[0]
  }
  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.hr-app-01.disks.0.size
    thin_provisioned = data.vsphere_virtual_machine.hr-app-01.disks.0.thin_provisioned
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.hr-app-01.id
  }
}

resource "vsphere_virtual_machine" "vm4" {
  name             = "CICD-HR-DB01"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  num_cpus         = 1
  memory           = 1024
  guest_id         = data.vsphere_virtual_machine.hr-db-01.guest_id
  scsi_type        = data.vsphere_virtual_machine.hr-db-01.scsi_type
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.hr-db-01.network_interface_types[0]
  }
  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.hr-db-01.disks.0.size
    thin_provisioned = data.vsphere_virtual_machine.hr-db-01.disks.0.thin_provisioned
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.hr-db-01.id
  }
}

#Apply tags to newly created VMs

resource "nsxt_policy_vm_tags" "web01_vm_tag" {
  instance_id = vsphere_virtual_machine.vm.id
  tag {
    scope = "tier"
    tag   = "Web"
  }
  tag {
    scope = "app"
    tag   = "HR"
  }
}

resource "nsxt_policy_vm_tags" "web02_vm_tag" {
  instance_id = vsphere_virtual_machine.vm2.id
  tag {
    scope = "tier"
    tag   = "Web"
  }
  tag {
    scope = "app"
    tag   = "HR"
  }
}

resource "nsxt_policy_vm_tags" "app01_vm_tag" {
  instance_id = vsphere_virtual_machine.vm3.id
  tag {
    scope = "tier"
    tag   = "App"
  }
  tag {
    scope = "app"
    tag   = "HR"
  }
}

resource "nsxt_policy_vm_tags" "db01_vm_tag" {
  instance_id = vsphere_virtual_machine.vm4.id
  tag {
    scope = "tier"
    tag   = "DB"
  }
  tag {
    scope = "app"
    tag   = "HR"
  }
}
