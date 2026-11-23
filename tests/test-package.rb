require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

root = File.expand_path("..", __dir__)
program = <<~'SH'
  #!/bin/sh
  case "$1" in
    -v) echo 'PHP 8.3.0 (cli)' ;;
    -r) printf %s 8.3.0 ;;
    *) exit 1 ;;
  esac
SH
def execute(*args, dir:)
  output, status = Open3.capture2e(*args, chdir: dir)
  raise "#{args.last}: #{output}" unless status.success?
  output
end
%w[build build-tools].each do |workflow|
  steps = YAML.load_file("#{root}/.github/workflows/#{workflow}.yml").fetch("jobs").fetch("build").fetch("steps")
  package = steps.find { |step| step["name"] == "Package" }.fetch("run")
  files = workflow == "build" ? { "php" => "php-8.3-cli" } : { "zip" => "zip", "rsync" => "rsync" }
  Dir.mktmpdir do |dir|
    FileUtils.mkdir_p("#{dir}/buildroot/bin")
    FileUtils.cp_r("#{root}/scripts", dir) if File.directory?("#{root}/scripts")
    previous = {}
    [0, 1, 2].each do |pass|
      bytes = pass == 2 ? program + "# changed\n" : program
      files.each_key do |member|
        path = member == "php" ? "#{dir}/buildroot/bin/php" : "#{dir}/#{member}"
        File.write(path, bytes)
        File.chmod(pass.zero? ? 0755 : 0700, path)
        time = Time.at(100 + pass)
        File.utime(time, time, path)
      end
      # PHP installs a fresh staging copy. Cross a wall-clock second to test its timestamp too.
      sleep 1.1 if workflow == "build" && pass == 1
      execute({ "PHP_VERSION" => "8.3", "GITHUB_OUTPUT" => "#{dir}/outputs" }, "bash", "-c", package, dir: dir)
      files.each do |member, prefix|
        archive = "#{prefix}-linux-x86_64.tar.gz"
        current = File.binread("#{dir}/#{archive}")
        raise "#{archive}: metadata changed digest" if pass == 1 && current != previous[member]
        raise "#{archive}: byte change was lost" if pass == 2 && current == previous[member]
        previous[member] = current
        raise "#{archive}: wrong members" unless execute("tar", "-tzf", archive, dir: dir).lines.map(&:chomp) == [member]
        dest = Dir.mktmpdir("extract", dir)
        execute("tar", "-xzf", archive, "-C", dest, dir: dir)
        extracted = "#{dest}/#{member}"
        raise "#{archive}: payload changed" unless File.binread(extracted) == bytes
        raise "#{archive}: wrong mode" unless (File.stat(extracted).mode & 0777) == 0755
      end
    end
  end
end
puts "Both packaging steps passed equal-byte, changed-byte, layout, content and mode checks for all three member names"
