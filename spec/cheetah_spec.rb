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

      describe "capturing" do
        before do
          @command = create_command(<<-EOT)
            echo -n 'output'
            echo -n 'error' 1>&2
            exit 1
          EOT
        end

        it "raises an exception with both stdout and stderr not set with no :capture option" do
          lambda {
            Cheetah.run(@command)
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.stdout.should == "output"
            e.stderr.should == "error"
          }
        end

        it "raises an exception with both stdout and stderr not set with :capture => nil" do
          lambda {
            Cheetah.run(@command, :capture => nil)
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.stdout.should == "output"
            e.stderr.should == "error"
          }
        end

        it "raises an exception with only stdout set with :capture => :stdout" do
          lambda {
            Cheetah.run(@command, :capture => :stdout)
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.stdout.should == "output"
            e.stderr.should == "error"
          }
        end

        it "raises an exception with only stderr set with :capture => :stderr" do
          lambda {
            Cheetah.run(@command, :capture => :stderr)
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.stdout.should == "output"
            e.stderr.should == "error"
          }
        end

        it "raises an exception with both stdout and stderr set with :capture => [:stdout, :stderr]" do
          lambda {
            Cheetah.run(@command, :capture => [:stdout, :stderr])
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.stdout.should == "output"
            e.stderr.should == "error"
          }
        end

        it "handles commands that output nothing correctly" do
          lambda {
            Cheetah.run("/bin/false", :capture => [:stdout, :stderr])
          }.should raise_exception(Cheetah::ExecutionFailed) { |e|
            e.stdout.should == ""
            e.stderr.should == ""
          }
        end
      end
    end

    describe "capturing" do
      before do
        @command = create_command(<<-EOT)
          echo -n 'output'
          echo -n 'error' 1>&2
        EOT
      end

      it "does not use standard output of the parent process with no :capture option" do
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

      it "does not use error output of the parent process with no :capture option" do
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

      it "returns nil with no :capture option" do
        Cheetah.run(@command).should be_nil
      end

      it "returns nil with :capture => nil" do
        Cheetah.run(@command, :capture => nil).should be_nil
      end

      it "returns the standard output with :capture => :stdout" do
        Cheetah.run("echo", "-n", "output", :capture => :stdout).should == "output"
      end

      it "returns the error output with :capture => :stderr" do
        Cheetah.run(@command, :capture => :stderr).should == "error"
      end

      it "returns both outputs with :capture => [:stdout, :stderr]" do
        Cheetah.run(@command, :capture => [:stdout, :stderr]).should == ["output", "error"]
      end

      it "handles commands that output nothing correctly" do
        Cheetah.run("/bin/true", :capture => [:stdout, :stderr]).should == ["", ""]
      end
    end

    describe "logging" do
      it "logs a successful execution of a command without arguments" do
        logger = mock
        logger.should_receive(:debug).with("Executing command \"/bin/true\" with no arguments.")
        logger.should_receive(:debug).with("Standard input: (none)")
        logger.should_receive(:debug).with("Status: 0")
        logger.should_receive(:debug).with("Standard output: (none)")
        logger.should_receive(:debug).with("Error output: (none)")

        Cheetah.run("/bin/true", :logger => logger)
      end

      it "logs a successful execution of a command with arguments" do
        logger = mock
        logger.should_receive(:debug).with("Executing command \"/bin/true\" with arguments \"foo\", \"bar\", \"baz\".")
        logger.should_receive(:debug).with("Standard input: (none)")
        logger.should_receive(:debug).with("Status: 0")
        logger.should_receive(:debug).with("Standard output: (none)")
        logger.should_receive(:debug).with("Error output: (none)")

        Cheetah.run("/bin/true", "foo", "bar", "baz", :logger => logger)
      end

      it "logs a successful execution of a command doing I/O" do
        logger = mock
        logger.should_receive(:debug).with("Executing command \"#@tmp_dir/command\" with no arguments.")
        logger.should_receive(:debug).with("Standard input: (none)")
        logger.should_receive(:debug).with("Status: 0")
        logger.should_receive(:debug).with("Standard output: (none)")
        logger.should_receive(:debug).with("Error output: (none)")

        command = create_command(<<-EOT)
          echo -n ''
          echo -n '' 1>&2
        EOT
        Cheetah.run(command, :stdin => "", :logger => logger)

        logger = mock
        logger.should_receive(:debug).with("Executing command \"#@tmp_dir/command\" with no arguments.")
        logger.should_receive(:debug).with("Standard input: blah")
        logger.should_receive(:debug).with("Status: 0")
        logger.should_receive(:debug).with("Standard output: output")
        logger.should_receive(:debug).with("Error output: error")

        command = create_command(<<-EOT)
          echo -n 'output'
          echo -n 'error' 1>&2
        EOT
        Cheetah.run(command, :stdin => "blah", :logger => logger)
      end

      it "logs an unsuccessful execution of a command" do
        logger = mock
        logger.should_receive(:debug).with("Executing command \"/bin/false\" with no arguments.")
        logger.should_receive(:debug).with("Standard input: (none)")
        logger.should_receive(:debug).with("Status: 1")
        logger.should_receive(:debug).with("Standard output: (none)")
        logger.should_receive(:debug).with("Error output: (none)")

        begin
          Cheetah.run("/bin/false", :logger => logger)
        rescue Cheetah::ExecutionFailed
          # Eat it.
        end
      end
    end

    describe "input" do
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
          Cheetah.run("cat", :capture => :stdout).should == ""
        ensure
          STDIN.reopen(saved_stdin)
          reader.close
        end
      end

      it "passes :stdin option value to standard input" do
        Cheetah.run("cat", :stdin => "",      :capture => :stdout).should == ""
        Cheetah.run("cat", :stdin => "input", :capture => :stdout).should == "input"
      end
    end
  end
end
