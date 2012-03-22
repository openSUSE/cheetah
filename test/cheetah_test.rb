require File.expand_path(File.dirname(__FILE__) + "/test_helper")

class CheetahTest < Test::Unit::TestCase
  context "run" do
    # Fundamental question: To mock or not to mock the actual system interface?
    #
    # I decided not to mock so we can be sure Cheetah#run really works. Also the
    # mocking would be quite complex (if possible at all) given the
    # forking/piping/selecting in the code.
    #
    # Of course, this decision makes this unit test an intgration test by strict
    # definitions.

    setup do
      @tmp_dir = "/tmp/cheetah_test_#{Process.pid}"
      FileUtils.mkdir(@tmp_dir)
    end

    teardown do
      FileUtils.rm_rf(@tmp_dir)
    end

    context "running commands" do
      should "run a command without arguments" do
        command = create_command("touch #@tmp_dir/touched")

        Cheetah.run command

        assert File.exists?("#@tmp_dir/touched")
      end

      should "run a command with arguments" do
        command = create_command("echo -n \"$@\" >> #@tmp_dir/args")

        Cheetah.run command, "foo", "bar", "baz"

        assert_equal "foo bar baz", File.read("#@tmp_dir/args")
      end

      should "run a command without arguments using one array param" do
        command = create_command("touch #@tmp_dir/touched")

        Cheetah.run [command]

        assert File.exists?("#@tmp_dir/touched")
      end

      should "run a command with arguments using one array param" do
        command = create_command("echo -n \"$@\" >> #@tmp_dir/args")

        Cheetah.run [command, "foo", "bar", "baz"]

        assert_equal "foo bar baz", File.read("#@tmp_dir/args")
      end

      should "not mind weird characters in the command" do
        command = create_command("touch #@tmp_dir/touched", :name => "we ! ir $d")

        Cheetah.run command

        assert File.exists?("#@tmp_dir/touched")
      end

      should "not mind weird characters in the arguments" do
        command = create_command("echo -n \"$@\" >> #@tmp_dir/args")

        Cheetah.run command, "we ! ir $d", "we ! ir $d", "we ! ir $d"

        assert_equal "we ! ir $d we ! ir $d we ! ir $d", File.read("#@tmp_dir/args")
      end

      should "not pass the command to the shell" do
        command = create_command("touch #@tmp_dir/touched", :name => "foo < bar > baz | qux")

        Cheetah.run command

        assert File.exists?("#@tmp_dir/touched")
      end
    end

    context "error handling" do
      context "basics" do
        should "raise an exception when the command is not found" do
          e = assert_raise Cheetah::ExecutionFailed do
            Cheetah.run "unknown", "foo", "bar", "baz"
          end

          assert_equal "unknown",             e.command
          assert_equal ["foo", "bar", "baz"], e.args
          assert_equal 127,                   e.status.exitstatus
        end

        should "raise an exception when the command returns non-zero status" do
          e = assert_raise Cheetah::ExecutionFailed do
            Cheetah.run "false", "foo", "bar", "baz"
          end

          assert_equal "false",               e.command
          assert_equal ["foo", "bar", "baz"], e.args
          assert_equal 1,                     e.status.exitstatus
        end
      end

      context "error message" do
        should "raise an exception with a correct message for a command without arguments" do
          e = assert_raise Cheetah::ExecutionFailed do
            Cheetah.run "false"
          end

          assert_equal(
            "Execution of command \"false\" with no arguments failed with status 1.",
            e.message
          )
        end

        should "raise an exception with a correct message for a command with arguments" do
          e = assert_raise Cheetah::ExecutionFailed do
            Cheetah.run "false", "foo", "bar", "baz"
          end

          assert_equal(
            "Execution of command \"false\" with arguments \"foo\", \"bar\", \"baz\" failed with status 1.",
            e.message
          )
        end
      end

      context "capturing" do
        should "raise an exception with both stdout and stderr not set with no :capture option" do
          e = assert_raise Cheetah::ExecutionFailed do
            Cheetah.run "false"
          end

          assert_equal nil, e.stdout
          assert_equal nil, e.stderr
        end

        should "raise an exception with both stdout and stderr not set with :capture => nil" do
          e = assert_raise Cheetah::ExecutionFailed do
            Cheetah.run "false", :capture => nil
          end

          assert_equal nil, e.stdout
          assert_equal nil, e.stderr
        end

        should "raise an exception with only stdout set with :capture => :stdout" do
          e = assert_raise Cheetah::ExecutionFailed do
            command = create_command("echo -n ''; exit 1")
            Cheetah.run command, :capture => :stdout
          end

          assert_equal "",  e.stdout
          assert_equal nil, e.stderr

          e = assert_raise Cheetah::ExecutionFailed do
            command = create_command("echo -n output; exit 1")
            Cheetah.run command, :capture => :stdout
          end

          assert_equal "output", e.stdout
          assert_equal nil,      e.stderr
        end

        should "raise an exception with only stderr set with :capture => :stderr" do
          e = assert_raise Cheetah::ExecutionFailed do
            command = create_command("echo -n '' 1>&2; exit 1")
            Cheetah.run command, :capture => :stderr
          end

          assert_equal nil, e.stdout
          assert_equal "",  e.stderr

          e = assert_raise Cheetah::ExecutionFailed do
            command = create_command("echo -n error 1>&2; exit 1")
            Cheetah.run command, :capture => :stderr
          end

          assert_equal nil,     e.stdout
          assert_equal "error", e.stderr
        end

        should "raise an exception with both stdout and stderr set with :capture => [:stdout, :stderr]" do
          e = assert_raise Cheetah::ExecutionFailed do
            command = create_command(<<-EOT)
              echo -n ''
              echo -n '' 1>&2
              exit 1
            EOT
            Cheetah.run command, :capture => [:stdout, :stderr]
          end

          assert_equal "", e.stdout
          assert_equal "", e.stderr

          e = assert_raise Cheetah::ExecutionFailed do
            command = create_command(<<-EOT)
              echo -n output
              echo -n error 1>&2
              exit 1
            EOT
            Cheetah.run command, :capture => [:stdout, :stderr]
          end

          assert_equal "output", e.stdout
          assert_equal "error",  e.stderr
        end
      end
    end

    context "capturing" do
      should "not use standard output of the parent process with no :capture option" do
        # We just open a random file to get a file descriptor into which we can
        # save our stdout.
        saved_stdout = File.open("/dev/null", "w")
        saved_stdout.reopen(STDOUT)

        reader, writer = IO.pipe

        STDOUT.reopen(writer)
        begin
          Cheetah.run("echo", "-n", "output")
        ensure
          STDOUT.reopen(saved_stdout)
          writer.close
        end

        assert_equal "", reader.read
        reader.close
      end

      should "not use error output of the parent process with no :capture option" do
        # We just open a random file to get a file descriptor into which we can
        # save our stderr.
        saved_stderr = File.open("/dev/null", "w")
        saved_stderr.reopen(STDERR)

        reader, writer = IO.pipe

        STDERR.reopen(writer)
        begin
          command = create_command("echo -n error 1>&2")
          Cheetah.run command
        ensure
          STDERR.reopen(saved_stderr)
          writer.close
        end

        assert_equal "", reader.read
        reader.close
      end

      should "return nil with no :capture option" do
        assert_equal nil, Cheetah.run("true")
      end

      should "return nil with :capture => nil" do
        assert_equal nil, Cheetah.run("true", :capture => nil)
      end

      should "return the standard output with :capture => :stdout" do
        assert_equal "",       Cheetah.run("echo", "-n", "",       :capture => :stdout)
        assert_equal "output", Cheetah.run("echo", "-n", "output", :capture => :stdout)
      end

      should "return the error output with :capture => :stderr" do
        command = create_command("echo -n '' 1>&2")
        assert_equal "", Cheetah.run(command, :capture => :stderr)

        command = create_command("echo -n error 1>&2")
        assert_equal "error", Cheetah.run(command, :capture => :stderr)
      end

      should "return both outputs with :capture => [:stdout, :stderr]" do
        command = create_command(<<-EOT)
          echo -n ''
          echo -n '' 1>&2
        EOT
        assert_equal ["", ""], Cheetah.run(command, :capture => [:stdout, :stderr])

        command = create_command(<<-EOT)
          echo -n output
          echo -n error 1>&2
        EOT
        assert_equal ["output", "error"], Cheetah.run(command, :capture => [:stdout, :stderr])
      end
    end

    context "logging" do
      should "log a successful execution of a command without arguments" do
        logger = mock
        logger.expects(:debug).with("Executing command \"true\" with no arguments.")
        logger.expects(:debug).with("Standard input: (none)")
        logger.expects(:debug).with("Status: 0")
        logger.expects(:debug).with("Standard output: (none)")
        logger.expects(:debug).with("Error output: (none)")

        Cheetah.run "true", :logger => logger
      end

      should "log a successful execution of a command with arguments" do
        logger = mock
        logger.expects(:debug).with("Executing command \"true\" with arguments \"foo\", \"bar\", \"baz\".")
        logger.expects(:debug).with("Standard input: (none)")
        logger.expects(:debug).with("Status: 0")
        logger.expects(:debug).with("Standard output: (none)")
        logger.expects(:debug).with("Error output: (none)")

        Cheetah.run "true", "foo", "bar", "baz", :logger => logger
      end

      should "log a successful execution of a command doing I/O" do
        logger = mock
        logger.expects(:debug).with("Executing command \"#@tmp_dir/command\" with no arguments.")
        logger.expects(:debug).with("Standard input: (none)")
        logger.expects(:debug).with("Status: 0")
        logger.expects(:debug).with("Standard output: (none)")
        logger.expects(:debug).with("Error output: (none)")

        command = create_command(<<-EOT)
          echo -n ''
          echo -n '' 1>&2
        EOT
        Cheetah.run command, :stdin => "", :logger => logger

        logger = mock
        logger.expects(:debug).with("Executing command \"#@tmp_dir/command\" with no arguments.")
        logger.expects(:debug).with("Standard input: blah")
        logger.expects(:debug).with("Status: 0")
        logger.expects(:debug).with("Standard output: output")
        logger.expects(:debug).with("Error output: error")

        command = create_command(<<-EOT)
          echo -n output
          echo -n error 1>&2
        EOT
        Cheetah.run command, :stdin => "blah", :logger => logger
      end

      should "log an unsuccessful execution of a command" do
        logger = mock
        logger.expects(:debug).with("Executing command \"false\" with no arguments.")
        logger.expects(:debug).with("Standard input: (none)")
        logger.expects(:debug).with("Status: 1")
        logger.expects(:debug).with("Standard output: (none)")
        logger.expects(:debug).with("Error output: (none)")

        begin
          Cheetah.run "false", :logger => logger
        rescue Cheetah::ExecutionFailed
          # Eat it.
        end
      end
    end

    context "input" do
      should "not use standard input of the parent process with no :stdin option" do
        # We just open a random file to get a file descriptor into which we can
        # save our stdin.
        saved_stdin = File.open("/dev/null", "r")
        saved_stdin.reopen(STDIN)

        reader, writer = IO.pipe

        writer.write "blah"
        writer.close

        STDIN.reopen(reader)
        begin
          assert_equal "", Cheetah.run("cat", :capture => :stdout)
        ensure
          STDIN.reopen(saved_stdin)
          reader.close
        end
      end

      should "pass :stdin option value to standard input" do
        assert_equal "",     Cheetah.run("cat", :stdin => "",     :capture => :stdout)
        assert_equal "blah", Cheetah.run("cat", :stdin => "blah", :capture => :stdout)
      end
    end
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
end
