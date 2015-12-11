require "spec_helper"
require "fileutils"

describe Cheetah::DefaultRecorder do
  let(:logger) { double }
  subject(:recorder) { Cheetah::DefaultRecorder.new(logger) }

  describe "#record_commands" do
    it "logs execution of commands" do
      expect(logger).to receive(:info).with(
        "Executing \"one foo bar baz | two foo bar baz | three foo bar baz\"."
      )

      recorder.record_commands([
        ["one",   "foo", "bar", "baz"],
        ["two",   "foo", "bar", "baz"],
        ["three", "foo", "bar", "baz"]
      ])
    end

    it "escapes commands and their arguments" do
      expect(logger).to receive(:info).with(
        "Executing \"we\\ \\!\\ ir\\ \\$d we\\ \\!\\ ir\\ \\$d we\\ \\!\\ ir\\ \\$d \\<\\|\\>\\$\"."
      )

      recorder.record_commands([["we ! ir $d", "we ! ir $d", "we ! ir $d", "<|>$"]])
    end
  end

  describe "#record_stdin" do
    it "does not log anything for unterminated one-line input" do
      recorder.record_stdin("one")
    end

    it "logs all terminated lines for unterminated multi-line input" do
      expect(logger).to receive(:info).with("Standard input: one")
      expect(logger).to receive(:info).with("Standard input: two")

      recorder.record_stdin("one\ntwo\nthree")
    end

    it "remembers unlogged part of unterminated one-line input and combines it with new input" do
      expect(logger).to receive(:info).with("Standard input: one")
      expect(logger).to receive(:info).with("Standard input: two")
      expect(logger).to receive(:info).with("Standard input: three")

      recorder.record_stdin("one")
      recorder.record_stdin("\ntwo\nthree\n")
    end

    it "remembers unlogged part of unterminated multi-line input and combines it with new input" do
      expect(logger).to receive(:info).with("Standard input: one")
      expect(logger).to receive(:info).with("Standard input: two")
      expect(logger).to receive(:info).with("Standard input: three")

      recorder.record_stdin("one\ntwo\nthree")
      recorder.record_stdin("\n")
    end
  end

  describe "#record_stdout" do
    it "does not log anything for unterminated one-line output" do
      recorder.record_stdout("one")
    end

    it "logs all terminated lines for unterminated multi-line output" do
      expect(logger).to receive(:info).with("Standard output: one")
      expect(logger).to receive(:info).with("Standard output: two")

      recorder.record_stdout("one\ntwo\nthree")
    end

    it "remembers unlogged part of unterminated one-line output and combines it with new output" do
      expect(logger).to receive(:info).with("Standard output: one")
      expect(logger).to receive(:info).with("Standard output: two")
      expect(logger).to receive(:info).with("Standard output: three")

      recorder.record_stdout("one")
      recorder.record_stdout("\ntwo\nthree\n")
    end

    it "remembers unlogged part of unterminated multi-line output and combines it with new output" do
      expect(logger).to receive(:info).with("Standard output: one")
      expect(logger).to receive(:info).with("Standard output: two")
      expect(logger).to receive(:info).with("Standard output: three")

      recorder.record_stdout("one\ntwo\nthree")
      recorder.record_stdout("\n")
    end
  end

  describe "#record_stderr" do
    it "does not log anything for unterminated one-line output" do
      recorder.record_stderr("one")
    end

    it "logs all terminated lines for unterminated multi-line output" do
      expect(logger).to receive(:error).with("Error output: one")
      expect(logger).to receive(:error).with("Error output: two")

      recorder.record_stderr("one\ntwo\nthree")
    end

    it "remembers unlogged part of unterminated one-line output and combines it with new output" do
      expect(logger).to receive(:error).with("Error output: one")
      expect(logger).to receive(:error).with("Error output: two")
      expect(logger).to receive(:error).with("Error output: three")

      recorder.record_stderr("one")
      recorder.record_stderr("\ntwo\nthree\n")
    end

    it "remembers unlogged part of unterminated multi-line output and combines it with new output" do
      expect(logger).to receive(:error).with("Error output: one")
      expect(logger).to receive(:error).with("Error output: two")
      expect(logger).to receive(:error).with("Error output: three")

      recorder.record_stderr("one\ntwo\nthree")
      recorder.record_stderr("\n")
    end
  end

  describe "#record_status" do
    # I hate to mock Process::Status but it seems one can't create a new
    # instance of it without actually running some process, which would be
    # even worse.
    let(:status_success) { double(success?: true,  exitstatus: 0) }
    let(:status_failure) { double(success?: false, exitstatus: 1) }

    it "logs a success" do
      expect(logger).to receive(:info).with("Status: 0")

      recorder.record_status(status_success)
    end

    it "logs a failure" do
      expect(logger).to receive(:error).with("Status: 1")

      recorder.record_status(status_failure)
    end

    it "logs unlogged part of the standard input" do
      expect(logger).to receive(:info).with("Standard input: input")
      expect(logger).to receive(:info).with("Status: 0")

      recorder.record_stdin("input")
      recorder.record_status(status_success)
    end

    it "logs unlogged part of the standard output" do
      expect(logger).to receive(:info).with("Standard output: output")
      expect(logger).to receive(:info).with("Status: 0")

      recorder.record_stdout("output")
      recorder.record_status(status_success)
    end

    it "logs unlogged part of the error output" do
      expect(logger).to receive(:error).with("Error output: error")
      expect(logger).to receive(:info).with("Status: 0")

      recorder.record_stderr("error")
      recorder.record_status(status_success)
    end
  end
end

describe Cheetah do
  describe "#run" do
    # Fundamental question: To mock or not to mock the actual system interface?
    #
    # I decided not to mock so we can be sure Cheetah#run really works. Also the
    # mocking would be quite complex (if possible at all) given the
    # forking/piping/selecting in the code.
    #
    # Of course, this decision makes this unit test an intgration test by strict
    # definitions.
    let(:tmp_dir) { "/tmp/cheetah_test_#{Process.pid}" }

    around do |example|
      FileUtils.mkdir(tmp_dir)
      example.run
      FileUtils.rm_rf(tmp_dir)
    end

    def create_command(source, name: "command")
      command = File.join(tmp_dir, name)

      File.open(command, "w") do |f|
        f.puts "#!/bin/sh"
        f.puts source
      end
      FileUtils.chmod(0777, command)

      command
    end

    describe "running commands" do
      it "runs a command without arguments" do
        command = create_command("touch #{tmp_dir}/touched")
        expect { Cheetah.run(command) }.to touch("#{tmp_dir}/touched")
      end

      it "runs a command with arguments" do
        command = create_command("echo -n \"$@\" >> #{tmp_dir}/args")
        expect do
          Cheetah.run(command, "foo", "bar", "baz")
        end.to write("foo bar baz").into("#{tmp_dir}/args")
      end

      it "runs a command without arguments using one array param" do
        command = create_command("touch #{tmp_dir}/touched")
        expect { Cheetah.run([command]) }.to touch("#{tmp_dir}/touched")
      end

      it "runs a command with arguments using one array param" do
        command = create_command("echo -n \"$@\" >> #{tmp_dir}/args")
        expect do
          Cheetah.run([command, "foo", "bar", "baz"])
        end.to write("foo bar baz").into("#{tmp_dir}/args")
      end

      it "does not mind weird characters in the command" do
        command = create_command("touch #{tmp_dir}/touched", name: "we ! ir $d")
        expect { Cheetah.run([command]) }.to touch("#{tmp_dir}/touched")
      end

      it "does not mind weird characters in the arguments" do
        command = create_command("echo -n \"$@\" >> #{tmp_dir}/args")
        expect do
          Cheetah.run(command, "we ! ir $d", "we ! ir $d", "we ! ir $d")
        end.to write("we ! ir $d we ! ir $d we ! ir $d").into("#{tmp_dir}/args")
      end

      it "does not pass the command to the shell" do
        command = create_command("touch #{tmp_dir}/touched", name: "foo < bar > baz | qux")
        expect { Cheetah.run(command) }.to touch("#{tmp_dir}/touched")
      end
    end

    describe "running piped commands" do
      it "runs all commands without arguments" do
        command1 = create_command("touch #{tmp_dir}/touched1", name: "command1")
        command2 = create_command("touch #{tmp_dir}/touched2", name: "command2")
        command3 = create_command("touch #{tmp_dir}/touched3", name: "command3")

        expect do
          Cheetah.run([command1], [command2], [command3])
        end.to touch(
          "#{tmp_dir}/touched1",
          "#{tmp_dir}/touched2",
          "#{tmp_dir}/touched3"
        )
      end

      it "runs all commands with arguments" do
        command = create_command(<<-EOT)
          cat
          echo "$@"
        EOT

        expect(Cheetah.run(
                 [command, "foo1", "bar1", "baz1"],
                 [command, "foo2", "bar2", "baz2"],
                 [command, "foo3", "bar3", "baz3"],
                 stdout: :capture
        )).to eq "foo1 bar1 baz1\nfoo2 bar2 baz2\nfoo3 bar3 baz3\n"
      end

      it "passes standard output of one command to the next one" do
        command1 = create_command(<<-EOT, name: "command1")
          message=message
          echo $message >> #{tmp_dir}/messages
          echo $message
        EOT

        command2 = create_command(<<-EOT, name: "command2")
          read message
          echo $message >> #{tmp_dir}/messages
          echo $message
        EOT

        command3 = create_command(<<-EOT, name: "command3")
          read message
          echo $message >> #{tmp_dir}/messages
          echo $message
        EOT

        expect do
          Cheetah.run([command1], [command2], [command3])
        end.to write([
          "message\n",
          "message\n",
          "message\n"
        ].join("")).into("#{tmp_dir}/messages")
      end

      it "combines error output of all commands" do
        command = create_command("echo 'error' 1>&2")

        expect(Cheetah.run([command], [command], [command], stderr: :capture)).to eq "error\nerror\nerror\n"
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
          expect(Cheetah.run("cat", stdout: :capture)).to eq ""
        ensure
          STDIN.reopen(saved_stdin)
          reader.close
        end
      end

      it "reads standard input from :stdin when set to a string" do
        expect(Cheetah.run("cat", stdin: "",      stdout: :capture)).to eq ""
        expect(Cheetah.run("cat", stdin: "input", stdout: :capture)).to eq "input"
      end

      it "reads standard input from :stdin when set to an IO" do
        StringIO.open("") do |stdin|
          expect(Cheetah.run("cat", stdin: stdin, stdout: :capture)).to eq ""
        end
        StringIO.open("input") do |stdin|
          expect(Cheetah.run("cat", stdin: stdin, stdout: :capture)).to eq "input"
        end
      end
    end

    describe "output capturing" do
      let(:command) do
        create_command(<<-EOT)
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
          Cheetah.run(command)
        ensure
          STDOUT.reopen(saved_stdout)
          writer.close
        end

        expect(reader.read).to eq ""
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
          Cheetah.run(command)
        ensure
          STDERR.reopen(saved_stderr)
          writer.close
        end

        expect(reader.read).to eq ""
        reader.close
      end

      it "returns nil with no :stdout and :stderr options" do
        expect(Cheetah.run(command)).to be_nil
      end

      it "returns nil with :stdout => nil" do
        expect(Cheetah.run(command, stdout: nil)).to be_nil
      end

      it "returns nil with :stderr => nil" do
        expect(Cheetah.run(command, stderr: nil)).to be_nil
      end

      it "returns the standard output with :stdout => :capture" do
        expect(Cheetah.run("echo", "-n", "output", stdout: :capture)).to eq "output"
      end

      it "returns the error output with :stderr => :capture" do
        expect(Cheetah.run(command, stderr: :capture)).to eq "error"
      end

      it "returns both outputs with :stdout => :capture and :stderr => :capture" do
        expect(Cheetah.run(command, stdout: :capture, stderr: :capture)).to eq ["output", "error"]
      end

      it "handles commands that output nothing correctly with :stdout => :capture and :stderr => :capture" do
        expect(Cheetah.run("/bin/true", stdout: :capture, stderr: :capture)).to eq ["", ""]
      end

      it "writes standard output to :stdout when set to an IO" do
        StringIO.open("", "w") do |stdout|
          Cheetah.run(command, stdout: stdout)
          expect(stdout.string).to eq "output"
        end
      end

      it "writes error output to :stderr when set to an IO" do
        StringIO.open("", "w") do |stderr|
          Cheetah.run(command, stderr: stderr)
          expect(stderr.string).to eq "error"
        end
      end
    end

    describe "logging" do
      it "uses the default recorder with no :recorder option" do
        logger = double
        expect(logger).to receive(:info).with("Executing \"/bin/true\".")
        expect(logger).to receive(:info).with("Status: 0")

        Cheetah.run("/bin/true", logger: logger)
      end

      it "uses the passed recorder with a :recorder option" do
        recorder = double
        expect(recorder).to receive(:record_commands).with([["/bin/true"]])
        expect(recorder).to receive(:record_status)

        Cheetah.run("/bin/true", recorder: recorder)
      end

      it "records standard input" do
        command = create_command(<<-EOT)
          read line || true
        EOT

        recorder = double
        expect(recorder).to receive(:record_commands).with([[command]])
        expect(recorder).to_not receive(:record_stdin)
        expect(recorder).to receive(:record_status)

        Cheetah.run(command, recorder: recorder, stdin: "")

        recorder = double
        expect(recorder).to receive(:record_commands).with([[command]])
        expect(recorder).to receive(:record_stdin).with("input")
        expect(recorder).to receive(:record_status)

        Cheetah.run(command, recorder: recorder, stdin: "input")
      end

      it "records standard output" do
        recorder = double
        expect(recorder).to receive(:record_commands).with([["/bin/true"]])
        expect(recorder).to_not receive(:record_stdout)
        expect(recorder).to receive(:record_status)

        Cheetah.run("/bin/true", recorder: recorder)

        recorder = double
        expect(recorder).to receive(:record_commands).with([["echo", "-n", "output"]])
        expect(recorder).to receive(:record_stdout).with("output")
        expect(recorder).to receive(:record_status)

        Cheetah.run("echo", "-n", "output", recorder: recorder)
      end

      it "records error output" do
        recorder = double
        expect(recorder).to receive(:record_commands).with([["/bin/true"]])
        expect(recorder).to_not receive(:record_stderr)
        expect(recorder).to receive(:record_status)

        Cheetah.run("/bin/true", recorder: recorder)

        command = create_command(<<-EOT)
          echo -n 'error' 1>&2
        EOT

        recorder = double
        expect(recorder).to receive(:record_commands).with([[command]])
        expect(recorder).to receive(:record_stderr).with("error")
        expect(recorder).to receive(:record_status)

        Cheetah.run(command, recorder: recorder)
      end
    end

    describe "options handling" do
      # To cover the code properly, the following specs should test all the
      # options. However, that would introduce unwanted dependency on the list
      # of options, so let's just test that one option (:stdin) works properly.

      it "uses default options for unspecified options" do
        saved_default_options = Cheetah.default_options
        Cheetah.default_options = { stdin: "input" }

        begin
          expect(Cheetah.run("cat", stdout: :capture)).to eq "input"
        ensure
          Cheetah.default_options = saved_default_options
        end
      end

      it "prefers passed options over the global ones" do
        saved_default_options = Cheetah.default_options
        Cheetah.default_options = { stdin: "global_input" }

        begin
          expect(Cheetah.run("cat", stdin: "passed_input", stdout: :capture)).to eq "passed_input"
        ensure
          Cheetah.default_options = saved_default_options
        end
      end
    end

    describe "error handling" do
      describe "basics" do
        it "raises an exception when the command is not found" do
          expect do
            Cheetah.run("unknown", "foo", "bar", "baz")
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.commands).to eq [["unknown", "foo", "bar", "baz"]]
            expect(e.status.exitstatus).to eq 127
          }
        end

        it "raises an exception when the command returns non-zero status" do
          expect do
            Cheetah.run("/bin/false", "foo", "bar", "baz")
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.commands).to eq [["/bin/false", "foo", "bar", "baz"]]
            expect(e.status.exitstatus).to eq 1
          }
        end
      end

      describe "piped commands" do
        it "raises an exception when the last piped command fails" do
          expect do
            Cheetah.run(["/bin/true"], ["/bin/true"], ["/bin/false"])
          end.to raise_error(Cheetah::ExecutionFailed)
        end

        it "does not raise an exception when other than last piped command fails" do
          expect do
            Cheetah.run(["/bin/true"], ["/bin/false"], ["/bin/true"])
          end.to_not raise_error

          expect do
            Cheetah.run(["/bin/false"], ["/bin/true"], ["/bin/true"])
          end.to_not raise_error
        end
      end

      describe "error messages" do
        it "raises an exception with a correct message for a command without arguments" do
          expect do
            Cheetah.run("/bin/false")
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.message).to eq(
              "Execution of \"/bin/false\" failed with status 1 (no error output)."
            )
          }
        end

        it "raises an exception with a correct message for a command with arguments" do
          expect do
            Cheetah.run("/bin/false", "foo", "bar", "baz")
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.message).to eq(
              "Execution of \"/bin/false foo bar baz\" failed with status 1 (no error output)."
            )
          }
        end

        it "raises an exception with a correct message for piped commands" do
          expect do
            Cheetah.run(["/bin/true"], ["/bin/true"], ["/bin/false"])
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.message).to eq(
              "Execution of \"/bin/true | /bin/true | /bin/false\" failed with status 1 (no error output)."
            )
          }
        end

        it "raises an exception with a correct message for commands writing no error output" do
          expect do
            Cheetah.run("/bin/false")
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.message).to eq(
              "Execution of \"/bin/false\" failed with status 1 (no error output)."
            )
          }
        end

        it "raises an exception with a correct message for commands writing one line of error output" do
          command = create_command(<<-EOT)
            echo 'one' 1>&2
            exit 1
          EOT

          expect do
            Cheetah.run(command)
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.message).to eq(
              "Execution of \"#{command}\" failed with status 1: one."
            )
          }
        end

        it "raises an exception with a correct message for commands writing more lines of error output" do
          command = create_command(<<-EOT)
            echo 'one'   1>&2
            echo 'two'   1>&2
            echo 'three' 1>&2
            exit 1
          EOT

          expect do
            Cheetah.run(command)
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.message).to eq(
              "Execution of \"#{command}\" failed with status 1: one (...)."
            )
          }
        end

        it "raises an exception with a correct message for commands writing an error output with :stderr set to an IO" do
          command = create_command(<<-EOT)
            echo -n 'error' 1>&2
            exit 1
          EOT

          expect do
            StringIO.open("", "w") do |stderr|
              Cheetah.run(command, stderr: stderr)
            end
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.message).to eq(
              "Execution of \"#{command}\" failed with status 1 (error output streamed away)."
            )
          }
        end
      end

      describe "output capturing" do
        let(:command) do
          create_command(<<-EOT)
            echo -n 'output'
            echo -n 'error' 1>&2
            exit 1
          EOT
        end

        it "raises an exception with both stdout and stderr set" do
          expect do
            Cheetah.run(command)
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.stdout).to eq "output"
            expect(e.stderr).to eq "error"
          }
        end

        it "raises an exception with stdout set to nil with :stdout set to an IO" do
          expect do
            StringIO.open("", "w") do |stdout|
              Cheetah.run(command, stdout: stdout)
            end
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.stdout).to be_nil
          }
        end

        it "raises an exception with stderr set to nil with :stderr set to an IO" do
          expect do
            StringIO.open("", "w") do |stderr|
              Cheetah.run(command, stderr: stderr)
            end
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.stderr).to be_nil
          }
        end

        it "handles commands that output nothing correctly" do
          expect do
            Cheetah.run("/bin/false")
          end.to raise_error(Cheetah::ExecutionFailed) { |e|
            expect(e.stdout).to eq ""
            expect(e.stderr).to eq ""
          }
        end
      end
    end
  end
end
