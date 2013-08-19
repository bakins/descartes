def find(name)
  Docker::Container.all.each do |c|
    c = c.json
    if c['Config']['Hostname'] == name
      return c
    end
  end
  return nil
end

action :create do

  name = new_resource.instance

  unless find(name)

    image = new_resource.image

    # can do via API?
    #  bash "docker pull #{image}" do
    #    code "docker -H tcp://localhost:4243 pull #{image}"

    opts = {
      Hostname: name,
      Cmd: new_resource.command,
      Image: new_resource.image,
      PortSpecs: [ new_resource.port.to_s ],
      Env: new_resource.env,
      AttachStderr: false,
      AttachStdin: false,
      AttachStdout: false
    }

    c = Docker::Container.create(opts)
    c.start
  end

end

action :delete do
  name = new_resource.instance
  Docker::Container.all(all: 1).each do |c|
    if c.hostname == name  or (new_resource.container_id and c.id == new_resource.container_id)
      if c.running?
        Chef::Log.info "Stopping: #{c.id} : #{name}"
        c.stop(t: 30)
        sleep 5
      end
      Chef::Log.info "Deleting: #{c.id} : #{name}"
      c.delete
    end
  end
end
