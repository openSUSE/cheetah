Cheetah
=======

Cheetah is a simple library for executing external commands safely and conveniently.

Examples
--------

    # Run a command and capture its output
    files = Cheetah.run("ls", "-la", :capture => :stdout)

    # Run a command and handle errors
    begin
      Cheetah.run("rm", "/etc/passwd")
    rescue Cheetah::ExecutionFailed => e
      puts e.message
      puts "Standard output: #{e.stdout}"
      puts "Error ouptut:    #{e.stderr}"
    end

Features
--------
  * Easy passing of command input
  * Easy capturing of command output (standard, error, or both)
  * 100% secure (shell expansion is impossible by design)
  * Raises exceptions on errors (no more manual status code checks)
  * Optional logging for easy debugging

Non-features
------------

  * Handling of commands producing big outputs
  * Handling of interactive commands

Installation
------------

    $ gem install cheetah

Usage
-----

First, require the library:

    require "cheetah"

You can now use the `Cheetah.run` method to run commands, pass them an input and capture their output:

    # Run a command with arguments
    Cheetah.run("tar", "xzf", "foo.tar.gz")

    # Pass an input
    Cheetah.run("python", :stdin => source_code)

    # Capture standard output
    files = Cheetah.run("ls", "-la", :capture => :stdout)

    # Capture both standard and error output
    results, errors = Cheetah.run("grep", "-r", "User", ".", :capture => [:stdout, :stderr))

If the command can't be executed for some reason or returns a non-zero exit status, the method raises an exception with detailed information about the failure:

    # Run a command and handle errors
    begin
      Cheetah.run("rm", "/etc/passwd")
    rescue Cheetah::ExecutionFailed => e
      puts e.message
      puts "Standard output: #{e.stdout}"
      puts "Error ouptut:    #{e.stderr}"
    end

For debugging purposes, you can also use a logger. Cheetah will log the command, its status, input and both outputs to it at the `debug` level:

    # Log the execution
    Cheetah.run("ls -l", :logger => logger)

    # Or, if you're tired of passing the :logger option all the time...
    Cheetah.logger = my_logger
    Cheetah.run("./configure")
    Cheetah.run("make")
    Cheetah.run("make", "install")
    Cheetah.logger = nil

For more information, see the [API documentation](http://rubydoc.info/github/openSUSE/cheetah/frames).
