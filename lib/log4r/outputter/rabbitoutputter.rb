# :nodoc:
require "rubygems"
require 'logger'
require "log4r/outputter/outputter"
require 'bunny'
require 'yaml'
require 'pathname'

module Log4r
  # See log4r/logserver.rb
  class RabbitOutputter < Outputter

    def initialize(_name, hash={})
      # Configuration defaults
      super(_name, hash)
      stderr_log "Unable to find rabbit configuration file" unless load_config_file("rabbitmq.yml")
      @config ||= {:host => "localhost"}
      @queue_name = @config.delete(:queue) || ''
      start_bunny
    end

    def load_config_file(name)
      path = Pathname(Dir.pwd).join('config', name)
      if File.exist?(path)
        # symbolize_keys without the active_support dependency
        @config = Hash[YAML::load(IO.read(path)).map{|(k,v)| [k.to_sym,v]}]
      end
    end

    def start_bunny
      begin
        stderr_log "Starting Bunny Client"
        config = @config.clone
        config[:pass] &&= "**redacted**"
        stderr_log config
        @conn = Bunny.new @config
        @conn.start
        create_channel
      rescue Bunny::TCPConnectionFailed => e
        stderr_log "rescued from: #{e}. Unable to connect to Rabbit Server"
      rescue Exception => e
        stderr_log "rescued from: #{e}. Encountered when attempting to initialize Bunny Client"
      end
    end

    def stderr_log(msg)
      $stderr.puts "[#{Time.now.utc}] #{msg}"
    end

    def create_channel
      ch = @conn.create_channel
      @queue  = ch.queue(@queue_name, auto_delete: false, durable: true)
    end

    private

    def write(data)
      start_bunny if @conn.nil?
      @queue.publish data, { routing_key: @queue.name } if !@conn.nil? && @conn.connected? && @queue
    rescue Exception => e
      @conn.send(:handle_network_failure, e)
      create_channel if @conn.connected?
    end

  end
end
