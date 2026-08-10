terraform {
  required_version = ">= 1.15"

  required_providers {
    # The extension is an azapi_resource and the reboot an azapi_resource_action,
    # so this module speaks only azapi. The parent VM stays an azurerm resource
    # in the CALLER - only its id and location are passed in as strings.
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.0, < 3.0"
    }
  }
}
