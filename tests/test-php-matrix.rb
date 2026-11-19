require "json"
require "yaml"

workflow = YAML.load_file(File.expand_path("../.github/workflows/build.yml", __dir__))
# Psych may parse an unquoted YAML 1.1 'on' key as true.
trigger = workflow.fetch("on") { workflow.fetch(true) }
inputs = trigger.fetch("workflow_dispatch").fetch("inputs")
default = JSON.parse(inputs.fetch("php-versions").fetch("default"))
raise "default release matrix is incomplete" unless default == %w[8.1 8.3 8.4]
matrix = workflow.fetch("jobs").fetch("build").fetch("strategy").fetch("matrix")
raise "custom dispatch matrix no longer used" unless matrix.fetch("php") == '${{ fromJSON(github.event.inputs.php-versions) }}'
puts "Default release minors and custom dispatch input verified"
