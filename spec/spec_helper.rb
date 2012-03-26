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
