#
# Auto-generated Chef Remediation Cookbook
# InSpec Control: xccdf_org.cisecurity.benchmarks_rule_4.2.1.1.3_Ensure_systemd-journal-remote_is_enabled
# Generated: 2025-08-29T14:02:28.238Z
# Source: Nuclia AI via HealOps Extended
# Review Status: Automated generation - manual review recommended
#

# Auto-generated Chef Remediation Cookbook - Ubuntu
# InSpec Control: xccdf_org.cisecurity.benchmarks_rule_4.2.1.1.3_Ensure_systemd-journal-remote_is_enabled
# Platform: Ubuntu

# Ensure systemd-journal-remote is installed
package 'systemd-journal-remote' do
  action :install
end

# Enable and start the systemd-journal-upload service
service 'systemd-journal-upload' do
  action [:enable, :start]
end

# Ensure systemd-journal-remote is configured
file '/etc/systemd/journal-upload.conf' do
  content <<-EOF
[Upload]
URL=@JOURNALD_SERVER@
ServerKeyFile=@JOURNALD_SERVER_KEY@
ServerCertificateFile=@JOURNALD_SERVER_CERT@
TrustedCertificateFile=@JOURNALD_TRUSTED_CERT@
EOF
  mode '0640'
  owner 'root'
  group 'root'
end
