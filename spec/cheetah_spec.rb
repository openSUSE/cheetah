require "spec_helper"

describe Cheetah do
  describe "run" do
    # Fundamental question: To mock or not to mock the actual system interface?
    #
    # I decided not to mock so we can be sure Cheetah#run really works. Also the
    # mocking would be quite complex (if possible at all) given the
    # forking/piping/selecting in the code.
    #
    # Of course, this decision makes this unit test an intgration test by strict
    # definitions.

    before do
      @tmp_dir = "/tmp/cheetah_test_#{Process.pid}"
      FileUtils.mkdir(@tmp_dir)
    end

    after do
      FileUtils.rm_rf(@tmp_dir)
    end

    def create_command(source, options = {})
      command = "#@tmp_dir/" + (options[:name] || "command")

      File.open(command, "w") do |f|
        f.puts "#!/bin/sh"
        f.puts source
      end
      FileUtils.chmod(0777, command)

      command
    end

    describe "running commands" do
      it "runs a command without arguments" do
        command = create_command("touch #@tmp_dir/touched")
        lambda { Cheetah.run(command) }.should touch("#@tmp_dir/touched")
      end

      it "runs a command with arguments" do
        command = create_command("echo -n \"$@\" >> #@tmp_dir/args")
        lambda {
          Cheetah.run(command, "foo", "bar", "baz")
        }.should write("foo bar baz").into("#@tmp_dir/args")
      end

      it "runs a command without arguments using one array param" do
        command = create_command("touch #@tmp_dir/touched")
        lambda { Cheetah.run([command]) }.should touch("#@tmp_dir/touched")
      end

      it "runs a command with arguments using one array param" do
        command = create_command("echo -n \"$@\" >> #@tmp_dir/args")
        lambda {
          Cheetah.run([command, "foo", "bar", "baz"])
        }.should write("foo bar baz").into("#@tmp_dir/args")
      end

      it "does not mind weird characters in the command" do
        command = create_command("touch #@tmp_dir/touched", :name => "we ! ir $d")
        lambda { Cheetah.run([command]) }.should touch("#@tmp_dir/touched")
      end

      it "does not mind weird characters in the arguments" do
        command = create_command("echo -n \"$@\" >> #@tmp_dir/args")
        lambda {
          Cheetah.run(command, "we ! ir $d", "we ! ir $d", "we ! ir $d")
        }.should write("we ! ir $d we ! ir $d we ! ir $d").into("#@tmp_dir/args")
      end

      it "does not pass the command to the shell" do
        command = create_command("touch #@tmp_dir/touched", :name => "foo < bar > baz | qux")
        lambda { Cheetah.run(command) }.should touch("#@tmp_dir/touched")
      end
    end

    describe "input passing" do
      it "does not use standard input of the parent process with no :stdin option" do
        # We just open a random file to get a file descriptor into which we can
        # save our stdin.
        saved_stdin = File.open("/dev/null", "r")
        saved_stdin.reopen(STDIN)

        reader, writer = IO.pipe

        writer.write "blah"
        writer.close

        STDIN.reopen(reader)
        begin
          Cheetah.run("cat", :stdout => :capture).should == ""
        ensure
          STDIN.reopen(saved_stdin)
          reader.close
        end
      end

      it "reads standard input from :stdin when set to a string" do
        Cheetah.run("cat", :stdin => "",      :stdout => :capture).should == ""
        Cheetah.run("cat", :stdin => "input", :stdout => :capture).should == "input"
      end

      it "reads standard input from :stdin when set to an IO" do
        StringIO.open("") do |stdin|
          Cheetah.run("cat", :stdin => stdin, :stdout => :capture).should == ""
        end
        StringIO.open("input") do |stdin|
          Cheetah.run("cat", :stdin => stdin, :stdout => :capture).should == "input"
        end
      end
    end

    describe "output capturing" do
      before do
        @command = create_command(<<-EOT)
          echo -n 'output'
          echo -n 'error' 1>&2
        EOT
      end

      it "does not use standard output of the parent process with no :stdin and :stderr options" do
        # We just open a random file to get a file descriptor into which we can
        # save our stdout.
        saved_stdout = File.open("/dev/null", "w")
        saved_stdout.reopen(STDOUT)

        reader, writer = IO.pipe

        STDOUT.reopen(writer)
        begin
          Cheetah.run(@command)
        ensure
          STDOUT.reopen(saved_stdout)
          writer.close
        end

        reader.read.should == ""
        reader.close
      end

      it "does not use error output of the parent process with no :stdin and :stderr options" do
        # We just open a random file to get a file descriptor into which we can
        # save our stderr.
        saved_stderr = File.open("/dev/null", "w")
        saved_stderr.reopen(STDERR)

        reader, writer = IO.pipe

        STDERR.reopen(writer)
        begin
          Cheetah.run(@command)
        ensure
          STDERR.reopen(saved_stderr)
          writer.close
        end

        reader.read.should == ""
        reader.close
      end

      it "returns nil with no :stdout and :stderr options" do
        Cheetah.run(@command).should be_nil
      end

      it "returns nil with :stdout => nil" do
        Cheetah.run(@command, :stdout => nil).should be_nil
      end

      it "returns nil with :stderr => nil" do
        Cheetah.run(@command, :stderr => nil).should be_nil
      end

      it "returns the standard output with :stdout => :capture" do
        Cheetah.run("echo", "-n", "output", :stdout => :capture).should == "output"
      end

      it "returns the error output with :stderr => :capture" do
        Cheetah.run(@command, :stderr => :capture).should == "error"
      end

      it "returns both outputs with :stdout => :capture and :stderr => :capture" do
        Cheetah.run(@command, :stdout => :capture, :stderr => :capture).should == ["output", "error"]
      end

      it "handles commands that output nothing correctly with :stdout => :capture and :stderr => :capture" do
        Cheetah.run("/bin/true", :stdout => :capture, :stderr => :capture).should == ["", ""]
      end
    end

    describe "logging" do
      it "does not log anything with no :logger option" do
        lambda { Cheetah.run("/bin/true") }.should log("")
      end

      it "does not log anything with :logger => nil" do
        lambda { Cheetah.run("/bin/true") }.should log("")
      end

      it "logs a successful execution of a command without arguments" do
        lambda { |logger|
          Cheetah.run("/bin/true", :logger => logger)
        }.should log(<<-EOT)
          INFO Executing command "/bin/true" with no arguments.
          INFO Standard input: (none)
          INFO Status: 0
          INFO Standard output: (none)
          INFO Error output: (none)
        EOT
      end

      it "logs a successful execution of a command with arguments" do
        lambda { |logger|
          Cheetah.run("/bin/true", "foo", "bar", "baz", :logger => logger)
        }.should log(<<-EOT)
          INFO Executing command "/bin/true" with arguments "foo", "bar", "baz".
          INFO Standard input: (none)
          INFO Status: 0
          INFO Standard output: (none)
          INFO Error output: (none)
        EOT
      end

      it "logs a successful execution of a command producing output" do
        command = create_command(<<-EOT)
          echo -n ''
          echo -n '' 1>&2
        EOT

        lambda { |logger|
          Cheetah.run(command, :stdin => "", :logger => logger)
        }.should log(<<-EOT)
          INFO Executing command "#@tmp_dir/command" with no arguments.
          INFO Standard input: (none)
          INFO Status: 0
          INFO Standard output: (none)
          INFO Error output: (none)
        EOT

        command = create_command(<<-EOT)
          echo -n 'output'
          echo -n 'error' 1>&2
        EOT

        lambda { |logger|
          Cheetah.run(command, :stdin => "blah", :logger => logger)
        }.should log(<<-EOT)
          INFO Executing command "#@tmp_dir/command" with no arguments.
          INFO Standard input: blah
          INFO Status: 0
          INFO Standard output: output
          ERROR Error output: error
        EOT
      end

      it "logs standard input with no :stdin option" do
        lambda { |logger|
          Cheetah.run("/bin/true", :logger => logger)
        }.should log(<<-EOT)
          INFO Executing command "/bin/true" with no arguments.
          INFO Standard input: (none)
          INFO Status: 0
          INFO Standard output: (none)
          INFO Error output: (none)
        EOT
      end

      it "logs standard input with :stdin set to a string" do
        lambda { |logger|
          Cheetah.run("/bin/true", :stdin => "", :logger => logger)
        }.should log(<<-EOT)
          INFO Executing command "/bin/true" with no arguments.
          INFO Standard input: (none)
          INFO Status: 0
          INFO Standard output: (none)
          INFO Error output: (none)
        EOT

        lambda { |logger|
          Cheetah.run("/bin/true", :stdin => "blah", :logger => logger)
        }.should log(<<-EOT)
          INFO Executing command "/bin/true" with no arguments.
          INFO Standard input: blah
          INFO Status: 0
          INFO Standard output: (none)
          INFO Error output: (none)
        EOT
      end

      it "logs standard input with :stdin set to an IO" do
        StringIO.open("") do |stdin|
          lambda { |logger|
            Cheetah.run("/bin/true", :stdin => stdin, :logger => logger)
          }.should log(<<-EOT)
            INFO Executing command "/bin/true" with no arguments.
            INFO Status: 0
            INFO Standard output: (none)
            INFO Error output: (none)
          EOT
        end

        StringIO.open("blah") do |stdin|
          lambda { |logger|
            Cheetah.run("/bin/true", :stdin => stdin, :logger => logger)
          }.should log(<<-EOT)
            INFO Executing command "/bin/true" with no arguments.
            INFO Status: 0
            INFO Standard output: (none)
            INFO Error output: (none)
          EOT
        end
      end

      it "logs an unsuccessful execution of a command" do
        lambda { |logger|
          begin
            Cheetah.run("/bin/false", :logger => logger)
          rescue Cheetah::ExecutionFailed
            # Eat it.
          end
        }.should log(<<-EOT)
          INFO Executing command "/bin/false" with no arguments.
          INFO Standard input: (none)
          ERROR Status: 1
          INFO Standard output: (none)
          INFO Error output: (none)
        EOT
      end

      it "logs info messages on the level specified by the :logger_level_info option" do
        lambda { |logger|
          Cheetah.run("/bin/true", :logger => logger, :logger_level_info => Logger::DEBUG)
        }.should log(<<-EOT)
          DEBUG Executing command "/bin/true" with no arguments.
          DEBUG Standard input: (none)
          DEBUG Status: 0
          DEBUG Standard output: (none)
          DEBUG Error output: (none)
        EOT
      end

      it "logs error messages on the level specified by the :logger_level_error option" do
        lambda { |logger|
          begin
            Cheetah.run("/bin/false", :logger => logger, :logger_level_error => Logger::WARN)
          rescue Cheetah::ExecutionFailed
            # Eat it.
          end
        }.should log(<<-EOT)
          INFO Executing command "/bin/false" with no arguments.
          INFO Standard input: (none)
          WARN Status: 1
          INFO Standard output: (none)
          INFO Error output: (none)
        EOT
      end
    end

    describe "options handling" do
      # To cover the code properly, the following specs should test all the
      # options. However, that would introduce unwanted dependency on the list
      # of options, so let's just test that one option (:stdin) works properly.

      it "uses default options for unspecified options" do
        saved_default_options = Cheetah.default_options
        Cheetah.default_options = { :stdin => "input" }

        begin
          Cheetah.run("cat", :stdout => :capture).should == "input"
        ensure
          Cheetah.default_options = saved_default_options
        end
      end

      it "prefers passed options over the global ones" do
        saved_default_options = Cheetah.default_options
        Cheetah.default_options = { :stdin => "global_input" }

        begin
          Cheetah.run("cat", :stdin => "passed_input", :stdout => :capture).should == "passed_input"
        ensure
          Cheetah.default_options = saved_default_options
        end
      end
    end

    describe "error handling" do
      describe "basics" do
        it "raises an exception when the command is not found" do
          lambda {
            Cheetah.run("unknown", "foo", "bar", "baz")
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.command.should          == "unknown"
            e.args.should             == ["foo", "bar", "baz"]
            e.status.exitstatus.should == 127
          }
        end

        it "raises an exception when the command returns non-zero status" do
          lambda {
            Cheetah.run("/bin/false", "foo", "bar", "baz")
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.command.should          == "/bin/false"
            e.args.should             == ["foo", "bar", "baz"]
            e.status.exitstatus.should == 1
          }
        end
      end

      describe "error messages" do
        it "raises an exception with a correct message for a command without arguments" do
          lambda {
            Cheetah.run("/bin/false")
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.message.should ==
              "Execution of command \"/bin/false\" with no arguments failed with status 1."
          }
        end

        it "raises an exception with a correct message for a command with arguments" do
          lambda {
            Cheetah.run("/bin/false", "foo", "bar", "baz")
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.message.should ==
              "Execution of command \"/bin/false\" with arguments \"foo\", \"bar\", \"baz\" failed with status 1."
          }
        end
      end

      describe "output capturing" do
        before do
          @command = create_command(<<-EOT)
            echo -n 'output'
            echo -n 'error' 1>&2
            exit 1
          EOT
        end

        it "raises an exception with both stdout and stderr set" do
          lambda {
            Cheetah.run(@command)
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.stdout.should == "output"
            e.stderr.should == "error"
          }
        end

        it "handles commands that output nothing correctly" do
          lambda {
            Cheetah.run("/bin/false", :stdout => :capture, :stderr => :capture)
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.stdout.should == ""
            e.stderr.should == ""
          }
        end
      end
    end
  end
end
