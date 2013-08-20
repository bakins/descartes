action :create do
  name = new_resource.instance

  log_dir = ::File.join(node[:descartes][:log_dir], name)
  directory log_dir do
    recursive true
  end

  config = ::File.join(node[:descartes][:app_dir], "#{name}.yml")

  template config do
    source "instance.yml.erb"
    variables(
              hostname: name,
              image: new_resource.image,
              command: new_resource.command,
              port: new_resource.port,
              env: new_resource.env
              )
    notifies :restart, "runit_service[#{name}]"
  end

  runit_service name do
    run_template_name "lxc"
    log_template_name "lxc"
    options(
            config: config,
            log_dir: log_dir
            )
    action [ :enable, :start ]
  end

end

action :delete do
  Chef::Log.info "deleting #{new_resource}"

  name = new_resource.instance

  runit_service name do
    action [ :stop, :disable ]
  end

  directory ::File.join(node[:runit][:sv_dir], name) do
    recursive true
    action :delete
  end

  file ::File.join(node[:descartes][:app_dir], "#{name}.yml") do
    action :delete
  end

end
