# -*- encoding: utf-8 -*-
require File.expand_path('../lib/activerecord-postgis-array/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Hannah Howard"]
  gem.email         = ["hannah@techgirlwonder.com"]
  gem.description   = %q{Adds missing native PostgreSQL array types to ActiveRecord}
  gem.summary       = %q{Extends ActiveRecord to handle native PostgreSQL array types and is compatible with postgis}
  gem.homepage      = ""

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = "activerecord-postgis-array"
  gem.require_paths = ["lib"]
  gem.version       = ActiveRecordPostgisArray::VERSION

  gem.add_dependency 'activerecord', '~> 3.2.0'
  gem.add_dependency 'pg_array_parser', '~> 0.0.8'

  gem.add_development_dependency 'rails', '~> 3.2.0'
  gem.add_development_dependency 'rspec-rails', '~> 2.12.0'
  gem.add_development_dependency 'bourne', '~> 1.3.0'
  if RUBY_PLATFORM =~ /java/
    gem.add_development_dependency 'activerecord-jdbcpostgresql-adapter'
  else
    gem.add_development_dependency 'pg', '~> 0.13.2'
  end
end
