#
# Parameters to be passed along when setting up the PCF pipelines
#

locals {
  environment = "${length(var.environment) > 0 
    ? var.environment 
    : data.terraform_remote_state.bootstrap.pcf_sandbox_environment}"
}

data "template_file" "params" {
  template = "${file(var.params_template_file)}"

  vars {
    vsphere_server               = "${data.terraform_remote_state.bootstrap.vsphere_server}"
    vsphere_user                 = "${data.terraform_remote_state.bootstrap.vsphere_user}"
    vsphere_password             = "${data.terraform_remote_state.bootstrap.vsphere_password}"
    vsphere_allow_unverified_ssl = "${data.terraform_remote_state.bootstrap.vsphere_allow_unverified_ssl}"

    pdns_server_url = "http://${data.terraform_remote_state.bootstrap.bastion_admin_fqdn}:8888"
    pdns_api_key    = "${data.terraform_remote_state.bootstrap.powerdns_api_key}"

    s3_access_key_id            = "${data.terraform_remote_state.bootstrap.s3_access_key_id}"
    s3_secret_access_key        = "${data.terraform_remote_state.bootstrap.s3_secret_access_key}"
    s3_default_region           = "${data.terraform_remote_state.bootstrap.s3_default_region}"
    terraform_state_s3_endpoint = "${data.terraform_remote_state.bootstrap.terraform_state_s3_endpoint}"

    terraform_state_bucket = "${data.terraform_remote_state.bootstrap.terraform_state_bucket}"
    bootstrap_state_prefix = "${data.terraform_remote_state.bootstrap.bootstrap_state_prefix}"

    vpc_name = "${data.terraform_remote_state.bootstrap.vpc_name}"

    environment = "${local.environment}"

    automation_pipelines_repo   = "${data.terraform_remote_state.bootstrap.automation_pipelines_repo}"
    automation_pipelines_branch = "${data.terraform_remote_state.bootstrap.automation_pipelines_branch}"

    automation_extensions_repo   = "${data.terraform_remote_state.bootstrap.automation_extensions_repo}"
    automation_extensions_branch = "${data.terraform_remote_state.bootstrap.automation_extensions_branch}"

    pcf_terraform_templates_path = "${data.terraform_remote_state.bootstrap.pcf_terraform_templates_path}"
    pcf_tile_templates_path      = "${data.terraform_remote_state.bootstrap.pcf_tile_templates_path}"

    vpc_dns_zone = "${data.terraform_remote_state.bootstrap.vpc_dns_zone}"

    pivnet_token           = "${data.terraform_remote_state.bootstrap.pivnet_token}"
    opsman_admin_password  = "${data.terraform_remote_state.bootstrap.opsman_admin_password}"
    common_admin_password  = "${data.terraform_remote_state.bootstrap.common_admin_password}"
    pas_system_dbpassword  = "${data.terraform_remote_state.bootstrap.pas_system_dbpassword}"
    credhub_encryption_key = "${data.terraform_remote_state.bootstrap.credhub_encryption_key}"
  }
}

resource "local_file" "params" {
  content  = "${data.template_file.params.rendered}"
  filename = "${var.params_file}"
}
