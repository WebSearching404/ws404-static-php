require "yaml"

workflow = YAML.load_file(File.expand_path("../.github/workflows/build.yml", __dir__))
uses = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps").map { |step| step["uses"] }.compact }
third_party = uses.reject { |action| action.start_with?("./", "WebSearching404/") }
raise "no external actions examined" if third_party.empty?
third_party.each do |action|
  raise "expected a full commit for #{action}" unless action.match?(/@[0-9a-f]{40}\z/)
end
puts "#{third_party.size} external action uses pinned"
