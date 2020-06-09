# frozen_string_literal: true

LIB_DIR = File.expand_path(__dir__, 'lib')
$LOAD_PATH.unshift(LIB_DIR) unless $LOAD_PATH.include?(LIB_DIR)

Gem::Specification.new do |s|
  s.name = 'sidekiq-max-jobs'
  s.version = File.read(File.join(File.dirname(__FILE__), 'VERSION')).strip
  s.date = Time.now.strftime('%Y-%m-%d')
  s.authors = ['Jonathan W. Zaleski']
  s.email = ['JonathanZaleski@gmail.com']
  s.summary = <<-EOL
A simple plugin used to control the maximum number of jobs for a Sidekiq worker
to process
EOL
  s.description = <<-EOL
This gem provides the ability to configure the maximum number of jobs a Sidekiq
worker will process before terminating. For an environment running Kubernetes
this is a perfect addition because once the affected pod dies it will
automatically be restarted [gracefully] resetting memory, database-connections,
etc. with minimal interruption to throughput
EOL
  s.homepage = 'http://github.com/jzaleski/sidekiq-max-jobs'
  s.license = 'MIT'

  s.files = `git ls-files`.split($/)
  s.require_paths = %w[lib]

  s.add_dependency('sidekiq', '>= 4.0.0', '< 7.0.0')

  s.add_development_dependency('pry', '~> 0.13.0')
  s.add_development_dependency('rake', '~> 13.0.0')
  s.add_development_dependency('rspec', '~> 3.9.0')
  s.add_development_dependency('rubocop', '~> 0.85.0')
  s.add_development_dependency('rubocop-rspec', '~> 1.39.0')
end
