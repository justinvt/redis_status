class RedisStatus

  @@redis_status =  {}

  SERVER_PROCESS_NAME="redis-server"
  CLIENT_PROCESS_NAME="redis-cli"
  GUESS_HOST=`ifconfig | grep -o -P "(192|127)\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | head -n 1`.strip
  CONFIG_LOCATIONS=["/etc/redis.conf", "/etc/redis/redis.conf", "/usr/local/etc/redis.conf"]

  def self.process_info
    @info = `ps aux | grep "#{SERVER_PROCESS_NAME}" | grep -v "grep"`.strip.split(/\s+/)
    {
      :user => @info[0],
      :pid => @info[1],
      :cpu=> @info[2],
      :mem=> @info[3],
      :vsz=> @info[4],
      :rss=> @info[5],
      :tt=> @info[6],
      :stat=> @info[7],
      :started=> @info[8],
      :time=> @info[9],
      :command=> @info[10],
      :args=> @info[11..-1]
      }
  end

  def self.pid
    process_info[:pid]
  end

  def self.running?
    !self.pid.nil?
  end

  def self.find_config
     CONFIG_LOCATIONS.select{|f| File.exist?(f) }.first
  end

  def self.config_filename
    process_info[:args].nil? ? self.find_config : process_info[:args][0]
  end

  def self.conf
     parse_settings(`cat #{config_filename || "/dev/null"}`)
  end

  def self.set_status(*args)
    if args.size == 1 && args[0].is_a?(Hash)
      @@redis_status.merge!(args[0])
    elsif args.size == 2 && [Symbol, String].include?(args[0].class)
      @@redis_status[args[0].to_sym] = args[1]
    end
  end

  # Accepts output from `redis-cli info` or the contents of redis.conf and parses it, populating a hash with the results
  def self.parse_settings(settings)
    set = {}
    settings.split(/\n|\r/).reject{|line| line =~ /^#/ || line.strip == ""}.map{|line| line.split(/:|\s+/)}.reject{|kv| kv.size != 2 }.each do |keypair|
      set[keypair[0].to_sym] = keypair[1]
    end
    set
  end

  def self.status(key=nil)
    key.nil? ? @@redis_status : @@redis_status[key.to_sym]
  end

  def self.cli_exec(command, *args)
    `#{CLIENT_PROCESS_NAME} -h #{status[:bind] || GUESS_HOST} #{command.to_s} #{args.join}`
  end

  def self.cli_info
     parse_settings(cli_exec :info)
  end

  def self.config(key)
    output = cli_exec "config get", key
    result = output.split(/\n|\r/)[1]
    set_status(key, result)
    return result
  end

  def self.db_file
    File.join(config(:dir),config(:dbfilename))
  end

  def self.dbs
    self.cli_info.select{|k,v| k.to_s =~ /db/}
  end

  def self.tail
    `tail -n 50 #{self.conf[:logfile] || "/dev/null"}`.split(/\n|\r/)
  end

  def self.recent_errors
     tail.select{|line| line.match(/#/)}
  end

  def self.last_save
    Time.at(cli_exec(:lastsave).match(/\d+$/).to_s.to_i)
  end

  def self.errors?
    !recent_errors.empty?
  end

  def self.memory_allocation
    self.cli_info[:allocation_stats].split(",").map{|e| e.split("=").select{|i| i =~ /\d+/}}
  end

  def self.method_missing(m, *args, &block)
    return @@redis_status[m.to_sym]
  end


end
