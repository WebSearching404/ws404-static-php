require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

root = File.expand_path("..", __dir__)
steps = YAML.load_file("#{root}/.github/workflows/build-tools.yml").fetch("jobs").fetch("build").fetch("steps")
def write_tool(path, body)
  File.write(path, "#!/bin/bash\nset -e\n" + body)
  File.chmod(0755, path)
end
Dir.mktmpdir do |dir|
  %w[mock src/zip30 src/rsync-fixture].each { |path| FileUtils.mkdir_p("#{dir}/#{path}") }
  %w[mock/sudo mock/make src/rsync-fixture/configure].each { |path| write_tool("#{dir}/#{path}", "exit 0") }
  banner = <<~'SH'
    echo "Version fixture"
    echo "Copyright fixture"
    awk 'BEGIN { for (i = 0; i < 10000; i++) print "extra banner line", i }'
    exit "$BANNER_STATUS"
  SH
  %w[mock/musl-gcc src/zip30/zip src/rsync-fixture/rsync].each { |path| write_tool("#{dir}/#{path}", banner) }
  names = ["Install musl toolchain", "Build zip", "Build rsync"]
  names.each do |name|
    step = steps.find { |s| s["name"] == name }.fetch("run")
    [0, 7].each do |exit_code|
      env = { "PATH" => "#{dir}/mock:#{ENV.fetch("PATH")}", "RSYNC_VERSION" => "fixture", "BANNER_STATUS" => exit_code.to_s }
      log, status = Open3.capture2e(env, "bash", "-c", step, chdir: dir)
      raise "#{name}: expected #{exit_code}, got #{status.exitstatus}" unless status.exitstatus == exit_code
      raise "#{name}: missing version" unless log.include?("Version fixture")
      raise "#{name}: unexpected verbose output" if log.include?("extra banner line")
    end
  end
end
puts "Three workflow steps retained concise banners and propagated tool exit status in six cases"
