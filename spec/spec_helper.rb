require File.expand_path(File.dirname(__FILE__) + "/../lib/cheetah")

RSpec.configure do |c|
  c.color_enabled = true
end

RSpec::Matchers.define :touch do |*files|
  match do |proc|
    proc.call
    files.all? { |f| File.exists?(f) }
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
