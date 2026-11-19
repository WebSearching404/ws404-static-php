require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

root = File.expand_path("..", __dir__)
def build_step(root, workflow, name)
  steps = YAML.load_file("#{root}/.github/workflows/#{workflow}.yml").fetch("jobs").fetch("build").fetch("steps")
  steps.find { |step| step["name"] == name }.fetch("run")
end
php_checks = build_step(root, "build", "Assert version and every required module")
config = YAML.load_file("#{root}/.github/workflows/build.yml").fetch("env")
required = config.fetch("REQUIRED_MODULES")
modules = required.split.reject { |name| name == "pcntl" } + ["pcntl"]
php_elf = build_step(root, "build", "Assert the binary is genuinely static")
tools_elf = build_step(root, "build-tools", "Assert both binaries are genuinely static and functional")

Dir.mktmpdir do |dir|
  FileUtils.mkdir_p("#{dir}/buildroot/bin")
  FileUtils.mkdir_p("#{dir}/mock")
  FileUtils.cp_r("#{root}/scripts", dir) if File.directory?("#{root}/scripts")
  def executable(path, script)
    File.write(path, "#!/bin/bash\n" + script)
    File.chmod(0755, path)
  end
  executable("#{dir}/buildroot/bin/php", <<~'SH')
    case "$1" in
      -v) echo "PHP $TEST_VERSION.0 (cli)" ;;
      -m) printf '%s\n' "$TEST_MODULES"; exit "$MODULE_STATUS" ;;
      -r) [[ "$2" == *mb_ereg* ]] && exit "$REGEX_STATUS"; exit 2 ;;
      *) exit 2 ;;
    esac
  SH
  env = { "PHP_VERSION" => "8.3", "REQUIRED_MODULES" => required, "TEST_VERSION" => "8.3",
          "TEST_MODULES" => modules.join("\n"), "MODULE_STATUS" => "0", "REGEX_STATUS" => "0",
          "PATH" => "#{dir}/mock:#{ENV.fetch("PATH")}" }
  [{}, { "TEST_MODULES" => (modules - ["pcntl"]).join("\n") }, { "REGEX_STATUS" => "1" },
   { "MODULE_STATUS" => "1" }, { "TEST_VERSION" => "8.4" }].each_with_index do |change, i|
    output, status = Open3.capture2e(env.merge(change), "bash", "-c", php_checks, chdir: dir)
    raise "PHP case #{i}: #{output}" unless status.success? == i.zero?
  end

  executable("#{dir}/mock/readelf", 'echo "$HEADER"; exit "$INSPECT_STATUS"')
  executable("#{dir}/mock/ldd", 'echo "not a dynamic executable"; exit 1')
  executable("#{dir}/mock/file", "exit 0")
  # The tools step also exercises copy and archive behavior. Use fixture-only stand-ins for that tail.
  executable("#{dir}/rsync", 'mkdir -p t/out/keep && cp t/src/keep/a.txt t/out/keep/')
  executable("#{dir}/zip", "exit 0")
  executable("#{dir}/mock/unzip", 'echo "keep/a.txt"')
  [php_elf, tools_elf].each_with_index do |step, index|
    [["  LOAD 0x0", "0", true], ["  INTERP 0x0", "0", false], ["", "2", false]].each do |header, rc, expected|
      output, status = Open3.capture2e(env.merge("HEADER" => header, "INSPECT_STATUS" => rc),
                                       "bash", "-c", step, chdir: dir)
      raise "ELF workflow #{index}, rc=#{rc}, header=#{header}: #{output}" unless status.success? == expected
    end
  end
end
puts "Five PHP capability cases and six ELF workflow cases passed"
