require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

root = File.expand_path("..", __dir__)
jobs = YAML.load_file("#{root}/.github/workflows/build.yml").fetch("jobs")
package = jobs.fetch("build").fetch("steps").find { |s| s["name"] == "Package" }.fetch("run")
publish = jobs.fetch("publish").fetch("steps").find { |s| s["name"] == "Publish" }.fetch("run")
minors = %w[8.1 8.3 8.4]
Dir.mktmpdir do |dir|
  build = "#{dir}/build"
  release = "#{dir}/release"
  FileUtils.mkdir_p("#{build}/buildroot/bin")
  FileUtils.mkdir_p("#{release}/dist")
  FileUtils.cp_r("#{root}/scripts", build)
  FileUtils.mkdir_p("#{release}/scripts")
  FileUtils.cp("#{root}/scripts/php-built-lines.py", "#{release}/scripts/")
  File.write("#{release}/scripts/publish-release.sh", <<~'SH')
    #!/bin/bash
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --notes-file ]]; then cp -- "$2" "$CAPTURE"; exit; fi
      shift
    done
    exit 1
  SH
  File.write("#{build}/buildroot/bin/php", <<~'SH')
    #!/bin/sh
    case "$1" in
      -v) echo "PHP $PHP_VERSION.7 (cli)" ;;
      -r) [ "${PROBE_FAIL:-0}" = 0 ] || exit 5; printf '%s.7' "$PHP_VERSION" ;;
      *) exit 1 ;;
    esac
  SH
  File.chmod(0755, "#{build}/buildroot/bin/php")
  output = "#{dir}/outputs"
  env = { "GITHUB_OUTPUT" => output, "GITHUB_WORKSPACE" => release, "RUNNER_TEMP" => dir,
          "CAPTURE" => "#{dir}/notes", "REPO" => "example/project", "RELEASE_TAG" => "v-test" }
  _, status = Open3.capture2e(env.merge("PHP_VERSION" => "8.3", "PROBE_FAIL" => "1"), "bash", "-c", package, chdir: build)
  raise "failed version probe accepted" if status.success?
  minors.each do |minor|
    msg, status = Open3.capture2e(env.merge("PHP_VERSION" => minor), "bash", "-c", package, chdir: build)
    raise "package: #{msg}" unless status.success?
  end
  cases = ["single", "matrix", "missing record", "missing archive", "different bytes", "wrong minor", "unexpected archive", "duplicate minor"]
  cases.each do |name|
    dist = "#{release}/dist"
    FileUtils.rm_rf(dist)
    FileUtils.mkdir_p(dist)
    FileUtils.rm_f(env.fetch("CAPTURE"))
    selected = name == "single" ? ["8.3"] : minors
    selected.each do |minor|
      asset = "php-#{minor}-cli-linux-x86_64.tar.gz"
      FileUtils.cp(["#{build}/#{asset}", "#{build}/#{asset}.version"], dist)
    end
    asset = "#{dist}/php-8.3-cli-linux-x86_64.tar.gz"
    case name
    when "missing record" then FileUtils.rm(asset + ".version")
    when "missing archive" then FileUtils.rm(asset)
    when "different bytes" then File.open(asset, "ab") { |f| f << "." }
    when "wrong minor" then File.write(asset + ".version", File.read(asset + ".version").sub(/8\.3\.7$/, "8.4.7"))
    when "unexpected archive" then File.write("#{dist}/extra.tar.gz", "extra")
    when "duplicate minor" then selected = selected + ["8.3"]
    end
    msg, status = Open3.capture2e(env.merge("PHP_VERSIONS" => JSON.generate(selected)), "bash", "-c", publish, chdir: release)
    valid = ["single", "matrix"].include?(name)
    raise "#{name}: #{msg}" unless status.success? == valid && File.exist?(env.fetch("CAPTURE")) == valid
    if valid
      records = File.readlines(env.fetch("CAPTURE"), chomp: true).grep(/^PHP-BUILT /)
      raise "#{name}: patch records" unless records == selected.map { |minor| "PHP-BUILT #{minor} #{minor}.7" }
    end
  end
end
puts "Read-only packaging and eight release metadata cases passed"
