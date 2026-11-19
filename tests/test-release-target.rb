require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

root = File.expand_path("..", __dir__)
publisher = File.join(root, "scripts/publish-release.sh")
%w[build build-tools].each do |workflow|
  job = YAML.load_file("#{root}/.github/workflows/#{workflow}.yml").fetch("jobs").fetch("publish")
  steps = job.fetch("steps")
  raise "missing checkout in #{workflow}" unless steps.any? { |step| step["uses"].to_s.start_with?("actions/checkout@") }
  publish = steps.find { |step| step["name"] == "Publish" }.fetch("run")
  raise "publisher bypassed in #{workflow}" unless publish.include?('bash "$GITHUB_WORKSPACE/scripts/publish-release.sh" "$RELEASE_TAG"')
  raise "unexpected second publisher" if publish.include?("gh release create")
end

Dir.mktmpdir do |dir|
  sha = "1" * 40
  ref = "refs/tags/v-test"
  # Read-only remote ref advertisement. gh records requests instead of contacting GitHub.
  File.write("#{dir}/git", <<~'SH')
    #!/bin/sh
    if [ "$1" = ls-remote ]; then
      [ "$LAST_READ" = error ] && exit 128
      printf '%s' "$REFS"
    else
      exec /usr/bin/git "$@"
    fi
  SH
  File.write("#{dir}/gh", <<~'SH')
    #!/bin/sh
    printf '%s\n' "$*" >> "$REQUESTS"
    if [ "$1" = api ] && [ "$CREATE_RACE" = yes ]; then exit 1; fi
    exit 0
  SH
  %w[git gh].each { |tool| File.chmod(0755, "#{dir}/#{tool}") }
  cases = {
    "absent" => ["", true],
    "lightweight" => ["#{sha}\t#{ref}\n", true],
    "annotated" => ["#{'a' * 40}\t#{ref}\n#{sha}\t#{ref}^{}\n", true],
    "different" => ["#{'2' * 40}\t#{ref}\n", false],
    "unreadable" => ["", false],
    "creation race" => ["", false]
  }
  cases.each do |name, (refs, expected)|
    requests = "#{dir}/requests"
    File.write(requests, "")
    env = { "PATH" => "#{dir}:#{ENV.fetch("PATH")}", "REFS" => refs,
            "GITHUB_REPOSITORY" => "example/project", "GITHUB_SERVER_URL" => "https://example.invalid",
            "GITHUB_SHA" => sha, "REQUESTS" => requests, "LAST_READ" => name == "unreadable" ? "error" : "",
            "CREATE_RACE" => name == "creation race" ? "yes" : "" }
    output, status = Open3.capture2e(env, "bash", publisher, "v-test", "--latest=false", "asset.tar.gz")
    calls = File.readlines(requests, chomp: true)
    raise "#{name}: #{output}" unless status.success? == expected
    creates = calls.select { |line| line.start_with?("api ") }
    if ["absent", "creation race"].include?(name)
      raise "#{name}: wrong new tag" unless creates.one? && creates.first.include?("ref=#{ref}") && creates.first.include?("sha=#{sha}")
    else
      raise "#{name}: unexpected tag write" unless creates.empty?
    end
    published = calls.select { |line| line.start_with?("release create ") }
    if expected
      raise "#{name}: wrong release arguments" unless published.one? && %W[v-test --verify-tag --latest=false asset.tar.gz --target #{sha}].all? { |arg| published.first.split.include?(arg) }
    else
      raise "#{name}: release attempted" unless published.empty?
    end
  end
end
puts "Both publishers wired, six release target cases passed"
