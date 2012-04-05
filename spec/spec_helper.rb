require "logger"

require "cheetah"

RSpec.configure do |c|
  c.color_enabled = true
end

RSpec::Matchers.define :touch do |file|
  match do |proc|
    proc.call
    File.exists?(file)
  end
end

RSpec::Matchers.define :write do |output|
  chain :into do |file|
    @file = file
  end

  match do |proc|
    proc.call
    File.read(@file).should == output
  end
end

def logger_with_io
  io = StringIO.new
  logger = Logger.new(io)
  logger.formatter = lambda { |severity, time, progname, msg|
    "#{severity} #{progname ? progname + ": " : ""}#{msg}\n"
  }

  [logger, io]
end

RSpec::Matchers.define :log do |output|
  match do |proc|
    logger, io = logger_with_io

    proc.call(logger)

    io.string.should == output.gsub(/^\s+/, "")
  end
end
