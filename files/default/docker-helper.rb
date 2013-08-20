#!/opt/chef/embedded/bin/ruby
require 'net/http'
require 'json'
require 'yaml'

STDOUT.sync = true

config = YAML.load_file(ARGV[0])

http = Net::HTTP.new("127.0.0.1", 4243)
req = Net::HTTP::Post.new("/containers/create", {'Content-Type' => 'text/json'})

req.body = {
  Cmd: config["command"],
  Image: config["image"],
  PortSpecs: [ config["port"].to_s ],
  AttachStderr: false,
  AttachStdin: false,
  AttachStdout: false,
  StdinOnce: false,
  Tty: false
}.to_json

puts req.body

res = http.request req

unless res.code.to_i == 201
  raise "#{res.code}: #{res.body}"
end

data =  JSON.parse(res.body)
id = data['Id']

req = Net::HTTP::Post.new("/containers/#{id}/start")
req.body = {}.to_json
res = http.request req

unless res.code.to_i == 204
  raise "#{res.code}: #{res.body}"
end

#self_pipe stuff copied from chef-client, who copied from unicorn??
SELF_PIPE = []

SELF_PIPE.replace IO.pipe

$running = true

def do_signal()
  puts "got signalled"
  $running = false
  SELF_PIPE[1].putc('.')
end

Signal.trap("INT") { do_signal }
Signal.trap("TERM") { do_signal }

def pipe_sleep(sec)
  puts "selecting"
  IO.select([ SELF_PIPE[0] ], nil, nil, sec) or return
  SELF_PIPE[0].getc
end

Thread.new {
  while $running do
    pipe_sleep(10)
  end
  puts "stopping"
  http = Net::HTTP.new("127.0.0.1", 4243)
  req = Net::HTTP::Post.new("/containers/#{id}/stop?t=5")
  req.body = {}.to_json
  res = http.request req
  unless res.code.to_i == 204
    raise "#{res.code}: #{res.body}"
  end
}

# we only want to dump log buffer the first time through
logs = 1

while $running
  req = Net::HTTP::Post.new("/containers/#{id}/attach?logs=#{logs}&stdout=1&stream=1&stderr=1")
  Net::HTTP.start("127.0.0.1", 4243) do |http|
    http.request req do |res|
      unless res.code.to_i == 200
        #what if is a transient error?
        puts "#{res.code}: #{res.body}"
        logs = 0
      end
      res.read_body do |chunk|
        print chunk
      end
    end
  end
end

