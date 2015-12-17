Cheetah
=======
[![Travis Build](https://travis-ci.org/openSUSE/cheetah.svg?branch=master)](https://travis-ci.org/openSUSE/cheetah)
[![Code Climate](https://codeclimate.com/github/openSUSE/cheetah/badges/gpa.svg)](https://codeclimate.com/github/openSUSE/cheetah)
[![Coverage Status](https://img.shields.io/coveralls/openSUSE/cheetah.svg)](https://coveralls.io/r/openSUSE/cheetah?branch=master)


Your swiss army knife for executing external commands in Ruby safely and
conveniently.

Examples
--------

```ruby
# Run a command and capture its output
files = Cheetah.run("ls", "-la", stdout: :capture)

# Run a command and capture its output into a stream
File.open("files.txt", "w") do |stdout|
  Cheetah.run("ls", "-la", stdout: stdout)
end

# Run a command and handle errors
begin
  Cheetah.run("rm", "/etc/passwd")
rescue Cheetah::ExecutionFailed => e
  puts e.message
  puts "Standard output: #{e.stdout}"
  puts "Error output:    #{e.stderr}"
end
```

Features
--------

  * Easy passing of command input
  * Easy capturing of command output (standard, error, or both)
  * Piping commands together
  * 100% secure (shell expansion is impossible by design)
  * Raises exceptions on errors (no more manual status code checks)
    but allows to specify which non-zero codes are still a success run
  * Thread-safety
  * Allows overriding environment variables
  * Optional logging for easy debugging

Non-features
------------

  * Handling of interactive commands

Installation
------------

    $ gem install cheetah

Usage
-----

First, require the library:

```ruby
require "cheetah"
```

You can now use the `Cheetah.run` method to run commands.

### Running Commands

To run a command, just specify it together with its arguments:

```ruby
Cheetah.run("tar", "xzf", "foo.tar.gz")

Cheetah converts each argument to a string using `#to_s`.

```
### Passing Input

Using the `:stdin` option you can pass a string to command's standard input:

```ruby
Cheetah.run("python", stdin: source_code)
```

If the input is big you may want to avoid passing it in one huge string. In that
case, pass an `IO` as a value of the `:stdin` option. The command will read its
input from it gradually.

```ruby
File.open("huge_program.py") do |stdin|
  Cheetah.run("python", stdin: stdin)
end
```

### Capturing Output

To capture command's standard output, set the `:stdout` option to `:capture`.
You will receive the output as a return value of the call:

```ruby
files = Cheetah.run("ls", "-la", stdout: :capture)
```

The same technique works with the error output — just use the `:stderr` option.
If you specify capturing of both outputs, the return value will be a two-element
array:

```ruby
results, errors = Cheetah.run("grep", "-r", "User", ".", stdout: => :capture, stderr: => :capture)
```

If the output is big you may want to avoid capturing it into a huge string. In
that case, pass an `IO` as a value of the `:stdout` or `:stderr` option. The
command will write its output into it gradually.

```ruby
File.open("files.txt", "w") do |stdout|
  Cheetah.run("ls", "-la", stdout: stdout)
end
```

### Piping Commands

You can pipe multiple commands together and execute them as one. Just specify
the commands together with their arguments as arrays:

```ruby
processes = Cheetah.run(["ps", "aux"], ["grep", "ruby"], stdout: :capture)
```

### Error Handling

If the command can't be executed for some reason or returns an unexpected non-zero exit
status, Cheetah raises an exception with detailed information about the failure:

```ruby
# Run a command and handle errors
begin
  Cheetah.run("rm", "/etc/passwd")
rescue Cheetah::ExecutionFailed => e
  puts e.message
  puts "Standard output: #{e.stdout}"
  puts "Error output:    #{e.stderr}"
  puts "Exit status:     #{e.status.exitstatus}"
end
```
### Logging

For debugging purposes, you can use a logger. Cheetah will log the command, its
status, input and both outputs to it:

```ruby
Cheetah.run("ls -l", logger: logger)
```

### Overwriting env

If the command needs adapted environment variables, use the :env option.
Passed hash is used to update existing env (for details see ENV.update).
Nil value means unset variable. Environment is restored to its original state after
running the command.

```ruby
  Cheetah.run("env", env: { "LC_ALL" => "C" })
```

### Expecting Non-zero Exit Status

If command is expected to return valid a non-zero exit status like `grep` command
which return `1` if given regexp is not found, then option `:allowed_exitstatus`
can be used:

```ruby
# Run a command, handle exitstatus  and handle errors
begin
  exitstatus = Cheetah.run("grep", "userA", "/etc/passwd", allowed_exitstatus: 1)
  if exitstates == 0
    puts "found"
  else
    puts "not found"
  end
rescue Cheetah::ExecutionFailed => e
  puts e.message
  puts "Standard output: #{e.stdout}"
  puts "Error output:    #{e.stderr}"
  puts "Exit status:     #{e.status.exitstatus}"
end
```

Exit status is returned as last element of result. If it is only captured thing,
then it is return without array.
Supported input for `allowed_exitstatus` are anything supporting include, fixnum
or nil for no allowed existatus.

```ruby
# allowed inputs
allowed_exitstatus: 1
allowed_exitstatus: 1..5
allowed_exitstatus: [1, 2]
allowed_exitstatus: object_with_include_method
allowed_exitstatus: nil
```

### Setting Defaults

To avoid repetition, you can set global default value of any option passed too
`Cheetah.run`:

```ruby
# If you're tired of passing the :logger option all the time...
Cheetah.default_options = { :logger => my_logger }
Cheetah.run("./configure")
Cheetah.run("make")
Cheetah.run("make", "install")
Cheetah.default_options = {}
```

### Changing Working Directory

If diferent working directory is needed for running program, then suggested
usage is to enclose call into `Dir.chdir` method.

```ruby
Dir.chdir("/workspace") do
  Cheetah.run("make")
end
```

### More Information

For more information, see the
[API documentation](http://rubydoc.info/github/openSUSE/cheetah/frames).

Compatibility
-------------

Cheetah should run well on any Unix system with Ruby 2.0.0, 2.1 and 2.2. Non-Unix
systems and different Ruby implementations/versions may work too but they were
not tested.

Authors
-------

  * [David Majda](http://github.com/dmajda)
  * [Josef Reidinger](http://github.com/jreidinger)
