# frozen_string_literal: true

# Cookbook:: firezone
# Recipe:: phoenix
#
# Copyright:: 2014 Chef Software, Inc.
# Copyright:: 2021 Firezone
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Common configuration for Phoenix

include_recipe 'firezone::config'
include_recipe 'firezone::nginx'

[node['firezone']['phoenix']['log_directory'],
 "#{node['firezone']['var_directory']}/phoenix/run"].each do |dir|
  directory dir do
    owner node['firezone']['user']
    group node['firezone']['group']
    mode '0700'
    recursive true
  end
end

template 'phoenix.nginx.conf' do
  path "#{node['firezone']['nginx']['directory']}/sites-enabled/phoenix"
  source 'phoenix.nginx.conf.erb'
  owner node['firezone']['user']
  group node['firezone']['group']
  mode '0600'
  variables(nginx: node['firezone']['nginx'],
            phoenix: node['firezone']['phoenix'],
            fqdn: node['firezone']['fqdn'],
            fips_enabled: node['firezone']['fips_enabled'],
            ssl: node['firezone']['ssl'],
            app_directory: node['firezone']['app_directory'])
end

if node['firezone']['phoenix']['enable']
  component_runit_service 'phoenix' do
    package 'firezone'
    action :enable
    subscribes :restart, 'file[environment-variables]'
  end
else
  runit_service 'phoenix' do
    action :disable
  end
end