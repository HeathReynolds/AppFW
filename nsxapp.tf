terraform {
  required_providers {
    nsxt = {
      source = "vmware/nsxt"
    }
  }
}

provider "vsphere" {
  user                 = "administrator@vsphere.local"
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
    destination_groups    = [nsxt_policy_group.hr_web_group.path]
    source_groups         = [nsxt_policy_group.hr_app_group.path]
    scope                 = [nsxt_policy_group.all_HR.path]
  }

   rule {
    display_name          = "HR App to DB"
    description           = "Allow App to DB in HR app"
    action                = "ALLOW"
    logged                = true
    ip_version            = "IPV4"
    destination_groups    = [nsxt_policy_group.hr_web_group.path]
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